. ./common.sh

add_test_function test_in_nonexistent_dir
test_in_nonexistent_dir() {
	local TMP expected original

	TMP="$(mktemp -ut in_dir)"
	original="${PWD}"
	expected="${PWD}"
	assert_false test -e /nonexistent
	expect_error_on_stderr assert_false in_dir /nonexistent pwd > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	assert "${original}" "${PWD}"
	assert "${original}" "$(pwd)"
}

add_test_function test_in_dot
test_in_dot() {
	local TMP expected original

	TMP="$(mktemp -ut in_dir)"
	original="${PWD}"
	expected="${PWD}"
	assert_true in_dir . pwd > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	${expected}
	EOF
	assert "${original}" "${PWD}"
	assert "${original}" "$(pwd)"
}

add_test_function test_in_subdir
test_in_subdir() {
	local TMP TMPD expected original

	TMP="$(mktemp -ut in_dir)"
	TMPD="$(mktemp -dt in_dir)"
	original="${PWD}"
	expected="${TMPD}"
	assert_true in_dir "${TMPD}" pwd > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	${expected}
	EOF
	assert "${original}" "${PWD}"
	assert "${original}" "$(pwd)"
	assert_true rmdir "${TMPD}"
}

nested_cd() {
	local nested_dir="${1:?}"
	shift || return
	cd "${nested_dir:?}" || return
	"$@"
}

add_test_function test_nested_cd
test_nested_cd() {
	local TMP TMPD expected original

	TMP="$(mktemp -ut in_dir)"
	TMPD="$(mktemp -dt in_dir)"
	original="${PWD}"
	expected="/tmp"
	assert_true in_dir "${TMPD}" nested_cd "${expected}" pwd > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	${expected}
	EOF
	assert "${original}" "${PWD}"
	assert "${original}" "$(pwd)"
	assert_true rmdir "${TMPD}"
}

add_test_function test_nested_cd_2
test_nested_cd_2() {
	local TMP TMPD expected original

	TMP="$(mktemp -ut in_dir)"
	TMPD="$(mktemp -dt in_dir)"
	original="${PWD}"
	expected="${TMPD}"
	assert_true nested_cd /tmp in_dir "${expected}" pwd > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	${expected}
	EOF
	assert "/tmp" "${PWD}"
	assert "/tmp" "$(pwd)"
	assert_true rmdir "${TMPD}"
}

run_test_functions
