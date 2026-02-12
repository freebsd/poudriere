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

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <sys/param.h>
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifndef HAVE_FUNLINKAT
#define funlinkat(dfd, path, fd, flag) unlinkat(dfd, path, flag)
#endif

#ifdef SHELL
#define main locked_mkdircmd
#include "bltin/bltin.h"
#include "helpers.h"
#include "trap.h"
#undef FILE	/* Avoid sh version */
#undef fprintf	/* Avoid sh version */
#endif

static int dirfd = -1;
static int lockfd = -1;
static volatile sig_atomic_t timed_out;
#ifdef SHELL
static int did_sigalrm;
#endif
static struct sigaction oact;
#ifdef SHELL
static struct sigdata oinfo;
#endif

static void cleanup(void);

/*
 * Try to acquire a lock on the given file, creating the file if
 * necessary.  Returns an open file descriptor on success, or -1 on failure.
 */
static int
acquire_lock(const int dirfd, const char *name)
{
	int fd;

	if ((fd = openat(dirfd, name,
	    O_CREAT | O_RDONLY | O_EXLOCK | O_CLOEXEC,
	    0666)) == -1) {
		if (errno == EAGAIN || errno == EINTR)
			return (-1);
#ifdef SHELL
		cleanup();
		INTON;
#endif
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
	if (dirfd != -1) {
		close(dirfd);
		dirfd = -1;
	}
	if (lockfd != -1) {
		flock(lockfd, LOCK_UN);
		close(lockfd);
		lockfd = -1;
	}
#ifdef SHELL
	if (did_sigalrm == 1) {
		alarm(0);
		sigaction(SIGALRM, &oact, NULL);
	}
	trap_pop(SIGINFO, &oinfo);
	errno = serrno;
#endif
}

/*
 * Write the given pid while holding the flock.
 */
static void
write_pid(const int dirfd, const char *lockdirpath, pid_t writepid)
{
	FILE *f;
	char pidpath[MAXPATHLEN];
	int fd, serrno;

	if (writepid == -1)
		return;
	/* XXX: Could probably store this in the .flock file */
	snprintf(pidpath, sizeof(pidpath), "%s.pid", lockdirpath);

	/* Protected by the flock */
	fd = openat(dirfd, pidpath,
	    O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NONBLOCK,
	    0666);
	if (fd == -1) {
		serrno = errno;
		(void)unlinkat(dirfd, pidpath, 0);
		(void)unlinkat(dirfd, lockdirpath, AT_REMOVEDIR);
#ifdef SHELL
		cleanup();
		INTON;
#endif
		errno = serrno;
		err(1, "openat(%s): %s", lockdirpath, pidpath);
	}
	if ((f = fdopen(fd, "w")) == NULL) {
		serrno = errno;
		close(fd);
		(void)funlinkat(dirfd, pidpath, fd, 0);
		(void)unlinkat(dirfd, lockdirpath, AT_REMOVEDIR);
#ifdef SHELL
		cleanup();
		INTON;
#endif
		errno = serrno;
		err(1, "fdopen: %s", pidpath);
	}

	if (fprintf(f, "%u\n", writepid) < 0) {
		serrno = errno;
		(void)funlinkat(dirfd, pidpath, fd, 0);
		(void)unlinkat(dirfd, lockdirpath, AT_REMOVEDIR);
#ifdef SHELL
		fclose(f);
		cleanup();
		INTON;
#endif
		errno = serrno;
		err(1, "%s", "fprintf(pid)");
	}

	if (fclose(f) != 0) {
		serrno = errno;
		(void)funlinkat(dirfd, pidpath, fd, 0);
		(void)unlinkat(dirfd, lockdirpath, AT_REMOVEDIR);
#ifdef SHELL
		cleanup();
		INTON;
#endif
		errno = serrno;
		err(1, "%s", "fclose(pid)");
	}
}

static bool
stale_lock(const int dirfd, const char *lockdirpath, pid_t *outpid)
{
	FILE *f;
	char pidpath[MAXPATHLEN], pidbuf[16];
	char *end;
	size_t pidlen;
	pid_t pid;
	bool stale;
	int fd;

	f = NULL;
	stale = true;
	pid = -1;
	/* XXX: Could probably store this in the .flock file */
	snprintf(pidpath, sizeof(pidpath), "%s.pid", lockdirpath);
	/* Missing file is considered stale. */
	fd = openat(dirfd, pidpath, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
	if (fd == -1)
		goto done;
	if ((f = fdopen(fd, "r")) == NULL) {
		close(fd);
		goto done;
	}

	/* Read failure is fatal. */
	if (fgets(pidbuf, sizeof(pidbuf), f) == NULL) {
#ifdef SHELL
		fclose(f);
		cleanup();
		INTON;
#endif
		err(1, "%s", "fread(pid)");
	}
	pidlen = strlen(pidbuf);
	if (pidbuf[pidlen - 1] == '\n')
		pidbuf[--pidlen] = '\0';
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
			(void)funlinkat(dirfd, pidpath, fd, 0);
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
	const char *lockdirpath, *dirpath;
	char *end;
	char pathbuf[MAXPATHLEN], dirbuf[MAXPATHLEN], basebuf[MAXPATHLEN];
	int kq, lockdirfd, waitsec, nevents;
	pid_t writepid, lockpid;
#ifdef SHELL
	int ret, serrno, sig;

	dirfd = -1;
	lockfd = -1;
	timed_out = 0;
	did_sigalrm = 0;
#endif
	lockdirfd = -1;
	lockpid = -1;

	if (argc != 3 && argc != 4)
		errx(1, "Usage: <timeout> <directory> [pid]");

	waitsec = atoi(argv[1]);
	lockdirpath = argv[2];

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
	trap_push(SIGINFO, &oinfo);
#endif
	strlcpy(dirbuf, lockdirpath, sizeof(dirbuf));
	dirpath = dirname(dirbuf);
	dirfd = open(dirpath, O_RDONLY | O_DIRECTORY);
	if (dirfd == -1) {
#ifdef SHELL
		serrno = errno;
		cleanup();
		INTON;
		errno = serrno;
#endif
		err(1, "%s", "opendir");
	}
	strlcpy(basebuf, lockdirpath, sizeof(basebuf));
	lockdirpath = basename(basebuf);

	act.sa_handler = sig_timeout;
	sigemptyset(&act.sa_mask);
	act.sa_flags = 0;	/* Note that we do not set SA_RESTART. */
#ifdef SHELL
	did_sigalrm = 1;
#endif
	sigaction(SIGALRM, &act, &oact);
	alarm(waitsec);

	/* Open a file lock to serialize other locked_mkdir processes. */
	snprintf(pathbuf, sizeof(pathbuf), "%s.flock", lockdirpath);

	while (lockfd == -1 && !timed_out)
		lockfd = acquire_lock(dirfd, pathbuf);
	waitsec = alarm(0);
#ifdef SHELL
	sigaction(SIGALRM, &oact, NULL);
	did_sigalrm = 0;
#endif
	if (lockfd == -1) {		/* We failed to acquire the lock. */
#ifdef SHELL
		cleanup();
		INTON;
#endif
		if (timed_out)
			return (124);
		else
			return (EX_TEMPFAIL);
	}

	/* At this point, we own the lock. */
#ifndef SHELL
	if (atexit(cleanup) == -1)
		err(EX_OSERR, "%s", "atexit failed");
#endif
retry:
	/* Try creating the directory. */
	if (mkdirat(dirfd, lockdirpath, S_IRWXU) == 0)
		goto success;
	else if (errno != EEXIST) {
#ifdef SHELL
		cleanup();
		INTON;
#endif
		err(EX_CANTCREAT, "mkdirat(%s): %s", dirpath, lockdirpath);
	}

	/* Failed, the directory already exists. */
	/* If a pid was given then check for a stale lock. */
	if (writepid != -1 && stale_lock(dirfd, lockdirpath, &lockpid)) {
		/* The last owner is gone. Take ownership. */
		goto success;
	}

	lockdirfd = openat(dirfd, lockdirpath,
	    O_RDONLY | O_CLOEXEC | O_NONBLOCK);
	/* It was deleted while we did a stale check */
	if (lockdirfd == -1 && errno == ENOENT)
		goto retry;
	else if (lockdirfd == -1) {
#ifdef SHELL
		cleanup();
		INTON;
#endif
		err(1, "openat(%s): %s", dirpath, lockdirpath);
	}

	timeout.tv_sec = waitsec;
	timeout.tv_nsec = 0;

	if ((kq = kqueue()) == -1) {
#ifdef SHELL
		serrno = errno;
		close(lockdirfd);
		cleanup();
		INTON;
		errno = serrno;
#endif
		err(1, "%s", "kqueue()");
	}

	nevents = 0;
	EV_SET(&event[nevents++], lockdirfd, EVFILT_VNODE, EV_ADD | EV_ENABLE |
	    EV_ONESHOT, NOTE_DELETE, 0, NULL);
	if (writepid != -1 && lockpid != -1) {
		EV_SET(&event[nevents++], lockpid, EVFILT_PROC,
		    EV_ADD | EV_ENABLE | EV_ONESHOT, NOTE_EXIT, 0, NULL);
	}

#ifdef SHELL
retry_kevent:
#endif
	switch (kevent(kq, (struct kevent *)&event, nevents,
	    (struct kevent *)&event, nevents, &timeout)) {
	    case -1:
#ifdef SHELL
		serrno = errno;
		if ((timeout.tv_nsec > 0 || timeout.tv_nsec > 0) &&
		    serrno == EINTR) {
			sig = pendingsig;
			if (sig == 0) {
				goto retry_kevent;
			}
			ret = 128 + sig;
		} else {
			ret = EX_OSERR;
		}
		close(kq);
		close(lockdirfd);
		cleanup();
		INTON;
		errno = serrno;
		if (errno == EINTR) {
			exit(ret);
		} else {
			err(ret, "kevent");
		}
#else
		err(EX_OSERR, "%s", "kevent");
#endif
		/* NOTREACHED */
	    case 0:
		/* Timeout */
#ifdef SHELL
		close(kq);
		close(lockdirfd);
		cleanup();
		INTON;
#endif
		return (124);
		/* NOTREACHED */
	    default:
		break;
	}
#ifdef SHELL
	close(kq);
#endif

	/* If the dir was deleted then we can recreate it. */
	if (event[0].filter == EVFILT_VNODE &&
	    /* This is expected to succeed. */
	    mkdirat(dirfd, lockdirpath, S_IRWXU) != 0) {
#ifdef SHELL
		serrno = errno;
		close(lockdirfd);
		cleanup();
		INTON;
		errno = serrno;
#endif
		err(1, "mkdirat(%s): %s", dirpath, lockdirpath);
	}
success:
	if (lockdirfd != -1)
		close(lockdirfd);
	write_pid(dirfd, lockdirpath, writepid);

#ifdef SHELL
	cleanup();
	INTON;
#endif
	return (0);
}
