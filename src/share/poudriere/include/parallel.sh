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
	echo >&6 || :
	exit ${ret}
	# set -e will be restored by 'local -'
}

parallel_start() {
	local fifo

	if [ -n "${MASTERMNT}" ]; then
		fifo=${MASTERMNT}/poudriere/parallel.pipe
	else
		fifo=$(mktemp -ut parallel)
	fi
	mkfifo ${fifo}
	exec 6<> ${fifo}
	rm -f ${fifo}
	export NBPARALLEL=0
	export PARALLEL_PIDS=""
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

	exec 6<&-
	exec 6>&-
	unset PARALLEL_PIDS
	unset NBPARALLEL

	return ${ret}
}

parallel_shutdown() {
	kill_and_wait 30 "${PARALLEL_PIDS}" 2>/dev/null || :
	# Reap the pids
	parallel_stop 0 2>/dev/null || :
}

parallel_run() {
	local cmd="$1"
	shift 1

	# Occasionally reap dead children. Don't do this too often or it
	# becomes a bottleneck. Do it too infrequently and there is a risk
	# of PID reuse/collision
	_SHOULD_REAP=$((_SHOULD_REAP + 1))
	if [ ${_SHOULD_REAP} -eq 16 ]; then
		_SHOULD_REAP=0
		_reap_children || return $?
	fi

	# Only read once all slots are taken up; burst jobs until maxed out.
	# NBPARALLEL is never decreased and only inreased until maxed.
	if [ ${NBPARALLEL} -eq ${PARALLEL_JOBS} ]; then
		unset a; until trappedinfo=; read a <&6 || [ -z "$trappedinfo" ]; do :; done
	fi

	[ ${NBPARALLEL} -lt ${PARALLEL_JOBS} ] && NBPARALLEL=$((NBPARALLEL + 1))
	PARALLEL_CHILD=1 parallel_exec $cmd "$@" &
	PARALLEL_PIDS="${PARALLEL_PIDS} $! "
}
