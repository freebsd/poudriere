. ./common.sh

if ! have_builtin tr; then
	exit 77;
fi

add_test_function test_tr_usage_exit
test_tr_usage_exit()
{
	# Run in sub-shell to check if it exits early.
	foo() (
		expect_error_on_stderr assert_ret 1 sed --foo
		exit 42
	)
	assert_ret 42 foo
}

add_test_function test_tr_reads_stdin
test_tr_reads_stdin()
{
	local val

	val=$(echo foo/bar | tr '/' ' ')
	assert "foo bar" "${val}"

	val=$(echo bar/foo | tr '/' ':')
	assert "bar:foo" "${val}"
}

add_test_function test_tr_reads_file
test_tr_reads_file()
{
	local val TMPFILE

	TMPFILE="$(mktemp -ut tr)"

	echo foo/bar > "${TMPFILE}"
	val="$(tr '/' ':' < "${TMPFILE}")"
	assert "foo:bar" "${val}"

	echo bar/foo > "${TMPFILE}"
	val="$(tr '/' ' ' < "${TMPFILE}")"
	assert "bar foo" "${val}"

	rm -f "${TMPFILE}"
}

run_test_functions
