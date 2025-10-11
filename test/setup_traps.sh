set -e
. ./common.sh
set +e

READY_FILE="channel"
EXIT_FILE="exit_file"

# Basic test: should return 143 from handler
{
	worker_cleanup() {
		local ret="$?"
		echo "in here" >&2
		echo "${ret}" > "${EXIT_FILE}"
	}
	worker() {
		set -x
		echo "I AM $(getpid)" >&2
		setup_traps worker_cleanup
		trap >&2
		assert_true cond_signal child
		while :; do
			sleep 0.001
		done
	}
	assert_true spawn_job worker
	assert_not '' "${spawn_jobid}"
	assert_true cond_timedwait 5 child
	assert_ret 143 kill_job 5 "%${spawn_jobid}"
	assert_file - "${EXIT_FILE}" <<-EOF
	143
	EOF
}

# Should return 1 from set -e failure
{
	worker_cleanup() {
		local ret=$?
		echo "in here $ret" >&2
		assert_true cond_signal child
		echo "${ret}" > "${EXIT_FILE}"
	}
	worker() {
		echo "I AM $(getpid)" >&2
		setup_traps worker_cleanup
		set -e
		false
	}
	assert_true spawn_job worker
	assert_not '' "${spawn_jobid}"
	assert_true cond_timedwait 5 child
	assert_ret 1 kill_job 2 "%${spawn_jobid}"
	assert_file - "${EXIT_FILE}" <<-EOF
	1
	EOF
}

# Should exit 42 from exit call
{
	worker_cleanup() {
		local ret=$?
		echo "in here $ret" >&2
		assert_true cond_signal child
		echo "${ret}" > "${EXIT_FILE}"
	}
	worker() {
		echo "I AM $(getpid)" >&2
		setup_traps worker_cleanup
		exit 42
	}
	assert_true spawn_job worker
	assert_not '' "${spawn_jobid}"
	assert_true cond_timedwait 5 child
	assert_ret 42 kill_job 2 "%${spawn_jobid}"
	assert_file - "${EXIT_FILE}" <<-EOF
	42
	EOF
}

# Should exit 41 from cleanup changing exit code
{
	worker_cleanup() {
		local ret=$?
		echo "in here $ret" >&2
		assert_true cond_signal child
		echo "${ret}" > "${EXIT_FILE}"
		exit 41
	}
	worker() {
		echo "I AM $(getpid)" >&2
		setup_traps worker_cleanup
		exit 42
	}
	assert_true spawn_job worker
	assert_not '' "${spawn_jobid}"
	assert_true cond_timedwait 5 child
	assert_ret 41 kill_job 2 "%${spawn_jobid}"
	assert_file - "${EXIT_FILE}" <<-EOF
	42
	EOF
}


# Should show handler got $?=143 but then exit 41
{
	worker_cleanup() {
		local ret=$?
		echo "in here $ret" >&2
		echo "${ret}" > "${EXIT_FILE}"
		exit 41
	}
	worker() {
		echo "I AM $(getpid)" >&2
		setup_traps worker_cleanup
		assert_true cond_signal child
		while :; do
			sleep 0.001
		done
	}
	assert_true spawn_job worker
	assert_not '' "${spawn_jobid}"
	assert_true cond_timedwait 5 child
	assert_ret 41 kill_job 7 "%${spawn_jobid}"
	assert_file - "${EXIT_FILE}" <<-EOF
	143
	EOF
}

# Should NOT exit SIGPIPE from handler
{
	worker_cleanup() {
		local ret=$?
		assert 0 "${ret}" "worker had error before entering worker_cleanup; should not SIGPIPE until here" 2>&4
		# Cause an SIGPIPE here to ensure it does not recurse
		pipe_ret=0
		echo "in here $ret" >&2 || pipe_ret=$?
		assert 2 "${pipe_ret}" "stderr should cause write error" 2>&4
		echo "${ret}" > "${EXIT_FILE}"
		assert_true cond_timedwait 5 parent 2>&4
		assert_true cond_signal child "exiting" 2>&4
	}
	worker() {
		echo "I AM $(getpid)" >&2
		assert_true [ -p "${FIFO}" ]
		ret=0
		exec 2>"${FIFO}" || ret=$?
		assert 0 "$ret" "redirect stderr to ${FIFO}" 2>&4
		setup_traps worker_cleanup
		ret=0
		echo "FIFO should work" >&2 || ret=$?
		assert 0 "$ret" "echo to stderr" 2>&4
		# We should now SIGPIPE if writing to stderr.
		# The process will only SIGPIPE in worker_cleanup()
		{
			assert_true cond_signal child "piped stderr"
			assert_true cond_timedwait 5 parent
			set -x
			assert_true cond_signal child "worker end"
			echo "leaving set -x block" >&2
		} 2>&4
	}
	stderr_reader() {
		assert_true cond_signal stderr_reader
		exec 3<"${FIFO}"
		ret=0
		read_blocking -t20 n <&3 || ret=0
		assert 0 "${ret}"
		assert "FIFO should work" "${n}"
		exec 3>&-
		assert_true cond_signal stderr_reader
	}
	FIFO=$(mktemp -ut fifo)
	assert_true mkfifo "${FIFO}"
	assert_true spawn_job stderr_reader
	stderr_jobid="${spawn_jobid}"
	assert_not '' "${stderr_jobid}"
	assert_true cond_timedwait 5 stderr_reader
	exec 4>&2
	assert_true spawn_job worker
	writer_jobid="${spawn_jobid}"
	assert_not '' "${writer_jobid}"
	assert_true cond_timedwait 5 child "piped stderr"
	assert_true cond_timedwait 5 stderr_reader
	# Nuke stderr reader
	assert_ret 0 timed_wait_and_kill_job 5 "%${stderr_jobid}"
	# This serializes some of the test to ensure proper setup of set -x
	# for the SIGPIPE test.
	assert_true cond_signal parent
	assert_true cond_timedwait 5 child "worker end"
	assert_true cond_signal parent
	assert_true cond_timedwait 5 child "exiting"
	# No SIGPIPE should come through from exit handler
	assert_ret 0 kill_job 2 "%${writer_jobid}"
	exec 4>&-
	assert_file - "${EXIT_FILE}" <<-EOF
	0
	EOF
	rm -f "${FIFO}"
}
