/*-
 * Copyright (c) 2015 Bryan Drewery <bdrewery@FreeBSD.org>
 * Copyright (C) 1997 John D. Polstra.  All rights reserved.
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

/*
 * Wait until the directory specified can be created. Used for
 * locking shell functions. Based on lockf(1).
 */

#include <sys/param.h>
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifdef SHELL
#define main locked_mkdircmd
#include "bltin/bltin.h"
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#endif

static int lockfd = -1;
static volatile sig_atomic_t timed_out;

/*
 * Try to acquire a lock on the given file, creating the file if
 * necessary.  Returns an open file descriptor on success, or -1 on failure.
 */
static int
acquire_lock(const char *name)
{
	int fd;

	if ((fd = open(name, O_CREAT|O_RDONLY|O_EXLOCK, 0666)) == -1) {
		if (errno == EAGAIN || errno == EINTR)
			return (-1);
		err(EX_CANTCREAT, "cannot open %s", name);
	}
	return (fd);
}

/*
 * Remove the lock file.
 */
static void
cleanup(void)
{

	flock(lockfd, LOCK_UN);
}

/*
 * Signal handler for SIGALRM.
 */
static void
sig_timeout(int sig __unused)
{

	timed_out = 1;
}

int
main(int argc, char **argv)
{
	struct sigaction act;
	struct kevent event, change;
	struct timespec timeout;
	const char *path;
	char flock[MAXPATHLEN];
	int kq, fd, waitsec;

	if (argc != 3)
		errx(1, "Usage: <timeout> <directory>");

	waitsec = atoi(argv[1]);
	path = argv[2];

	act.sa_handler = sig_timeout;
	sigemptyset(&act.sa_mask);
	act.sa_flags = 0;	/* Note that we do not set SA_RESTART. */
	sigaction(SIGALRM, &act, NULL);
	alarm(waitsec);

	/* Open a file lock to serialize other locked_mkdir processes. */
	snprintf(flock, sizeof(flock), "%s.flock", path);

	while (lockfd == -1 && !timed_out)
		lockfd = acquire_lock(flock);
	waitsec = alarm(0);
	if (lockfd == -1)		/* We failed to acquire the lock. */
		return (EX_TEMPFAIL);

	/* At this point, we own the lock. */
	if (atexit(cleanup) == -1)
		err(EX_OSERR, "%s", "atexit failed");

	/* Try creating the directory. */
	fd = open(path, O_RDONLY);
	if (fd == -1 && errno == ENOENT) {
		if (mkdir(path, S_IRWXU) == 0)
			return (0);
		if (errno != EEXIST)
			err(1, "%s", "mkdir()");
	}

	/* Failed, the directory already exists. */

	timeout.tv_sec = waitsec;
	timeout.tv_nsec = 0;

	if ((kq = kqueue()) == -1)
		err(1, "%s", "kqueue()");

	EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE |
	    EV_ONESHOT, NOTE_DELETE, 0, 0);

#ifdef SHELL
	INTOFF;
#endif
	switch (kevent(kq, &change, 1, &event, 1, &timeout)) {
	    case -1:
		err(1, "%s", "kevent()");
		/* NOTREACHED */
	    case 0:
		/* Timeout */
		close(fd);
		return (1);
		/* NOTREACHED */
	    default:
		break;
	}
#ifdef SHELL
	INTON;
#endif
	close(fd);

	/* This is expected to succeed. */
	if (mkdir(path, S_IRWXU) != 0)
		err(1, "%s", "mkdir()");

	return (0);
}
