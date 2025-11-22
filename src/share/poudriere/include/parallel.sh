# Copyright (c) 2012-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

# shellcheck shell=ksh

_wait() {
	[ "$#" -ge 0 ] || eargs _wait '[%job|pid...]'
	local wret ret pid

	if [ "$#" -eq 0 ]; then
		return 0
	fi

	ret=0
	for pid in "$@"; do
		while :; do
			wret=0
			wait "${pid}" || wret="$?"
			case "${wret}" in
			157) # SIGINFO [EINTR]
				continue
				;;
			0) ;;
			*) ret="${wret}" ;;
			esac
			msg_dev "Job ${pid} collected ret=${wret}"
			break
		done
	done

	return "${ret}"
}

timed_wait_and_kill() {
	[ $# -eq 2 ] || eargs timed_wait_and_kill time pids
	local time="$1"
	local pids="$2"
	local status ret
	local -

	ret=0
	# Give children $time seconds to exit and then force kill
	set -o noglob
	# shellcheck disable=SC2086
	pwait -t "${time}" ${pids} || ret="$?"
	set +o noglob
	case "${ret}" in
	124)
		# Something still running, be more dramatic.
		kill_and_wait 1 "${pids}" || ret=$?
		;;
	*)
		# Nothing running, collect their status.
		set -o noglob
		# shellcheck disable=SC2086
		_wait ${pids} 2>/dev/null || ret=$?
		set +o noglob
		;;
	esac
	return "${ret}"
}

case "$(type pwait)" in
"pwait is a shell builtin")
	PWAIT_BUILTIN=1
	;;
esac
# Wrapper to fix SIGINFO [EINTR], -t 0, and ssert on errors.
pwait() {
	[ "$#" -ge 1 ] || eargs pwait '[pwait flags]' pids
	local OPTIND=1 flag
	local ret oflag tflag timeout time_start vflag

	tflag=
	while getopts "ot:v" flag; do
		case "${flag}" in
		o) oflag=1 ;;
		t) tflag="${OPTARG}" ;;
		v) vflag=1 ;;
		*) err 1 "pwait: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))

	[ "$#" -ge 1 ] || eargs pwait '[pwait flags]' pids
	case "${tflag:+set}" in
	set)
		time_start="$(clock -monotonic)"
		# pwait does not handle -t 0 well.
		case "${tflag:?}" in
		0) tflag="0.00001" ;;
		esac
		timeout="${tflag:?}"
		;;
	esac
	while :; do
		ret=0
		# If pwait is NOT builtin then sh will update its jobs state
		# which means we may pwait on dead procs unexpectedly. It returns
		# status==0 but may write to stderr.
		case "${PWAIT_BUILTIN:-0}" in
		1)
			# This not returning error assumes that the pid being waited on
			# is the only pid in the job. Multi-pid jobs may return
			# ESRCH on stderr.
			command pwait \
			    ${tflag:+-t "${timeout}"} \
			    ${vflag:+-v} ${oflag:+-o} \
			    "$@" || ret="$?"
			;;
		*)
			# allow vfork
			{
				command pwait \
				    ${tflag:+-t "${timeout}"} \
				    ${vflag:+-v} ${oflag:+-o} \
				    "$@" || ret="$?"
			} 2>/dev/null
			;;
		esac
		case "${ret}" in
		# Read again on SIGINFO interrupts
		157)
			case "${tflag:+set}" in
			set)
				if ! adjust_timeout "${tflag:?}" \
				    "${time_start:?}" timeout; then
					ret=124
					break
				fi
				;;
			esac
			continue
			;;
		esac
		break
	done
	case "${ret}" in
	124|0) return "${ret}" ;;
	esac
	err "${EX_SOFTWARE:-70}" "pwait: timeout=${timeout} pids=${pids} ret=${ret}"
}

kill_and_wait() {
	[ $# -eq 2 ] || eargs kill_and_wait time pids
	local time="$1"
	local pids="$2"
	local ret=0
	local -

	case "${pids}" in
	"") return 0 ;;
	esac

	{
		set -o noglob
		# shellcheck disable=SC2086
		kill -STOP ${pids} || :
		# shellcheck disable=SC2086
		kill ${pids} || :
		# shellcheck disable=SC2086
		kill -CONT ${pids} || :

		# Wait for the pids. Non-zero status means something is still running.
		# shellcheck disable=SC2086
		pwait -t "${time}" ${pids} || ret="$?"
		case "${ret}" in
		124)
			# Kill remaining children instead of waiting on them
			# shellcheck disable=SC2086
			kill -9 ${pids} || :
			# shellcheck disable=SC2086
			_wait ${pids} || ret=$?
			;;
		*)
			# Nothing running, collect status directly.
			# shellcheck disable=SC2086
			_wait ${pids} || ret=$?
			;;
		esac
		set +o noglob
	}
	return "${ret}"
}

timed_wait_and_kill_job() {
	[ "$#" -eq 2 ] || eargs timed_wait_and_kill_job time '%job'
	local timeout="$1"
	local jobid="$2"

	case "${jobid}" in
	"%"*) ;;
	*)
		err "${EX_USAGE}" "timed_wait_and_kill_job: Only %jobid is supported."
		;;
	esac

	# Wait $timeout
	# kill -TERM
	# Wait 1
	# kill -KILL
	_kill_job timed_wait_and_kill_job "${jobid}" \
	    ":${timeout}" TERM ":1" KILL
}

kill_job() {
	[ "$#" -eq 2 ] || eargs kill_job timeout '%job|pid'
	local timeout="$1"
	local jobid="$2"

	# kill -TERM
	# Wait $timeout
	# kill -KILL
	_kill_job kill_job "${jobid}" \
	    TERM ":${timeout}" "${KILL_JOB_FINAL_SIGNAL:-KILL}"
}

# _kill_job funcname jobid :${wait-timeout} SIG :${wait-timeout} SIG
_kill_job() {
	[ "$#" -ge 3 ] || eargs _kill_job funcname '%job|pid' 'killspec'
	local funcname="$1"
	local jobid="$2"
	local timeout ret pgid status action

	shift 2
	if ! jobid "${jobid}" >/dev/null; then
		case "${jobid}" in
		"%"*) ;;
		*)
			if jobid "%${jobid}" >/dev/null; then
				err "${EX_SOFTWARE}" "${funcname}: trying to kill unknown job ${jobid}: Did you mean %${jobid}?"
			fi
			;;
		esac
		err "${EX_SOFTWARE}" "${funcname}: trying to kill unknown job ${jobid}"
	fi
	ret=0
	case "${jobid}" in
	"%"*)
		if msg_level dev; then
			# pgid only used in msg_dev calls
			pgid="$(jobs -p "${jobid}")"
		else
			unset pgid
		fi
		;;
	*)
		pgid="${jobid}"
		get_job_id "${pgid}" jobid ||
		    err "${EX_SOFTWARE}" "${funcname}: Failed to get jobid for pgid=${pgid}"
		jobid="%${jobid}"
		;;
	esac
	msg_dev "${funcname} job ${jobid} pgid=${pgid-} spec: $*"
	for action in "$@"; do
		case "${action}" in
		":"*) timeout="${action#:}" ;;
		*) unset timeout ;;
		esac
		get_job_status "${jobid}" status ||
		    err "${EX_SOFTWARE}" "${funcname}: Could not get status for job ${jobid}"
		case "${status}" in
		"Running")
			case "${timeout:+set}" in
			set)
				msg_dev "Pwait -t ${timeout} on ${status}" \
				    "job=${jobid} pgid=${pgid-}"
				case "${jobid}" in
				"%"*)
					pwait_jobs -t "${timeout}" "${jobid}" ||
					    ret="$?"
					;;
				*)
					pwait -t "${timeout}" "${pgid}" || ret="$?"
					;;
				esac
				msg_dev "Pwait -t ${timeout} on ${status}" \
				    "job=${jobid} pgid=${pgid-} ret=${ret}"
				case "${ret}" in
				124)
					# Timeout. Keep going on the
					# action list.
					continue
					;;
				*)
					# Nothing running. Drop out and wait.
					break
					;;
				esac
				;;
			*)
				msg_dev "Killing -${action} ${status}" \
				    "job=${jobid} pgid=${pgid-}"
				if ! kill -STOP "${jobid}" ||
				    ! kill -"${action}" "${jobid}" ||
				    ! kill -CONT "${jobid}"; then
					# This should never happen
					err "${EX_SOFTWARE}" "${funcname}: Error killing ${jobid}: $?"
				fi
				;;
			esac
			;;
		*)
			# Nothing running. Drop out and wait.
			;;
		esac
	done
	msg_dev "Collecting status='${status}' job=${jobid} pgid=${pgid-}"
	# Truncate away pwait timeout for whatever the process exited with
	# from the spec.
	case "${ret}" in
	124) ret=0 ;;
	esac
	_wait "${jobid}" || ret="$?"
	msg_dev "Job ${jobid} pgid=${pgid-} exited ${ret}"
	return "${ret}"
}

pwait_jobs() {
	[ "$#" -ge 0 ] || eargs pwait_jobs '[pwait flags]' '%job...'
	local job pid pids allpids job_status
	local OPTIND=1 flag
	local oflag timeout vflag
	# shellcheck disable=SC2034
	local jobs_it
	local -

	while getopts "ot:v" flag; do
		case "${flag}" in
		o) oflag=1 ;;
		t) timeout="${OPTARG}" ;;
		v) vflag=1 ;;
		*) err 1 "pwait: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))

	case "$#" in
	0) return 0 ;;
	esac

	allpids=
	pids=
	unset jobs_it
	while jobs_with_statuses jobs_it job job_status pids -- "$@"; do
		# Unless the job is *Running* there is nothing to do.
		case "${job_status:?}" in
		"Running") ;;
		*) continue ;;
		esac
		for pid in ${pids}; do
			if ! kill -0 "${pid:?}" 2>&5; then
				continue
			fi
			allpids="${allpids:+${allpids} }${pid:?}"
		done
	done 5>/dev/null
	case "${allpids:+set}" in
	set) ;;
	*)
		# No pids to check. So everything is Done.
		return 0
		;;
	esac
	set -o noglob
	# shellcheck disable=SC2086
	pwait -t "${timeout}" ${vflag:+-v} ${oflag:+-o} ${allpids}
}

kill_jobs() {
	[ "$#" -ge 1 ] || eargs kill_jobs '[timeout]' '%job...'
	local timeout="${1:-5}"
	shift
	local ret kret jobno

	case "$#" in
	0) return 0 ;;
	esac
	ret=0
	for jobno in "$@"; do
		case "${jobno}" in
		"%"*) ;;
		*) err "${EX_SOFTWARE}" "kill_jobs: invalid job spec: ${jobno}" ;;
		esac
		kret=0
		kill_job "${timeout}" "${jobno}" || kret="$?"
		# Don't truncate a non-TERM ret with a TERM ret.
		case "${kret}" in
		143)
			case "${ret}" in
			0) ret="${kret}" ;;
			esac
			;;
		*)
			ret="${kret}"
			;;
		esac
	done
	return "${ret}"
}

kill_all_jobs() {
	[ "$#" -eq 0 ] || [ "$#" -eq 1 ] || eargs kill_all_jobs '[timeout]'
	local timeout="${1:-5}"
	local jobid ret rest alljobs
	local -

	if msg_level dev; then
		msg_dev "Jobs: $(jobs -l)"
	fi
	ret=0
	alljobs=
	while mapfile_read_loop_redir jobid rest; do
		case "${jobid:+set}" in
		set) ;;
		*) continue ;;
		esac
		case "${jobid}" in
		"["*"]")
			# [1] + 52255 Running
			;;
		*)
			# If a job has a pipe it may list out multiple pids.
			# The jobid gets read on the first line.
			# [1] + 52255 Running
			#       52256
			continue
			;;
		esac
		jobid="${jobid#"["}"
		jobid="${jobid%%"]"*}"
		alljobs="${alljobs:+${alljobs} }%${jobid}"
	done <<-EOF
	$(jobs -l)
	EOF
	set -o noglob
	# shellcheck disable=SC2086
	kill_jobs "${timeout}" ${alljobs} || ret="$?"
	set +o noglob
	return "${ret}"
}

_parallel_exec_exit() {
	local ret="$?"
	echo . >&8
	return "${ret}"
}

_parallel_exec() {
	setup_traps _parallel_exec_exit
	"$@"
}

parallel_start() {
	local fifo

	case "${NBPARALLEL:+set}" in
	set)
		echo "parallel_start: Already started" >&2
		return 1
		;;
	esac
	fifo="$(mktemp -ut parallel.pipe)"
	mkfifo "${fifo}"
	exec 8<> "${fifo}"
	unlink "${fifo}" || :
	NBPARALLEL=0
	PARALLEL_JOBNOS=""
	: "${PARALLEL_JOBS:="$(nproc)"}"
	_SHOULD_REAP=0
	delay_pipe_fatal_error
}

# For all running children, look for dead ones, collect their status, error out
# if any have non-zero return, and then remove them from the PARALLEL_JOBNOS
# list.
_reap_children() {
	local job job_status ret
	# shellcheck disable=SC2034
	local jobs_it
	local -

	ret=0
	case "${PARALLEL_JOBNOS:+set}" in
	set) ;;
	*) return 0 ;;
	esac
	set -o noglob
	unset jobs_it
	# shellcheck disable=SC2086
	while jobs_with_statuses jobs_it job job_status -- \
	    ${PARALLEL_JOBNOS}; do
		case "${job_status:?}" in
		"Running") continue ;;
		esac
		_wait "${job:?}" || ret="$?"
		list_remove PARALLEL_JOBNOS "${job:?}" ||
		    err 1 "_reap_children did not find ${job} in PARALLEL_JOBNOS"
	done
	return "${ret}"
}

# Wait on all remaining running processes and clean them up. Error out if
# any have non-zero return status.
parallel_stop() {
	[ "$#" -eq 0 ] || [ "$#" -eq 1 ] || eargs parallel_stop '[do_wait]'
	local do_wait="${1:-1}"
	local ret
	local jobno -

	ret=0
	if [ "${do_wait}" -eq 1 ]; then
		set -o noglob
		# shellcheck disable=SC2086
		_wait ${PARALLEL_JOBNOS} || ret="$?"
		set +o noglob
	fi

	exec 8>&-
	unset PARALLEL_JOBNOS
	unset NBPARALLEL

	case "${ret}" in
	0)
		if check_pipe_fatal_error; then
			ret=1
		fi
		;;
	esac

	return "${ret}"
}

parallel_shutdown() {
	local ret -
	local parallel_jobnos jobno

	set -o noglob
	ret=0
	# PARALLEL_JOBNOS may be stale if we received SIGINT while
	# inside of parallel_stop() or _reap_children(). Clean it up
	# before kill_job() is called which asserts that all jobs are
	# known.
	unset parallel_jobnos
	for jobno in ${PARALLEL_JOBNOS-}; do
		if ! jobid "${jobno}"; then
			continue
		fi
		parallel_jobnos="${parallel_jobnos:+${parallel_jobnos} }${jobno}"
	done >/dev/null 2>&1
	# shellcheck disable=SC2086
	kill_jobs 30 ${parallel_jobnos-} || ret="$?"
	parallel_stop 0 || ret="$?"
	return "${ret}"
}

: "${PARALLEL_REAP_PERCENT:=200}"
parallel_run() {
	local ret
	local spawn_jobid spawn_job spawn_pgid spawn_pid

	ret=0
	case "${NBPARALLEL:+set}" in
	set) ;;
	*) err 1 "parallel_run: did not parallel_start" ;;
	esac

	# Occasionally reap dead children. Don't do this too often or it
	# becomes a bottleneck.
	_SHOULD_REAP="$((_SHOULD_REAP + 1))"
	case "${_SHOULD_REAP}" in
	"$(((PARALLEL_JOBS * PARALLEL_REAP_PERCENT) / 100))")
		msg_dev "parallel_run: REAPING AT ${_SHOULD_REAP} JOBS=${PARALLEL_JOBS}"
		_SHOULD_REAP=0
		_reap_children || ret="$?"
		;;
	esac

	# Only read once all slots are taken up; burst jobs until maxed out.
	# NBPARALLEL is never decreased and only increased until maxed.
	case "${NBPARALLEL}" in
	"${PARALLEL_JOBS}")
		local a

		if read_blocking a <&8; then
			case "${a}" in
			".") ;;
			*) err 1 "parallel_run: Invalid token: ${a}" ;;
			esac
		fi
		;;
	esac

	if [ "${NBPARALLEL}" -lt "${PARALLEL_JOBS}" ]; then
		NBPARALLEL="$((NBPARALLEL + 1))"
	fi
	PARALLEL_CHILD=1 spawn_job _parallel_exec "$@"
	list_add PARALLEL_JOBNOS "%${spawn_jobid}"

	return "${ret}"
}

nohang() {
	[ "$#" -gt 5 ] || eargs nohang cmd_timeout log_timeout logfile pidfile cmd
	local cmd_timeout
	local log_timeout
	local logfile
	local pidfile
	local childpid
	local now starttime
	local fifo
	local n
	local read_timeout
	local ret=0

	cmd_timeout="$1"
	log_timeout="$2"
	logfile="$3"
	pidfile="$4"
	shift 4

	read_timeout="$((log_timeout / 10))"

	fifo="$(mktemp -ut nohang.pipe)"
	mkfifo "${fifo}"
	# If the fifo is over NFS, newly created fifos have the server's
	# mtime not the client's mtime until the client writes to it
	touch "${fifo}"
	exec 8<> "${fifo}"
	unlink "${fifo}" || :

	starttime="$(clock -epoch)"

	# Run the actual command in a child subshell
	(
		trap 'exit 130' INT
		local ret=0
		if [ "${OUTPUT_REDIRECTED:-0}" -eq 1 ]; then
			exec 3>&- 4>&-
			unset OUTPUT_REDIRECTED OUTPUT_REDIRECTED_STDERR \
			    OUTPUT_REDIRECTED_STDOUT
		fi
		setproctitle "nohang (${logfile})" || :
		SUPPRESS_INT=1 _spawn_wrapper "$@" || ret=$?
		# Notify the pipe the command is done
		echo "done" >&8 2>/dev/null || :
		exit "${ret}"
	) &
	childpid=$!
	msg_dev "nohang spawned pid=${childpid} cmd: $*"
	echo "${childpid}" > "${pidfile}"

	# Now wait on the cmd with a timeout on the log's mtime
	while :; do
		if ! kill -0 "${childpid}" 2>/dev/null; then
			_wait "${childpid}" || ret=1
			break
		fi

		# Wait until it is done, but check on it every so often
		# This is done instead of a 'sleep' as it should recognize
		# the command has completed right away instead of waiting
		# on the 'sleep' to finish
		n=
		read_blocking -t "${read_timeout}" n <&8 || :
		case "${n}" in
		done)
			_wait "${childpid}" || ret=1
			break
			;;
		esac

		# Not done, was a timeout, check the log time
		lastupdated="$(stat -f "%m" "${logfile}")"
		now="$(clock -epoch)"

		# No need to actually kill anything as stop_build()
		# will be called and kill -9 -1 the jail later
		if [ "$((now - lastupdated))" -gt "${log_timeout}" ]; then
			ret=2
			break
		elif [ "$((now - starttime))" -gt "${cmd_timeout}" ]; then
			ret=3
			break
		fi
	done

	exec 8>&-

	unlink "${pidfile}" || :

	return "${ret}"
}

if [ -f /usr/bin/protect ] && [ "$(/usr/bin/id -u)" -eq 0 ]; then
	PROTECT=/usr/bin/protect
fi
madvise_protect() {
	[ "$#" -eq 1 ] || eargs madvise_protect pid
	local pid="$1"

	case "${PROTECT:+set}" in
	set) ;;
	*)
		return 0
		;;
	esac
	case "${pid}" in
	-*)
		msg_debug "Protecting PGID ${pid}"
		# allow vfork
		{ ${PROTECT} -g "${pid#-}"; } 2>/dev/null || :
		;;
	*)
		msg_debug "Protecting process ${pid}"
		# allow vfork
		{ ${PROTECT} -p "${pid}"; } 2>/dev/null || :
		;;
	esac
}

# while jobs_with_statuses jobs_it job status -- %1 ...; do
# 	echo "${job} ${status}"
# done
if ! have_builtin jobs_with_statuses; then
jobs_with_statuses() {
	[ "$#" -ge 4 ] ||
	    eargs jobs_with_statuses tmpvar job_var status_var \
	    '[pids_var]' '--' '%job...'
	local jws_stackvar="$1"
	local jws_stack
	[ "$#" -ge 3 ] ||
	    eargs jobs_with_statuses tmpvar job_var status_var \
	    '[pids_var]' '--' '%job...'
	shift
	local jws_job_var="$1"
	local jws_status_var="$2"
	shift 2
	[ "$#" -ge 1 ] ||
	    eargs jobs_with_statuses tmpvar job_var status_var \
	    '[pids_var]' '--' '%job...'
	local jws_pids_var=
	case "$1" in
	"--") shift ;;
	*)
		[ "$#" -ge 1 ] ||
		    eargs jobs_with_statuses tmpvar job_var status_var \
		    '[pids_var]' '--' '%job...'
		jws_pids_var="$1"
		shift
		case "$1" in
		"--") shift ;;
		*) err "${EX_USAGE:-64}" \
		    "jobs_with_statuses: Expected '--' after vars" ;;
		esac
		;;
	esac
	if ! getvar "${jws_stackvar:?}" jws_stack; then
		jws_stack="JWS_STACK"
		setvar "${jws_stackvar:?}" "${jws_stack:?}" || return
		if ! _jobs_with_statuses "${jws_stack:?}" "$@"; then
			return 1
		fi
	fi
	local jws_line

	jws_line=
	if ! stack_pop "${jws_stack:?}" jws_line; then
		return 1
	fi
	local -
	set -o noglob
	# shellcheck disable=SC2086
	set -- ${jws_line}
	set +o noglob
	setvar "${jws_job_var:?}" "${1:?}" || return
	setvar "${jws_status_var:?}" "${2:?}" || return
	case "${jws_pids_var:+set}" in
	set)
		shift 2
		setvar "${jws_pids_var:?}" "$*" || return
		;;
	esac
}

_jobs_with_statuses() {
	[ "$#" -ge 1 ] ||
	    eargs _jobs_with_statuses jobs_stackvar '%job..'
	local _jws_stackvar="$1"
	shift
	local _jws_jobs_jobid _jws_jobs_rest
	local _jws_jobid _jws_status _jws_pids
	local _jws_arg _jws_filter _jws_jobs
	local -

	_jws_jobs="$(jobs)"
	case "${_jws_jobs:+set}" in
	set) ;;
	*)
		stack_unset "${_jws_stackvar:?}" || return
		return 0
		;;
	esac
	case "$#" in
	0) _jws_filter= ;;
	*)
		for _jws_jobs_jobid in "$@"; do
			case "${_jws_jobs_jobid}" in
			"%"*) ;;
			*)
				err "${EX_USAGE}" "_jobs_with_statuses:" \
				    "Only %jobid is supported."
				;;
			esac
			_jws_filter="${_jws_filter:+${_jws_filter} }[${_jws_jobs_jobid#%}]"
		done
		;;
	esac
	stack_unset "${_jws_stackvar:?}" || return
	while mapfile_read_loop_redir _jws_jobs_jobid _jws_jobs_rest; do
		case "${_jws_filter:+set}" in
		set)
			case " ${_jws_filter} " in
			*" ${_jws_jobs_jobid} "*) ;;
			*) continue ;;
			esac
			;;
		esac
		case "${_jws_jobs_jobid}" in
		"["*"]")
			_jws_jobid="${_jws_jobs_jobid#"["}"
			_jws_jobid="${_jws_jobid%%"]"*}"
			;;
		*) continue ;;
		esac
		set -o noglob
		# shellcheck disable=SC2086
		set -- ${_jws_jobs_rest}
		set +o noglob
		for _jws_arg in "$@"; do
			case "${_jws_arg}" in
			"+"|"-") continue ;;
			[0-9][0-9]|\
			[0-9][0-9][0-9]|\
			[0-9][0-9][0-9][0-9]|\
			[0-9][0-9][0-9][0-9][0-9]|\
			[0-9][0-9][0-9][0-9][0-9][0-9]|\
			[0-9][0-9][0-9][0-9][0-9][0-9][0-9]|\
			[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) continue ;;
			*)
				_jws_status="${_jws_arg}"
				break
				;;
			esac
		done
		_jws_pids="$(jobid "%${_jws_jobid:?}")"
		stack_push_back "${_jws_stackvar:?}" \
		    "%${_jws_jobid:?} ${_jws_status:?} ${_jws_pids:?}"
	done <<-EOF
	${_jws_jobs:?}
	EOF
}
fi

if ! have_builtin get_job_status; then
get_job_status() {
	[ "$#" -eq 2 ] || eargs get_job_status '%job|pid' var_return
	local gjs_pid="$1"
	local gjs_var_return="$2"
	local gjs_output ret
	local - gjs_arg

	# Trigger checkzombies(). pwait_racy() in jobs.sh test can make it
	# appear that this is useless since it execs ps and forces a check.
	# But without an external fork+exec, or jobs(1) call, the job status
	# does not update.
	# The $(jobs -l $pid) does not lead to checkzombies() as it runs
	# through showjob() rather than showjobs()->checkzombies().
	jobs >/dev/null || err 1 "get_job_status: jobs failed $?"
	ret=0
	gjs_output="$(jobs -l "${gjs_pid}")" || ret="$?"
	case "${gjs_pid}" in
	"%"*)
		case "${gjs_output}" in
		"[${gjs_pid#%}] "?" "*)
			;;
		"")
			setvar "${gjs_var_return}" "" || return
			return "${ret}"
			;;
		*)
			err "${EX_SOFTWARE}" "get_job_status: Failed to parse jobs -l output for job ${gjs_pid}: $(echo "${gjs_output}" | cat -vet)"
			;;
		esac
		;;
	*)
		case "${gjs_output}" in
		# First cases cover piped jobs.
		"["*"] "?" "[0-9]*$'\n'*" "[0-9]*$'\n'*" ${gjs_pid} "*|\
		"["*"] "?" "[0-9]*$'\n'*" ${gjs_pid} "*|\
		"["*"] "?" ${gjs_pid} "*)
			;;
		"")
			setvar "${gjs_var_return}" "" || return
			return "${ret}"
			;;
		*)
			err "${EX_SOFTWARE}" "get_job_status: Failed to parse jobs -l output for pid ${gjs_pid}: $(echo "${gjs_output}" | cat -vet)"
			;;
		esac
		;;
	esac
	set -o noglob
	# shellcheck disable=SC2086
	set -- ${gjs_output}
	set +o noglob
	local gjs_n
	gjs_n=0
	# shellcheck disable=SC2167
	for gjs_arg in "$@"; do
		gjs_n="$((gjs_n + 1))"
		case "${gjs_arg}" in
		"["*"]") continue ;;
		"+"|"-") continue ;;
		[0-9][0-9]|\
		[0-9][0-9][0-9]|\
		[0-9][0-9][0-9][0-9]|\
		[0-9][0-9][0-9][0-9][0-9]|\
		[0-9][0-9][0-9][0-9][0-9][0-9]|\
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9]|\
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) continue ;;
		*)
			local gjs_reason

			unset gjs_reason
			shift "$((gjs_n - 1))"
			# shellcheck disable=SC2165
			for gjs_arg in "$@"; do
				case "${gjs_arg}" in
				[0-9]*)
					break
					;;
				*)
					gjs_reason="${gjs_reason:+${gjs_reason} }${gjs_arg}"
					;;
				esac
			done
			setvar "${gjs_var_return}" "${gjs_reason}" || return
			return 0
		esac
	done

	setvar "${gjs_var_return}" "" || return
	return 1
}
fi

if ! have_builtin get_job_id; then
get_job_id() {
	[ "$#" -eq 2 ] || eargs get_job_id pid var_return
	local gji_pid="$1"
	local gji_var_return="$2"
	local gji_jobid gji_output ret

	ret=0
	gji_output="$(jobs -l "${gji_pid}")" || ret="$?"
	case "${gji_output}" in
	# First cases cover piped jobs.
	"["*"] "?" "[0-9]*$'\n'*" "[0-9]*$'\n'*" ${gji_pid} "*|\
	"["*"] "?" "[0-9]*$'\n'*" ${gji_pid} "*|\
	"["*"] "?" ${gji_pid} "*)
		;;
	"")
		setvar "${gji_var_return}" "" || return
		return "${ret}"
		;;
	*)
		err "${EX_SOFTWARE}" "get_job_id: Failed to parse jobs -l output for pid ${gji_pid}: $(echo "${gji_output}" | cat -vet)"
		;;
	esac
	gji_jobid="${gji_output#"["}"
	gji_jobid="${gji_jobid%%"]"*}"
	setvar "${gji_var_return}" "${gji_jobid}"
}
fi

spawn_job() {
	local -

	set -m
	spawn_jobid=
	spawn "$@" || return
	get_job_id "$!" spawn_jobid || return
	spawn_job="%${spawn_jobid}"
	spawn_pgid="$(jobs -p "${spawn_job:?}")"
	spawn_pid="$!"
	msg_dev "spawn_job: Spawned job ${spawn_job:?} pgid=${spawn_pgid:?} pid=${spawn_pid:?} cmd=$*"
}

spawn_job_protected() {
	spawn_job "$@" || return
	madvise_protect "-$!" || return
}

_spawn_wrapper() {
	case $- in
	*m*)	# Job control
		# Don't stop processes if they try using TTY.
		trap '' SIGTTIN
		trap '' SIGTTOU
		;;
	*)	# No job control
		# Reset SIGINT to the default to undo POSIX's SIG_IGN in
		# 2.11 "Signals and Error Handling". This will ensure no
		# foreground process is left around on SIGINT.
		# This is only relevant for asynchronous lists, &, which
		# _spawn_wrapper is expected to be used in.
		case "${SUPPRESS_INT:-0}" in
		0)
			trap - INT
			;;
		esac
		;;
	esac
	# No need to keep job control on.
	# It also would block vfork if left on.
	set +m

	"$@"
}

# Note that 'spawn foo < $fifo' will block but 'foo < $fifo &' will not.
spawn() {
	_spawn_wrapper "$@" &
}

spawn_protected() {
	spawn "$@"
	madvise_protect $! || :
}

_coprocess_wrapper() {
	setproctitle "$1"
	"$@"
}

# Start a background process from function 'name'.
coprocess_start() {
	[ "$#" -eq 1 ] || eargs coprocess_start name
	local name="$1"
	local main pid jobid

	main="${name}_main"
	spawn_job_protected _coprocess_wrapper "${main}"
	pid=$!
	jobid="${spawn_jobid}"

	hash_set coprocess_pid "${name}" "${pid}"
	hash_set coprocess_jobid "${name}" "${jobid}"

	return 0
}

coprocess_stop() {
	[ "$#" -eq 1 ] || eargs coprocess_stop name
	local name="$1"
	local ret pid jobid

	hash_remove coprocess_pid "${name}" pid || return 0
	hash_remove coprocess_jobid "${name}" jobid || return 0

	ret=0
	kill_job 60 "%${jobid}" || ret="$?"
	case "${ret}" in
	143) ret=0 ;;
	esac
	return "${ret}"
}

raise() {
	local sig="$1"

	kill -"${sig}" "$(getpid)"
}

setreturnstatus() {
	[ $# -eq 1 ] || eargs setreturnstatus ret
	local ret="$1"

	# This case is because the callers cannot do any conditional checks.
	case "${ret-}" in
	[0-9]*) return "${ret}" ;;
	esac
	return 0
}

# Need to cleanup some stuff before calling traps.
# This is ran with 2>/dev/null
# _ERET is done to chain exitstatus down to all handlers.
_trap_pre_handler() {
	_ERET="$?"
	unset IFS
	set +u
	case "$-" in
	*e*) ;;
	*)
		# shellcheck disable=SC2034
		ERROR_VERBOSE=0
		;;
	esac
	set +e
	trap '' PIPE INT INFO HUP TERM
	SUPPRESS_INT=1
	redirect_to_real_tty exec
	case "$-" in
	*x*) _trap_x=x ;;
	esac
	set +x
	return "${_ERET}"
}
_trap_pre_handler2() {
	_ERET="$?"
	case "$-" in
	*x*) err 1 "_trap_pre_handler2: set -x should not be on here" ;;
	esac
	# Fix stderr
	redirect_to_real_tty exec
	return "${_ERET}"
}
# {} 2>/dev/null is used to avoid set -x SIGPIPE; set +x done in there.
# after set +x is done we call _trap_pre_handler2 to redirect stderr.
alias trap_pre_handler='{ _trap_pre_handler; } 2>/dev/null; _trap_pre_handler2'
sig_handler() {
	local ret
	local -

	case "${SHFLAGS-$-}${_trap_x-}${SETX_EXIT:-0}" in
	*x*1) set -x ;;
	*) set +x ;;
	esac

	[ $# -eq 1 ] || eargs sig_handler sig

	local sig="$1"
	local exit_handler

	trap - EXIT
	# shellcheck disable=SC2034
	EXIT_BSTATUS="SIG${sig:?}:"
	case "${USE_DEBUG:-no}.$$" in
	yes.*|"no.$(getpid)")
		msg "[$(getpid)${PROC_TITLE:+:${PROC_TITLE}}] Signal ${sig} caught" >&2
		;;
	esac
	# Let the handler know what status is being exited with even though
	# we will later reraise it.
	# Would be nice if we could (raise "${sig}") here but it does not
	# set $? while inside of a trap.
	local sig_ret

	case "${sig}" in
	TERM) sig_ret=$((128 + 15)) ;;
	INT)  sig_ret=$((128 + 2)) ;;
	HUP)  sig_ret=$((128 + 1)) ;;
	PIPE) sig_ret=$((128 + 13)) ;;
	*)    sig_ret= ;;
	esac
	# return ignored since we will exit on signal
	local TRAPSVAR
	# shellcheck disable=SC2034
	local tmp

	TRAPSVAR="TRAPS$(getpid)"
	ret="${sig_ret}"
	unset tmp
	while stack_foreach "${TRAPSVAR}" exit_handler tmp; do
		# Ensure the handler sees the real status.
		# Don't wrap around if/case/etc.
		setreturnstatus "${sig_ret-}"
		"${exit_handler}" || ret="$?"
	done
	trap - "${sig}"
	# A handler may have changed the status, but if not raise.
	if [ "${ret}" -gt 128 ]; then
		raise "$(kill -l "${ret}")"
	else
		exit "${ret}"
	fi
}

# Take "return" value from real exit handler and exit with it.
exit_return() {
	local ret="$?"
	local -

	# shellcheck disable=SC2034
	IN_EXIT_HANDLER=1
	trap - EXIT

	case "${SHFLAGS-$-}${_trap_x-}${SETX_EXIT:-0}" in
	*x*1) set -x ;;
	*) set +x ;;
	esac

	[ $# -eq 0 ] || eargs exit_return

	local exit_handler TRAPSVAR
	# shellcheck disable=SC2034
	local tmp

	TRAPSVAR="TRAPS$(getpid)"
	unset tmp
	while stack_foreach "${TRAPSVAR}" exit_handler tmp; do
		# Ensure the real handler sees the real status
		# Don't wrap around if/case/etc.
		setreturnstatus "${ret-}"
		"${exit_handler}" || ret="$?"
	done
	exit "${ret}"
}

setup_traps() {
	[ "$#" -eq 0 ] || [ "$#" -eq 1 ] ||
	    eargs setup_traps '[exit_handler]'
	local exit_handler="$1"
	local sig TRAPSVAR

	TRAPSVAR="TRAPS$(getpid)"
	if ! stack_isset "${TRAPSVAR}"; then
		for sig in INT HUP PIPE TERM; do
			# shellcheck disable=SC2064
			trap "trap_pre_handler; sig_handler ${sig}" "${sig}"
		done
		trap "trap_pre_handler; exit_return" EXIT
	fi
	case "${exit_handler:+set}" in
	set)
		stack_push_front "${TRAPSVAR}" "${exit_handler}"
		;;
	esac
}
