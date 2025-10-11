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
static int Dflag;
static struct timespec start;
pid_t child_pid = -1;

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

static inline int
print_prefix(const struct kdata *kd, const char *prefix, const size_t prefix_len,
    const struct timespec lastline, struct timespec *now)
{
	struct timespec elapsed;
	char timestamp[TIMESTAMP_BUFSIZ]; /* '[HH:MM:SS] ' + 1 */
	const size_t tlen = sizeof(timestamp);
	size_t dlen;

	if (kd->timestamp || kd->timestamp_line)
		if (clock_gettime(CLOCK_MONOTONIC_FAST, now))
			err(EXIT_FAILURE, "%s", "clock_gettime");
	if (kd->timestamp) {
		timespecsub(now, &start, &elapsed);
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
		timespecsub(now, &lastline, &elapsed);
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
	return (0);
}

static int
prefix_output(struct kdata *kd, const int dynamic_prefix_support)
{
	static const char prefix_change[] = "\001PX:";
	char prefix_override[128] = {0};
	const char *prefix;
	int ch, ret;
	unsigned int changing_prefix;
	struct timespec lastline = {0}, now = {0};
	size_t prefix_len;
	bool newline;

	prefix = kd->prefix;
	prefix_len = kd->prefix_len;
	newline = true;
	changing_prefix = 0;
	if (kd->timestamp_line)
		if (clock_gettime(CLOCK_MONOTONIC_FAST, &lastline))
			err(EXIT_FAILURE, "%s", "clock_gettime");
	while ((ch = getc(kd->fp_in)) != EOF) {
		if (dynamic_prefix_support) {
			if (ch == prefix_change[changing_prefix]) {
				changing_prefix++;
				if (changing_prefix == strlen(prefix_change)) {
					char *p = prefix_override;

					changing_prefix = 0;
					/* Read in a new prefix */
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
				}
				continue;
			} else if (changing_prefix > 0) {
				if (newline &&
				    (ret = print_prefix(kd, prefix, prefix_len,
				    lastline, &now)) != 0) {
					return (ret);
				}
				for (size_t i = 0; i < changing_prefix; ++i) {
					assert(i <= strlen(prefix_change));
					if (putc(prefix_change[i],
					    kd->fp_out) == EOF) {
						return (-1);
					}
				}
				newline = false;
				changing_prefix = 0;
			}
		}
		if (newline) {
			newline = false;
			if ((ret = print_prefix(kd, prefix, prefix_len,
			    lastline, &now)) != 0)
				return (ret);
		}
		if (ch == '\n' || ch == '\r') {
			newline = true;
			if (kd->timestamp_line)
				lastline = now;
			changing_prefix = 0;
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
	prefix_output(kd, Dflag);

	return (NULL);
}

static void
usage(void)
{

	fprintf(stderr, "%s\n",
	    "usage: timestamp [-1 <stdout prefix>] [-2 <stderr prefix>] [-eo in.fifo] [-P <proctitle>] [-dDutT] [command]");
	exit(EX_USAGE);
}

static void
gotterm(int sig __unused)
{
	if (child_pid == -1)
		return;
	warnx("killing child pid %d with SIGTERM", child_pid);
	kill(child_pid, SIGTERM);
	/*
	 * We could reraise SIGTERM but let's ensure we flush everything
	 * out that the child sends on its own SIGTERM.
	 */
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
	char *prefix_stdout, *prefix_stderr, *time_start;
	char *end;
	int child_stdout[2], child_stderr[2];
	int ch, status, ret, dflag, uflag, tflag, Tflag;

	ret = 0;
	dflag = tflag = Tflag = uflag = 0;
	thr_stdout = thr_stderr = NULL;
	prefix_stdout = prefix_stderr = NULL;
	fp_in_stdout = fp_in_stderr = NULL;

	while ((ch = getopt(argc, argv, "1:2:dDe:o:P:tTu")) != -1) {
		switch (ch) {
		case '1':
			prefix_stdout = strdup(optarg);
			if (prefix_stdout == NULL)
				err(EXIT_FAILURE, "strdup");
			break;
		case '2':
			prefix_stderr = strdup(optarg);
			if (prefix_stderr == NULL)
				err(EXIT_FAILURE, "strdup");
			break;
		case 'd':
			dflag = 1;
			break;
		case 'D': /* dynamic prefix support */
			Dflag = 1;
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

	signal(SIGTERM, gotterm);
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
			if (thr_stdout == NULL)
				err(EXIT_FAILURE, "calloc");

			if (pthread_create(thr_stdout, NULL, prefix_main,
			    &kdata_stdout))
				err(EXIT_FAILURE, "pthread_create stdout");
			pthread_set_name_np(*thr_stdout, "prefix_stdout");
		}

		if (fp_in_stderr != NULL) {
			thr_stderr = calloc(1, sizeof(pthread_t));
			if (thr_stderr == NULL)
				err(EXIT_FAILURE, "calloc");

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
