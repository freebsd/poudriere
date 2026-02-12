set -e
. ./common.sh
set +e

add_test_function test_timeout_unfired
test_timeout_unfired() {
	assert_runs_less_than 3 assert_ret 0 timeout 10 sleep 1
}

add_test_function test_timeout_fired
test_timeout_fired() {
	assert_runs_less_than 3 assert_ret 124 timeout 1 sleep 5
}

add_test_function test_timeout_zero
test_timeout_zero() {
	assert_runs_less_than 2 assert_ret 124 timeout 0 sleep 5
}

add_test_function test_timeout_builtin
test_timeout_builtin() {
	if ! have_builtin alarm; then
		assert_true true
		return
	fi
	assert_runs_less_than 2 assert_ret 124 timeout 0 pwait 1
}

run_test_functions
