/*-
 * Copyright (c) 2015 Bryan Drewery <bdrewery@FreeBSD.org>
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

#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sysexits.h>

#ifdef SHELL
#define main clockcmd
#include "bltin/bltin.h"
#include <errno.h>
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#endif

static void
usage(void)
{

		errx(EX_USAGE, "Usage: clock [-monotonic | -epoch]");
}
/*
 * Simple helper to return clock_gettime(CLOCK_MONOTONIC) for duration
 * display purposes. Faster than `date +%s` and ensures a monotonic time.
 */
int
main(int argc, char **argv)
{
	struct timespec ts;

	if (argc != 2)
		usage();

#ifndef CLOCK_MONOTONIC_FAST
# define CLOCK_MONOTONIC_FAST CLOCK_MONOTONIC
#endif
#ifndef CLOCK_REALTIME_FAST
# define CLOCK_REALTIME_FAST CLOCK_REALTIME
#endif
	if (strcmp(argv[1], "-monotonic") == 0) {
		if (clock_gettime(CLOCK_MONOTONIC_FAST, &ts))
			err(EXIT_FAILURE, "%s", "clock_gettime");
	} else if  (strcmp(argv[1], "-epoch") == 0) {
		if (clock_gettime(CLOCK_REALTIME_FAST, &ts))
			err(EXIT_FAILURE, "%s", "clock_gettime");
	} else
		usage();
	printf("%ld\n", (long)ts.tv_sec);
	return (EXIT_SUCCESS);
}
