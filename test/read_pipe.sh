set -e
. ./common.sh
set +e

add_test_function test_no_timeout
test_no_timeout()
{
	local in start

	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	( echo 1 > "${TMP}" ) &
	assert_ret 0 read_pipe "${TMP}" in
	assert "1" "${in}"
	assert_true _wait $!
	exec 4>&-
	rm -f "${TMP}"
}

add_test_function test_timeout_basic
test_timeout_basic()
{
	local in start

	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	assert_runs_between 4 7 assert_ret 142 \
	    expect_error_on_stderr read_pipe "${TMP}" -t 5 in
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	rm -f "${TMP}"
}

add_test_function test_timeout_decimal
test_timeout_decimal()
{
	local in start

	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	exec 4<> "${TMP}"
	# The decimal gets trimmed off
	assert_runs_between 4 7 assert_ret 142 read_pipe "${TMP}" -t 5.9 in
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	rm -f "${TMP}"
}

add_test_function test_timeout_decimal_zero
test_timeout_decimal_zero()
{
	local in start

	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	exec 4<> "${TMP}"
	# The decimal gets trimmed off to be 0
	assert_runs_less_than 1 assert_ret 142 read_pipe "${TMP}" -t 0.9 in
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	rm -f "${TMP}"
}

# Test that SIGINFO with [EINTR] is restarted
add_test_function test_siginfo_restart
test_siginfo_restart()
{
	local in start gotinfo

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
	# If this fails it is possible SIGINFO caused an [EINTR] which
	# was not ignored.
	assert_runs_between 4 7 assert_ret 142 read_pipe "${TMP}" -t 5 in
	assert 1 "${gotinfo}" "should have received SIGINFO"
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	kill "$!" || :
	wait "$!" >/dev/null 2>&1 || :
	rm -f "${TMP}"
	trap - INFO
}

run_test_functions
