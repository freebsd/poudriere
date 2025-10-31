. ./common.sh

if ! have_builtin cut; then
	exit 77;
fi

add_test_function test_cut_usage_exit
test_cut_usage_exit()
{
	# Run in sub-shell to check if it exits early.
	foo() (
		expect_error_on_stderr assert_ret 1 sed --foo
		exit 42
	)
	assert_ret 42 foo
}

add_test_function test_cut_reads_stdin
test_cut_reads_stdin()
{
	local val

	val=$(echo foo/bar | cut -d / -f 2)
	assert "bar" "${val}"

	val=$(echo bar/foo | cut -d / -f 2)
	assert "foo" "${val}"
}

add_test_function test_cut_reads_file
test_cut_reads_file()
{
	local val TMPFILE

	TMPFILE="$(mktemp -ut cut)"

	echo foo/bar > "${TMPFILE}"
	val="$(cut -d / -f 2 < "${TMPFILE}")"
	assert "bar" "${val}"

	echo bar/foo > "${TMPFILE}"
	val="$(cut -d / -f 2 < "${TMPFILE}")"
	assert "foo" "${val}"

	rm -f "${TMPFILE}"
}

run_test_functions
