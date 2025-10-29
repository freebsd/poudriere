. ./common.sh

add_test_function test_remove_many_file_default_empty_file
test_remove_many_file_default_empty_file()
{
	TMP=$(mktemp -ut filelist)
	:> "${TMP}"
	assert_true remove_many_file "${TMP}"
	assert_false [ -e "${TMP}" ]
}

add_test_function test_remove_many_rmdir
test_remove_many_rmdir()
{
	TMPD=$(mktemp -d)
	TMP=$(mktemp -ut filelist)

	echo "${TMPD}" > "${TMP}"
	assert_true remove_many_file "${TMP}" rmdir
	assert_false [ -e "${TMP}" ]
	assert_false [ -d "${TMPD}" ]
}

add_test_function test_remove_many_default_files
test_remove_many_default_files()
{
	local n max

	TMPD=$(mktemp -d)
	TMP=$(mktemp -ut filelist)

	n=0
	max=10
	until [ "${n}" -eq "${max}" ]; do
		n="$((n + 1))"
		:> "${TMPD}/file ${n}"
		echo "${TMPD}/file ${n}"
	done > "${TMP}"
	assert_true remove_many_file "${TMP}"
	assert_false [ -e "${TMP}" ]
	assert_true [ -d "${TMPD}" ]
	assert_true rmdir "${TMPD}"
}

add_test_function test_remove_many_default_files_rmrf
test_remove_many_default_files_rmrf()
{
	local n max

	TMPD=$(mktemp -d)
	TMP=$(mktemp -ut filelist)

	n=0
	max=10
	until [ "${n}" -eq "${max}" ]; do
		n="$((n + 1))"
		:> "${TMPD}/file ${n}"
		echo "${TMPD}/file ${n}"
	done > "${TMP}"
	assert_true remove_many_file "${TMP}" rm -rf
	assert_false [ -e "${TMP}" ]
	assert_true [ -d "${TMPD}" ]
	assert_true rmdir "${TMPD}"
}

add_test_function test_remove_many_default_nested
test_remove_many_default_nested()
{
	local n max

	TMPD=$(mktemp -d)
	TMP=$(mktemp -ut filelist)

	n=0
	max=10
	until [ "${n}" -eq "${max}" ]; do
		n="$((n + 1))"
		mkdir "${TMPD}/file ${n}"
		echo "${TMPD}/file ${n}"
	done > "${TMP}"
	assert_true remove_many_file "${TMP}" rm -rf
	assert_false [ -e "${TMP}" ]
	assert_true [ -d "${TMPD}" ]
	assert_true rmdir "${TMPD}"
}

add_test_function test_remove_many_default_not_recursive
test_remove_many_default_not_recursive()
{
	local n max

	TMPD=$(mktemp -d)
	TMP=$(mktemp -ut filelist)

	n=0
	max=10
	until [ "${n}" -eq "${max}" ]; do
		n="$((n + 1))"
		mkdir "${TMPD}/file ${n}"
		echo "${TMPD}/file ${n}"
	done > "${TMP}"
	assert_false expect_error_on_stderr remove_many_file "${TMP}"
	assert_true [ -e "${TMP}" ]
	assert_true [ -d "${TMPD}" ]
	assert_false expect_error_on_stderr rmdir "${TMPD}"
	assert_true remove_many_file "${TMP}" rmdir
	assert_true [ -d "${TMPD}" ]
	assert_true rmdir "${TMPD}"
	assert_true unlink "${TMP}"
}

run_test_functions
