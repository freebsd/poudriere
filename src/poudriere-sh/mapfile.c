/*-
 * Copyright (c) 2018 Bryan Drewery <bdrewery@FreeBSD.org>
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

#include <sys/param.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>

#include <assert.h>
#include <err.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#define _WITH_GETLINE
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>

#ifndef SHELL
#error Only supported as a builtin
#endif

#ifdef DEBUG
#define debug(...) do { \
	fprintf(stderr, __VA_ARGS__); \
	flushout(stderr); \
} while (0);
#else
#define debug(...)
#endif

#include "bltin/bltin.h"
#include "helpers.h"
#undef FILE	/* Avoid sh version */
#undef fwrite	/* Avoid sh version */
#undef fputc	/* Avoid sh version */
#include "eval.h"
#include "redir.h"
#include "trap.h"
#include "var.h"

extern int loopnest;
extern int funcnest;

#define MAX_FILES 256
struct mapped_data {
	FILE *fp;
	char *file;
	int handle;
	int fd0_redirected;
	int pid;
};
static struct mapped_data *mapped_files[MAX_FILES] = {0};

static int
_mapfile_read(struct mapped_data *md, char **linep, ssize_t *linelenp,
    struct timeval *tvp);
static int
_mapfile_readcmd(struct mapped_data *md, int argc, char **argv);

static void
md_close(struct mapped_data *md)
{
	int idx;

	debug("%d: Closing %s handle '%d'\n", getpid(),
	    md->file, md->handle);
	assert(is_int_on());

	idx = md->handle;
	md->handle = -1;
	free(md->file);
	md->file = NULL;
	if (md->fp != NULL) {
		if (fileno(md->fp) == STDIN_FILENO ||
		    fileno(md->fp) == STDOUT_FILENO ||
		    fileno(md->fp) == STDERR_FILENO) {
			fdclose(md->fp, NULL);
		} else {
			fclose(md->fp);
		}
		md->fp = NULL;
	}
	free(mapped_files[idx]);
	mapped_files[idx] = NULL;
}

static struct mapped_data*
md_find(const char *handle)
{
	struct mapped_data *md;
	int idx;
	char *end;

	assert(is_int_on());
	errno = 0;
	if (handle == NULL || *handle == '\0')
		errx(EX_DATAERR, "%s", "Missing handle");
	idx = strtod(handle, &end);
	if (end == handle || errno == ERANGE || idx < 0 || idx >= MAX_FILES)
		errx(EX_DATAERR, "Invalid handle '%s'", handle);
	md = mapped_files[idx];
	if (md == NULL || md->handle != idx)
		errx(EBADF, "Invalid handle '%s'", handle);
	if (md->fp == NULL)
		errx(EBADF, "handle '%s' is not opened", handle);
	return (md);
}

extern int fd0_redirected;

static struct mapped_data *
_mapfile_open(const char *file, const char *modes, int Fflag, int qflag)
{
	FILE *fp;
	struct mapped_data *md;
#if 0
	struct stat sb;
#endif
	const char *p;
	char *dupp;
	char dupmodes[7];
	int nextidx, idx, serrno, cmd, newfd;

	fp = NULL;
	nextidx = -1;
	for (idx = 0; idx < MAX_FILES; idx++) {
		if (mapped_files[idx] == NULL) {
			nextidx = idx;
			break;
		}
	}
	if (nextidx == -1 || mapped_files[nextidx] != NULL) {
		INTON;
		errx(EX_SOFTWARE, "%s", "mapped files stack exceeded");
	}

	if (strchr(modes, 'B') && !(strchr(modes, 'w') || strchr(modes, '+') ||
	    strchr(modes, 'a'))) {
	    INTON;
	    errx(EX_USAGE, "%s", "using 'B' without writing makes no sense");
	}

	if (strcmp(file, "-") == 0 ||
	    strcmp(file, "/dev/stdin") == 0 ||
	    strcmp(file, "/dev/fd/0") == 0) {
		if ((fp = fdopen(STDIN_FILENO, modes)) == NULL) {
			serrno = errno;
			errno = serrno;
			if (!qflag) {
				INTON;
				err(EX_NOINPUT, "%s: %s", "fopen", file);
			} else {
				return (NULL);
			}
		}
	} else if (strcmp(file, "/dev/stdout") == 0 ||
	    strcmp(file, "/dev/fd/1") == 0) {
		if ((fp = fdopen(STDOUT_FILENO, modes)) == NULL) {
			serrno = errno;
			errno = serrno;
			if (!qflag) {
				INTON;
				err(EX_NOINPUT, "%s: %s", "fopen", file);
			} else {
				return (NULL);
			}
		}
	} else if (strcmp(file, "/dev/stderr") == 0 ||
	    strcmp(file, "/dev/fd/2") == 0) {
		if ((fp = fdopen(STDERR_FILENO, modes)) == NULL) {
			serrno = errno;
			errno = serrno;
			if (!qflag) {
				INTON;
				err(EX_NOINPUT, "%s: %s", "fopen", file);
			} else {
				return (NULL);
			}
		}
	} else {
		if ((fp = fopen(file, modes)) == NULL) {
			serrno = errno;
			errno = serrno;
			if (!qflag) {
				INTON;
				err(EX_NOINPUT, "%s: %s", "fopen", file);
			} else {
				return (NULL);
			}
		}
#if 0
		if (fstat(fileno(fp), &sb) != 0) {
			serrno = errno;
			fclose(fp);
			INTON;
			errno = serrno;
			err(EX_OSERR, "%s", "fstat");
		}
		if (!(S_ISFIFO(sb.st_mode) || S_ISREG(sb.st_mode) ||
		    S_ISCHR(sb.st_mode))) {
			serrno = errno;
			fclose(fp);
			INTON;
			errno = serrno;
			errx(EX_DATAERR, "%s not a regular file or FIFO",
			    file);
		}
#endif
		if (!Fflag) {
			/* sh has <=10 reserved. */
			if (fileno(fp) < 10) {
				cmd = -1;
				dupp = dupmodes;
				for (p = modes; *p; p++) {
					if (*p == 'e') {
						cmd = F_DUPFD_CLOEXEC;
						continue;
					}
					*dupp++ = *p;
				}
				*dupp = '\0';
				if (cmd == -1)
					cmd = F_DUPFD;

				if ((newfd = fcntl(fileno(fp), cmd, 10)) == -1) {
					serrno = errno;
					fclose(fp);
					INTON;
					errno = serrno;
					err(EX_NOINPUT, "%s", "fcntl");
				}
				assert(newfd >= 10);
				(void)fclose(fp);
				if ((fp = fdopen(newfd, dupmodes)) == NULL) {
					serrno = errno;
					INTON;
					errno = serrno;
					err(EX_NOINPUT, "%s", "fdopen");
				}
			}
		}
	}
	md = calloc(1, sizeof(*md));
	md->fp = fp;
	md->file = strdup(file);
	md->handle = nextidx;
	if (strchr(modes, 'B') == NULL) {
		setlinebuf(md->fp);
	}

	mapped_files[md->handle] = md;
	return (md);
}

int
mapfilecmd(int argc, char **argv)
{
	static const char usage[] = "Usage: mapfile [-q] <handle_name> "
	    "<file> [modes]";
	struct mapped_data *md;
	const char *file, *var_return, *modes;
	char handle[32];
	int ch, qflag, Fflag, ret;

	ret = 0;
	Fflag = qflag = 0;
	while ((ch = getopt(argc, argv, "Fq")) != -1) {
		switch (ch) {
		case 'F':
			/* "fast" - avoid some unneeded protections. */
			Fflag = 1;
			break;
		case 'q':
			qflag = 1;
			break;
		default:
			errx(EX_USAGE, "%s", usage);
		}
	}
	argc -= optind;
	argv += optind;

	if (argc != 2 && argc != 3)
		errx(EX_USAGE, "%s", usage);
	INTOFF;

	var_return = argv[0];
	file = argv[1];

	if (argc == 3)
		modes = argv[2];
	else
		modes = "re";

	md = _mapfile_open(file, modes, Fflag, qflag);
	if (qflag) {
		assert(is_int_on());
	}
	if ((md == NULL) && qflag) {
		ret = EX_NOINPUT;
		goto done;
	}
	assert(md != NULL);

	snprintf(handle, sizeof(handle), "%d", md->handle);
	if (setvarsafe(var_return, handle, 0)) {
		md_close(md);
		ret = 1;
		goto done;
	}
	debug("%d: Mapped %s to handle '%s' modes '%s'\n", getpid(),
	    md->file, handle, modes);
done:
	INTON;

	return (ret);
}

int
mapfile_readcmd(int argc, char **argv)
{
	static const char usage[] = "Usage: mapfile_read <handle> "
	    "[-t timeout] <output_var> ...";
	struct mapped_data *md;
	const char *handle;

	if (argc < 2)
		errx(EX_USAGE, "%s", usage);

	handle = argv[1];
	optind = 2;

	INTOFF;
	md = md_find(handle);
	INTON;
	return (_mapfile_readcmd(md, argc, argv));
}

static int
_mapfile_readcmd(struct mapped_data *md, int argc, char **argv)
{
	static const char usage[] = "Usage: mapfile_read <handle> "
	    "[-t timeout] <output_var> ...";
	struct timeval tv = {};
	char **var_return_ptr;
	char *end, *line, *linep, *ifsp;
	const char *ifs;
	ssize_t linelen;
	double timeout;
	int ch, ret, tflag;

	ifs = NULL;
	timeout = 0;
	tflag = 0;

	assert(optind == 2);
	while ((ch = getopt(argc, argv, "I:t:")) != -1) {
		switch (ch) {
		case 'I':
			ifs = optarg;
			break;
		case 't':
			tflag = 1;
			timeout = strtod(optarg, &end);
			if (end == optarg || errno == ERANGE ||
			    timeout < 0)
				errx(EX_DATAERR, "timeout value");
			switch(*end) {
			case 0:
			case 's':
				break;
			case 'h':
				timeout *= 60;
				/* FALLTHROUGH */
			case 'm':
				timeout *= 60;
				break;
			default:
				errx(EX_DATAERR, "timeout unit");
			}
			if (timeout > 100000000L)
				errx(EX_DATAERR, "timeout value");
			tv.tv_sec = (time_t)timeout;
			timeout -= (time_t)timeout;
			tv.tv_usec =
			    (suseconds_t)(timeout * 1000000UL);
			break;
		default:
			errx(EX_USAGE, "%s", usage);
		}
	}
	argc -= optind;
	argv += optind;

	if (argc < 1)
		errx(EX_USAGE, "%s", usage);

	INTOFF;
	var_return_ptr = &argv[0];
	debug("%d: Reading %s handle '%d' timeout: %0.6f feof: %d "
	    "ferror: %d\n",
	    getpid(), md->file, md->handle, tv.tv_sec + tv.tv_usec / 1e6,
	    feof(md->fp), ferror(md->fp));

	ret = _mapfile_read(md, &line, &linelen, tflag ? &tv : NULL);
	linep = line;

	if (ifs == NULL && (ifs = getenv("IFS")) == NULL)
		ifs = " \t\n";
	ifsp = NULL;
	while (linelen != -1 && linep - line < linelen) {
		if (ifs[0] != '\0') {
			/* Trim leading IFS chars. */
			while (*linep != '\0' && strchr(ifs, *linep) != NULL)
				++linep;
			if (*linep == '\0')
				break;
			/* Find the next IFS char to tokenize at. */
			ifsp = linep + 1;
			while (*ifsp != '\0' && strchr(ifs, *ifsp) == NULL)
				++ifsp;
		}
		if (*(var_return_ptr + 1) != NULL && ifsp != NULL) {
			*ifsp++ = '\0';
			if (setvarsafe(*var_return_ptr++, linep, 0)) {
				ret = 1;
				goto done;
			}
			linep = ifsp;
		} else {
			/* No more vars/words, set the rest in the last var. */
			/* Trim trailing IFS chars. */
			if (ifs[0] != '\0' && ifsp != NULL) {
				/* Fixup linelen to the current length. */
				linelen -= linep - line;
				while (linelen > 0 &&
				    strchr(ifs, linep[linelen - 1]) != NULL)
					--linelen;
				linep[linelen] = '\0';
			}
			if (setvarsafe(*var_return_ptr++, linep, 0)) {
				ret = 1;
				goto done;
			}
			break;
		}
	}

	/* Set any remaining args to "" */
	while (*var_return_ptr != NULL) {
		if (unsetvar(*var_return_ptr++)) {
			goto done;
		}
	}
done:
	INTON;

	return (ret);
}

/*
 * Cache recently used handles.
 * Hack for not using a hash table.
 */
static int read_loop_handles[5] = {-1, -1, -1, -1, -1};

static bool
read_loop_check_file(struct mapped_data *md, const char *file)
{
	if (strcmp(md->file, file) == 0) {
		return (true);
	}
	return (false);
}

static bool
read_loop_check_stdin(struct mapped_data *md, const char *arg __unused)
{
	if (fileno(md->fp) != STDIN_FILENO) {
		return (false);
	}
	if (md->fd0_redirected != fd0_redirected) {
		return (false);
	}
	return (true);
}

static struct mapped_data *
read_loop_find(bool (*function)(struct mapped_data *, const char *),
    const char *arg)
{
	struct mapped_data* md;

	for (int i = 0; i < nitems(read_loop_handles); i++) {
		if (read_loop_handles[i] == -1) {
			continue;
		}
		md = mapped_files[read_loop_handles[i]];
		assert(md != NULL);
		assert(md->handle != -1);
		if (md->pid != shpid) {
			continue;
		}
		if (function(md, arg)) {
			return (md);
		}
	}
	md = NULL;

	for (int i = 0; i < MAX_FILES; i++) {
		md = mapped_files[i];
		if (md == NULL) {
			continue;
		}
		if (md->handle == -1) {
			continue;
		}
		if (md->pid != shpid) {
			continue;
		}
		if (function(md, arg)) {
			break;
		}
	}
	if (md != NULL) {
		for (int i = 0; i < nitems(read_loop_handles); i++) {
			if (read_loop_handles[i] == -1) {
				read_loop_handles[i] = md->handle;
				break;
			}
		}
	}
	return (md);
}


void
mapfile_read_loop_close_stdin(void)
{
	struct mapped_data* md;
	int i;

	md = NULL;
	i = -1;
	for (i = 0; i < nitems(read_loop_handles); i++) {
		if (read_loop_handles[i] == -1) {
			continue;
		}
		if (mapped_files[i] == NULL) {
			continue;
		}
		if (mapped_files[i]->pid != shpid) {
			continue;
		}
		if (read_loop_check_stdin(mapped_files[i], NULL)) {
			md = mapped_files[i];
			break;
		}
	}
	if (md == NULL) {
		return;
	}
#ifndef NDEBUG
	md = read_loop_find(read_loop_check_stdin, NULL);
	assert(md != NULL);
	assert(md->handle != -1);
	assert(read_loop_handles[i] == md->handle);
#endif
	assert(md->fd0_redirected == fd0_redirected);
	assert(md->pid == shpid);
	read_loop_handles[i] = -1;
	md_close(md);
}

int
mapfile_read_loopcmd(int argc, char **argv)
{
	static const char usage[] = "Usage: mapfile_read_loop <file> "
	    "[mapfile_read -flags] <vars>";
	struct mapped_data *md;
	const char *file;
	int error;

	if (argc < 2)
		errx(EX_USAGE, "%s", usage);

	file = argv[1];
	optind = 2;

	INTOFF;
	if (strcmp(file, "-") == 0 ||
	    strcmp(file, "/dev/stdin") == 0 ||
	    strcmp(file, "/dev/fd/0") == 0) {
		md = read_loop_find(read_loop_check_stdin, NULL);
	} else {
		md = read_loop_find(read_loop_check_file, file);
	}
	if (md == NULL) {
		/* Create handle */
		md = _mapfile_open(file, "r", 0, 0);
		assert(md != NULL);
		md->fd0_redirected = fd0_redirected;
		md->pid = shpid;
		for (int i = 0; i < nitems(read_loop_handles); i++) {
			if (read_loop_handles[i] == -1) {
				read_loop_handles[i] = md->handle;
				break;
			}
		}
	}
	INTON;
	error = _mapfile_readcmd(md, argc, argv);
	if (error != 0) {
		INTOFF;
		for (int i = 0; i < nitems(read_loop_handles); i++) {
			if (read_loop_handles[i] == md->handle) {
				read_loop_handles[i] = -1;
				break;
			}
		}
		md_close(md);
		INTON;
	}
	return (error);
}

static int
_mapfile_cat(struct mapped_data *md)
{
	char *line;
	ssize_t linelen;
	int rret, ret;

	assert(is_int_on());
	ret = 0;
	while ((rret = _mapfile_read(md, &line, &linelen, NULL)) == 0) {
		INTON;
		outbin(line, linelen, out1);
		out1c('\n');
		INTOFF;
	}
	/* 1 == EOF */
	if (rret != 1) {
		ret = rret;
	}
	return (ret);
}

int
mapfile_catcmd(int argc, char **argv)
{
	static const char usage[] = "Usage: mapfile_cat <handle> ...";
	struct mapped_data *md;
	const char *handle;
	int i, error, ret;

	if (argc < 2)
		errx(EX_USAGE, "%s", usage);

	error = 0;
	ret = 0;
	for (i = 1; i < argc; i++) {
		handle = argv[i];
		INTOFF;
		md = md_find(handle);
		if ((error = _mapfile_cat(md)) != 0) {
			ret = error;
		}
		assert(is_int_on());
		INTON;
	}

	return (ret);
}

int
mapfile_cat_filecmd(int argc, char **argv)
{
	static const char usage[] = "Usage: mapfile_cat_file [-q] <file> ...";
	struct mapped_data *md;
	const char *file;
	int error, ret;
	int i, ch, qflag;

	qflag = 0;
	while ((ch = getopt(argc, argv, "q")) != -1) {
		switch (ch) {
		case 'q':
			qflag = 1;
			break;
		default:
			errx(EX_USAGE, "%s", usage);
		}
	}
	argc -= optind;
	argv += optind;

	if (argc < 1)
		errx(EX_USAGE, "%s", usage);

	ret = 0;
	for (i = 0; i < argc; i++) {
		file = argv[i];
		INTOFF;
		/* Create handle */
		md = _mapfile_open(file, "r", 1, qflag);
		if ((md == NULL) && qflag) {
			ret = 1;
			INTON;
			continue;
		}
		assert(md != NULL);
		if ((error = _mapfile_cat(md)) != 0) {
			ret = error;
		}
		assert(is_int_on());
		md_close(md);
		INTON;
	}
	return (ret);
}


static int
_mapfile_read(struct mapped_data *md, char **linep, ssize_t *linelenp,
    struct timeval *tvp)
{
	struct timeval tv = {};
	fd_set ifds;
	ssize_t linelen;
	int flags, ret, serrno, sig;
	/* Avoid remallocing every call */
	static char *line = NULL;
	/* Start a bit larger to avoid needing reallocs in children. */
	static size_t linecap = 4096;

	assert(is_int_on());
	/* Copying here just to avoid expected future merge conflicts. */
	if (tvp != NULL) {
		tv.tv_sec = tvp->tv_sec;
		tv.tv_usec = tvp->tv_usec;
	}
	const char *handle = md->file;

	/* Malloc once per sh process.  getline(3) may grow it. */
	if (line == NULL) {
	    line = malloc(linecap);
	    if (line == NULL) {
		    INTON;
		    err(EX_TEMPFAIL, "malloc");
	    }
	}

	linelen = -1;
	flags = 0;
	ret = 0;
	if (tvp != NULL) {
		flags = fcntl(fileno(md->fp), F_GETFL, 0);
		flags |= O_NONBLOCK;
		if (fcntl(fileno(md->fp), F_SETFL, flags) < 0) {
			ret = EX_IOERR;
			flags &= ~O_NONBLOCK;
			warn("fcntl(%s, F_SETFL, O_NONBLOCK)", handle);
			goto out;
		}
	}
	while ((linelen = getline(&line, &linecap, md->fp)) == -1) {
		serrno = errno;
		debug("%d: getline %s errno %d timeout %0.6f feof: %d "
		    "ferror: %d\n",
		    getpid(), handle, serrno, tv.tv_sec + tv.tv_usec / 1e6,
		    feof(md->fp),
		    ferror(md->fp));
		if (serrno == EWOULDBLOCK) {
			clearerr(md->fp);
			debug("%d: Handle '%s' got EWOULDBLOCK timeout: %0.6f "
			    "SELECTING on %d\n", getpid(), handle,
			    tv.tv_sec + tv.tv_usec / 1e6,
			    fileno(md->fp));
			FD_ZERO(&ifds);
			FD_SET(fileno(md->fp), &ifds);
			switch (select(fileno(md->fp) + 1, &ifds, NULL, NULL,
			    &tv)) {
			case 0:
				debug("%d: SELECT timeout getline %s "
				    "errno %d\n",
				    getpid(), handle, errno);
				sig = pendingsig;
				ret = (128 + (sig != 0 ? sig : SIGALRM));
				goto out;
			case -1:
				debug("%d: SELECT error getline %s errno %d\n",
				    getpid(), handle, errno);
				ret = EX_IOERR;
				warn("%s", "select");
				goto out;
			}
			/* Data ready to read */
			debug("%d: SELECT ready getline %s errno %d RETRYING\n",
			    getpid(), handle, errno);
			continue;
		} else if (feof(md->fp)) {
			clearerr(md->fp);
			ret = 1;
			goto out;
		} else if (serrno == EINTR) {
			sig = pendingsig;
			if (sig == 0)
				continue;
			ret = 128 + sig;
			goto out;
		}
		errno = serrno;
		warn("failed to read handle '%s' mapped to %s", handle,
		    md->file);
		ret = EX_IOERR;
		goto out;
	}
	debug("%d: Read %s handle '%s': %s", getpid(),
	    md->file, handle, line);
out:
	if (flags & O_NONBLOCK) {
		flags &= ~O_NONBLOCK;
		if (fcntl(fileno(md->fp), F_SETFL, flags) < 0)
			warn("fcntl(%s, F_SETFL, ~O_NONBLOCK)",
			    handle);
	}
	/* Don't close on EOF or timeout as more data may come later. */
	if (ret != 1 && ret != 0 && ret != 142)
		md_close(md);

	if (linelen == -1) {
		line[0] = '\0';
	} else if (feof(md->fp)) {
		/*
		 * EOF without newline.
		 * EOF with newline is handled above.
		 */
		assert(ret == 0);
		assert(line[linelen - 1] != '\n');
		assert(ferror(md->fp) == 0);
		ret = 1; /* EOF */
		clearerr(md->fp);
	} else {
		/* Remove newline. */
		line[linelen - 1] = '\0';
		--linelen;
	}

	if (linelenp != NULL) {
		*linelenp = linelen;
	}
	*linep = line;
	return (ret);
}
int
mapfile_closecmd(int argc, char **argv)
{
	struct mapped_data *md;
	const char *handle;

	if (argc != 2)
		errx(EX_USAGE, "%s", "Usage: mapfile_close <handle>");
	handle = argv[1];
	INTOFF;
	md = md_find(handle);
	md_close(md);
	INTON;

	return (0);
}

static int
_mapfile_write(/*XXX const*/ struct mapped_data *md, const char *handle,
    const int nflag, const int Tflag, const char *data, ssize_t datalen)
{
	int serrno, ret;

	ret = 0;
	if (datalen == -1) {
		datalen = strlen(data);
	}
	debug("%d: Writing to %s for handle '%s' fd: %d: %s\n",
	    getpid(), md->file, handle, fileno(md->fp), data);
	if (fwrite(data, sizeof(*data), datalen, md->fp) == EOF ||
	    (!nflag && fputc('\n', md->fp) == EOF) ||
	    ferror(md->fp)) {
		serrno = errno;
		debug("%d: Writing to %s for handle '%s' fd: %d feof: %d "
		    "ferror: %d errno: %d\n",
		    getpid(), md->file, handle, fileno(md->fp), feof(md->fp),
		    ferror(md->fp), serrno);
		md_close(md);
		if (serrno == EPIPE)
			ret = EPIPE;
		else if (serrno == EINTR)
			ret = 1;
		else
			ret = EX_IOERR;
		errno = serrno;
		INTON;
		err(ret, "failed to write to handle '%s' mapped to %s",
		    handle, md->file);
	}
	if (Tflag) {
		outbin(data, datalen, out1);
		out1c('\n');
	}
	return (ret);
}

int evalcmd(int argc, char **argv);

int
mapfile_writecmd(int argc, char **argv)
{
	struct mapped_data *md;
	const char *handle, *data;
	int ch, nflag, Tflag, ret;

	static const char usage[] = "Usage: mapfile_write <handle> [-nT] "
		    "<data>";
	if (argc < 2)
		errx(EX_USAGE, "%s", usage);
	nflag = Tflag = 0;
	handle = argv[1];
	optind = 2;
	while ((ch = getopt(argc, argv, "nT")) != -1) {
		switch (ch) {
		case 'n':
			nflag = 1;
			break;
		case 'T':
			Tflag = 1;
			break;
		default:
			errx(EX_USAGE, "%s", usage);
		}
	}
	argc -= optind;
	argv += optind;
	INTOFF;
	md = md_find(handle);
	if (argc == 1) {
		data = argv[0];
		ret = _mapfile_write(md, handle, nflag, Tflag, data, -1);
		assert(is_int_on());
	} else {
		char *line;
		struct mapped_data *md_read = NULL;
		ssize_t linelen;
		int rret;

		/* Read from TTY */
		ret = 0;
		md_read = _mapfile_open("/dev/fd/0", "r", 1, 0);
		assert(md_read != NULL);
		assert(is_int_on());
		while ((rret = _mapfile_read(md_read, &line, &linelen, NULL)) == 0) {
			ret = _mapfile_write(md, handle, nflag, Tflag, line,
			    linelen);
			assert(is_int_on());
			if (ret != 0) {
				md_close(md_read);
				INTON;
				err(ret, "mapfile_write");
			}
			assert(is_int_on());
		}

		/* 1 == EOF */
		if (rret != 1) {
			ret = rret;
		}
		md_close(md_read);
	}
	INTON;

	return (ret);
}
