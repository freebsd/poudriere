/*-
 * Copyright (c) 1988, 1993, 1994
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#if 0
#ifndef lint
static char const copyright[] =
"@(#) Copyright (c) 1988, 1993, 1994\n\
	The Regents of the University of California.  All rights reserved.\n";
#endif /* not lint */

#ifndef lint
static char sccsid[] = "@(#)sleep.c	8.3 (Berkeley) 4/2/94";
#endif /* not lint */
#endif
#include <sys/cdefs.h>
__FBSDID("$FreeBSD: head/bin/sleep/sleep.c 308432 2016-11-08 05:31:01Z cem $");

#ifndef SHELL
#include <capsicum_helpers.h>
#endif
#include <ctype.h>
#include <err.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#ifdef SHELL
#define main sleepcmd
#include "bltin/bltin.h"
#include <errno.h>
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#endif

static void usage(void);

static volatile sig_atomic_t report_requested;
static void
report_request(int signo __unused)
{

	report_requested = 1;
}

int
main(int argc, char *argv[])
{
#ifdef SHELL
	struct sigaction act, oact;
#endif
	struct timespec time_to_sleep;
	double d;
	time_t original;
	char buf[2];

#ifndef SHELL
	if (caph_limit_stdio() < 0 || (cap_enter() < 0 && errno != ENOSYS))
		err(1, "capsicum");
#endif

	if (argc != 2)
		usage();

	if (sscanf(argv[1], "%lf%1s", &d, buf) != 1)
		usage();
	if (d > INT_MAX)
		usage();
	if (d <= 0)
		return (0);
	original = time_to_sleep.tv_sec = (time_t)d;
	time_to_sleep.tv_nsec = 1e9 * (d - time_to_sleep.tv_sec);

#ifdef SHELL
	INTOFF;
	memset(&oact, sizeof(oact), 0);
	act.sa_handler = report_request;
	sigemptyset(&act.sa_mask);
	act.sa_flags = SA_RESTART;
	sigaction(SIGINFO, &act, &oact);
#else
	signal(SIGINFO, report_request);
#endif

	/*
	 * Note: [EINTR] is supposed to happen only when a signal was handled
	 * but the kernel also returns it when a ptrace-based debugger
	 * attaches. This is a bug but it is hard to fix.
	 */
	while (nanosleep(&time_to_sleep, &time_to_sleep) != 0) {
		if (report_requested) {
			/* Reporting does not bother with nanoseconds. */
			warnx("about %d second(s) left out of the original %d",
			    (int)time_to_sleep.tv_sec, (int)original);
			report_requested = 0;
		} else if (errno != EINTR) {
#ifdef SHELL
			sigaction(SIGINFO, &oact, NULL);
			INTON;
#endif
			err(1, "%s", "nanosleep");
#ifdef SHELL
		} else if (errno == EINTR) {
			/* Don't ignore interrupts that aren't SIGINFO. */
			break;
#endif
		}
	}
#ifdef SHELL
	sigaction(SIGINFO, &oact, NULL);
	INTON;
#endif
	return (0);
}

static void
usage(void)
{

#ifdef SHELL
	error("usage: sleep seconds");
#else
	fprintf(stderr, "usage: sleep seconds\n");
	exit(1);
#endif
}
