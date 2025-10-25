/*-
 * Copyright (c) 2013 Baptiste Daroussin <bapt@FreeBSD.org>
 * Copyright (c) 2025 Bryan Drewery <bdrewery@FreeBSD.org>
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
#include <dirent.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifdef SHELL
#define main dirwatchcmd
#include "bltin/bltin.h"
#include "helpers.h"
#include "trap.h"
#endif

/*
 * Returns 1 if non-empty, 0 if not, -1 on error.
 */
static int
dir_nonempty_fd(int fd)
{
	struct dirent *ent;
	int ret;
	DIR *d;

	ret = 0;
#ifdef SHELL
	INTOFF;
#endif
	if ((d = fdopendir(fd)) == NULL) {
		warnx("fdopendir()");
		goto out;
	}
	while ((ent = readdir(d))) {
		if (strcmp(ent->d_name, ".") == 0 ||
		    (strcmp(ent->d_name, "..")) == 0) {
			continue;
		}
		ret = 1;
		break;
	}
	(void)fdclosedir(d);
out:
#ifdef SHELL
	INTON;
#endif
	return (ret);
}

static void
usage(void)
{
	errx(EX_USAGE, "Usage: dirwatch [-n] <directory>");
}

/*
 * Watch a directory and exit immediately once a new file is added.
 * Used by poudriere-daemon to watch for items added by poudriere-queue
 */
int
main(int argc, char **argv)
{
	struct kevent event, change;
	bool want_non_empty;
	int ch, kq, fd;
	int error;
#ifdef SHELL
	int ret;
#endif

	want_non_empty = false;
	while ((ch = getopt(argc, argv, "n")) != -1) {
		switch(ch) {
		case 'n':
			want_non_empty = true;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;

	if (argc != 1) {
		usage();
	}
#ifdef SHELL
	INTOFF;
#endif
	fd = open(argv[0], O_RDONLY | O_DIRECTORY);
	if (fd == -1) {
#ifdef SHELL
		INTON;
#endif
		err(1, "open()");
	}

	if ((kq = kqueue()) == -1) {
#ifdef SHELL
		close(fd);
		INTON;
#endif
		err(1, "kqueue()");
	}

	EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_ONESHOT,
	    NOTE_WRITE, 0, 0);
	if (kevent(kq, &change, 1, NULL, 0, NULL) < 0) {
#ifdef SHELL
		close(kq);
		close(fd);
		INTON;
#endif
		err(1, "kevent()");
	}
	if (want_non_empty) {
		/*
		 * Now that the event is registered, check if the dir is
		 * non-empty before blocking. This avoids a race.
		 */
		error = dir_nonempty_fd(fd);
		/* 1 (is non-empty) -1 (error) both should exit. */
		if (error != 0) {
#ifdef SHELL
			close(kq);
			close(fd);
			INTON;
#endif
			return (error == 1 ? EXIT_SUCCESS : EXIT_FAILURE);
		}
	}
#ifdef SHELL
	/*
	 * XXX: Might be better to use a timeout and check for interrupts
	 * occasionally.
	 */
	INTON;
#endif
	if (kevent(kq, NULL, 0, &event, 1, NULL) < 0) {
#ifdef SHELL
		int serrno = errno;

		INTOFF;
		if (errno == EINTR) {
			if (pendingsig == 0) {
				ret = 1;
			} else {
				ret = 128 + pendingsig;
			}
		} else {
			ret = 1;
		}
		close(kq);
		close(fd);
		INTON;
		if (serrno == EINTR) {
			exit(ret);
		} else {
			err(ret, "kevent()");
		}
#else
		err(1, "kevent()");
#endif
	}
#ifdef SHELL
	INTOFF;
	close(kq);
	close(fd);
	INTON;
#endif
	return (0);
}
