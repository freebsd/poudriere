set -e
. ./common.sh
set +e
set_pipefail

add_test_function test_remove_many_pipe_rmdir
test_remove_many_pipe_rmdir()
{
	TMPD=$(mktemp -dt remove_many_pipe)
	TMPD2=$(mktemp -dt remove_many_pipe)

	{
		echo "${TMPD}"
		echo "${TMPD2}"
	} | assert_true rmdir_many_pipe
	assert 0 "$?"
	assert_false [ -d "${TMPD}" ]
	assert_false [ -d "${TMPD2}" ]
}

add_test_function test_remove_many_pipe_unlink
test_remove_many_pipe_unlink()
{
	TMP=$(mktemp -t remove_many_pipe)
	TMP2=$(mktemp -t remove_many_pipe)

	{
		echo "${TMP}"
		echo "${TMP2}"
	} | assert_true unlink_many_pipe
	assert 0 "$?"
	assert_false [ -e "${TMP}" ]
	assert_false [ -e "${TMP2}" ]
}

add_test_function test_remove_many_pipe_rmrf
test_remove_many_pipe_rmrf()
{
	TMPD=$(mktemp -dt remove_many_pipe)
	TMPD2=$(mktemp -dt remove_many_pipe)

	:> "${TMPD}/1"
	:> "${TMPD}/2"
	:> "${TMPD2}/1"
	:> "${TMPD2}/2"

	{
		echo "${TMPD}"
		echo "${TMPD2}"
	} | assert_true rmrf_many_pipe
	assert 0 "$?"
	assert_false [ -d "${TMPD}" ]
	assert_false [ -d "${TMPD2}" ]
}

add_test_function test_remove_many_pipe
test_remove_many_pipe()
{
	TMPD=$(mktemp -dt remove_many_pipe)
	TMPD2=$(mktemp -dt remove_many_pipe)

	:> "${TMPD}/1"
	:> "${TMPD}/2"
	:> "${TMPD2}/1"
	:> "${TMPD2}/2"

	{
		echo "${TMPD}"
		echo "${TMPD2}"
	} | assert_true remove_many_pipe rm -rf
	assert_false [ -d "${TMPD}" ]
	assert_false [ -d "${TMPD2}" ]
}

run_test_functions
