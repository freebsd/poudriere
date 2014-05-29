/*-
 * Copyright (c) 2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

#define _WITH_GETLINE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static void
calculate_duration(char *timestamp, size_t tlen, time_t elapsed)
{
	int hours, minutes, seconds;

	seconds = elapsed % 60;
	minutes = (elapsed / 60) % 60;
	hours = elapsed / 3600;

	snprintf(timestamp, tlen, "(%02d:%02d:%02d) ", hours, minutes,
	    seconds);
}

/**
 * Timestamp stdout
 */
int
main(int argc, char **argv) {
	const char *format;
	time_t elapsed, start, now;
	char *line = NULL;
	char timestamp[8 + 3 + 1]; /* '[HH:MM:SS] ' + 1 */
	size_t linecap, tlen;
	ssize_t linelen;

	start = time(NULL);
	format = argv[1];
	linecap = 0;
	setlinebuf(stdout);
	tlen = sizeof(timestamp);

	while ((linelen = getline(&line, &linecap, stdin)) > 0) {
		now = time(NULL);
		elapsed = now - start;
		calculate_duration((char *)&timestamp, tlen, elapsed);
		fwrite(timestamp, tlen, 1, stdout);
		fwrite(line, linelen, 1, stdout);
	}

	return 0;
}
