set -e
. ./common.sh
set +e

reader() {
	local stdin="$1"
	local stdout="$2"
	local IFS line

	exec > "${stdout}"
	exec < "${stdin}"

	while IFS= read -r line; do
		echo "${line}"
	done
}

# First check that without pipe_hold, reader() dies.
{
	OUTPUT="$(mktemp -ut output)"
	FIFO="$(mktemp -ut fifo)"
	assert_true mkfifo "${FIFO}"
	spawn_job reader "${FIFO}" "${OUTPUT}"
	assert 0 "$?"
	reader_pid="$!"
	assert_true get_job_id "${reader_pid}" reader_job
	assert_true kill -0 "%${reader_job}"
	echo "Blah1" > "${FIFO}"
	assert 0 "$?"
	# Having closed the pipe the child will die.
	assert_true _wait "%${reader_job}"
	assert_file - "${OUTPUT}" <<-EOF
	Blah1
	EOF
	rm -f "${OUTPUT}" "${FIFO}"
}

# Now with pipe_hold
{
	OUTPUT="$(mktemp -ut output)"
	FIFO="$(mktemp -ut fifo)"
	assert_true mkfifo "${FIFO}"
	spawn_job reader "${FIFO}" "${OUTPUT}"
	assert 0 "$?"
	reader_pid="$!"
	assert_true get_job_id "${reader_pid}" reader_job
	assert_true pipe_hold pipe_hold_jobid "${reader_pid}" "${FIFO}"
	assert_true kill -0 "%${reader_job}"
	assert_true get_job_status "%${reader_job}" status
	assert "Running" "${status}"
	echo "Blah1" > "${FIFO}"
	assert 0 "$?"
	assert_true kill -0 "%${reader_job}"
	assert_true get_job_status "%${reader_job}" status
	assert "Running" "${status}"
	echo "Blah2" > "${FIFO}"
	assert 0 "$?"
	assert_true kill -0 "%${reader_job}"
	assert_true get_job_status "%${reader_job}" status
	assert "Running" "${status}"
	assert_file - "${OUTPUT}" <<-EOF
	Blah1
	Blah2
	EOF
	kill_job 1 "%${reader_job}"
	ret="$?"
	case "${ret}" in
	143) ret=0 ;;
	esac
	assert 0 "${ret}"
	kill_job 1 "%${pipe_hold_jobid}"
	ret="$?"
	case "${ret}" in
	143) ret=0 ;;
	esac
	assert 0 "${ret}"
	rm -f "${OUTPUT}" "${FIFO}"
}
