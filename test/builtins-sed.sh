. ./common.sh

if ! have_builtin sed; then
	exit 77;
fi

add_test_function test_sed_usage_exit
test_sed_usage_exit()
{
	# Run in sub-shell to check if it exits early.
	foo() (
		expect_error_on_stderr assert_ret 1 sed --foo
		exit 42
	)
	assert_ret 42 foo
}

add_test_function test_sed_reads_stdin
test_sed_reads_stdin()
{
	local val

	val=$(echo foo/bar | sed -e 's,foo/,,')
	assert "bar" "${val}"

	val=$(echo bar/foo | sed -e 's,bar/,,')
	assert "foo" "${val}"
}

add_test_function test_sed_reads_file
test_sed_reads_file()
{
	local val TMPFILE

	TMPFILE="$(mktemp -ut sed)"

	echo foo/bar > "${TMPFILE}"
	val="$(sed -e 's,foo/,,' < "${TMPFILE}")"
	assert "bar" "${val}"

	echo bar/foo > "${TMPFILE}"
	val="$(sed -e 's,bar/,,' < "${TMPFILE}")"
	assert "foo" "${val}"

	rm -f "${TMPFILE}"
}

add_test_function test_sed_modifies_file
test_sed_modifies_file()
{
	local val TMPFILE

	TMPFILE="$(mktemp -ut sed)"

	echo foo/bar > "${TMPFILE}"
	sed -i '' -e 's,foo/,,' "${TMPFILE}"
	assert_file - "${TMPFILE}" <<-EOF
	bar
	EOF

	echo bar/foo > "${TMPFILE}"
	sed -i '' -e 's,bar/,,' "${TMPFILE}"
	assert_file - "${TMPFILE}" <<-EOF
	foo
	EOF
}

run_test_functions
