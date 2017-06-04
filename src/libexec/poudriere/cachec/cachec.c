/*-
 * Copyright (c) 2016 Baptiste Daroussin <bapt@FreeBSD.org>
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

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <mqueue.h>
#include <fcntl.h>

#ifdef SHELL
#define main cacheccmd
#include "bltin/bltin.h"
#include "options.h"
#include "helpers.h"
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#endif

int
main(int argc, char **argv)
{
	char *queuepath = NULL;
	mqd_t qserver, qme;
	int ch;
	char out[BUFSIZ];
	char spath[BUFSIZ];
	ssize_t sz;
	size_t outlen;
	bool set = false;
#ifdef SHELL
	struct sigaction oact;

	while ((ch = nextopt("s:")) != '\0') {
		switch (ch) {
		case 's':
			queuepath = shoptarg;
			break;
		}
	}
	argc -= argptr - argv;
	argv = argptr;
#else
	while ((ch = getopt(argc, argv, "s:")) != -1) {
		switch (ch) {
		case 's':
			queuepath = optarg;
			break;
		}
	}
	argc -= optind;
	argv += optind;
#endif

	if (!queuepath || argc < 1)
		errx(EXIT_FAILURE, "usage: cachec -s queuepath \"msg\"");

	if (strncasecmp(argv[0], "set ", 4) == 0)
		set = true;

	struct mq_attr attr;
	attr.mq_flags = 0;
	attr.mq_maxmsg = 1;
	attr.mq_msgsize = BUFSIZ;
	attr.mq_curmsgs = 0;

#ifdef SHELL
	INTOFF;
	siginfo_push(&oact);
#endif
	qserver = mq_open(queuepath, O_WRONLY);
	if (qserver == (mqd_t)-1) {
#ifdef SHELL
		siginfo_pop(&oact);
		INTON;
#endif
		err(EXIT_FAILURE, "%s", "mq_open");
	}
	if (set)
		snprintf(out, sizeof(out), "%s", argv[0]);
	else
		snprintf(out, sizeof(out), "%d%s", getpid(), argv[0]);
	outlen = strlen(out);

	if (set) {
		mq_send(qserver, out, outlen, 0);
		mq_close(qserver);
#ifdef SHELL
		siginfo_pop(&oact);
		INTON;
#endif
		return (0);
	}

	snprintf(spath, sizeof(spath),"%s%d", queuepath, getpid());
	qme = mq_open(spath, O_RDONLY | O_CREAT, 0600, &attr);
	mq_send(qserver, out, outlen, 0);
	sz = mq_receive(qme, out, sizeof(out), NULL);
	if (sz > 0) {
		out[sz] = '\0';
		printf("%s\n", out);
	}
	mq_close(qme);
	mq_unlink(spath);
#ifdef SHELL
	siginfo_pop(&oact);
	INTON;
#endif
	return (0);
}
