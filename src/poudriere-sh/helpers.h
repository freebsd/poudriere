/*-
 * Copyright (c) 2017 Bryan Drewery <bdrewery@FreeBSD.org>
 * All rights reserved.
 *~
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *~
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

#include <assert.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>

struct sigdata {
	struct sigaction oact;
	char *action_str;
	char sigmode;
	int signo;
	bool sh;
};

void trap_push(int signo, struct sigdata *sd);
void trap_push_sh(int signo, struct sigdata *sd);
void trap_pop(int signo, struct sigdata *sd);
double parse_duration(const char *duration);

#ifdef SHELL
#include <errno.h>

/*
 * fprintf(stderr) and fprintf(stdout) are defined special to use
 * the shell buffering.
 * Any other functions can use stdio as long as they undef what they
 * use from here. No mixing between stdio functions and the shell
 * builtins can be done.
 * -- Using these are fine as long as stdio/stdin/stderr is not used.
 */
#undef FILE
#define FILE MUST_NOT_MIX_STDIO_WITH_SH_HANDLING

#undef getchar
static inline char mygetchar(void) {
    char c;

    return (read(STDIN_FILENO, &c, 1) ? c : EOF);
}
#define getchar mygetchar
/* Use the sh version */
#undef fputc
#define fputc(c, stream) putc((c), (stream))

#undef stdin

#define err_set_exit notimplemented
#define err_set_file notimplemented
#define verrc notimplemented
#define verrx notimplemented
#define vwarn notimplemented
#define vwarnc notimplemented
#undef err
#undef errc
#undef errx
#undef verrx
#undef vwarnx
#undef warn
#undef warnc
#undef warnx

#define warnx 			warning
#define vwarnx			vwarning
#define warnc(code, fmt, ...) 	warnx(fmt ": %s", ##__VA_ARGS__, strerror(code))
#define warn(...) 		warnc(errno, __VA_ARGS__)

#define errx 			errorwithstatus
#define verrx			verrorwithstatus
#define errc(exitstatus, code, fmt, ...) \
    errx(exitstatus, fmt ": %s", ##__VA_ARGS__, strerror(code))
#define err(exitstatus, ...) 	errc(exitstatus, errno, __VA_ARGS__)

#define getenv(var) bltinlookup(var, 1)

#include "shell.h"

/*
 * Avoiding sh's version of these as explained in FreeBSD add265c6b.
 */
static void
badalloc(const char *message)
{
	write(2, message, strlen(message));
	abort();
}

static inline void*
ckmalloc(size_t nbytes)
{
	void *p;

	if (!is_int_on())
		badalloc("Unsafe ckmalloc() call\n");
	p = malloc(nbytes);
	return p;
}


/*
 * Same for realloc.
 */

static inline void*
ckrealloc(void *p, int nbytes)
{
	if (!is_int_on())
		badalloc("Unsafe ckrealloc() call\n");
	p = realloc(p, nbytes);
	return p;
}

static inline void
ckfree(void *p)
{
	if (!is_int_on())
		badalloc("Unsafe ckfree() call\n");
	free(p);
}


/* This kinda works but does not free memory, close fd, or INTON. */
#undef exit
extern int exitstatus;
void flushall(void);
void verrorwithstatus(int, const char *, va_list) __printf0like(2, 0) __dead2;
/* https://stackoverflow.com/a/25172698/285734 */
#define exit(...)		exit_(_, ##__VA_ARGS__)
#define exit_(...)		exit_X(__VA_ARGS__, _1, _0)(__VA_ARGS__)
#define exit_X(_0, _1, X, ...)	exit ## X
#define exit_0(_)		return (0)
#define exit_1(_, status)	do {			\
	va_list va_empty;				\
	verrorwithstatus(status, NULL, va_empty);	\
} while (0)

/* Getopt compat */
#include "options.h"
#ifndef _NEED_SH_FLAGS
#undef Aflag
#undef Bflag
#undef Cflag
#undef Dflag
#undef Eflag
#undef Fflag
#undef Gflag
#undef Hflag
#undef Iflag
#undef Jflag
#undef Kflag
#undef Lflag
#undef Mflag
#undef Nflag
#undef Oflag
#undef Pflag
#undef Qflag
#undef Rflag
#undef Sflag
#undef Tflag
#undef Uflag
#undef Vflag
#undef Wflag
#undef Xflag
#undef Yflag
#undef Zflag
#undef aflag
#undef bflag
#undef cflag
#undef dflag
#undef eflag
#undef fflag
#undef gflag
#undef hflag
#undef iflag
#undef jflag
#undef kflag
#undef lflag
#undef mflag
#undef nflag
#undef oflag
#undef pflag
#undef qflag
#undef rflag
#undef sflag
#undef tflag
#undef uflag
#undef vflag
#undef wflag
#undef xflag
#undef yflag
#undef zflag
#endif

#undef getopt
#define getopt pgetopt
#define getopt_long(argc, argv, optstring, longopts, longindex) \
    getopt(argc, argv, optstring)
#undef opterr
#undef optreset
#undef optarg
#define optarg shoptarg
static inline int
pgetopt(const int argc, char *argv[], const char *optstring)
{
	int ch;

	assert(optind != 1 || argptr == argv + optind);
	argptr = argv + optind;
	ch = nextopt(optstring);
	if (ch == '\0') {
		ch = -1;
		optind = 1;
	}
	optind = argptr - argv;
	assert(argc - optind == argc - (argptr - argv));
	assert(argv + optind == argptr);
	return ((optopt = ch));
}

#define getpid	pgetpid
extern long shpid;
#ifndef NDEBUG
pid_t __sys_getpid(void);
#endif
inline static pid_t
pgetpid(void)
{

	assert(__sys_getpid() == shpid);
	return (shpid);
}

#define getprogname pgetprogname
extern char *commandname;
inline static const char *
getprogname() {

	return (commandname);
}

#endif
