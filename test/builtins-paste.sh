. ./common.sh

if ! have_builtin paste; then
	exit 77;
fi

add_test_function test_paste_usage_exit
test_paste_usage_exit()
{
	# Run in sub-shell to check if it exits early.
	foo() (
		expect_error_on_stderr assert_ret 1 paste --foo
		exit 42
	)
	assert_ret 42 foo
}

add_test_function test_paste_reads_stdin
test_paste_reads_stdin()
{
	local TMPFILE

	TMPFILE=$(mktemp -ut paste)
	assert_true seq 1 10 > "${TMPFILE}"

	paste -s -d "A" - < "${TMPFILE}" > "${TMPFILE}.out"
	assert_file - "${TMPFILE}.out" <<-EOF
	1A2A3A4A5A6A7A8A9A10
	EOF

	paste -s - < "${TMPFILE}" > "${TMPFILE}.out"
	assert_file - "${TMPFILE}.out" <<-EOF
	1	2	3	4	5	6	7	8	9	10
	EOF

	paste -s -d "B" - < "${TMPFILE}" > "${TMPFILE}.out"
	assert_file - "${TMPFILE}.out" <<-EOF
	1B2B3B4B5B6B7B8B9B10
	EOF

	rm -f "${TMPFILE}" "${TMPFILE}.out"
}

run_test_functions
