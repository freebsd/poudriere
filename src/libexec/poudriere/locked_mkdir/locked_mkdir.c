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
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifdef SHELL
#define main locked_mkdircmd
#include "bltin/bltin.h"
#include "helpers.h"
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#undef fclose
#undef fopen
#undef fprintf
#undef FILE
#endif

static int lockfd = -1;
static volatile sig_atomic_t timed_out;
static struct sigaction oact;
#ifdef SHELL
static struct sigaction oact_siginfo;
#endif

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
#ifdef SHELL
	int serrno;

	serrno = errno;
#endif
	if (lockfd != -1) {
		flock(lockfd, LOCK_UN);
		close(lockfd);
		lockfd = -1;
	}
#ifdef SHELL
	sigaction(SIGALRM, &oact, NULL);
	siginfo_pop(&oact_siginfo);
	errno = serrno;
#endif
}

/*
 * Write the given pid while holding the flock.
 */
static void
write_pid(const char *dirpath, pid_t writepid)
{
	FILE *f;
	char pidpath[MAXPATHLEN];

	if (writepid == -1)
		return;

	/* XXX: Could probably store this in the .flock file */
	snprintf(pidpath, sizeof(pidpath), "%s.pid", dirpath);
	if ((f = fopen(pidpath, "w")) == NULL) {
#ifdef SHELL
		cleanup();
		INTON;
#endif
		err(1, "%s", "fopen(pid)");
	}

	if (fprintf(f, "%u", writepid) < 0) {
#ifdef SHELL
		fclose(f);
		cleanup();
		INTON;
#endif
		err(1, "%s", "fprintf(pid)");
	}

	if (fclose(f) != 0) {
#ifdef SHELL
		cleanup();
		INTON;
#endif
		err(1, "%s", "fclose(pid)");
	}
}

static bool
stale_lock(const char *dirpath, pid_t *outpid)
{
	FILE *f;
	char pidpath[MAXPATHLEN], pidbuf[16];
	char *end;
	pid_t pid;
	bool stale;

	f = NULL;
	stale = true;
	pid = -1;
	/* XXX: Could probably store this in the .flock file */
	snprintf(pidpath, sizeof(pidpath), "%s.pid", dirpath);
	/* Missing file is considered stale. */
	if ((f = fopen(pidpath, "r")) == NULL)
		goto done;

	/* Read failure is fatal. */
	if (fgets(pidbuf, sizeof(pidbuf), f) == NULL) {
#ifdef SHELL
		fclose(f);
		cleanup();
		INTON;
#endif
		err(1, "%s", "fread(pid)");
	}

	/* Bad pid is considered stale. */
	errno = 0;
	pid = strtol(pidbuf, &end, 10);
	if (pid < 0 || *end != '\0' || errno != 0)
		goto done;

	/* Check if the process is still alive. */
	if (kill(pid, 0) == 0)
		stale = false;
done:
	if (stale) {
		/*
		 * This won't race with other locked_mkdir since we hold
		 * the flock.
		 */
		if (f != NULL)
			(void)unlink(pidpath);
		(void)rmdir(dirpath);
	}
	if (f != NULL)
		fclose(f);
	if (outpid != NULL)
		*outpid = pid;

	return (stale);
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
	struct kevent event[2];
	struct timespec timeout;
	const char *path;
	char *end;
	char flock[MAXPATHLEN];
	int kq, fd, waitsec, nevents;
	pid_t writepid, lockpid;
#ifdef SHELL
	int serrno;

	lockfd = -1;
	timed_out = 0;
	memset(&oact, sizeof(oact), 0);
	memset(&oact_siginfo, sizeof(oact_siginfo), 0);
#endif
	lockpid = -1;

	if (argc != 3 && argc != 4)
		errx(1, "Usage: <timeout> <directory> [pid]");

	waitsec = atoi(argv[1]);
	path = argv[2];
	if (argc == 4) {
		errno = 0;
		writepid = strtol(argv[3], &end, 10);
		if (writepid < 0 || *end != '\0' || errno != 0) {
			errx(1, "%s: bad process id", argv[3]);
		}
	} else
		writepid = -1;

#ifdef SHELL
	INTOFF;
	siginfo_push(&oact_siginfo);
#endif
	act.sa_handler = sig_timeout;
	sigemptyset(&act.sa_mask);
	act.sa_flags = 0;	/* Note that we do not set SA_RESTART. */
	sigaction(SIGALRM, &act, &oact);
	alarm(waitsec);

	/* Open a file lock to serialize other locked_mkdir processes. */
	snprintf(flock, sizeof(flock), "%s.flock", path);

	while (lockfd == -1 && !timed_out)
		lockfd = acquire_lock(flock);
	waitsec = alarm(0);
	if (lockfd == -1) {		/* We failed to acquire the lock. */
#ifdef SHELL
		cleanup();
		INTON;
#endif
		return (EX_TEMPFAIL);
	}

	/* At this point, we own the lock. */
#ifndef SHELL
	if (atexit(cleanup) == -1)
		err(EX_OSERR, "%s", "atexit failed");
#endif
retry:
	/* Try creating the directory. */
	fd = open(path, O_RDONLY);
	if (fd == -1 && errno == ENOENT) {
		if (mkdir(path, S_IRWXU) == 0) {
			write_pid(path, writepid);
#ifdef SHELL
			cleanup();
			INTON;
#endif
			return (0);
		}
		if (errno != EEXIST) {
#ifdef SHELL
			cleanup();
			INTON;
#endif
			err(1, "%s", "mkdir()");
		}
	}

	/* Failed, the directory already exists. */
	/* If a pid was given then check for a stale lock. */
	if (writepid != -1 && stale_lock(path, &lockpid))
		goto retry;

	timeout.tv_sec = waitsec;
	timeout.tv_nsec = 0;

	if ((kq = kqueue()) == -1) {
#ifdef SHELL
		serrno = errno;
		close(fd);
		cleanup();
		INTON;
		errno = serrno;
#endif
		err(1, "%s", "kqueue()");
	}

	nevents = 0;
	EV_SET(&event[nevents++], fd, EVFILT_VNODE, EV_ADD | EV_ENABLE |
	    EV_ONESHOT, NOTE_DELETE, 0, NULL);
	if (writepid != -1 && lockpid != -1) {
		EV_SET(&event[nevents++], lockpid, EVFILT_PROC,
		    EV_ADD | EV_ENABLE | EV_ONESHOT, NOTE_EXIT, 0, NULL);
	}

	switch (kevent(kq, (struct kevent *)&event, nevents,
	    (struct kevent *)&event, nevents, &timeout)) {
	    case -1:
#ifdef SHELL
		serrno = errno;
		close(kq);
		close(fd);
		cleanup();
		INTON;
		errno = serrno;
#endif
		err(1, "%s", "kevent()");
		/* NOTREACHED */
	    case 0:
		/* Timeout */
#ifdef SHELL
		close(kq);
		close(fd);
		cleanup();
		INTON;
#endif
		return (1);
		/* NOTREACHED */
	    default:
		break;
	}
#ifdef SHELL
	close(kq);
#endif
	close(fd);

	/* If the dir was deleted then we can recreate it. */
	if (event[0].filter == EVFILT_VNODE &&
	    /* This is expected to succeed. */
	    mkdir(path, S_IRWXU) != 0) {
#ifdef SHELL
		cleanup();
		INTON;
#endif
		err(1, "%s", "mkdir()");
	}

	write_pid(path, writepid);

#ifdef SHELL
	cleanup();
	INTON;
#endif
	return (0);
}
