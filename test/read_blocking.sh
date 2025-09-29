set -e
. ./common.sh
set +e

# Basic timeout test
{
	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	exec 4<> "${TMP}"
	read_blocking -t 5 in < "${TMP}"
	now=$(clock -monotonic)
	diff=$((now - start))
	[ "${diff}" -ge 5 ]
	assert 0 "$?" "Timeout of 5 should be reached but found: ${diff}"
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	rm -f "${TMP}"
}

# Test that SIGINFO with [EINTR] is restarted
{
	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	gotinfo=0
	trap 'gotinfo=1' INFO
	exec 4<> "${TMP}"
	in=bad
	(
		trap - INT
		sleep 1
		kill -INFO $$
	) &
	read_blocking -t 5 in < "${TMP}"
	assert 142 "$?"
	assert 1 "${gotinfo}" "should have received SIGINFO"
	now=$(clock -monotonic)
	diff=$((now - start))
	[ "${diff}" -ge 5 ]
	# If this fails it is possible SIGINFO caused an [EINTR] which
	# was not ignored.
	assert 0 "$?" "Timeout of 5 should be reached but found: ${diff}"
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	kill "$!" || :
	wait "$!" >/dev/null 2>&1 || :
	rm -f "${TMP}"
	trap - INFO
}

exit 0
