/*-
 * Copyright (c) 2014 Bryan Drewery <bdrewery@FreeBSD.org>
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
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <paths.h>
#include <pthread.h>
#include <pthread_np.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define min(a, b) ((a) > (b) ? (b) : (a))

static bool newline;
static time_t start;

struct kdata {
	FILE *fp_in;
	FILE *fp_out;
};

static void
calculate_duration(char *timestamp, size_t tlen, time_t elapsed)
{
	int hours, minutes, seconds;

	seconds = elapsed % 60;
	minutes = (elapsed / 60) % 60;
	hours = elapsed / 3600;

	snprintf(timestamp, tlen, "(%02d:%02d:%02d) ", hours, minutes,
	    seconds);
}

static int
prefix_output(FILE *fp_in, FILE *fp_out)
{
	char timestamp[8 + 3 + 1]; /* '[HH:MM:SS] ' + 1 */
	int ch;
	time_t elapsed, now;
	const size_t tlen = sizeof(timestamp);

	while ((ch = getc(kd->fp_in)) != EOF) {
		if (newline) {
			newline = false;
			now = time(NULL);
			elapsed = now - start;
			calculate_duration((char *)&timestamp, tlen, elapsed);
			fwrite(timestamp, tlen - 1, 1, fp_out);
			if (ferror(fp_out))
				return (-1);
		}
		if (ch == '\n' || ch == '\r')
			newline = true;
		if (putc(ch, fp_out) == EOF)
			return (-1);
	}
	if (ferror(fp_out) || ferror(fp_in) || feof(fp_in))
		return (-1);
	return (0);
}

static void*
prefix_main(void *arg)
{
	struct kdata *kdata = arg;

	prefix_output(kdata->fp_in, kdata->fp_out);

	return (NULL);
}

/**
 * Timestamp stdout
 */
int
main(int argc, char **argv)
{
	FILE *fp_stdout, *fp_stderr;
	pthread_t *thr_stdout, *thr_stderr;
	struct kdata kdata_stdout, kdata_stderr;
	struct kevent *ev;
	pid_t child_pid;
	int child_stdout[2], child_stderr[2];
	int ch, kq, nevents, nev, kn, i, status, ret, done, uflag;

	ev = NULL;
	nev = nevents = 0;
	child_pid = -1;
	start = time(NULL);
	ret = 0;
	done = 0;
	newline = true;
	uflag = 0;
	thr_stdout = thr_stderr = NULL;

	while ((ch = getopt(argc, argv, "u")) != -1) {
		switch (ch) {
		case 'u':
			uflag = 1;
			break;
		}
	}
	argc -= optind;
	argv += optind;

	if (argc > 0) {
		if (pipe(child_stdout) != 0)
			err(EXIT_FAILURE, "pipe");
		if (pipe(child_stderr) != 0)
			err(EXIT_FAILURE, "pipe");

		child_pid = vfork();
		if (child_pid == -1)
			err(EXIT_FAILURE, "fork");
		if (child_pid == 0) {
			close(child_stdout[0]);
			dup2(child_stdout[1], STDOUT_FILENO);
			close(child_stdout[1]);

			close(child_stderr[0]);
			dup2(child_stderr[1], STDERR_FILENO);
			close(child_stderr[1]);

			execvp(argv[0], &argv[0]);
			_exit(127);
		}
		close(STDIN_FILENO);
		close(child_stdout[1]);
		close(child_stderr[1]);
		if ((fp_stdout = fdopen(child_stdout[0], "r")) == NULL)
		    err(EXIT_FAILURE, "fdopen stdout");
		if ((fp_stderr = fdopen(child_stderr[0], "r")) == NULL)
		    err(EXIT_FAILURE, "fdopen stderr");
		nev = 3;
	} else
		nev = 1;

	if ((kq = kqueue()) == -1)
		err(EXIT_FAILURE, "kqueue");
	ev = calloc(sizeof(struct kevent), nev);
	if (ev == NULL)
		err(EXIT_FAILURE, "malloc");

	if (child_pid != -1) {
		EV_SET(ev + nevents++, child_pid, EVFILT_PROC, EV_ADD,
		    NOTE_EXIT, 0, NULL);
		kdata_stdout.fp_in = fp_stdout;
		kdata_stdout.fp_out = stdout;
		thr_stdout = calloc(sizeof(pthread_t), 1);
		if (pthread_create(thr_stdout, NULL, prefix_main,
		    &kdata_stdout))
			err(EXIT_FAILURE, "pthread_create stdout");
		pthread_set_name_np(*thr_stdout, "prefix_stdout");

		kdata_stderr.fp_in = fp_stderr;
		kdata_stderr.fp_out = stderr;
		thr_stderr = calloc(sizeof(pthread_t), 1);
		if (pthread_create(thr_stderr, NULL, prefix_main,
		    &kdata_stderr))
			err(EXIT_FAILURE, "pthread_create stderr");
		pthread_set_name_np(*thr_stderr, "prefix_stderr");
	} else {
		kdata_stdout.fp_in = stdin;
		kdata_stdout.fp_out = stdout;
		thr_stdout = calloc(sizeof(pthread_t), 1);
		if (pthread_create(thr_stdout, NULL, prefix_main,
		    &kdata_stdout))
			err(EXIT_FAILURE, "pthread_create stdout");
		pthread_set_name_np(*thr_stdout, "prefix_stdout");
	}
	if (uflag)
		setbuf(stdout, NULL);

	if (nevents == 0)
		goto no_events;

	kevent(kq, ev, nevents, NULL, 0, NULL);

	for (;;) {
		if ((kn = kevent(kq, NULL, 0, ev, nevents, NULL)) == -1) {
			if (errno == EINTR)
				continue;
			err(EXIT_FAILURE, "kevent");
		}
		for (i = 0; i < kn; i++) {
			if (ev[i].filter == EVFILT_PROC) {
				/* Pwait code here */
				status = ev[i].data;
				if (WIFEXITED(status))
					ret = WEXITSTATUS(status);
				else if (WIFSTOPPED(status))
					ret = WSTOPSIG(status) + 128;
				else
					ret = WTERMSIG(status) + 128;
				done = 1;
			}
		}
		if (done == 1)
			break;
	}
no_events:

	if (thr_stdout != NULL)
		pthread_join(*thr_stdout, NULL);
	if (thr_stderr != NULL)
		pthread_join(*thr_stderr, NULL);

	free(ev);
	return (ret);
}
