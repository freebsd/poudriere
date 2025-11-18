/* Included from external/sh/jobs.c */
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
#include <assert.h>
#include <stdbool.h>

static bool
job_has_pid(const struct job *jp, pid_t pid)
{
	if (!jp->used || jp->nprocs == 0)
		return (false);
	for (int n = 0; n < jp->nprocs; n++)
		if (jp->ps[n].pid == pid)
			return (true);
	return (false);
}

static struct job*
get_job_from_pid(pid_t pid)
{
	struct job *jp;

	for (jp = jobmru; jp != NULL; jp = jp->next) {
		if (job_has_pid(jp, pid)) {
			return (jp);
		}
	}
	for (jp = jobtab; jp < jobtab + njobs; jp++) {
		if (job_has_pid(jp, pid)) {
			return (jp);
		}
	}
	return (NULL);
}

int
get_job_idcmd(int argc, char *argv[])
{
	struct job *jp;
	char *outvar;
	pid_t pid;
	int ret;

	if (argc != 3)
		error("Usage: get_job_id pid outvar");
	pid = number(argv[1]);
	outvar = argv[2];
	jp = get_job_from_pid(pid);
	ret = 0;
	if (jp == NULL) {
		ret = 1;
		(void)unsetvar(outvar);
	} else {
		char value[10];

		fmtstr(value, sizeof(value), "%ld", jp - jobtab + 1);
		if (setvarsafe(outvar, value, 0))
			ret = 1;
	}
	return (ret);
}

static bool
get_job_status(const struct job *jp, char *outstr, size_t outstrsize)
{
	/* Taken from showjob(). */
	char statebuf[16];
	const char *statestr, *coredump;
	struct procstat *ps;
	int i, status;

	if (jp == NULL || jp->used == 0)
		return (false);

	coredump = "";
	status = getjobstatus(jp);
	if (jp->state == 0) {
		statestr = "Running";
#if JOBS
	} else if (jp->state == JOBSTOPPED) {
		ps = jp->ps + jp->nprocs - 1;
		while (!WIFSTOPPED(ps->status) && ps > jp->ps)
			ps--;
		if (WIFSTOPPED(ps->status))
			i = WSTOPSIG(ps->status);
		else
			i = -1;
		statestr = strsignal(i);
		if (statestr == NULL)
			statestr = "Suspended";
#endif
	} else if (WIFEXITED(status)) {
		if (WEXITSTATUS(status) == 0)
			statestr = "Done";
		else {
			fmtstr(statebuf, sizeof(statebuf), "Done(%d)",
			    WEXITSTATUS(status));
			statestr = statebuf;
		}
	} else {
		i = WTERMSIG(status);
		statestr = strsignal(i);
		if (statestr == NULL)
			statestr = "Unknown signal";
		if (WCOREDUMP(status))
			coredump = " (core dumped)";
	}
	fmtstr(outstr, outstrsize, "%s%s", statestr, coredump);
	return (true);
}

int
get_job_statuscmd(int argc, char *argv[])
{
	struct job *jp;
	char *outvar;
	char statestr[32];
	pid_t pid;
	int jobno, ret;

	if (argc != 3)
		error("Usage: get_job_status %%job|pid outvar");
	jp = NULL;
	outvar = argv[2];
	/* Ensure job status updates. */
	checkzombies();
	if (argv[1][0] == '%') {
		jobno = number(++argv[1]);
		if (jobno < 1 || jobno > njobs) {
			error("Invalid jobno");
		}
		jp = jobtab + jobno - 1;
	} else {
		pid = number(argv[1]);
		jp = get_job_from_pid(pid);
	}
	if (jp == NULL) {
		error("Job not found");
	}
	ret = 0;
	if (!get_job_status(jp, statestr, sizeof(statestr))) {
		(void)unsetvar(outvar);
		return (1);
	}
	if (setvarsafe(outvar, statestr, 0))
		ret = 1;
	return (ret);
}

int
jobs_with_statusescmd(int argc, char *argv[] __unused)
{
	struct job *jp;
	static int jobsidx;
	static int *jobsfilter = NULL;
	static size_t jobsfilter_size;
	const char *tmp_var, *job_var, *status_var, *pids_var, *tmp_val;
	char buf[32];
	int argn, jobno;

	if (argc < 5)
		error("Usage: jobs_with_statuses tmp_var job_var "
		    "status_var [pids_var] -- %%job...");
	argn = 1;
	tmp_var = argv[argn++];
	INTOFF;
	if ((tmp_val = lookupvar(tmp_var)) == NULL || tmp_val[0] == '\0') {
		jobsidx = 0;
		free(jobsfilter);
		jobsfilter = NULL;
		jobsfilter_size = 0;
		if (setvarsafe(tmp_var, "1", 0)) {
			goto bad;
		}
		/* Ensure job status updates. */
		checkzombies();
	} else if (
	    (jobsfilter != NULL && jobsidx == jobsfilter_size) ||
	    (jobsfilter == NULL && jobsidx > njobs)) {
		/* Done. */
		goto bad;
	}
	job_var = argv[argn++];
	status_var = argv[argn++];
	pids_var = NULL;
	if (strcmp(argv[argn], "--") != 0) {
		pids_var = argv[argn++];
		if (strcmp(argv[argn], "--") != 0) {
			INTON;
			error("Usage: jobs_with_statusescmd tmp_var job_var "
			    "status_var [pids_var] -- %%job...");
		}
	}
	argn++;
	// argv[argn]... now contains the job filter
	if (jobsfilter == NULL) {
		int filtern;

		filtern = 0;
		while (argn != argc) {
			if (argv[argn][0] != '%') {
				jobsidx = 0;
				free(jobsfilter);
				jobsfilter = NULL;
				jobsfilter_size = 0;
				(void)unsetvar(tmp_var);
				INTON;
				error("jobs_with_statuses: Only %%job is "
				    "supported");
			}
			jobno = number(argv[argn] + 1);
			jobsfilter_size++;
			jobsfilter = realloc(jobsfilter,
			    sizeof(*jobsfilter) * jobsfilter_size);
			jobsfilter[filtern++] = jobno;
			argn++;
		}
	}
	if (jobsfilter != NULL) {
		do {
			assert(jobsidx < jobsfilter_size);
			assert(jobsfilter[jobsidx] <= njobs);
			jp = jobtab + jobsfilter[jobsidx] - 1;
			jobsidx++;
		} while (jobsidx < jobsfilter_size &&
		    (jp->used == 0 || jp->nprocs == 0));
	} else {
		do {
			assert(jobsidx < njobs);
			jp = jobtab + jobsidx;
			jobsidx++;
		} while (jobsidx < njobs &&
		    (jp->used == 0 || jp->nprocs == 0));
	}
	if (jp == NULL || jp > jobtab + njobs - 1) {
		goto bad;
	}
	fmtstr(buf, sizeof(buf), "%%%ld", jp - jobtab + 1);
	if (setvarsafe(job_var, buf, 0)) {
		goto bad;
	}
	if (!get_job_status(jp, buf, sizeof(buf))) {
		goto bad;
	}
	if (setvarsafe(status_var, buf, 0)) {
		goto bad;
	}
	if (pids_var != NULL) {
		char *bufp;
		size_t bufsize, bufn, wantsize;

		bufn = 0;
		wantsize = (7 * jp->nprocs);
		/* Check if the small buf is big enough. */
		if (sizeof(buf) > wantsize) {
			bufsize = sizeof(buf);
			bufp = buf;
		} else {
			bufsize = wantsize;
			bufp = malloc(sizeof(*bufp) * bufsize);
		}
		for (int n = 0; n < jp->nprocs; n++) {
			bufn += snprintf(bufp + bufn,
			    bufsize - bufn, "%d ",
			    jp->ps[n].pid);
		}
		assert(bufp[bufn - 1] == ' ');
		bufp[bufn - 1] = '\0';
		if (setvarsafe(pids_var, bufp, 0)) {
			goto bad;
		}
		if (bufp != buf) {
			free(bufp);
		}
	}
	INTON;
	return (0);
bad:
	jobsidx = 0;
	free(jobsfilter);
	jobsfilter = NULL;
	jobsfilter_size = 0;
	(void)unsetvar(tmp_var);
	INTON;
	return (1);
}
