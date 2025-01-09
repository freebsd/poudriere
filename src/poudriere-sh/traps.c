/*-
 * Copyright (c) 2018 Bryan Drewery <bdrewery@FreeBSD.org>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 
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

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>

#ifndef SHELL
#error Only supported as a builtin
#endif

#include "bltin/bltin.h"
#include <errno.h>
#include "helpers.h"
#include "var.h"

extern int rootpid;
static int critsnest;
static sigset_t osigmask;

#define MAX_SIGNALS 32
static struct sigdata *signals[MAX_SIGNALS] = {0};

static int
signame_to_signum(const char *sig)
{
	int n;

	if (strncasecmp(sig, "SIG", 3) == 0)
		sig += 3;
	for (n = 1; n < sys_nsig; n++) {
		if (!strcasecmp(sys_signame[n], sig))
			return (n);
	}
	return (-1);
}

int
trap_pushcmd(int argc, char **argv)
{
	struct sigdata *sd;
	char buf[32];
	int nextidx, idx, ret, signo;

	if (argc != 3)
		errx(EX_USAGE, "%s", "Usage: trap_push <signal> <var_return>");

	if ((signo = signame_to_signum(argv[1])) == -1)
		errx(EX_DATAERR, "Invalid signal %s", argv[1]);

	INTOFF;
	ret = 0;
	nextidx = -1;
	for (idx = 0; idx < MAX_SIGNALS; idx++) {
		if (signals[idx] == NULL) {
			nextidx = idx;
			break;
		}
	}
	if (nextidx == -1)
		errx(EX_SOFTWARE, "%s", "Signal stack exceeded");

	sd = calloc(1, sizeof(*sd));
	trap_push_sh(signo, sd);

	snprintf(buf, sizeof(buf), "%d", nextidx);

	signals[nextidx] = sd;
	INTON;
	if (setvarsafe(argv[2], buf, 0)) {
		ret = 1;
	}

	return (ret);
}

int
critical_startcmd(int argc __unused, char **argv __unused)
{
	sigset_t sigmask;

	++critsnest;
	if (critsnest > 1)
		return (0);

	sigemptyset(&sigmask);
	sigaddset(&sigmask, SIGINT);
	sigaddset(&sigmask, SIGTERM);
	sigaddset(&sigmask, SIGINFO);
	sigaddset(&sigmask, SIGHUP);
	sigaddset(&sigmask, SIGPIPE);
	sigprocmask(SIG_BLOCK, &sigmask, &osigmask);

	return (0);
}

int
critical_endcmd(int argc __unused, char **argv __unused)
{

	if (critsnest == 0) {
		errx(EX_DATAERR, "%s",
		    "critical_end called without critical_start");
	}
	--critsnest;
	if (critsnest > 0)
		return (0);

	sigprocmask(SIG_SETMASK, &osigmask, NULL);

	return (0);
}

int
trap_popcmd(int argc, char **argv)
{
	struct sigdata *sd;
	char *end;
	int signo, idx;

	if (argc != 3)
		errx(EX_USAGE, "%s", "Usage: trap_popcmd <signal> <saved_trap>");

	if ((signo = signame_to_signum(argv[1])) == -1)
		errx(EX_DATAERR, "Invalid signal %s", argv[1]);

	errno = 0;
	idx = strtod(argv[2], &end);
	if (end == argv[2] || errno == ERANGE || idx < 0 || idx >= MAX_SIGNALS)
		errx(EX_DATAERR, "%s", "Invalid saved_trap");
	INTOFF;
	sd = signals[idx];
	if (sd == NULL || sd->signo != signo)
		errx(EX_DATAERR, "%s", "Invalid saved_trap");

	trap_pop(sd->signo, sd);
	free(signals[idx]);
	signals[idx] = NULL;
	INTON;

	return (0);

}
