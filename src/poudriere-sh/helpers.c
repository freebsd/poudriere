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

#include <sys/types.h>
#include <sys/sbuf.h>
#include <errno.h>
#include <fnmatch.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>

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

int
getvarcmd(int argc, char **argv)
{
	const char *value;
	int ret;

	if (argc != 2 && argc != 3)
		errx(EX_USAGE, "%s", "Usage: getvar <var> [var_return]");

	value = NULL;
	ret = 0;
	if ((value = lookupvar(argv[1])) == NULL) {
		value = "";
		ret = 1;
		goto out;
	}
out:
	if (argc == 3)
		setvar(argv[2], value, 0);
	else
		printf("%s\n", value);
	return (ret);
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

	if (argc != 3)
		errx(EX_USAGE, "%s", "Usage: _gsub_var_name <var> <var_return>");
	const char *string = argv[1];
	const char *var_return = argv[2];
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
	setvar(var_return, newvar, 0);
	return (0);
}

int
_gsub_badcharscmd(int argc, char **argv)
{
	char *n;
	char newvar[512];

	if (argc != 4)
		errx(EX_USAGE, "%s", "Usage: _gsub_badchars <var> <badchars> "
		    "<var_return>");
	const char *string = argv[1];
	const char *badchars = argv[2];
	const char *var_return = argv[3];
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
	setvar(var_return, newvar, 0);
	return (0);
}

static int
_gsub_shell(struct sbuf *newstr, char *string, const char *pattern,
    size_t pattern_len, const char *replacement, size_t replacement_len,
    char *buf, size_t bufsiz)
{
	char *p, *c;
	char save;
	int ret;

	char pattern_r[pattern_len + 2];
	snprintf(pattern_r, sizeof(pattern_r), "%s*", pattern);

	ret = 0;
	INTOFF;
	if (sbuf_new(newstr, buf, bufsiz, SBUF_AUTOEXTEND) == NULL) {
		errx(EX_SOFTWARE, "%s", "sbuf_new");
		ret = 1;
		goto out;
	}
	/*
	 * fnmatch(3) doesn't return the length matched so we need to
	 * look at increasingly larger substrings to find a match to
	 * replace. This is similar to how sh does it in subevalvar_trim()
	 * as well. Not great but the other builtin cases in _gsub might make
	 * this worth it.
	 */
	for (p = string; *p != '\0'; ++p) {
		/*
		 * Before going O(n^n) see if the pattern starts at this
		 * point. If so then we need to look for the end.
		 */
		if (fnmatch(pattern_r, p, 0) != 0) {
			sbuf_putc(newstr, *p);
			continue;
		}
		/*
		 * Search for the smallest match since fnmatch(3) doesn't
		 * return that length for us.
		 */
		for (c = p + 1; *(c - 1) != '\0'; ++c) {
			save = *c;
			*c = '\0';
			if (fnmatch(pattern, p, 0) == 0) {
				/* Found a match. */
				sbuf_bcat(newstr, replacement,
				    replacement_len);
				*c = save;
				p = c - 1;
				break; /* next p */
			} else if (save == '\0') {
				/*
				 * The rest of the string doesn't match.
				 * Take 1 character and try fnmatching
				 * on the next range. Ick.
				 */
				sbuf_putc(newstr, *p);
			}
			*c = save;
		}
	}

	sbuf_finish(newstr);
out:
	return (ret);
}

static int
_gsub_inplace(char *string, const char pattern, const char replacement)
{

	for (char *p = string; *p != '\0'; ++p) {
		if (*p == pattern)
			*p = replacement;
	}
	return (0);
}

static int
_gsub_shift(char *string, const char pattern)
{
	char *shift;

	shift = NULL;
	for (char *p = string; *p != '\0'; ++p) {
		if (shift != NULL && *p != pattern)
			*shift++ = *p;
		else if (shift == NULL && *p == pattern)
			shift = p;
	}
	if (shift != NULL)
		*shift = '\0';
	return (0);
}

static int
_gsub_strstr(struct sbuf *newstr, const char *string, const char *pattern,
    size_t pattern_len, const char *replacement, size_t replacement_len,
    char *buf, size_t bufsiz)
{
	const char *p, *p2;
	size_t string_len, new_len;
	int ret, replacements;

	ret = replacements = string_len = new_len = 0;
	/* Get the string size and count how many replacements there are. */
	for (p = string; (p2 = strstr(p, pattern)) != NULL; p2 += pattern_len,
	    p = p2) {
		string_len += p2 - p + pattern_len;
		++replacements;
	}
	if ((p2 = strchr(p, '\0')) != NULL)
		string_len += p2 - p;
	new_len = string_len +
	    ((replacement_len - pattern_len) * replacements) + 1;
	if (new_len > 1024) {
		buf = NULL;
		bufsiz = new_len;
	}
	INTOFF;
	if (sbuf_new(newstr, buf, bufsiz, SBUF_FIXEDLEN) == NULL) {
		errx(EX_SOFTWARE, "%s", "sbuf_new");
		ret = 1;
		goto out;
	}
	for (p = string; (p2 = strstr(p, pattern)) != NULL; p2 += pattern_len,
	    p = p2) {
		sbuf_bcat(newstr, p, p2 - p);
		sbuf_cat(newstr, replacement);
	}
	sbuf_cat(newstr, p);
	sbuf_finish(newstr);
out:
	return (ret);
}

static int
_gsub(int argc, char **argv, const char *var_return)
{
	struct sbuf newstr = {};
	const char *pattern, *replacement, *p;
	char buf[1024], *string, *outstr;
	size_t pattern_len, replacement_len;
	int ret;
	bool match_shell, sbuf_free;

	ret = 0;
	string = argv[1];
	pattern = argv[2];
	replacement = argv[3];
	replacement_len = strlen(replacement);
	buf[0] = '\0';
	sbuf_free = false;
	outstr = NULL;

	match_shell = false;
	pattern_len = 0;
	for (p = pattern; *p != '\0'; ++p) {
		++pattern_len;
		if (!match_shell && strchr("*?[", *p) != NULL)
			match_shell = true;
	}
	if (pattern_len == 0) {
		outstr = string;
		goto empty_pattern;
	}
	if (match_shell) {
		ret = _gsub_shell(&newstr, string, pattern, pattern_len,
		    replacement, replacement_len, buf, sizeof(buf));
	} else if (pattern_len == 1 && replacement_len == 1) {
		ret = _gsub_inplace(string, *pattern, *replacement);
		outstr = string;
		INTOFF;
	} else if (pattern_len == 1 && replacement_len == 0) {
		ret = _gsub_shift(string, *pattern);
		outstr = string;
		INTOFF;
	} else {
		ret = _gsub_strstr(&newstr, string, pattern, pattern_len,
		    replacement, replacement_len, buf, sizeof(buf));
	}
	if (ret != 0)
		goto out;
	if (outstr == NULL) {
		outstr = sbuf_data(&newstr);
		sbuf_free = true;
	}
empty_pattern:
	if (var_return == NULL)
		printf("%s\n", outstr);
	else
		setvar(var_return, outstr, 0);
	if (sbuf_free)
		sbuf_delete(&newstr);
out:
	INTON;
	return (ret);
}

int
_gsubcmd(int argc, char **argv)
{
	const char *var_return;

	if (argc != 4 && argc != 5)
		errx(EX_USAGE, "%s", "Usage: _gsub <string> <pattern> "
		    "<replacement> [var_return]");
	var_return = argc == 5 && argv[4][0] != '\0' ? argv[4] : "_gsub";
	return (_gsub(argc, argv, var_return));
}

int
gsubcmd(int argc, char **argv)
{
	const char *var_return;

	if (argc != 4 && argc != 5)
		errx(EX_USAGE, "%s", "Usage: gsub <string> <pattern> "
		    "<replacement> [var_return]");
	var_return = argc == 5 && argv[4][0] != '\0' ? argv[4] : NULL;
	return (_gsub(argc, argv, var_return));
}
