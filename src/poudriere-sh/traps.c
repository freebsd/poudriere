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

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>

#ifndef SHELL
#error Only supported as a builtin
#endif

#include "bltin/bltin.h"
#define _NEED_SH_FLAGS
#include "helpers.h"
#include "var.h"

extern int rootpid;
static int critsnest;
static sigset_t osigmask;

#define MAX_SIGNALS 32
static struct sigdata *signals[MAX_SIGNALS] = {0};

extern int rootshell;

/* From external/sh/trap.c */
extern char *volatile trap[NSIG];	/* trap handler commands */
extern char sigmode[NSIG];	/* current value of signal */
extern char *savestr(const char *);
extern void onsig(int);
#define S_DFL 1			/* default signal handling (SIG_DFL) */
#define S_CATCH 2		/* signal is caught */
#define S_IGN 3			/* signal is ignored (SIG_IGN) */
#define S_HARD_IGN 4		/* signal is ignored permanently */
#define S_RESET 5		/* temporary - to reset a hard ignored sig */

/*
 * Allow signal to use SA_RESTART.  The trapcmd always registers
 * traps without SA_RESTART, but for the builtins we do want that
 * behavior on SIGINFO.  This is also for restoring signal handlers
 * that are modified temporarily in the builtin.
 */
static void
_trap_push(int signo, struct sigdata *sd, bool sh)
{
	struct sigaction act;
	sig_t sigact = SIG_DFL;
	char *action_str = "-", *t;
	int action;

	memset(sd, 0, sizeof(*sd));
	sd->signo = signo;
	sd->sh = sh;

	/* Adapted from setsignal() */
	/* While a trap is stashed we want to use S_DFL (-) by default. */
	action = S_DFL;
	switch (signo) {
	case SIGINT:
	case SIGQUIT:
		action = S_CATCH;
		break;
	case SIGINFO:
		/* Ignore to avoid [EINTR]. */
		action = S_DFL;
		break;
	case SIGALRM:
		action = S_IGN;
		break;
	case SIGTERM:
		if (rootshell && iflag)
			action = S_IGN;
		break;
#if JOBS
	case SIGTSTP:
	case SIGTTOU:
		if (rootshell && mflag)
			action = S_IGN;
		else
			action = S_DFL;
		break;
#endif
	default:
		action = S_DFL;
		break;
	}
	switch (action) {
		case S_DFL:	sigact = SIG_DFL; action_str=NULL; break;
		case S_CATCH:  	sigact = onsig;   action_str=NULL; break;
		case S_IGN:	sigact = SIG_IGN; action_str="";   break;
	}

	if (sh) {
		sd->action_str = trap[signo];
		if (action_str != NULL)
			action_str = savestr(action_str);
		trap[signo] = action_str;
	}
	act.sa_handler = sigact;
	sigemptyset(&act.sa_mask);
	act.sa_flags = SA_RESTART;
	sigaction(signo, &act, &sd->oact);

	if (sh) {
		t = &sigmode[signo];
		if (*t == 0) {
			if (sd->oact.sa_handler == SIG_IGN) {
				if (mflag && (signo == SIGTSTP ||
				    signo == SIGTTIN || signo == SIGTTOU)) {
					*t = S_IGN;	/* don't hard ignore these */
				} else
					*t = S_HARD_IGN;
			} else {
				*t = S_RESET;	/* force to be set */
			}
		}
		*t = action;
		sd->sigmode = sigmode[sd->signo];
	}
}
void
trap_push(int signo, struct sigdata *sd)
{
	_trap_push(signo, sd, 0);
}
void
trap_push_sh(int signo, struct sigdata *sd)
{
	_trap_push(signo, sd, 1);
}

void
trap_pop(int signo, struct sigdata *sd)
{
	int serrno;

	serrno = errno;
	sigaction(signo, &sd->oact, NULL);
	if (sd->sh) {
		if (trap[sd->signo])
			ckfree(trap[sd->signo]);
		trap[sd->signo] = sd->action_str;
		sigmode[sd->signo] = sd->sigmode;
	}
	errno = serrno;
}


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

	fmtstr(buf, sizeof(buf), "%d", nextidx);

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
