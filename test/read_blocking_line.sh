set -e
. ./common.sh
set +e

add_test_function test_timeout_basic
test_timeout_basic()
{
	local in start

	TMP=$(mktemp -u)
	assert_ret 0 mkfifo "${TMP}"
	start=$(clock -monotonic)
	exec 4<> "${TMP}"
	assert_runs_between 4 7 assert_ret 142 read_blocking_line -t 5 in < "${TMP}"
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
	assert_runs_between 4 7 assert_ret 142 read_blocking_line -t 5.9 in < "${TMP}"
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
	assert_runs_less_than 1 assert_ret 142 read_blocking_line -t 0.9 in < "${TMP}"
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
	assert_runs_between 4 7 assert_ret 142 read_blocking_line -t 5 in < "${TMP}"
	assert 1 "${gotinfo}" "should have received SIGINFO"
	assert "" "${in}" "read with timeout should reset the output vars"
	exec 4>&-
	kill "$!" || :
	wait "$!" >/dev/null 2>&1 || :
	rm -f "${TMP}"
	trap - INFO
}

add_test_function test_read_IFS
test_read_IFS() {
	local expected actual

	TMP=$(mktemp -u)
	expected="    test   "
	echo "${expected}" > "${TMP}"
	assert_true read_blocking_line actual < "${TMP}"
	assert "|${expected}|" "|${actual}|"
	assert_file - "${TMP}" <<-EOF
	${expected}
	EOF
}

run_test_functions
