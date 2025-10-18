. ./common.sh

add_test_function test_remove_many_rmdir
test_remove_many_rmdir()
{
	TMPD=$(mktemp -dt remove_many)
	TMPD2=$(mktemp -dt remove_many)

	assert_true rmdir_many "${TMPD} ${TMPD2}"
	assert_false [ -d "${TMPD}" ]
	assert_false [ -d "${TMPD2}" ]
}

add_test_function test_remove_many_unlink
test_remove_many_unlink()
{
	TMP=$(mktemp -t remove_many)
	TMP2=$(mktemp -t remove_many)

	assert_true unlink_many "${TMP} ${TMP2}"
	assert_false [ -e "${TMP}" ]
	assert_false [ -e "${TMP2}" ]
}

add_test_function test_remove_many_rmrf
test_remove_many_rmrf()
{
	TMPD=$(mktemp -dt remove_many)
	TMPD2=$(mktemp -dt remove_many)

	:> "${TMPD}/1"
	:> "${TMPD}/2"
	:> "${TMPD2}/1"
	:> "${TMPD2}/2"

	assert_true rmrf_many "${TMPD} ${TMPD2}"
	assert_false [ -d "${TMPD}" ]
	assert_false [ -d "${TMPD2}" ]
}

add_test_function test_remove_many
test_remove_many()
{
	TMPD=$(mktemp -dt remove_many)
	TMPD2=$(mktemp -dt remove_many)

	:> "${TMPD}/1"
	:> "${TMPD}/2"
	:> "${TMPD2}/1"
	:> "${TMPD2}/2"

	assert_true remove_many "${TMPD} ${TMPD2}"
	assert_false [ -d "${TMPD}" ]
	assert_false [ -d "${TMPD2}" ]
}

run_test_functions
