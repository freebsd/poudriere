#include <sys/types.h>
#include <sys/event.h>
#include <sys/param.h>
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
#include <spawn.h>
#define _WITH_DPRINTF
#include <stdio.h>
#include <histedit.h>
#include <ucl.h>
#include <unistd.h>

static ucl_object_t *conf;
static ucl_object_t *queue = NULL;
static int server_fd = -1;
static ucl_object_t *running = NULL;
extern char **environ;
static int kq;
static int nbevq = 0;
static struct kevent ke;

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

	if (!ucl_parser_add_file(parser, PREFIX"/etc/poudriered.conf")) {
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
		ucl_object_unref(conf);
		exit(dummy);
	}

	unlink(ucl_object_tostring(o));
	ucl_object_unref(conf);

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
	const char **argv;
	int argc;
	Tokenizer *t = NULL;

	nbargs = ok = 0;

	if (a == NULL)
		return (false);

	t = tok_init(NULL);
	if (tok_str(t, ucl_object_tostring(a), &argc, &argv) != 0) {
		dprintf(cl->fd, "Error: bad arguments");
		tok_end(t);
		return (false);
	}

	for (int i = 0; i < argc; i++) {
		if (argv[i][0] != '-')
			continue;
		nbargs++;
		ok += check_argument(cmd, cl, argv[i]);
	}

	tok_end(t);

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


static int
mkdirs(const char *_path)
{
	char path[MAXPATHLEN];
	char *p;

	strlcpy(path, _path, sizeof(path));
	p = path;
	if (*p == '/')
		p++;

	for (;;) {
		if ((p = strchr(p, '/')) != NULL)
			*p = '\0';

		if (mkdir(path, S_IRWXU | S_IRWXG | S_IRWXO) < 0)
			if (errno != EEXIST && errno != EISDIR)
				err(EXIT_FAILURE, "mkdir");

		/* that was the last element of the path */
		if (p == NULL)
			break;

		*p = '/';
		p++;
	}

	return (0);
}


static void
execute_cmd() {
	posix_spawn_file_actions_t action;
	int logfd;
	pid_t pid;
	int error;
	const char **argv;
	int argc;
	struct sbuf *cmdline;
	ucl_object_t *o, *a;
	Tokenizer *t;

	if (running == NULL)
		return;

	logfd = open("/tmp/poudriered-test.log", O_CREAT|O_RDWR|O_TRUNC,0644);

	o = ucl_object_find_key(running, "command");
	a = ucl_object_find_key(running, "arguments");

	posix_spawn_file_actions_init(&action);
	posix_spawn_file_actions_adddup2(&action, logfd, STDOUT_FILENO);
	posix_spawn_file_actions_adddup2(&action, logfd, STDERR_FILENO);

	cmdline = sbuf_new_auto();
	sbuf_printf(cmdline, "poudriere %s", ucl_object_tostring(o));
	if (a != NULL)
		sbuf_printf(cmdline, " %s", ucl_object_tostring(a));
	sbuf_finish(cmdline);

	t = tok_init(NULL);
	tok_str(t, sbuf_data(cmdline), &argc, &argv);

	if ((error = posix_spawn(&pid, PREFIX"/bin/poudriere",
		&action, NULL, __DECONST(char **, argv), environ)) != 0) {
		errno = error;
		warn("Cannot run poudriere");
		return;
	}

	EV_SET(&ke, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, &logfd);
	kevent(kq, &ke, 1, NULL, 0, NULL);
	nbevq++;
}

static void
process_queue(void) {
	if (running != NULL)
		return;

	running = ucl_array_pop_first(queue);

	execute_cmd();
}

static bool
append_to_queue(ucl_object_t *cmd)
{
	queue = ucl_array_append(queue, cmd);

	process_queue();

	return (true);
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
		ucl_object_unref(cmd);
		return;
	}
	/* validate credentials */
	cmd_allowed = is_command_allowed(c, cl, &cmd_cred);

	if (!cmd_allowed && cmd_cred != NULL) {
		c = ucl_object_find_key(cmd, "arguments");
		if (c && c->type != UCL_STRING)
			dprintf(cl->fd, "Error: expecting a string for the arguments");
		if (c && c->type == UCL_STRING)
			cmd_allowed = is_arguments_allowed(c, cmd_cred, cl);
	}

	if (!cmd_allowed) {
		/* still not allowed, let's check per args */
		dprintf(cl->fd, "Error: permission denied\n");
		ucl_object_unref(cmd);
		return;
	}

	/* ok just proceed */
	if (!append_to_queue(cmd)) {
		dprintf(cl->fd, "Error: unknown, command not queued");
		ucl_object_unref(cmd);
		return;
	}
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
check_schedules() {
	struct tm *now;
	time_t now_t;
	ucl_object_t *o, *tmp, *cmd, *when, *dateformat;
	ucl_object_iter_t it = NULL;
	char datestr[BUFSIZ];

	now_t = time(NULL);
	now = gmtime(&now_t);
	o = ucl_object_find_key(conf, "schedule");

	while ((tmp = ucl_iterate_object(o, &it, true))) {
		when = ucl_object_find_key(tmp, "when");
		dateformat = ucl_object_find_key(tmp, "format");
		cmd = ucl_object_find_key(tmp, "cmd");
		if (cmd == NULL ||
		    when == NULL ||
		    dateformat == NULL)
			continue;

		if (strftime_l(datestr, BUFSIZ, ucl_object_tostring(dateformat), now, NULL) <= 0)
			continue;

		if (!strcmp(datestr, ucl_object_tostring(when)))
			queue = ucl_array_append(queue, cmd);
	}
}

static void
serve(void) {
	struct kevent *evlist = NULL;
	struct client *cl;
	int nev, i;
	int max_queues = 0;

	if ((kq = kqueue()) == -1)
		err(EXIT_FAILURE, "kqueue");

	if (ucl_object_find_key(conf, "schedule") != NULL) {
		EV_SET(&ke, 1, EVFILT_TIMER, EV_ADD, 0, 1000, NULL);
		kevent(kq, &ke, 1, NULL, 0, NULL);
		nbevq++;
	}
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
				continue;
			}

			/* process died */
			if (evlist[i].filter == EVFILT_PROC) {
				int fd = *(int *)evlist[i].udata;
				close(fd);
				ucl_object_unref(running);
				running = NULL;
				continue;
			}

			if (evlist[i].filter == EVFILT_TIMER)
				check_schedules();

		}
		process_queue();
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
		ucl_object_unref(conf);

		return (EXIT_FAILURE);
	}

	memset(&un, 0, sizeof(struct sockaddr_un));
	if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
		ucl_object_unref(conf);
		err(EXIT_FAILURE, "socket()");
	}

	un.sun_family = AF_UNIX;
	strlcpy(un.sun_path, ucl_object_tostring(o), sizeof(un.sun_path));
	if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, (int[]){1}, sizeof(int)) < 0) {
		ucl_object_unref(conf);
		err(EXIT_FAILURE, "setsockopt()");
	}

	if (bind(server_fd, (struct sockaddr *) &un, sizeof(struct sockaddr_un)) == -1) {
		ucl_object_unref(conf);
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
