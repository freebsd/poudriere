TEST_OVERRIDE_ERR=0
set -e
. ./common.sh
set +e

foo() {
	echo stdout
	err 9 eRROR
}

{
	assert_false check_pipe_fatal_error
	assert_true delay_pipe_fatal_error
	assert_ret 7 catch_err err 7 eRRoR
	assert_true check_pipe_fatal_error
}

{
	assert_false check_pipe_fatal_error
	assert_true delay_pipe_fatal_error
	assert_ret 7 catch_err err 7 eRRoR
	assert_true clear_pipe_fatal_error
	assert_false check_pipe_fatal_error
}
