#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/sbuf.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <grp.h>
#include <signal.h>
#define _WITH_DPRINTF
#include <stdio.h>
#include <ucl.h>
#include <unistd.h>

static ucl_object_t *conf;
static int server_fd = -1;

struct client {
	int fd;
	struct sockaddr_storage ss;
	struct sbuf *buf;
	uid_t uid;
	gid_t gid;
};

static ucl_object_t *
load_conf(void)
{
	struct ucl_parser *parser = NULL;
	ucl_object_t *obj;

	parser = ucl_parser_new(UCL_PARSER_KEY_LOWERCASE);

	if (!ucl_parser_add_file(parser, PREFIX"/etc/artilleur.conf")) {
		warnx("Failed to parse configuration file: %s", ucl_parser_get_error(parser));
		return (NULL);
	}

	obj = ucl_parser_get_object(parser);

	ucl_parser_free(parser);

	return (obj);
}

static void
close_socket(int dummy) {
	if (server_fd != -1)
		close(server_fd);

	ucl_object_t *o;
	o = ucl_object_find_key(conf, "socket");

	if (o == NULL || o->type != UCL_STRING) {
		ucl_object_free(conf);
		exit(dummy);
	}

	unlink(ucl_object_tostring(o));
	ucl_object_free(conf);

	exit(dummy);
}

void
client_free(struct client *cl)
{
	sbuf_delete(cl->buf);
	close(cl->fd);
	free(cl);
}

static bool
valid_user(ucl_object_t *o, struct client *cl)
{
	struct passwd *pw;

	switch (o->type) {
		case UCL_STRING:
			if (ucl_object_tostring(o)[0] == '*')
				return (true);
			pw = getpwnam(ucl_object_tostring(o));
			if (pw && pw->pw_uid == cl->uid)
				return (true);
			break;
		case UCL_INT:
			if (cl->uid == ucl_object_toint(o))
				return (true);
			break;
		default:
			break;
	}

	return (false);
}

static bool
valid_group(ucl_object_t *o, struct client *cl)
{
	struct group *gr;

	switch (o->type) {
		case UCL_STRING:
			if (ucl_object_tostring(o)[0] == '*')
				return (true);
			gr = getgrnam(ucl_object_tostring(o));
			if (gr && gr->gr_gid == cl->gid)
				return (true);
			break;
		case UCL_INT:
			if (cl->gid == ucl_object_toint(o))
				return (true);
			break;
		default:
			break;
	}

	return (false);
}

static int
check_argument(ucl_object_t *cmd, struct client *cl, const char *arg) {

	ucl_object_t *cred_cmds, *cred, *tmp, *wild, *o;
	ucl_object_iter_t it = NULL;

	cred_cmds = ucl_object_find_key(cmd, "argument");
	if (cred_cmds == NULL)
		return (0);

	cred = wild = NULL;
	while ((tmp = ucl_iterate_object(cred_cmds, &it, false))) {
		if ((cred = ucl_object_find_key(tmp, arg)))
			break;
		if (!wild)
			wild = ucl_object_find_key(tmp, "*");
	}
	
	if (cred == NULL && wild == NULL)
		return (0);

	/* check the groups */
	o = ucl_object_find_key(cred, "group");
	if (o != NULL) {
		it = NULL;
		while ((tmp = ucl_iterate_object(o, &it, false))) {
			if (valid_group(o, cl))
				return (1);
		}
	}

	o = ucl_object_find_key(cred, "user");
	if (o != NULL) {
		it = NULL;
		while ((tmp = ucl_iterate_object(o, &it, false))) {
			if (valid_user(o, cl))
				return (1);
		}
	}

	return (0);
}

static bool
is_arguments_allowed(ucl_object_t *a, ucl_object_t *cmd, struct client *cl)
{
	ucl_object_t *tmp;
	ucl_object_iter_t it = NULL;
	int nbargs, ok;

	nbargs = ok = 0;

	if (a == NULL)
		return (false);

	if (a->type == UCL_STRING) {
		nbargs++;
		ok += check_argument(cmd, cl, ucl_object_tostring(a));
	} else {
		while ((tmp = ucl_iterate_object(a, &it, false))) {
			nbargs++;
			if (tmp->type == UCL_STRING)
				ok += check_argument(cmd, cl, ucl_object_tostring(a));
		}
	}

	return (ok == nbargs);
}

static bool
is_command_allowed(ucl_object_t *req, struct client *cl, ucl_object_t **ret)
{
	ucl_object_t *cred_cmds, *cred, *tmp, *wild, *o;
	ucl_object_iter_t it = NULL;

	*ret = NULL;
	cred_cmds = ucl_object_find_key(conf, "command");
	if (cred_cmds == NULL)
		return (false);

	cred = wild = NULL;
	while ((tmp = ucl_iterate_object(cred_cmds, &it, false))) {
		if ((cred = ucl_object_find_key(tmp, ucl_object_tostring(req))))
			break;
		if (!wild)
			wild = ucl_object_find_key(tmp, "*");
	}

	if (cred == NULL && wild == NULL)
		return (false);

	if (!cred)
		cred = wild;

	*ret = cred;

	/* Check the groups */
	o = ucl_object_find_key(cred, "group");
	if (o != NULL) {
		it = NULL;
		while ((tmp = ucl_iterate_object(o, &it, false))) {
			if (valid_group(o, cl))
				return (true);
		}
	}
	/* check the users */
	o = ucl_object_find_key(cred, "user");
	if (o != NULL) {
		it = NULL;
		while ((tmp = ucl_iterate_object(o, &it, false))) {
			if (valid_user(o, cl))
				return (true);
		}
	}

	return (false);
}

static void
client_exec(struct client *cl)
{
	ucl_object_t *cmd, *c, *cmd_cred;
	bool cmd_allowed = false;
	struct ucl_parser *p;
	/* unpack the command */
	p = ucl_parser_new(UCL_PARSER_KEY_LOWERCASE);
	if (!ucl_parser_add_chunk(p, (const unsigned char *)sbuf_data(cl->buf), sbuf_len(cl->buf))) {
		dprintf(cl->fd, "Error: %s\n", ucl_parser_get_error(p));
		ucl_parser_free(p);
		return;
	}

	cmd = ucl_parser_get_object(p);
	ucl_parser_free(p);
	c = ucl_object_find_key(cmd, "command");
	if (c == NULL || c->type != UCL_STRING) {
		dprintf(cl->fd, "Error: no command specified\n");
		ucl_object_free(cmd);
		return;
	}
	/* validate credentials */
	cmd_allowed = is_command_allowed(c, cl, &cmd_cred);

	if (!cmd_allowed && cmd_cred != NULL) {
		c = ucl_object_find_key(cmd, "argument");
		cmd_allowed = is_arguments_allowed(c, cmd_cred, cl);
	}

	if (!cmd_allowed) {
		/* still not allowed, let's check per args */
		dprintf(cl->fd, "Error: permission denied\n");
		ucl_object_free(cmd);
		return;
	}

	/* ok just proceed */
}

static void
client_read(struct client *cl, long len)
{
	int r;
	char buf[BUFSIZ];

	r = read(cl->fd, buf, sizeof(buf));
	if (r < 0 && (errno == EINTR || errno == EAGAIN))
		return;

	sbuf_bcat(cl->buf, buf, r);

	if ((long)r == len) {
		sbuf_finish(cl->buf);
		client_exec(cl);
		sbuf_clear(cl->buf);
	}
}

static struct client *
client_new(int fd)
{
	socklen_t sz;
	struct client *cl;
	int flags;

	if ((cl = malloc(sizeof(struct client))) == NULL)
		errx(EXIT_FAILURE, "Unable to allocate memory");

	sz = sizeof(cl->ss);
	cl->buf = sbuf_new_auto();

	cl->fd = accept(fd, (struct sockaddr *)&(cl->ss), &sz);

	if (cl->fd < 0) {
		if (errno == EINTR || errno == EAGAIN || errno == EPROTO) {
			client_free(cl);
			return (NULL);
		}
		err(EXIT_FAILURE, "accept()");
	}
	
	if (getpeereid(cl->fd, &cl->uid, &cl->gid) != 0)
		err(EXIT_FAILURE, "getpeereid()");

	if (-1 == (flags = fcntl(cl->fd, F_GETFL, 0)))
		flags = 0;

	fcntl(cl->fd, F_SETFL, flags | O_NONBLOCK);

	return (cl);
}

static void
serve(void) {
	int nev, i;
	int kq;
	int nbevq = 0;
	int max_queues = 0;
	struct kevent ke;
	struct kevent *evlist = NULL;
	struct client *cl;

	if ((kq = kqueue()) == -1)
		err(EXIT_FAILURE, "kqueue");

	EV_SET(&ke, server_fd,  EVFILT_READ, EV_ADD, 0, 0, NULL);
	kevent(kq, &ke, 1, NULL, 0, NULL);
	nbevq++;

	for (;;) {
		if (nbevq > max_queues) {
			max_queues += 1024;
			free(evlist);
			if ((evlist = malloc(max_queues * sizeof(struct kevent))) == NULL)
				errx(EXIT_FAILURE, "Unable to allocate memory");
		}

		nev = kevent(kq, NULL, 0, evlist, max_queues, NULL);
		for (i = 0; i < nev; i++) {
			/* New client */
			if (evlist[i].udata == NULL && evlist[i].filter == EVFILT_READ) {
				/* We are in the listener */
				if ((cl = client_new(evlist[i].ident)) == NULL)
					continue;

				EV_SET(&ke, cl->fd, EVFILT_READ, EV_ADD, 0, 0, cl);
				kevent(kq, &ke, 1, NULL, 0, NULL);
				nbevq++;
				continue;
			} 

			/* Reading from client */
			if (evlist[i].filter == EVFILT_READ) {
				if (evlist[i].flags & (EV_ERROR | EV_EOF)) {
					client_free(cl);
					nbevq--;
					continue;
				}
				client_read(evlist[i].udata, evlist[i].data);
			}
		}
	}
}

int
main(void)
{
	struct sockaddr_un un;

	ucl_object_t *o;

	if ((conf = load_conf()) == NULL)
		return (EXIT_FAILURE);


	if ((o = ucl_object_find_key(conf, "socket")) == NULL) {
		warnx("'socket' not found in the configuration file");
		ucl_object_free(conf);

		return (EXIT_FAILURE);
	}

	memset(&un, 0, sizeof(struct sockaddr_un));
	if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
		ucl_object_free(conf);
		err(EXIT_FAILURE, "socket()");
	}

	un.sun_family = AF_UNIX;
	strlcpy(un.sun_path, ucl_object_tostring(o), sizeof(un.sun_path));
	if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, (int[]){1}, sizeof(int)) < 0) {
		ucl_object_free(conf);
		err(EXIT_FAILURE, "setsockopt()");
	}

	if (bind(server_fd, (struct sockaddr *) &un, sizeof(struct sockaddr_un)) == -1) {
		ucl_object_free(conf);
		err(EXIT_FAILURE, "bind()");
	}

	chmod(un.sun_path, 0666);

	signal(SIGINT, close_socket);
	signal(SIGKILL, close_socket);
	signal(SIGQUIT, close_socket);
	signal(SIGTERM, close_socket);

	if (listen(server_fd, 1024) < 0) {
		warn("listen()");
		close_socket(EXIT_FAILURE);
	}

	serve();

	close_socket(EXIT_SUCCESS);
}
