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
#include <sys/time.h>
#include <sys/wait.h>

#include <assert.h>
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
#include <sysexits.h>
#include <time.h>
#include <unistd.h>

#define min(a, b) ((a) > (b) ? (b) : (a))
#ifndef timespecsub
#define	timespecsub(tsp, usp, vsp)					\
	do {								\
		(vsp)->tv_sec = (tsp)->tv_sec - (usp)->tv_sec;		\
		(vsp)->tv_nsec = (tsp)->tv_nsec - (usp)->tv_nsec;	\
		if ((vsp)->tv_nsec < 0) {				\
			(vsp)->tv_sec--;				\
			(vsp)->tv_nsec += 1000000000L;			\
		}							\
	} while (0)
#endif
#define TIMESTAMP_BUFSIZ 25
static const char *const typefmt[] = {"[]", "()"};

static struct timespec start;

struct kdata {
	FILE *fp_in;
	FILE *fp_out;
	const char *prefix;
	size_t prefix_len;
	bool timestamp;
	bool timestamp_line;
};

static size_t
calculate_duration(char *timestamp, size_t tlen, const struct timespec *elapsed)
{
	int days, hours, minutes, seconds;
	time_t elapsed_seconds;
	ssize_t len, slen;

	len = 0;
	elapsed_seconds = elapsed->tv_sec;

	days = elapsed_seconds / 86400;
	elapsed_seconds %= 86400;
	hours = elapsed_seconds / 3600;
	elapsed_seconds %= 3600;
	minutes = elapsed_seconds / 60;
	elapsed_seconds %= 60;
	seconds = elapsed_seconds;

	if (days > 0) {
		slen = snprintf(timestamp, tlen, "%dD:", days);
		len += slen;
		tlen -= len;
		timestamp += slen;
		assert(tlen > 0);
	}
	slen = snprintf(timestamp, tlen, "%02d:%02d:%02d",
	    hours, minutes, seconds);
	len += slen;
	tlen -= len;
	assert(tlen > 0);
	return (len);
}

static int
prefix_output(struct kdata *kd)
{
	char timestamp[TIMESTAMP_BUFSIZ]; /* '[HH:MM:SS] ' + 1 */
	const char *prefix;
	char prefix_override[128] = {0};
	char *p;
	int ch;
	struct timespec now, lastline, elapsed;
	const size_t tlen = sizeof(timestamp);
	size_t prefix_len, dlen;
	bool newline;

	p = NULL;
	prefix = kd->prefix;
	prefix_len = kd->prefix_len;
	newline = true;
	if (kd->timestamp_line)
		if (clock_gettime(CLOCK_MONOTONIC_FAST, &lastline))
			err(EXIT_FAILURE, "%s", "clock_gettime");
	while ((ch = getc(kd->fp_in)) != EOF) {
		if (newline) {
			if (ch == '\001') {
				/* Read in a new prefix */
				p = prefix_override;
				while (p != prefix_override +
				    sizeof(prefix_override) - 1) {
					if ((ch = getc(kd->fp_in)) == EOF)
						goto error;
					if (ch == '\n')
						break;
					*p++ = ch;
				}
				*p = '\0';
				if (prefix_override[0] != '\0') {
					prefix = prefix_override;
					prefix_len = p - prefix_override;
				} else {
					prefix = kd->prefix;
					prefix_len = kd->prefix_len;
				}
				continue;
			}
			newline = false;
			if (kd->timestamp || kd->timestamp_line)
				if (clock_gettime(CLOCK_MONOTONIC_FAST, &now))
					err(EXIT_FAILURE, "%s", "clock_gettime");
			if (kd->timestamp) {
				timespecsub(&now, &start, &elapsed);
				dlen = calculate_duration(timestamp,
				    tlen, &elapsed);
				if (putc(typefmt[0][0], kd->fp_out) == EOF)
					return (-1);
				if (fwrite(timestamp, sizeof(*timestamp), dlen,
				    kd->fp_out) < dlen)
					return (-1);
				if (putc(typefmt[0][1], kd->fp_out) == EOF)
					return (-1);
				if (putc(' ', kd->fp_out) == EOF)
					return (-1);
			}
			if (kd->timestamp_line) {
				timespecsub(&now, &lastline, &elapsed);
				if (putc(typefmt[1][0], kd->fp_out) == EOF)
					return (-1);
				dlen = calculate_duration(timestamp,
				    tlen, &elapsed);
				if (fwrite(timestamp, sizeof(*timestamp), dlen,
				    kd->fp_out) < dlen)
					return (-1);
				if (putc(typefmt[1][1], kd->fp_out) == EOF)
					return (-1);
				if (putc(' ', kd->fp_out) == EOF)
					return (-1);
			}
			if (prefix != NULL) {
				if (fwrite(prefix, sizeof(prefix[0]),
				    prefix_len, kd->fp_out) <
				    prefix_len)
					return (-1);
				if (putc(' ', kd->fp_out) == EOF)
					return (-1);
			}
		}
		if (ch == '\n' || ch == '\r') {
			newline = true;
			if (kd->timestamp_line)
				lastline = now;
		}
		if (putc(ch, kd->fp_out) == EOF)
			return (-1);
	}
error:
	if (ferror(kd->fp_out) || ferror(kd->fp_in) || feof(kd->fp_in))
		return (-1);
	return (0);
}

static void*
prefix_main(void *arg)
{
	struct kdata *kd = arg;

	if (kd->prefix != NULL)
		kd->prefix_len = strlen(kd->prefix);
	prefix_output(kd);

	return (NULL);
}

static void
usage(void)
{

	fprintf(stderr, "%s\n",
	    "usage: timestamp [-1 <stdout prefix>] [-2 <stderr prefix>] [-eo in.fifo] [-P <proctitle>] [-dutT] [command]");
	exit(EX_USAGE);
}

/**
 * Timestamp stdout
 */
int
main(int argc, char **argv)
{
	FILE *fp_in_stdout, *fp_in_stderr;
	pthread_t *thr_stdout, *thr_stderr;
	struct kdata kdata_stdout, kdata_stderr;
	const char *prefix_stdout, *prefix_stderr, *time_start;
	char *end;
	pid_t child_pid;
	int child_stdout[2], child_stderr[2];
	int ch, status, ret, dflag, uflag, tflag, Tflag;

	child_pid = -1;
	ret = 0;
	dflag = tflag = Tflag = uflag = 0;
	thr_stdout = thr_stderr = NULL;
	prefix_stdout = prefix_stderr = NULL;
	fp_in_stdout = fp_in_stderr = NULL;

	while ((ch = getopt(argc, argv, "1:2:de:o:P:tTu")) != -1) {
		switch (ch) {
		case '1':
			prefix_stdout = strdup(optarg);
			break;
		case '2':
			prefix_stderr = strdup(optarg);
			break;
		case 'd':
			dflag = 1;
			break;
		case 'e':
			if ((fp_in_stderr = fopen(optarg, "r")) == NULL)
				err(EX_DATAERR, "fopen");
			break;
		case 'o':
			if ((fp_in_stdout = fopen(optarg, "r")) == NULL)
				err(EX_DATAERR, "fopen");
			break;
		case 'P':
			setproctitle("%s", optarg);
			break;
		case 't':
			tflag = 1;
			break;
		case 'T':
			Tflag = 1;
			break;
		case 'u':
			uflag = 1;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;

	if ((time_start = getenv("TIME_START")) != NULL) {
		char *p;

		p = strchr(time_start, '.');
		if (p != NULL)
			*p = '\0';
		errno = 0;
		start.tv_sec = strtol(time_start, &end, 10);
		if (start.tv_sec < 0 || *end != '\0' || errno != 0)
			err(1, "Invalid START_TIME");
		if (p != NULL) {
			++p;
			errno = 0;
			start.tv_nsec = strtol(p, &end, 10);
			if (start.tv_nsec < 0 || *end != '\0' || errno != 0)
				err(1, "Invalid START_TIME");
		} else
			start.tv_nsec = 0;
	} else if (clock_gettime(CLOCK_MONOTONIC_FAST, &start))
		err(EXIT_FAILURE, "%s", "clock_gettime");

	if (dflag) {
		char timestamp[TIMESTAMP_BUFSIZ];
		size_t dlen;

		dlen = calculate_duration(timestamp,
		    TIMESTAMP_BUFSIZ, &start);
		assert(dlen < TIMESTAMP_BUFSIZ);
		printf("%s\n", timestamp);
		exit(0);
	}

	if (uflag)
		setbuf(stdout, NULL);
	else {
		setlinebuf(stdout);
		setlinebuf(stderr);
	}

	if (argc > 0) {
		if (fp_in_stdout != NULL)
			errx(EX_DATAERR, "Cannot use -o with command");
		if (fp_in_stderr != NULL)
			errx(EX_DATAERR, "Cannot use -e with command");
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
		signal(SIGINT, SIG_IGN);
		close(child_stdout[1]);
		close(child_stderr[1]);
		if ((fp_in_stdout = fdopen(child_stdout[0], "r")) == NULL)
		    err(EXIT_FAILURE, "fdopen stdout");
		if ((fp_in_stderr = fdopen(child_stderr[0], "r")) == NULL)
		    err(EXIT_FAILURE, "fdopen stderr");
	} else if (fp_in_stdout == NULL)
		fp_in_stdout = stdin;

	if (fp_in_stdout != stdin && fp_in_stderr != stdin)
		fclose(stdin);

	if (fp_in_stdout != NULL) {
		kdata_stdout.fp_in = fp_in_stdout;
		kdata_stdout.fp_out = stdout;
		kdata_stdout.prefix = prefix_stdout;
		kdata_stdout.timestamp = !Tflag;
		kdata_stdout.timestamp_line = tflag;
	}

	if (fp_in_stderr != NULL) {
		kdata_stderr.fp_in = fp_in_stderr;
		kdata_stderr.fp_out = stderr;
		kdata_stderr.prefix = prefix_stderr;
		kdata_stderr.timestamp = !Tflag;
		kdata_stderr.timestamp_line = tflag;
	}

	if (child_pid != -1 || (fp_in_stderr != NULL &&
	    fp_in_stdout != NULL)) {
		if (fp_in_stdout != NULL) {
			thr_stdout = calloc(1, sizeof(pthread_t));
			if (pthread_create(thr_stdout, NULL, prefix_main,
			    &kdata_stdout))
				err(EXIT_FAILURE, "pthread_create stdout");
			pthread_set_name_np(*thr_stdout, "prefix_stdout");
		}

		if (fp_in_stderr != NULL) {
			thr_stderr = calloc(1, sizeof(pthread_t));
			if (pthread_create(thr_stderr, NULL, prefix_main,
			    &kdata_stderr))
				err(EXIT_FAILURE, "pthread_create stderr");
			pthread_set_name_np(*thr_stderr, "prefix_stderr");
		}

		if (child_pid != -1) {
			if (waitpid(child_pid, &status, WEXITED) == -1)
				err(EXIT_FAILURE, "waitpid");
			if (WIFEXITED(status))
				ret = WEXITSTATUS(status);
			else if (WIFSTOPPED(status))
				ret = WSTOPSIG(status) + 128;
			else
				ret = WTERMSIG(status) + 128;
		}
	} else if (fp_in_stderr != NULL) {
		prefix_main(&kdata_stderr);
	} else if (fp_in_stdout != NULL) {
		prefix_main(&kdata_stdout);
	}

	if (thr_stdout != NULL)
		pthread_join(*thr_stdout, NULL);
	if (thr_stderr != NULL)
		pthread_join(*thr_stderr, NULL);

	return (ret);
}
