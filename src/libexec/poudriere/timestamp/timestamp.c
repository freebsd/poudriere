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

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>

#include <err.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#define min(a, b) ((a) > (b) ? (b) : (a))

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
	struct kevent ev, ch;
	time_t elapsed, start, now;
	char timestamp[8 + 3 + 1]; /* '[HH:MM:SS] ' + 1 */
	char buf[1024];
	char *p = NULL;
	bool newline;
	size_t tlen, pending_len;
	ssize_t read_len;
	int kq, fd_in, fd_out;

	start = time(NULL);
	tlen = sizeof(timestamp);
	newline = true;

	if ((kq = kqueue()) == -1)
		err(EXIT_FAILURE, "kqueue");

	EV_SET(&ev, STDIN_FILENO, EVFILT_READ, EV_ADD, 0, 0,
	    (void*)STDOUT_FILENO);
	kevent(kq, &ev, 1, NULL, 0, NULL);

	for (;;) {
		if (kevent(kq, &ev, 1, &ch, 1, NULL) == -1)
			err(EXIT_FAILURE, "kevent");
		fd_in = (int)ch.ident;
		fd_out = (int)(intptr_t)ch.udata;
		pending_len = (size_t)ch.data;

		while (pending_len > 0) {
			read_len = read(fd_in, buf,
			    min(sizeof(buf), pending_len));
			pending_len -= read_len;
			for (p = buf; read_len > 0; ++p, --read_len) {
				if (newline) {
					newline = false;
					now = time(NULL);
					elapsed = now - start;
					calculate_duration((char *)&timestamp,
					    tlen, elapsed);
					write(fd_out, timestamp, tlen - 1);
				}
				if (*p == '\n' || *p == '\r')
					newline = true;
				write(fd_out, p, 1);
			}
		}

		if (ch.flags & EV_EOF)
			break;
	}

	return 0;
}
