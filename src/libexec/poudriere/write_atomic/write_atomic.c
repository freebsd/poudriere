/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
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
#include <sys/stat.h>
#include <sys/uio.h>

#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#define BUF_SIZ 8192

#ifdef SHELL
#define main write_atomiccmd
#include "bltin/bltin.h"
#include "helpers.h"
#include "var.h"
#endif

int
mkostempsat_mode(int dfd, char *path, int slen, int oflags, mode_t mode);

/*
 * Compare destination file with temporary file to determine if overwrite
 * needed.
 * Parameters:
 *   file_existing/fd_existing: existing file on disk (may not exist).
 *   file_new/fd_new: newly created temporary file with content to write.
 * Returns:
 *   1 = files identical, skip overwrite.
 *   0 = files differ, proceed with overwrite.
 *  -1 = error during comparison.
 */
static int
file_cmp_overwrite(const int dirfd,
    const char *file_existing, int fd_existing,
    const char *file_new, int fd_new)
{
	struct stat st_existing, st_new;
	int ret;
	bool opened_existing, opened_new;

	opened_existing = opened_new = false;
	if (fd_existing == -1) {
		fd_existing = openat(dirfd, file_existing,
		    O_RDONLY | O_CLOEXEC);
		/* If the file does not exist then it is safe to replace it. */
		if (fd_existing < 0) {
			ret = 0;
			goto done;
		}
		opened_existing = true;
	}
	if (fstat(fd_existing, &st_existing) != 0) {
		ret = -1;
		goto done;
	}
	if (fd_new == -1) {
		fd_new = openat(dirfd, file_new,
		    O_RDONLY | O_CLOEXEC);
		if (fd_new < 0) {
			warn("open %s", file_new);
			ret = -1;
			goto done;
		}
		opened_new = true;
	}
	if (fstat(fd_new, &st_new) != 0) {
		warn("fstat %s", file_new);
		ret = -1;
		goto done;
	}
	if (st_existing.st_size != st_new.st_size) {
		ret = 0;
		goto done;
	}
	char buf_existing[BUF_SIZ], buf_new[BUF_SIZ];
	ssize_t len_existing, len_new;

	len_existing = len_new = -1;
	ret = 1;
	while ((len_existing = read(fd_existing, buf_existing,
	    sizeof(buf_existing))) > 0) {
		len_new = read(fd_new, buf_new, len_existing);
		if (len_new < 0) {
			warn("read %s", file_new);
			ret = -1;
			break;
		}
		if (len_new != len_existing ||
		    memcmp(buf_existing, buf_new, len_existing) != 0) {
			ret = 0;
			break;
		}
	}
	if (len_existing < 0) {
		warn("read %s", file_existing);
		ret = -1;
	}
done:
	if (opened_existing && fd_existing != -1) {
		close(fd_existing);
	}
	if (opened_new && fd_new != -1) {
		close(fd_new);
	}
	return (ret);
}

static void
usage(void)
{
	fprintf(stderr, "usage: write_atomic [-C] [-f] [-n] [-N] [-T] destfile "
	    "{< data | data...}\n");
	exit(EX_USAGE);
}

static inline int
do_outputv(const int Tflag, const int tmpfd, const struct iovec *iov,
    const int iovcnt)
{
	if (writev(tmpfd, iov, iovcnt) < 0) {
		warn("tmpfile write");
		return (1);
	}
	if (Tflag) {
		if (writev(STDOUT_FILENO, iov, iovcnt) < 0) {
			warn("stdout write");
			return (1);
		}
	}
	return (0);
}

/*
 * write_atomic [-C] [-n] [-N] [-T] destfile [data...]
 *   -C = compare existing destfile with data and skip rewrite if same.
 *        Note that comparison has a race between comparing and replacing.
 *   -f = fsync
 *   -n = no newline (when data specified as arguments)
 *   -N = noclobber
 *   -T = tee data to stdout
 * Data may be passed via arguments or stdin.
 */
int
main(int argc, char *argv[])
{
	const char *destpath, *destfile, *destdir;
	char dirname_buf[PATH_MAX], tmpfile[PATH_MAX];
	int opt, Cflag, fflag, nflag, Nflag, Tflag, dirfd, ret, tmpfd;

	if (argc < 2)
		usage();

	Cflag = fflag = nflag = Nflag = Tflag = 0;
	ret = 1;
	dirfd = tmpfd = -1;
	tmpfile[0] = '\0';
	if (getenv("NOCLOBBER") != NULL) {
		Nflag = 1;
	}
	while ((opt = getopt(argc, argv, "CfnNT")) != -1) {
		switch (opt) {
		case 'C':
			Cflag = 1;
			break;
		case 'f':
			fflag = 1;
			break;
		case 'n':
			nflag = 1;
			break;
		case 'N':
			Nflag = 1;
			break;
		case 'T':
			Tflag = 1;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;

	destpath = argv[0];
	argv++;
	argc--;

	strlcpy(dirname_buf, destpath, sizeof(dirname_buf));
	destdir = dirname(dirname_buf);
	dirfd = open(destdir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	if (dirfd == -1) {
		warn("open %s", destdir);
		goto done;
	}
	destfile = strrchr(destpath, '/');
	if (destfile == NULL)
		destfile = destpath;
	else
		++destfile;
	snprintf(tmpfile, sizeof(tmpfile), ".write_atomic-%s.XXXXXXXXXX",
	    destfile);
#if 0
	tmpfd = mkostempsat(dirfd, tmpfile, 0, O_CLOEXEC);
	if (tmpfd < 0) {
		warn("mkstemp");
		goto done;
	}
	/* We want readable with umask respected. */
	mode_t mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
	mode_t mask = umask(0);
	umask(mask);
	mode &= ~mask;
	if (fchmod(tmpfd, mode) != 0) {
		warn("fchmod");
		goto done;
	}
#else
	/*
	 * Use a custom mkostempat(3) that takes a mode argument which
	 * saves 3 extra syscalls compared to the idiomatic version above.
	 */
	tmpfd = mkostempsat_mode(dirfd, tmpfile, 0, O_CLOEXEC,
	    0644);
	if (tmpfd < 0) {
		warn("mkstemp");
		goto done;
	}
#endif
	if (argc > 0) {
		/* iovcnt = 2*argc (space + data per arg) + optional newline */
		struct iovec iov[argc * 2 + 1];
		int iovcnt = 0;

		for (int argn = 0; argn < argc; argn++) {
			if (argn > 0) {
				iov[iovcnt].iov_base = " ";
				iov[iovcnt].iov_len = 1;
				iovcnt++;
			}
			iov[iovcnt].iov_base = argv[argn];
			iov[iovcnt].iov_len = strlen(argv[argn]);
			iovcnt++;
		}
		if (nflag == 0) {
			iov[iovcnt].iov_base = "\n";
			iov[iovcnt].iov_len = 1;
			iovcnt++;
		}
		if (do_outputv(Tflag, tmpfd, iov, iovcnt) != 0) {
			goto done;
		}
	} else {
		struct iovec iov[1];
		char buf[BUF_SIZ];
		ssize_t n;

		while ((n = read(STDIN_FILENO, buf, sizeof(buf))) > 0) {
			iov[0].iov_base = buf;
			iov[0].iov_len = n;
			if (do_outputv(Tflag, tmpfd, iov, 1) != 0) {
				goto done;
			}
		}
		if (n < 0) {
			warn("stdin read");
			goto done;
		}
	}
	/*
	 * With noclobber we can only succeed if there is no file
	 * so no need to compare.
	 */
	if (Cflag && !Nflag) {
		if (lseek(tmpfd, 0, SEEK_SET) != 0) {
			warn("lseek %s", tmpfile);
			goto done;
		}
		switch (file_cmp_overwrite(dirfd, destfile, -1, tmpfile,
		    tmpfd)) {
		case -1:
			warnx("file_cmp_overwrite %s/%s -> %s",
			    destdir, tmpfile, destpath);
			goto done;
		case 0:
			/* File differs. */
			break;
		case 1:
			/* File is the same. */
			ret = 0;
			goto done;
		}
	}
	if (fflag) {
		if (fsync(tmpfd) != 0) {
			warn("fsync %s", tmpfile);
			goto done;
		}
	}
	close(tmpfd);
	tmpfd = -1;
	if (Nflag) {
		if (linkat(dirfd, tmpfile, dirfd, destfile, 0) != 0) {
			warn("%s", destpath);
			goto done;
		}
		ret = 0;
		/* The tmpfile will be unlinked. */
		goto done;
	} else if (renameat(dirfd, tmpfile, dirfd, destfile) != 0) {
		warn("rename %s -> %s", tmpfile, destpath);
		goto done;
	}
	if (fflag) {
		if (fsync(dirfd) != 0) {
			warn("fsync %s", destdir);
			goto done;
		}
	}
	tmpfile[0] = '\0';
	ret = 0;
done:
	if (dirfd != -1) {
		if (tmpfile[0] != '\0') {
			if (unlinkat(dirfd, tmpfile, 0) != 0) {
				ret++;
				warn("unlink %s", tmpfile);
			}
		}
		close(dirfd);
	}
	if (tmpfd != -1) {
		close(tmpfd);
	}
	return (ret);
}
