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

_wait() {
	# Workaround 'wait' builtin possibly returning early due to signals
	# by using 'pwait' to wait(2) and then 'wait' to collect return code
	local ret=0 pid

	pwait "$@" 2>/dev/null || :
	for pid in "$@"; do
		wait ${pid} || ret=$?
	done

	return ${ret}
}

timed_wait_and_kill() {
	[ $# -eq 2 ] || eargs timed_wait_and_kill time pids
	local time="$1"
	local pids="$2"
	local status ret

	ret=0

	# Give children $time seconds to exit and then force kill
	if ! timed_wait ${time} "${pids}"; then
		# Something still running, be more dramatic.
		kill_and_wait 1 "${pids}" || ret=$?
	else
		# Nothing running, collect their status.
		wait ${pids} || ret=$?
	fi

	return ${ret}
}

timed_wait() {
	[ $# -eq 2 ] || eargs timed_wait time pids
	local time="$1"
	local pids="$2"
	local status

	[ -z "${pids}" ] && return 0

	status=0
	# Wait for the pids.
	timeout ${time} pwait ${pids} 2>/dev/null >&1 || status=$?
	if [ ${status} -eq 124 ]; then
		# Timeout reached, something still running.
		return 1
	elif [ ${status} -gt 128 ]; then
		# XXX: Some signal interrupted the timeout check. Consider
		# it a failure.
		return 1
	fi

	return 0
}


kill_and_wait() {
	[ $# -eq 2 ] || eargs kill_and_wait time pids
	local time="$1"
	local pids="$2"
	local ret=0

	[ -z "${pids}" ] && return 0

	kill ${pids} 2>/dev/null || :

	# Wait for the pids. Non-zero status means something is still running.
	if ! timed_wait ${time} "${pids}"; then
		# Kill remaining children instead of waiting on them
		kill -9 ${pids} 2>/dev/null || :
		_wait ${pids} || ret=$?
	else
		# Nothing running, collect status directly.
		wait ${pids} || ret=$?
	fi

	return ${ret}
}


parallel_exec() {
	local cmd="$1"
	local ret=0
	local - # Make `set +e` local
	local errexit=0
	shift 1

	# Disable -e so that the actual execution failing does not
	# return early and prevent notifying the FIFO that the
	# exec is done
	case $- in *e*) errexit=1;; esac
	set +e
	(
		# Do still cause the actual command to return
		# non-zero if it has any failures, if caller
		# was set -e as well. Using 'if cmd' or 'cmd || '
		# here would disable set -e in the cmd execution
		[ $errexit -eq 1 ] && set -e
		${cmd} "$@"
	)
	ret=$?
	echo >&9 || :
	exit ${ret}
	# set -e will be restored by 'local -'
}

parallel_start() {
	local fifo

	if [ -n "${MASTERMNT}" ]; then
		fifo=${MASTERMNT}/.p/parallel.pipe
	else
		fifo=$(mktemp -ut parallel)
	fi
	mkfifo ${fifo}
	exec 9<> ${fifo}
	rm -f ${fifo}
	export NBPARALLEL=0
	export PARALLEL_PIDS=""
	: ${PARALLEL_JOBS:=$(sysctl -n hw.ncpu)}
	_SHOULD_REAP=0
}

# For all running children, look for dead ones, collect their status, error out
# if any have non-zero return, and then remove them from the PARALLEL_PIDS
# list.
_reap_children() {
	local pid
	local ret=0

	for pid in ${PARALLEL_PIDS}; do
		# Check if this pid is still alive
		if ! kill -0 ${pid} 2>/dev/null; then
			# This will error out if the return status is non-zero
			_wait ${pid} || ret=$?
			# Remove pid from PARALLEL_PIDS and strip away all
			# spaces
			PARALLEL_PIDS_L=${PARALLEL_PIDS%% ${pid} *}
			PARALLEL_PIDS_L=${PARALLEL_PIDS_L% }
			PARALLEL_PIDS_L=${PARALLEL_PIDS_L# }
			PARALLEL_PIDS_R=${PARALLEL_PIDS##* ${pid} }
			PARALLEL_PIDS_R=${PARALLEL_PIDS_R% }
			PARALLEL_PIDS_R=${PARALLEL_PIDS_R# }
			PARALLEL_PIDS=" ${PARALLEL_PIDS_L} ${PARALLEL_PIDS_R} "
		fi
	done

	return ${ret}
}

# Wait on all remaining running processes and clean them up. Error out if
# any have non-zero return status.
parallel_stop() {
	local ret=0
	local do_wait="${1:-1}"

	if [ ${do_wait} -eq 1 ]; then
		_wait ${PARALLEL_PIDS} || ret=$?
	fi

	exec 9<&-
	exec 9>&-
	unset PARALLEL_PIDS
	unset NBPARALLEL

	return ${ret}
}

parallel_shutdown() {
	kill_and_wait 30 "${PARALLEL_PIDS}" || :
	# Reap the pids
	parallel_stop 0 2>/dev/null || :
}

parallel_run() {
	local cmd="$1"
	local ret
	shift 1

	ret=0

	# Occasionally reap dead children. Don't do this too often or it
	# becomes a bottleneck. Do it too infrequently and there is a risk
	# of PID reuse/collision
	_SHOULD_REAP=$((${_SHOULD_REAP} + 1))
	if [ ${_SHOULD_REAP} -eq 16 ]; then
		_SHOULD_REAP=0
		_reap_children || ret=$?
	fi

	# Only read once all slots are taken up; burst jobs until maxed out.
	# NBPARALLEL is never decreased and only inreased until maxed.
	if [ ${NBPARALLEL} -eq ${PARALLEL_JOBS} ]; then
		unset a; until trappedinfo=; read a <&9 || [ -z "$trappedinfo" ]; do :; done
	fi

	[ ${NBPARALLEL} -lt ${PARALLEL_JOBS} ] && NBPARALLEL=$((NBPARALLEL + 1))
	PARALLEL_CHILD=1 parallel_exec $cmd "$@" &
	PARALLEL_PIDS="${PARALLEL_PIDS} $! "

	return ${ret}
}

nohang() {
	[ $# -gt 5 ] || eargs nohang cmd_timeout log_timeout logfile pidfile cmd
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

	read_timeout=$((log_timeout / 10))

	fifo=$(mktemp -ut nohang)
	mkfifo ${fifo}
	exec 8<> ${fifo}
	rm -f ${fifo}

	starttime=$(date +%s)

	# Run the actual command in a child subshell
	(
		local ret=0
		"$@" || ret=1
		# Notify the pipe the command is done
		echo done >&8 2>/dev/null || :
		exit $ret
	) &
	childpid=$!
	echo "$childpid" > ${pidfile}

	# Now wait on the cmd with a timeout on the log's mtime
	while :; do
		if ! kill -CHLD $childpid 2>/dev/null; then
			_wait $childpid || ret=1
			break
		fi

		lastupdated=$(stat -f "%m" ${logfile})
		now=$(date +%s)

		# No need to actually kill anything as stop_build()
		# will be called and kill -9 -1 the jail later
		if [ $((now - lastupdated)) -gt $log_timeout ]; then
			ret=2
			break
		elif [ $((now - starttime)) -gt $cmd_timeout ]; then
			ret=3
			break
		fi

		# Wait until it is done, but check on it every so often
		# This is done instead of a 'sleep' as it should recognize
		# the command has completed right away instead of waiting
		# on the 'sleep' to finish
		unset n; until trappedinfo=; read -t $read_timeout n <&8 ||
			[ -z "$trappedinfo" ]; do :; done
		if [ "${n}" = "done" ]; then
			_wait $childpid || ret=1
			break
		fi
		# Not done, was a timeout, check the log time
	done

	exec 8<&-
	exec 8>&-

	rm -f ${pidfile}

	return $ret
}

[ -f /usr/bin/protect ] && [ $(/usr/bin/id -u) -eq 0 ] &&
    PROTECT=/usr/bin/protect
madvise_protect() {
	[ $# -eq 1 ] || eargs madvise_protect pid
	if [ -n "${PROTECT}" ]; then
		${PROTECT} -p "$1" 2>/dev/null || :
	fi
	return 0
}

spawn() {
	"$@" &
	madvise_protect $! || :
}

# Start a background process from function 'name'. The 'atexit' function
# will be called from the main process after the coprocess is killed.
# 'locks' will be acquired before killing, which can be used to not kill
# a process in the middle of an operation.
coprocess_start() {
	[ $# -ge 1 ] || eargs coprocess_start name [atexit] [locks]
	local name="$1"
	local atexit="$2"
	local locks="$3"
	local main pid

	main="${name}_main"
	spawn ${main}
	pid=$!

	hash_set coprocess_pid "${name}" "${pid}"
	[ -n "${atexit}" ] && hash_set coprocess_atexit "${name}" "${atexit}"
	[ -n "${locks}" ] && hash_set coprocess_locks "${name}" "${locks}"

	return 0
}

coprocess_stop() {
	[ $# -eq 1 ] || eargs coprocess_stop name
	local name="$1"
	local pid atexit lockname locks took_locks

	hash_get coprocess_pid "${name}" pid || return 0
	hash_unset coprocess_pid "${name}"

	# Grab locks
	if hash_get coprocess_locks "${name}" locks; then
		hash_unset coprocess_locks "${name}"
		for lockname in ${locks}; do
			# Does this process already have the lock?
			lock_have "${lockname}" && continue
			if lock_acquire "${lockname}"; then
				took_locks="${took_locks} ${lockname}"
			else
				msg_warn "Failed to acquire lock ${lockname} while shutting down ${name}"
			fi
		done
	fi

	# kill -> timeout wait -> kill -9
	kill_and_wait 30 "${pid}" || :

	# Release locks
	for lockname in ${took_locks}; do
		lock_release "${lockname}"
	done

	# Run atexit functions
	if hash_get coprocess_atexit "${name}" atexit; then
		hash_unset coprocess_atexit "${name}"
		${atexit}
	fi
}
