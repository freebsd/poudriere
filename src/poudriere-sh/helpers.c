/*-
 * Copyright (c) 2017 Bryan Drewery <bdrewery@FreeBSD.org>
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

#include <errno.h>
#include <signal.h>
#include <string.h>

#include "helpers.h"

#include "bltin/bltin.h"
#include "options.h"
#include "syntax.h"
#include "var.h"

extern int rootshell;

/* From external/sh/trap.c */
extern char *volatile trap[NSIG];	/* trap handler commands */
extern char sigmode[NSIG];	/* current value of signal */
extern char *savestr(const char *);
extern void onsig(int);
extern void ckfree(pointer);
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

	memset(sd, sizeof(*sd), 0);
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

int
getvarcmd(int argc, char **argv)
{
	char *value;

	if (argc != 3)
		errx(EX_USAGE, "%s", "Usage: getvar <var> <var_return>");

	if ((value = lookupvar(argv[1])) == NULL) {
		setvar(argv[2], "", 0);
		return (1);
	}

	setvar(argv[2], value, 0);
	return (0);
}

int
issetvarcmd(int argc, char **argv)
{

	if (argc != 2)
		errx(EX_USAGE, "%s", "Usage: issetvar <var>");

	return (lookupvar(argv[1]) == NULL);
}

int
_gsub_var_namecmd(int argc, char **argv)
{
	char *n;
	char newvar[512];

	if (argc != 2)
		errx(EX_USAGE, "%s", "Usage: _gsub_var_name <var>");
	const char *string = argv[1];
	n = newvar;
	for (const char *p = string; *p != '\0'; ++p) {
		if (!is_in_name(*p))
			*n++ = '_';
		else
			*n++ = *p;
		if (n - newvar == sizeof(newvar) - 1)
			errx(EX_DATAERR, "var too long");
	}
	*n = '\0';
	setvar("_gsub", newvar, 0);
	return (0);
}

int
_gsub_simplecmd(int argc, char **argv)
{
	char *n;
	char newvar[512];

	if (argc != 3)
		errx(EX_USAGE, "%s", "Usage: _gsub_simple <var> <badchars>");
	const char *string = argv[1];
	const char *badchars = argv[2];
	n = newvar;
	for (const char *p = string; *p != '\0'; ++p) {
		if (strchr(badchars, *p) != NULL)
			*n++ = '_';
		else
			*n++ = *p;
		if (n - newvar == sizeof(newvar) - 1)
			errx(EX_DATAERR, "var too long");
	}
	*n = '\0';
	setvar("_gsub", newvar, 0);
	return (0);
}
