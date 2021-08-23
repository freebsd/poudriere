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
#undef FILE
#undef fclose
#undef fdopen
#undef fflush
#undef fopen
#undef fputs
#include "eval.h"
#include "trap.h"
#include "var.h"

#define MAX_FILES 256
struct mapped_data {
	FILE *fp;
	char *file;
	int handle;
	bool linebuffered;
};
static struct mapped_data *mapped_files[MAX_FILES] = {0};

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
		assert(fileno(md->fp) >= 10);
		fclose(md->fp);
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

int
mapfilecmd(int argc, char **argv)
{
	FILE *fp;
	struct mapped_data *md;
	struct stat sb;
	const char *file, *var_return, *modes, *p;
	char *dupp;
	char handle[32], dupmodes[7];
	int nextidx, idx, serrno, cmd, newfd;

	fp = NULL;
	if (argc != 3 && argc != 4)
		errx(EX_USAGE, "%s", "Usage: mapfile <handle_name> <file> [modes]");
	INTOFF;
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

	file = argv[2];
	var_return = argv[1];

	if (argc == 4)
		modes = argv[3];
	else
		modes = "re";

	if (strchr(modes, 'B') && !(strchr(modes, 'w') || strchr(modes, '+') ||
	    strchr(modes, 'a'))) {
	    INTON;
	    errx(EX_USAGE, "%s", "using 'B' without writing makes no sense");
	}

	if ((fp = fopen(file, modes)) == NULL) {
		serrno = errno;
		INTON;
		errno = serrno;
		err(EX_NOINPUT, "%s: %s", "fopen", file);
	}
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
	md = calloc(1, sizeof(*md));
	md->fp = fp;
	md->file = strdup(file);
	md->handle = nextidx;
	md->linebuffered = strchr(modes, 'B') == NULL;

	mapped_files[md->handle] = md;
	snprintf(handle, sizeof(handle), "%d", md->handle);
	setvar(var_return, handle, 0);
	debug("%d: Mapped %s to handle '%s' modes '%s'\n", getpid(),
	    md->file, handle, modes);
	INTON;

	return (0);
}

int
mapfile_readcmd(int argc, char **argv)
{
	struct mapped_data *md;
	struct timeval tv = {};
	fd_set ifds;
	int flags;
	char **var_return_ptr;
	char *end, *linep, *ifsp;
	const char *handle, *ifs;
	ssize_t linelen;
	double timeout;
	int ch, ret, serrno, sig, tflag;
	/* Avoid remallocing every call */
	static char *line = NULL;
	/* Start a bit larger to avoid needing reallocs in children. */
	static size_t linecap = 4096;

	ifs = NULL;
	timeout = 0;
	tflag = 0;

	if (argc < 2)
		errx(EX_USAGE, "%s", "Usage: mapfile_read <handle> "
		    "[-t timeout] <output_var> ...");

	handle = argv[1];
	argptr += 1;
	argc -= argptr - argv;
	argv = argptr;

	while ((ch = nextopt("I:t:")) != '\0') {
		switch (ch) {
		case 'I':
			ifs = shoptarg;
			break;
		case 't':
			tflag = 1;
			timeout = strtod(shoptarg, &end);
			if (end == shoptarg || errno == ERANGE ||
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
		}
	}
	argc -= argptr - argv;
	argv = argptr;

	if (argc < 1)
		errx(EX_USAGE, "%s", "Usage: mapfile_read <handle> "
		    "[-t timeout] <output_var> ...");

	INTOFF;
	md = md_find(handle);

	var_return_ptr = &argv[0];
	debug("%d: Reading %s handle '%s' timeout: %0.6f feof: %d "
	    "ferror: %d\n",
	    getpid(), md->file, handle, tv.tv_sec + tv.tv_usec / 1e6,
	    feof(md->fp), ferror(md->fp));

	linelen = -1;
	/* Malloc once per sh process.  getline(3) may grow it. */
	if (line == NULL) {
	    line = malloc(linecap);
	    if (line == NULL) {
		    INTON;
		    err(EX_TEMPFAIL, "malloc");
	    }
	}

	flags = 0;
	ret = 0;
	if (tflag) {
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
			setvar(*var_return_ptr++, linep, 0);
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
			setvar(*var_return_ptr++, linep, 0);
			break;
		}
	}
	INTON;

	/* Set any remaining args to "" */
	while (*var_return_ptr != NULL)
		setvar(*var_return_ptr++, "", 0);

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
    const int nflag, const char *data)
{
	int serrno, ret;

	ret = 0;
	debug("%d: Writing to %s for handle '%s' fd: %d: %s\n",
	    getpid(), md->file, handle, fileno(md->fp), data);
	if (fputs(data, md->fp) == EOF ||
	    (!nflag && fputc('\n', md->fp) == EOF) ||
	    (md->linebuffered && fflush(md->fp) == EOF) ||
	    ferror(md->fp)) {
		serrno = errno;
		debug("%d: Writing to %s for handle '%s' fd: %d feof: %d "
		    "ferror: %d errno: %d\n",
		    getpid(), md->file, handle, fileno(md->fp), feof(md->fp),
		    ferror(md->fp), serrno);
		md_close(md);
		INTON;
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
	return (ret);
}

int evalcmd(int argc, char **argv);

int
mapfile_writecmd(int argc, char **argv)
{
	struct mapped_data *md;
	const char *handle, *data;
	int ch, nflag, ret;

	if (argc < 2)
		errx(EX_USAGE, "%s", "Usage: mapfile_write <handle> [-n] "
		    "<data>");
	nflag = 0;
	handle = argv[1];
	argptr += 1;
	argc -= argptr - argv;
	argv = argptr;
	while ((ch = nextopt("n")) != '\0') {
		switch (ch) {
		case 'n':
			nflag = 1;
			break;
		}
	}
	argc -= argptr - argv;
	argv = argptr;
	INTOFF;
	md = md_find(handle);
	if (argc == 1) {
		data = argv[0];
		ret = _mapfile_write(md, handle, nflag, data);
	} else {
		/* Read from TTY */
		char *value;
		/*
		 * XXX: Using shell mapfile_cat until some changes from
		 * copool branch make it in to avoid massive conflicts
		 */
		const char *cmd = "__mapfile_write_cat=$(mapfile_cat)";

		evalstring(cmd, 0);
		if (exitstatus != 0) {
			ret = exitstatus;
			goto out;
		}
		value = lookupvar("__mapfile_write_cat");
		assert(value != NULL);
		ret = _mapfile_write(md, handle, nflag, value);
	}
out:
	INTON;

	return (ret);
}
