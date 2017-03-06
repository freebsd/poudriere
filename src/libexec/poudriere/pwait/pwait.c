/*-
 * Copyright (c) 2004-2009, Jilles Tjoelker
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with
 * or without modification, are permitted provided that the
 * following conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 * 2. Redistributions in binary form must reproduce the
 *    above copyright notice, this list of conditions and
 *    the following disclaimer in the documentation and/or
 *    other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
 * USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 */

#include <sys/cdefs.h>
__FBSDID("$FreeBSD$");

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifdef SHELL
#define main pwaitcmd
#include "bltin/bltin.h"
#include "options.h"
#include "helpers.h"
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#endif

static void
usage(void)
{

	fprintf(stderr, "usage: pwait [-v] pid ...\n");
#ifdef SHELL
	error(NULL);
#else
	exit(EX_USAGE);
#endif
}

static double
parse_duration(const char *duration)
{
	char *end;
	double ret;

	ret = strtod(duration, &end);
	if (ret == 0 && end == duration)
		errx(EX_DATAERR, "invalid duration");
	if (end == NULL || *end == '\0')
		return (ret);
	errx(EX_DATAERR, "invalid duration");
}

/*
 * pwait - wait for processes to terminate
 */
int
main(int argc, char *argv[])
{
#ifdef SHELL
	struct sigaction oact;
#endif
	struct timespec tspec;
	int kq;
	struct kevent *e;
	int tflag, verbose;
	int opt, nleft, n, i, duplicate, status;
	long pid;
	char *s, *end;

	tflag = verbose = 0;
	tspec.tv_sec = tspec.tv_nsec = 0;
#ifdef SHELL
	while ((opt = nextopt("t:v")) != '\0') {
#else
	while ((opt = getopt(argc, argv, "t:v")) != -1) {
#endif
		switch (opt) {
		case 't':
			tflag = 1;
#ifdef SHELL
			tspec.tv_sec = parse_duration(shoptarg);
#else
			tspec.tv_sec = parse_duration(optarg);
#endif
			break;
		case 'v':
			verbose = 1;
			break;
		default:
			usage();
			/* NOTREACHED */
		}
	}
#ifdef SHELL
	argc -= argptr - argv;
	argv = argptr;
#else
	argc -= optind;
	argv += optind;
#endif

	if (argc == 0)
		usage();
#ifdef SHELL
	INTOFF;
	siginfo_push(&oact);
#endif
	kq = kqueue();
	if (kq == -1) {
#ifdef SHELL
		siginfo_pop(&oact);
		INTON;
#endif
		err(1, "%s", "kqueue");
	}

	e = malloc(argc * sizeof(struct kevent));
	if (e == NULL) {
#ifdef SHELL
		close(kq);
		siginfo_pop(&oact);
		INTON;
#endif
		err(1, "%s", "malloc");
	}
	nleft = 0;
	for (n = 0; n < argc; n++) {
		s = argv[n];
		if (!strncmp(s, "/proc/", 6)) /* Undocumented Solaris compat */
			s += 6;
		errno = 0;
		pid = strtol(s, &end, 10);
		if (pid < 0 || *end != '\0' || errno != 0) {
			warnx("%s: bad process id", s);
			continue;
		}
		duplicate = 0;
		for (i = 0; i < nleft; i++)
			if (e[i].ident == (uintptr_t)pid)
				duplicate = 1;
		if (!duplicate) {
			EV_SET(e + nleft, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT,
			    0, NULL);
			if (kevent(kq, e + nleft, 1, NULL, 0, NULL) == -1)
				warn("%ld", pid);
			else
				nleft++;
		}
	}

	while (nleft > 0) {
		n = kevent(kq, NULL, 0, e, nleft, tflag == 1 ? &tspec : NULL);
		if (n == -1) {
#ifdef SHELL
			free(e);
			close(kq);
			siginfo_pop(&oact);
			INTON;
#endif
			err(1, "%s", "kevent");
		} else if (n == 0) {
#ifdef SHELL
			free(e);
			close(kq);
			siginfo_pop(&oact);
			INTON;
#endif
			return(124);
		}
		if (verbose)
			for (i = 0; i < n; i++) {
				status = e[i].data;
				if (WIFEXITED(status))
					printf("%ld: exited with status %d.\n",
					    (long)e[i].ident,
					    WEXITSTATUS(status));
				else if (WIFSIGNALED(status))
					printf("%ld: killed by signal %d.\n",
					    (long)e[i].ident,
					    WTERMSIG(status));
				else
					printf("%ld: terminated.\n",
					    (long)e[i].ident);
			}
		nleft -= n;
	}
#ifdef SHELL
	free(e);
	close(kq);
	siginfo_pop(&oact);
	INTON;
#endif
	return(EX_OK);
}
