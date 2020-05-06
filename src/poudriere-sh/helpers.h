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

#include <signal.h>
#include <stdbool.h>

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

#ifdef SHELL
#include <errno.h>
#define err(exitstatus, fmt, ...) error(fmt ": %s", __VA_ARGS__, strerror(errno))
#define getenv(var) bltinlookup(var, 1)

#include "shell.h"

void * ckmalloc(size_t);
void * ckrealloc(void *, int);
void ckfree(void *);

#define malloc ckmalloc
#define realloc ckrealloc
#define free ckfree

/* This kinda works but does not free memory, close fd, or INTON. */
#undef exit
extern int exitstatus;
void flushall(void);
#define exit(status) do { \
	exitstatus = status; \
	flushall(); \
	exraise(EXERROR); \
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
#undef optopt
#undef opterr
#undef optreset
int pgetopt(int argc, char *argv[], const char *optstring);

#endif
