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

#include <inttypes.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <libutil.h>
#include <err.h>
#include <errno.h>
#include <khash.h>
#include <mqueue.h>
#include <fcntl.h>
#include <signal.h>

struct cache {
	char *name;
	char *origin;
};
KHASH_MAP_INIT_STR(namecache, struct cache *);
KHASH_MAP_INIT_STR(origincache, struct cache *);

#define kh_add(name, h, val, k) do {         \
	int __ret;                                      \
	khint_t __i;                                    \
	if (!h) h = kh_init_##name();                   \
	__i = kh_put_##name(h, k, &__ret);              \
	if (__ret != 0)                                 \
		kh_val(h, __i) = val;                   \
} while (0)

#define kh_find(name, h, k, ret) do {                   \
	khint_t __k;                                    \
	ret = NULL;                                     \
	if (h != NULL) {                                \
		__k = kh_get(name, h, k);               \
		if (__k != kh_end(h)) {                 \
			ret = kh_value(h, __k);         \
		}                                       \
	}                                               \
} while (0)


#define kh_contains(name, h, v) ((h)?(kh_get_##name(h, v) != kh_end(h)):false)

static kh_namecache_t *namecache = NULL;
static kh_origincache_t *origincache = NULL;
static mqd_t qserver = (mqd_t)-1;
static const char *queuepath = NULL;

static void
close_mq(int sig __unused)
{
	if (qserver != (mqd_t)-1) {
		mq_close(qserver);
		mq_unlink(queuepath);
	}
	exit(0);
}

static void
parse_command(char *msg)
{
	char *name, *origin, *pattern, *p;
	struct cache *c;
	char client[BUFSIZ];
	char *buf;
	pid_t pid;
	mqd_t qclient;

	buf = msg;
	if (strncasecmp(buf, "set ", 4) == 0) {
		name = buf + 4;
		origin = strchr(name, ' ');
		if (origin == NULL) {
			return;
		}
		origin[0] = '\0';
		origin++;
		if (strchr(origin, '/') == NULL && strchr(name, '/') != NULL) {
			/* Swap to support origin-pkgname */
			p = name;
			name = origin;
			origin = p;
		}
		if (kh_contains(namecache, namecache, name))
			return;
		if (kh_contains(origincache, origincache, origin))
			return;
		c = malloc(sizeof(struct cache));
		c->name = strdup(name);
		c->origin = strdup(origin);
		kh_add(namecache, namecache, c, c->name);
		kh_add(origincache, origincache, c, c->origin);
		return;
	}

	pid = strtol(msg, &buf, 10);
	if (pid == 0)
		return;

	if (strncasecmp(buf, "get ", 4) != 0)
		return;

	snprintf(client, sizeof(client), "%s%ld", queuepath, (long) pid);
	qclient = mq_open(client, O_WRONLY);
	if (qclient == (mqd_t)-1)
		return;

	pattern = buf + 4;
	if (strchr(buf, '/') != NULL) {
		kh_find(origincache, origincache, pattern, c);
		if (c != NULL) {
			mq_send(qclient, c->name, strlen(c->name), 0);
		} else {
			mq_send(qclient, "", 0, 0);
		}
	} else {
		kh_find(namecache, namecache, pattern, c);
		if (c != NULL)
			mq_send(qclient, c->origin, strlen(c->origin), 0);
		else
			mq_send(qclient, "", 0, 0);
	}
	mq_close(qclient);
}

static void
serve(void) {
	char msg[BUFSIZ];
	ssize_t sz;

	for (;;) {
		if ((sz = mq_receive (qserver, msg, BUFSIZ, NULL)) == -1) {
			 err(EXIT_FAILURE, "Cached: mq_received");
		}
		msg[sz] = '\0';
		parse_command(msg);
	}
}

int
main(int argc, char **argv)
{
	char *pidfile = NULL;
	char *name = NULL;
	struct pidfh *pfh;
	pid_t otherpid;
	int ch, fd;
	bool foreground = false;

	while ((ch = getopt(argc, argv, "s:fp:n:")) != -1) {
		switch (ch) {
		case 's':
			queuepath = optarg;
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
	if (!pidfile || !queuepath)
		errx(EXIT_FAILURE, "usage: cached [-f] -s queuepath -p pidfile");

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
	struct mq_attr attr;
	attr.mq_flags = 0;
	attr.mq_maxmsg = 100;
	attr.mq_msgsize = BUFSIZ;
	attr.mq_curmsgs = 0;

	if (kld_load("mqueuefs") != 0 && errno != EEXIST) {
		err(EXIT_FAILURE, "Unable to use POSIX mqueues");
	}

	if (!foreground && daemon(0, 0) == -1) {
		pidfile_remove(pfh);
		err(EXIT_FAILURE, "Cannot daemonize");
	}

	qserver = mq_open(queuepath, O_RDONLY | O_CREAT, 0666, &attr);
	signal(SIGINT, close_mq);
	signal(SIGTERM, close_mq);
	signal(SIGQUIT, close_mq);
	signal(SIGKILL, close_mq);

	pidfile_write(pfh);
	serve();
}
