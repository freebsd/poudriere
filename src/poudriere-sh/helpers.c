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

#include <assert.h>
#include <errno.h>
#include <fnmatch.h>
#include <limits.h>
#include <string.h>
#include <stdlib.h>
#include <sysexits.h>

#include "bltin/bltin.h"
#include "exec.h"
#include "eval.h"
#include "syntax.h"
#include "var.h"
#include "helpers.h"

unsigned long
get_ulong(const char *str, const char *desc)
{
	char *endp = NULL;
	unsigned long val;

	errno = 0;
	val = strtoul(str, &endp, 10);
	if (*endp != '\0' || errno != 0) {
		err(EX_USAGE, "Invalid %s", desc);
	}
	return (val);
}

int
randintcmd(int argc, char **argv)
{
	const char *outvar = NULL;
	char valstr[40];
	int ret;
	uint32_t value;
	unsigned long min_val, max_val;

	if (argc != 2 && argc != 3 && argc != 4)
		errx(EX_USAGE, "%s", "Usage: randint [min_val] <max_val> " \
		    "[var_return]");

	ret = 0;
	min_val = 1;
	outvar = NULL;
	if (argc == 2) {
		max_val = get_ulong(argv[1], "max_val");
	} else if (argc == 3) {
		if (argv[2][0] >= '0' && argv[2][0] <= '9') {
			min_val = get_ulong(argv[1], "min_val");
			max_val = get_ulong(argv[2], "max_val");
		} else {
			max_val = get_ulong(argv[1], "max_val");
			outvar = argv[2];
		}
	} else {
		assert(argc == 4);
		min_val = get_ulong(argv[1], "min_val");
		max_val = get_ulong(argv[2], "max_val");
		outvar = argv[3];
	}
	INTOFF;
	value = min_val + arc4random_uniform((max_val - min_val) + 1);
	INTON;
	if (outvar != NULL) {
		fmtstr(valstr, sizeof(valstr), "%u", value);
		if (setvarsafe(outvar, valstr, 0))
			ret = 1;
	} else
		printf("%u\n", value);
	return (ret);
}

int
getvarcmd(int argc, char **argv)
{
	const char *value, *var, *var_return;
	int ret;

	if (argc != 2 && argc != 3)
		errx(EX_USAGE, "%s", "Usage: getvar <var> [var_return]");

	value = NULL;
	ret = 0;
	var = argv[1];
	var_return = argv[2];
	if ((value = lookupvar(var)) == NULL) {
		value = NULL;
		ret = 1;
		goto out;
	}
out:
	if (argc == 3 &&
	    var_return[0] != '\0' &&
	    strcmp(var_return, "-") != 0) {
		if (value == NULL) {
			INTOFF;
			if (unsetvar(var_return)) {
				ret = 1;
			}
			INTON;
		} else {
			if (setvarsafe(var_return, value, 0)) {
				ret = 1;
			}
		}
	} else if (value != NULL && strcmp(value, "") != 0) {
		printf("%s\n", value);
	}
	xtracestr("%s=%s", var, value);
	return (ret);
}

int
issetcmd(int argc, char **argv)
{

	if (argc != 2)
		errx(EX_USAGE, "%s", "Usage: isset <var>");

	return (lookupvar(argv[1]) == NULL);
}

int
_gsub_var_namecmd(int argc, char **argv)
{
	char *n;
	char newvar[512];
	int ret;

	if (argc != 3)
		errx(EX_USAGE, "%s", "Usage: _gsub_var_name <var> <var_return>");
	const char *string = argv[1];
	const char *var_return = argv[2];
	ret = 0;
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
	if (setvarsafe(var_return, newvar, 0)) {
		ret = 1;
	}
	return (ret);
}

int
_gsub_badcharscmd(int argc, char **argv)
{
	char *n;
	char newvar[512];
	int ret;

	if (argc != 4)
		errx(EX_USAGE, "%s", "Usage: _gsub_badchars <var> <badchars> "
		    "<var_return>");
	const char *string = argv[1];
	const char *badchars = argv[2];
	const char *var_return = argv[3];
	ret = 0;
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
	if (setvarsafe(var_return, newvar, 0)) {
		ret = 1;
	}
	return (ret);
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
	fmtstr(pattern_r, sizeof(pattern_r), "%s*", pattern);

	ret = 0;
	INTOFF;
	if (sbuf_new(newstr, buf, bufsiz, SBUF_AUTOEXTEND) == NULL) {
		INTON;
		errx(EX_SOFTWARE, "%s", "sbuf_new");
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
		INTON;
		errx(EX_SOFTWARE, "%s", "sbuf_new");
	}
	for (p = string; (p2 = strstr(p, pattern)) != NULL; p2 += pattern_len,
	    p = p2) {
		sbuf_bcat(newstr, p, p2 - p);
		sbuf_cat(newstr, replacement);
	}
	sbuf_cat(newstr, p);
	sbuf_finish(newstr);
	return (ret);
}

static int
_gsub(char **argv, const char *var_return)
{
	struct sbuf newstr = {};
	const char *pattern, *replacement, *p;
	char buf[1024], *string, *outstr;
	size_t pattern_len, replacement_len;
	int ret;
	bool match_shell, sbuf_free;
#ifndef NDEBUG
	const int inton = is_int_on();
#endif

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
		assert(is_int_on());
	} else if (pattern_len == 1 && replacement_len == 1) {
		ret = _gsub_inplace(string, *pattern, *replacement);
		outstr = string;
		assert(inton == is_int_on());
	} else if (pattern_len == 1 && replacement_len == 0) {
		ret = _gsub_shift(string, *pattern);
		outstr = string;
		assert(inton == is_int_on());
	} else {
		ret = _gsub_strstr(&newstr, string, pattern, pattern_len,
		    replacement, replacement_len, buf, sizeof(buf));
		assert(is_int_on());
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
	else {
		if (setvarsafe(var_return, outstr, 0)) {
			ret = 1;
		}
	}
	if (sbuf_free) {
		assert(is_int_on());
		sbuf_delete(&newstr);
		INTON;
	}
out:
	assert(inton == is_int_on());
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
	return (_gsub(argv, var_return));
}

int
gsubcmd(int argc, char **argv)
{
	const char *var_return;

	if (argc != 4 && argc != 5)
		errx(EX_USAGE, "%s", "Usage: gsub <string> <pattern> "
		    "<replacement> [var_return]");
	var_return = argc == 5 && argv[4][0] != '\0' ? argv[4] : NULL;
	return (_gsub(argv, var_return));
}

double
parse_duration(const char *duration)
{
	double ret;
	char *suffix;

#ifdef SHELL
	assert(is_int_on());
#endif
	ret = strtod(duration, &suffix);
	if (suffix == duration) {
#ifdef SHELL
		INTON;
#endif
		errx(EX_USAGE, "duration is not a number");
	}

	if (*suffix == '\0')
		return (ret);

	if (suffix[1] != '\0') {
#ifdef SHELL
		INTON;
#endif
		errx(EX_USAGE, "duration unit suffix too long");
	}

	switch (*suffix) {
	case 's':
		break;
	case 'm':
		ret *= 60;
		break;
	case 'h':
		ret *= 60 * 60;
		break;
	case 'd':
		ret *= 60 * 60 * 24;
		break;
	default:
#ifdef SHELL
		INTON;
#endif
		errx(EX_USAGE, "duration unit suffix invalid");
	}

	if (ret < 0 || ret >= 100000000UL) {
#ifdef SHELL
		INTON;
#endif
		errx(EX_USAGE, "duration out of range");
	}

	return (ret);
}

/* $$ is not correct in subshells. */
int
getpidcmd(int argc, char **argv)
{

	assert(getpid() == shpid);
	fprintf(stdout, "%ld\n", shpid);
	return (0);
}

int
have_builtin(int argc, char**argv)
{
	const char *cmd;
	int unused;

	if (argc != 2)
		errx(EX_USAGE, "Usage: %s: command", argv[0]);
	cmd = argv[1];
	if (find_builtin(cmd, &unused) >= 0) {
		return (0);
	}
	return (1);
}
