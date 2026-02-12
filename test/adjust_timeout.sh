. ./common.sh

add_test_function test_adjust_basic
test_adjust_basic() {
	local timeout start_time now new_timeout

	timeout=1
	start_time=5
	now=5
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "${timeout}" "${new_timeout}"
	now=6
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
	now=7
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
}

add_test_function test_adjust_zero
test_adjust_zero() {
	local timeout start_time now new_timeout

	timeout=0
	start_time=5
	now=5
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
	now=6
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
}

add_test_function test_adjust_blank
test_adjust_blank() {
	local timeout start_time now new_timeout

	timeout=
	start_time=5
	now=5
	new_timeout=stale
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "unset" "${new_timeout-unset}"
	now=6
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "unset" "${new_timeout-unset}"
}

add_test_function test_adjust_decimal
test_adjust_decimal() {
	local timeout start_time now new_timeout

	timeout=1.5
	start_time=5
	now=5
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "1.5" "${new_timeout}"
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "1.5" "${new_timeout}"
	now=6
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0.5" "${new_timeout}"
	assert_true adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0.5" "${new_timeout}"
	now=7
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
	now=8
	assert_ret 124 adjust_timeout "${timeout}" "${start_time}" \
	    new_timeout "${now}"
	assert "0" "${new_timeout}"
}

run_test_functions
