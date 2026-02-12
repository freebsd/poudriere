. ./common.sh

if ! have_builtin cp; then
	exit 77
fi

add_test_function test_cp_usage_exit
test_cp_usage_exit()
{
	# Run in sub-shell to check if it exits early.
	foo() (
		expect_error_on_stderr assert_ret 64 cp
		exit 42
	)
	assert_ret 42 foo
}

add_test_function test_cp_basic
test_cp_basic() {
	local TMP

	TMP="$(mktemp -ut cp)"
	cat > "${TMP}" <<-EOF
	1
	2
	EOF
	# Run in sub-shell to check if it exits early.
	foo() (
		assert_true cp "${TMP}" "${TMP}.copy"
		exit 42
	)
	assert_ret 42 foo
	assert_file "${TMP}" "${TMP}.copy"
}

add_test_function test_cp_dir
test_cp_dir() {
	local TMP

	TMP="$(mktemp -dt cp)"
	assert_true mkdir -p "${TMP}/a"
	assert_true mkdir -p "${TMP}/a/b"
	assert_true mkdir -p "${TMP}/c"
	( cd "${TMP}" && find . ) > "${TMP}.listing"
	# Run in sub-shell to check if it exits early.
	foo() (
		assert_true cp -R "${TMP}" "${TMP}.copy"
		exit 42
	)
	assert_ret 42 foo
	assert_file - "${TMP}.listing" <<-EOF
	$(cd "${TMP}.copy" && find .)
	EOF
	rm -rf "${TMP}.copy" "${TMP}"
}

run_test_functions
