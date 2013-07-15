/*-
 * Copyright (c) 2013 Baptiste Daroussin <bapt@FreeBSD.org>
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
#include <sys/stat.h>

#include <unistd.h>
#include <fcntl.h>
#include <err.h>

/*
 * Watch a directory and exit immediately once a new file is added.
 * Used by poudriere-daemon to watch for items added by poudriere-queue
 */
int
main(int argc, char **argv)
{
	struct kevent event, change;
	struct stat st;
	int kq, fd;

	if (argc != 2)
		errx(1, "Missing the directory argument");

	if (!(stat(argv[1], &st) == 0 && S_ISDIR(st.st_mode)))
		errx(1, "%s: not a directory", argv[1]);

	if ((kq = kqueue()) == -1)
		err(1, "kqueue()");

	fd = open(argv[1], O_RDONLY);

	EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_ONESHOT, NOTE_WRITE, 0, 0);

	if (kevent(kq, &change, 1, &event, 1, NULL) < 0)
		err(1, "kevent()");

	close(fd);

	return (0);
}
