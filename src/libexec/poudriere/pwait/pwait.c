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

	fprintf(stderr, "usage: pwait [-t timeout] [-v] pid ...\n");
#ifdef SHELL
	error(NULL);
#else
	exit(EX_USAGE);
#endif
}

/*
 * pwait - wait for processes to terminate
 */
int
main(int argc, char *argv[])
{
#ifdef SHELL
	struct sigaction info_oact, alrm_oact;
#endif
	struct itimerval itv;
	int kq;
	struct kevent *e;
	int tflag, verbose;
	int opt, nleft, n, i, duplicate, status;
	long pid;
	char *s, *end;
	double timeout;
	pid_t me;

	tflag = verbose = 0;
	memset(&itv, 0, sizeof(itv));
#ifdef SHELL
	while ((opt = nextopt("t:v")) != '\0') {
#else
	while ((opt = getopt(argc, argv, "t:v")) != -1) {
#endif
		switch (opt) {
		case 't':
			tflag = 1;
			errno = 0;
#ifdef SHELL
			timeout = strtod(shoptarg, &end);
			if (end == shoptarg || errno == ERANGE ||
			    timeout < 0)
#else
			timeout = strtod(optarg, &end);
			if (end == optarg || errno == ERANGE ||
			    timeout < 0)
#endif
				errx(EX_DATAERR, "timeout value");
			switch(*end) {
			case 0:
			case 's':
				break;
			case 'h':
				timeout *= 60;
				/* FALLTHROUGH */
			case 'm':
				timeout *= 60;
				break;
			default:
				errx(EX_DATAERR, "timeout unit");
			}
			if (timeout > 100000000L)
				errx(EX_DATAERR, "timeout value");
			itv.it_value.tv_sec = (time_t)timeout;
			timeout -= (time_t)timeout;
			itv.it_value.tv_usec =
			    (suseconds_t)(timeout * 1000000UL);
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

	me = getpid();

#ifdef SHELL
	INTOFF;
	trap_push(SIGINFO, &info_oact);
#endif
	kq = kqueue();
	if (kq == -1) {
#ifdef SHELL
		trap_pop(SIGINFO, &info_oact);
		INTON;
#endif
		err(1, "%s", "kqueue");
	}

	e = malloc((argc + tflag) * sizeof(struct kevent));
	if (e == NULL) {
#ifdef SHELL
		close(kq);
		trap_pop(SIGINFO, &info_oact);
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
		if (pid == me) {
			warnx("%s: ignoring own process id", s);
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

	if (tflag) {
		/*
		 * Explicitly detect SIGALRM so that an exit status of 124
		 * can be returned rather than 142.
		 */
		EV_SET(e + nleft, SIGALRM, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
		if (kevent(kq, e + nleft, 1, NULL, 0, NULL) == -1) {
#ifdef SHELL
			close(kq);
			free(e);
			trap_pop(SIGINFO, &info_oact);
			INTON;
#endif
			err(EX_OSERR, "%s", "kevent");
		}
		/* Ignore SIGALRM to not interrupt kevent(2). */
#ifdef SHELL
		trap_push(SIGALRM, &alrm_oact);
#endif
		signal(SIGALRM, SIG_IGN);
		if (setitimer(ITIMER_REAL, &itv, NULL) == -1) {
#ifdef SHELL
			close(kq);
			free(e);
			trap_pop(SIGINFO, &info_oact);
			trap_pop(SIGALRM, &alrm_oact);
			INTON;
#endif
			err(EX_OSERR, "%s", "setitimer");
		}
	}
	while (nleft > 0) {
		n = kevent(kq, NULL, 0, e, nleft + tflag, NULL);
		if (n == -1) {
#ifdef SHELL
			close(kq);
			free(e);
			trap_pop(SIGINFO, &info_oact);
			if (tflag) {
				alarm(0);
				trap_pop(SIGALRM, &alrm_oact);
			}
			INTON;
#endif
			err(1, "%s", "kevent");
		}
		for (i = 0; i < n; i++) {
			if (e[i].filter == EVFILT_SIGNAL) {
				if (verbose)
					printf("timeout\n");
#ifdef SHELL
				close(kq);
				free(e);
				trap_pop(SIGINFO, &info_oact);
				if (tflag) {
					alarm(0);
					trap_pop(SIGALRM, &alrm_oact);
				}
				INTON;
#endif
				return (124);
			}
			if (verbose) {
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
			--nleft;
		}
	}
#ifdef SHELL
	close(kq);
	free(e);
	trap_pop(SIGINFO, &info_oact);
	if (tflag) {
		alarm(0);
		trap_pop(SIGALRM, &alrm_oact);
	}
	INTON;
#endif
	return (EX_OK);
}
