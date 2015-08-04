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
#include <sys/socket.h>
#include <sys/un.h>

#include <libgen.h>
#include <unistd.h>
#define _WITH_DPRINTF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <libutil.h>
#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <uthash.h>

#define HASH_FIND_OSTR(head,findstr,out)                                          \
    HASH_FIND(ohh,head,findstr,strlen(findstr),out)
#define HASH_ADD_OSTR(head,strfield,add)                                          \
    HASH_ADD(ohh,head,strfield[0],strlen(add->strfield),add)

struct cache {
	char *name;
	char *origin;
	UT_hash_handle hh;
	UT_hash_handle ohh;
};

static struct cache *namecache = NULL;
static struct cache *origincache = NULL;

static void
parse_command(int fd)
{
	char buf[4096];
	int r;
	char *name, *origin, *pattern;
	struct cache *c;

	r = read(fd, buf, sizeof(buf));
	if (r <= 0)
		return;
	buf[r - 1] = '\0';
	if (strncasecmp(buf, "get ", 4) == 0) {
		pattern = buf + 4;
		if (strchr(buf, '/') != NULL) {
			HASH_FIND_OSTR(origincache, pattern,c);
			if (c != NULL)
				dprintf(fd, "%s\n", c->name);
		} else {
			HASH_FIND_STR(namecache, pattern, c);
			if (c != NULL)
				dprintf(fd, "%s\n", c->origin);
		}
	} else if (strncasecmp(buf, "set ", 4) == 0) {
		name = buf + 4;
		origin = strchr(name, ' ');
		if (origin == NULL) {
			close(fd);
			return;
		}
		origin[0] = '\0';
		origin++;
		HASH_FIND_STR(namecache, name, c);
		if (c != NULL) {
			close(fd);
			return;
		}
		HASH_FIND_OSTR(origincache, origin, c);
		if (c != NULL) {
			close(fd);
			return;
		}
		c = malloc(sizeof(struct cache));
		c->name = strdup(name);
		c->origin = strdup(origin);
		HASH_ADD_STR(namecache, name, c);
		HASH_ADD_OSTR(origincache, origin, c);
	} else {
		dprintf(fd, "Unknown command '%s'\n", buf);
	}
	close(fd);
}

static void
serve(int fd) {
	socklen_t sz;
	struct kevent ke;
	int kq, clfd;
	pid_t pid;
	struct sockaddr_storage ss;

	if ((kq = kqueue()) == -1)
		err(EXIT_FAILURE, "kqueue");

	EV_SET(&ke, fd, EVFILT_READ, EV_ADD, 0, 0, NULL);
	kevent(kq, &ke, 1, NULL, 0, NULL);

	for (;;) {
		kevent(kq, NULL, 0, &ke, 1, NULL);
		/* New client */
		if (ke.ident == fd && ke.filter == EVFILT_READ) {
			clfd = accept(ke.ident, (struct sockaddr *)&ss, &sz);
			if (clfd < 0) {
				if (errno == EINTR || errno == EAGAIN || errno == EPROTO)
					continue;
				err(EXIT_FAILURE, "accept()");
			}
			EV_SET(&ke, clfd, EVFILT_READ, EV_ADD, 0, 0, NULL);
			kevent(kq, &ke, 1, NULL, 0, NULL);
		} else if (ke.flags & (EV_ERROR | EV_EOF))
			close(ke.ident);
		else
			parse_command(ke.ident);
	}
}

int
main(int argc, char **argv)
{
	struct sockaddr_un un;
	char *socketpath = NULL;
	char *pidfile = NULL;
	char *name = NULL;
	struct pidfh *pfh;
	pid_t otherpid;
	int ch, fd;
	bool foreground = false;

	while ((ch = getopt(argc, argv, "s:fp:n:")) != -1) {
		switch (ch) {
		case 's':
			socketpath = optarg;
			break;
		case 'f':
			foreground = true;
			break;
		case 'p':
			pidfile = optarg;
			break;
		case 'n':
			name = optarg;
		}
	}
	if (!pidfile || !socketpath)
		errx(EXIT_FAILURE, "usage: cached [-f] -s socketpath -p pidfile");

	if (name)
		setproctitle("poudriere(%s)", name);

	pfh = pidfile_open(pidfile, 0600, &otherpid);
	if (pfh == NULL) {
		if (errno == EEXIST)
			errx(EXIT_FAILURE, "Daemon already running, pid: %jd.",
			    (intmax_t)otherpid);
		/* If we cannot create pidfile for other reasons, only warn. */
		warn("Cannot open or create pidfile: '%s'", pidfile);
	}
	
	memset(&un, 0, sizeof(struct sockaddr_un));
	if ((fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1)
		err(EXIT_FAILURE, "socket()");

	/* SO_REUSEADDR does not prevent EADDRINUSE, since we are locked by
	 * a pid, just unlink the old socket if needed. */
	unlink(socketpath);
	un.sun_family = AF_UNIX;
	if (chdir(dirname(socketpath)))
		err(EXIT_FAILURE, "chdir()");
	strlcpy(un.sun_path, basename(socketpath), sizeof(un.sun_path));
	if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (int[]){1},
	    sizeof(int)) < 0)
		err(EXIT_FAILURE, "setsockopt()");

	if (bind(fd, (struct sockaddr *) &un,
	    sizeof(struct sockaddr_un)) == -1)
		err(EXIT_FAILURE, "bind()");

	if (!foreground && daemon(0, 0) == -1) {
		pidfile_remove(pfh);
		err(EXIT_FAILURE, "Cannot daemonize");
	}

	pidfile_write(pfh);
	if (listen(fd, 1024) < 0)
		err(EXIT_FAILURE, "listen()");

	serve(fd);
}
