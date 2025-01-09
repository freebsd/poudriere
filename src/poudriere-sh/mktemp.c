/*-
 * Copyright (c) 1994, 1995, 1996, 1998 Peter Wemm <peter@netplex.com.au>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 */

/*
 * This program was originally written long ago, originally for a non
 * BSD-like OS without mkstemp().  It's been modified over the years
 * to use mkstemp() rather than the original O_CREAT|O_EXCL/fstat/lstat
 * etc style hacks.
 * A cleanup, misc options and mkdtemp() calls were added to try and work
 * more like the OpenBSD version - which was first to publish the interface.
 */
#include <sys/param.h>

#include <err.h>
#include <paths.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifndef lint
static const char rcsid[] =
	"$FreeBSD$";
#endif /* not lint */

static void usage(void);

#ifdef SHELL
#define main _mktemp_internal
#include "bltin/bltin.h"
#include "var.h"
#include "helpers.h"
#endif

int
#ifdef SHELL
main(int argc, char **argv, char output_str[MAXPATHLEN])
#else
main(int argc, char **argv)
#endif
{
	int c, fd, ret;
	char *tmpdir;
	const char *prefix;
	char *name;
	int dflag, qflag, tflag, uflag;

	ret = dflag = qflag = tflag = uflag = 0;
	prefix = "mktemp";
	name = NULL;

	while ((c = getopt(argc, argv, "dqt:u")) != -1) {
		switch (c) {
		case 'd':
			dflag++;
			break;

		case 'q':
			qflag++;
			break;

		case 't':
			prefix = optarg;
			tflag++;
			break;

		case 'u':
			uflag++;
			break;

		default:
			usage();
		}
	}

	argc -= optind;
	argv += optind;

	if (!tflag && argc < 1) {
		tflag = 1;
		prefix = "tmp";
	}

	if (tflag) {
		tmpdir = getenv("TMPDIR");
#ifdef SHELL
		INTOFF;
#endif
		if (tmpdir == NULL)
			asprintf(&name, "%s%s.XXXXXXXX", _PATH_TMP, prefix);
		else
			asprintf(&name, "%s/%s.XXXXXXXX", tmpdir, prefix);
		/* if this fails, the program is in big trouble already */
		if (name == NULL) {
#ifdef SHELL
			INTON;
#endif
			if (qflag)
				return (1);
			else
				errx(1, "cannot generate template");
		}
	}
		
	/* generate all requested files */
	while (name != NULL || argc > 0) {
		if (name == NULL) {
#ifdef SHELL
			INTOFF;
#endif
			name = strdup(argv[0]);
			argv++;
			argc--;
		}

		if (dflag) {
			if (mkdtemp(name) == NULL) {
				ret = 1;
				if (!qflag)
					warn("mkdtemp failed on %s", name);
			} else {
#ifdef SHELL
				strlcpy(output_str, name, MAXPATHLEN);
#else
				printf("%s\n", name);
#endif
				if (uflag)
					rmdir(name);
			}
		} else {
#ifdef SHELL
			INTOFF;
#endif
			fd = mkstemp(name);
			if (fd < 0) {
#ifdef SHELL
				INTON;
#endif
				ret = 1;
				if (!qflag)
					warn("mkstemp failed on %s", name);
			} else {
				close(fd);
#ifdef SHELL
				INTON;
#endif
				if (uflag)
					unlink(name);
#ifdef SHELL
				strlcpy(output_str, name, MAXPATHLEN);
#else
				printf("%s\n", name);
#endif
			}
		}
		if (name) {
			free(name);
#ifdef SHELL
			INTON;
#endif
		}
		name = NULL;
	}
	return (ret);
}

#ifdef SHELL
int
mktempcmd(int argc, char **argv)
{
	char output_str[MAXPATHLEN];
	int error;

	error = _mktemp_internal(argc, argv, output_str);
	if (error != 0)
		return (error);
	printf("%s\n", output_str);
	return (0);
}

int
_mktempcmd(int argc, char **argv)
{
	char output_str[MAXPATHLEN], *var_return;
	int ret;

	if (argc < 3)
		errx(EX_USAGE, "%s", "Usage: _mktemp <var_return> "
		    "mktemp(1) params...");
	var_return = argv[1];
	optind = 2;
	ret = _mktemp_internal(argc, argv, output_str);
	if (ret == 0 && setvarsafe(var_return, output_str, 0)) {
		ret = 1;
	}
	return (ret);
}
#endif

static void
usage(void)
{
	fprintf(stderr,
		"usage: mktemp [-d] [-q] [-t prefix] [-u] template ...\n");
	fprintf(stderr,
		"       mktemp [-d] [-q] [-u] -t prefix \n");
	exit (1);
}
