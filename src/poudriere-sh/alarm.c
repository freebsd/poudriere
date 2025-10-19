/*-
 * Copyright (c) 2025 Bryan Drewery <bdrewery@FreeBSD.org>
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

#include <sys/types.h>
#include <sys/time.h>

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sysexits.h>

#include "bltin/bltin.h"
#include "helpers.h"
#include "trap.h"
#include "var.h"

static int alarm_job = -1;
static volatile sig_atomic_t gotalrm = 0;
static struct sigdata alrm_oact;
static bool pushed_alrm;

static void
onalrm(int sig __unused)
{
	gotalrm = 142;
	pendingsig = SIGALRM;
}

int
_alarm_cleanup(void)
{
	struct itimerval itv = {0};
	int ret;

	if (alarm_job == -1) {
		return (0);
	}
	INTOFF;
	assert(alarm_job == shpid);
	timerclear(&itv.it_interval);
	if (setitimer(ITIMER_REAL, &itv, NULL) == -1) {
		INTON;
		err(EXIT_FAILURE, "setitimer");
	}
	if (pushed_alrm) {
		trap_pop(SIGALRM, &alrm_oact);
		pushed_alrm = false;
	}
	ret = gotalrm;
	gotalrm = 0;
	alarm_job = -1;
	INTON;
	return (ret);
}

int
alarmcmd(int argc, char **argv)
{
	struct sigaction act;
	struct itimerval itv = {0};
	double timeout;
	int error, ret;

	if (argc > 2)
		errx(EX_USAGE, "%s", "Usage: alarm [timeout]");

	ret = 0;
	if (argc == 2) {
		INTOFF;
		if (alarm_job != -1) {
			(void)_alarm_cleanup();
		}
		assert(alarm_job == -1);
		timeout = parse_duration(argv[1]);
		if (timeout > 100000000L) {
			INTON;
			errx(EX_DATAERR, "timeout value");
		}
		/* timeout==0 is immediate timeout. */
		if (timeout == 0) {
			INTON;
			return (124);
		}
		itv.it_value.tv_sec = (time_t)timeout;
		timeout -= (time_t)timeout;
		itv.it_value.tv_usec =
		    (suseconds_t)(timeout * 1000000UL);
		alarm_job = shpid;

		trap_push(SIGALRM, &alrm_oact);
		pushed_alrm = true;

		memset(&act, 0, sizeof(act));
		act.sa_handler = onalrm;
		sigemptyset(&act.sa_mask);
		sigaction(SIGALRM, &act, NULL);

		if (setitimer(ITIMER_REAL, &itv, NULL) == -1) {
			trap_pop(SIGALRM, &alrm_oact);
			pushed_alrm = false;
			INTON;
			err(EX_OSERR, "setitimer");
		}
		INTON;
	} else {
		error = _alarm_cleanup();
		if (error != 0) {
			ret = error;
		}
	}

	return (ret);
}
