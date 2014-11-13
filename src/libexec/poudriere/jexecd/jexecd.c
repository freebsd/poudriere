/*-
 * Copyright (c) 2014 Baptiste Daroussin <bapt@FreeBSD.org>
 * All rights reserved.
 *~
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *~
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/types.h>
#include <sys/event.h>
#include <sys/param.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/jail.h>
#include <spawn.h>

#include <unistd.h>
#define _WITH_DPRINTF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <signal.h>
#include <libutil.h>
#include <err.h>
#include <errno.h>
#include <login_cap.h>
#include <jail.h>
#include <inttypes.h>
#include <nv.h>

#define GET_USER_INFO do {						\
	pwd = getpwnam(username);					\
	if (pwd == NULL) {						\
		if (errno)						\
			err(1, "getpwnam: %s", username);		\
		else							\
			errx(1, "%s: no such user", username);		\
	}								\
	lcap = login_getpwclass(pwd);					\
	if (lcap == NULL)						\
		err(1, "getpwclass: %s", username);			\
	ngroups = ngroups_max;						\
	if (getgrouplist(username, pwd->pw_gid, groups, &ngroups) != 0)	\
		err(1, "getgrouplist: %s", username);			\
} while (0)

struct client {
	int fd;
	pid_t pid;
	struct sockaddr_storage ss;
};


static void
log_as(const char *username) {
	login_cap_t *lcap = NULL;
	gid_t *groups = NULL;
	struct passwd *pwd = NULL;
	int ngroups;
	long ngroups_max;

	ngroups_max = sysconf(_SC_NGROUPS_MAX) + 1;
	if ((groups = malloc(sizeof(gid_t) * ngroups_max)) == NULL)
		err(1, "malloc");

	GET_USER_INFO;
	if (setgroups(ngroups, groups) != 0)
		err(1, "setgroups");
	if (setgid(pwd->pw_gid) != 0)
		err(1, "setgid");
	if (setusercontext(lcap, pwd, pwd->pw_uid,
	    LOGIN_SETALL & ~LOGIN_SETGROUP & ~LOGIN_SETLOGIN) != 0)
		err(1, "setusercontext");
	login_close(lcap);
}

static pid_t
client_read(struct client *cl)
{
	char **argv = NULL;
	int argvl = 0;
	int argc = 0;
	nvlist_t *nv;
	int type;
	const nvlist_t *args;
	const char *username, *command, *arg;
	int fdout, fderr, fdin;
	void *cookie;
	pid_t pid;

	pid = -1;
	nv = nvlist_recv(cl->fd);
	if (nv == NULL)
		err(EXIT_FAILURE, "nvlist_recv() failed");

	username = nvlist_get_string(nv, "user");
	command = nvlist_get_string(nv, "command");
	fderr = nvlist_take_descriptor(nv, "stderr");
	fdout = nvlist_take_descriptor(nv, "stdout");
	fdin = nvlist_take_descriptor(nv, "stdin");
	args = nvlist_get_nvlist(nv, "arguments");

	cookie = NULL;
	while ((arg = nvlist_next(args, &type, &cookie)) != NULL) {
		if (type == NV_TYPE_STRING) {
			if (argc > argvl -2) {
				argvl += BUFSIZ;
				argv = reallocf(argv, argvl * sizeof(char *));
			}
			argv[argc++] = (char *)nvlist_get_string(args, arg);
			argv[argc] = NULL;
		}
	}

	if (argv == NULL)
		goto err;

	if ((pid = fork()) == 0) {
		log_as(username);

		close(STDIN_FILENO);
		dup2(fdin, STDIN_FILENO);
		close(STDOUT_FILENO);
		dup2(fdout, STDOUT_FILENO);
		close(STDERR_FILENO);
		dup2(fderr, STDERR_FILENO);
		setsid();
		if (execvp(argv[0], argv) == -1) {
			nvlist_destroy(nv);
			free(argv);
			nv = nvlist_create(0);
			nvlist_add_number(nv, "return", EXIT_FAILURE);
			nvlist_send(cl->fd, nv);
			close(cl->fd);
			exit (0);
		}
	}

	close(fderr);
	close(fdin);
	close(fdout);

err:
	if (pid != -1)
		cl->pid = pid;
	free(argv);
	nvlist_destroy(nv);

	return (pid);
}

static void
client_free(struct client *cl)
{
	if (cl->fd != -1)
		close(cl->fd);
	free(cl);
	cl = NULL;
}

static struct client *
client_accept(int fd)
{
	socklen_t sz;
	struct client *cl;

	cl = calloc(1, sizeof(struct client));
	cl->fd = accept(fd, (struct sockaddr *)&(cl->ss), &sz);

	if (cl->fd < 0) {
		free(cl);
		if (errno == EINTR || errno == EAGAIN || errno == EPROTO)
			return (NULL);
		err(EXIT_FAILURE, "accept()");
	}

	return (cl);
}
static void
serve(int fd) {
	struct kevent ke;
	struct client *cl;
	nvlist_t *nv;
	int kq;
	pid_t pid;

	if ((kq = kqueue()) == -1)
		err(EXIT_FAILURE, "kqueue");

	EV_SET(&ke, fd, EVFILT_READ, EV_ADD, 0, 0, NULL);
	kevent(kq, &ke, 1, NULL, 0, NULL);

	signal(SIGCHLD, SIG_IGN);

	for (;;) {
		kevent(kq, NULL, 0, &ke, 1, NULL);
		/* New client */
		if (ke.ident == fd && ke.filter == EVFILT_READ) {
			cl = client_accept(ke.ident);
			if (cl != NULL) {
				EV_SET(&ke, cl->fd, EVFILT_READ, EV_ADD, 0, 0, cl);
				kevent(kq, &ke, 1, NULL, 0, NULL);
			}
			continue;
		}
		cl = (struct client *)ke.udata;

		if (ke.filter == EVFILT_READ) {
			if (ke.flags & (EV_ERROR | EV_EOF)) {
				EV_SET(&ke, cl->pid, EVFILT_PROC, EV_DELETE, NOTE_EXIT, 0, cl);
				kevent(kq, &ke, 1, NULL, 0, NULL);
				killpg(cl->pid, SIGKILL);
				client_free(cl);
			} else {
				pid = client_read(cl);
				if (pid > 0) {
					EV_SET(&ke, cl->pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, cl);
					kevent(kq, &ke, 1, NULL, 0, NULL);
				}
			}
			continue;
		} else if (ke.filter == EVFILT_PROC) {
			killpg(cl->pid, SIGKILL);
			nv = nvlist_create(0);
			nvlist_add_number(nv, "return", WEXITSTATUS(ke.data));
			nvlist_send(cl->fd, nv);
			nvlist_destroy(nv);
			client_free(cl);

			continue;
		}
	}
}

int
main(int argc, char **argv)
{
	struct sockaddr_un un;
	char *jailname = NULL;
       	char *dir = NULL;
	char path[MAXPATHLEN];
	pid_t otherpid;
	int jid, ch;
	struct pidfh *pfh;
	bool foreground = false;
	int server_fd = -1;
	
	while ((ch = getopt(argc, argv, "j:d:f")) != -1) {
		switch (ch) {
		case 'd':
			dir = optarg;
			break;
		case 'j':
			jailname = optarg;
			break;
		case 'f':
			foreground = true;
			break;
		}
	}

	if (!jailname || !dir)
		errx(EXIT_FAILURE, "usage: jexecd -j jailname -d working_directory");

	setproctitle("poudriere(%s)", jailname);
	snprintf(path, sizeof(path), "%s/%s.pid", dir, jailname);
	pfh = pidfile_open(path, 0600, &otherpid);
	if (pfh == NULL) {
		if (errno == EEXIST) {
			errx(EXIT_FAILURE, "Daemon already running, pid: %jd.",
			    (intmax_t)otherpid);
		}
		/* If we cannot create pidfile from other reasons, only warn. */
		warn("Cannot open or create pidfile: '%s'", path);
	}

	memset(&un, 0, sizeof(struct sockaddr_un));
	if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1)
		err(EXIT_FAILURE, "socket()");
	/* SO_REUSEADDR does not prevent EADDRINUSE, since we are locked by
	 * a pid, just unlink the old socket if needed. */
	snprintf(path, sizeof(path), "%s/%s.sock", dir, jailname);
	unlink(path);
	un.sun_family = AF_UNIX;
	strlcpy(un.sun_path, path, sizeof(un.sun_path));
	if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, (int[]){1},
	    sizeof(int)) < 0)
		err(EXIT_FAILURE, "setsockopt()");

	if (bind(server_fd, (struct sockaddr *) &un,
	    sizeof(struct sockaddr_un)) == -1)
		err(EXIT_FAILURE, "bind()");

	if (!foreground && daemon(0, 0) == -1) {
		pidfile_remove(pfh);
		err(EXIT_FAILURE, "Cannot daemonize");
	}

	pidfile_write(pfh);

	if (listen(server_fd, 1024) < 0)
		err(EXIT_FAILURE, "listen()");

	jid = jail_getid(jailname);
	if (jid < 0) 
		errx(EXIT_FAILURE, "%s", jail_errmsg);
	if (jail_attach(jid) == -1)
		err(EXIT_FAILURE, "jail_attach(%d)", jid);
	chdir("/");

	log_as("root");

	serve(server_fd);
}
