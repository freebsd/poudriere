. ./common.sh

if ! have_builtin mv; then
	exit 77
fi

add_test_function test_mv_usage_exit
test_mv_usage_exit()
{
	# Run in sub-shell to check if it exits early.
	foo() (
		expect_error_on_stderr assert_ret 64 mv
		exit 42
	)
	assert_ret 42 foo
}

add_test_function test_mv_basic
test_mv_basic() {
	local TMP

	TMP="$(mktemp -ut mv)"
	cat > "${TMP}" <<-EOF
	1
	2
	EOF
	# Run in sub-shell to check if it exits early.
	foo() (
		assert_true mv "${TMP}" "${TMP}.copy"
		exit 42
	)
	assert_ret 42 foo
	assert_file - "${TMP}.copy" <<-EOF
	1
	2
	EOF
}

add_test_function test_mv_dir
test_mv_dir() {
	local TMP

	TMP="$(mktemp -dt mv)"
	assert_true mkdir -p "${TMP}/a"
	assert_true mkdir -p "${TMP}/a/b"
	assert_true mkdir -p "${TMP}/c"
	( cd "${TMP}" && find . ) > "${TMP}.listing"
	# Run in sub-shell to check if it exits early.
	foo() (
		assert_true mv "${TMP}" "${TMP}.copy"
		exit 42
	)
	assert_ret 42 foo
	assert_true [ -d "${TMP}.copy" ]
	assert_file - "${TMP}.listing" <<-EOF
	$(cd "${TMP}.copy" && find .)
	EOF
	rm -rf "${TMP}.copy" "${TMP}"
}

add_test_function test_mv_dir_xdev
test_mv_dir_xdev() {
	local TMP ret TMP_XDEV

	TMP="$(mktemp -dt mv)"
	assert_true mkdir -p "${TMP}/a"
	assert_true mkdir -p "${TMP}/a/b"
	assert_true mkdir -p "${TMP}/c"
	( cd "${TMP}" && find . ) > "${TMP}.listing"
	TMP_XDEV="$(mktemp -dt xdev)"
	# Run in sub-shell to check if it exits early.
	foo() (
		assert_true ${SUDO-} mount -t tmpfs tmpfs "${TMP_XDEV}"
		assert_true [ -d "${TMP_XDEV}" ]
		assert_true mv "${TMP}" "${TMP_XDEV}/copy"
		assert_true [ -d "${TMP_XDEV}/copy" ]
		assert_false [ -d "${TMP}" ]
		assert_file - "${TMP}.listing" <<-EOF
		$(cd "${TMP_XDEV}/copy" && find .)
		EOF
		exit 42
	)
	ret=0
	# Need to run things in an odd order to ensure tmpfs gets unmounted.
	foo || ret="$?"
	umount "${TMP_XDEV}" || :
	assert "42" "${ret:?}" "foo ret"
	rm -rf "${TMP_XDEV}" "${TMP}"
}

run_test_functions
