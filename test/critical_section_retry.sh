set -e
. ./common.sh
set +e

add_test_function test_critical_retry_basic
test_critical_retry_basic() {
	foo() {
		return 5
	}
	assert_ret 5 critical_retry foo
	critical_start
	assert_ret 5 critical_retry foo
	critical_end
	assert_ret 5 critical_retry foo
}

add_test_function test_critical_retry_no_critical_section
test_critical_retry_no_critical_section() {
	foo() {
		set -x
		assert 0 "${_CRITSNEST:-0}"
		ret=0
		critical_retry sh -c "sleep 5; exit 0" || ret="$?"
		echo "${ret}" > "${TMP:?}"
		# not reached
		return 99
	}
	TMP="$(mktemp -ut ret)"
	assert_true spawn_job foo
	assert_not '' "${spawn_pgid}"
	assert_not '' "${spawn_job}"
	sleep 2
	assert_true kill -TERM -- -"${spawn_pgid}"
	assert_ret 143 timed_wait_and_kill_job 7 "${spawn_job}"
	assert_false [ -e "${TMP}" ]
}

# This one just validates the problem being addressed by everything in this
# file but logically makes sense at this position.
add_test_function test_critical_section
test_critical_section() {
	foo() {
		set -x
		assert 0 "${_CRITSNEST:-0}"
		critical_start
		ret=0
		# This will get killed and exit 143 with /bin/sh
		# but poudriere-sh will exit 0.
		sh -xc "sleep 5; exit 0" || ret="$?"
		echo "${ret}" > "${TMP:?}"
		critical_end
		# not reached
		return 99
	}
	TMP="$(mktemp -ut ret)"
	assert_true spawn_job foo
	assert_not '' "${spawn_job}"
	assert_not '' "${spawn_job}"
	sleep 2
	assert_true kill -TERM -- -"${spawn_pgid}"
	assert_ret 143 timed_wait_and_kill_job 7 "${spawn_job}"
	case "${SH:?}" in
	/bin/sh)
		assert_file - "${TMP}" <<-EOF
		143
		EOF
		;;
	*)	# poudriere-sh blocks signals in critical_start
		assert_file - "${TMP}" <<-EOF
		0
		EOF
	esac
}

add_test_function test_critical_retry_critical_section
test_critical_retry_critical_section() {
	foo() {
		set -x
		assert 0 "${_CRITSNEST:-0}"
		critical_start
		ret=0
		critical_retry sh -xc "sleep 5; exit 0" || ret="$?"
		echo "${ret}" > "${TMP:?}"
		critical_end
		# not reached
		return 99
	}
	TMP="$(mktemp -ut ret)"
	assert_true spawn_job foo
	assert_not '' "${spawn_job}"
	assert_not '' "${spawn_job}"
	sleep 2
	assert_true kill -TERM -- -"${spawn_pgid}"
	assert_ret 143 timed_wait_and_kill_job 7 "${spawn_job}"
	# Now ensure the child did not exit 143 for /bin/sh and poudriere-sh.
	assert_file - "${TMP}" <<-EOF
	0
	EOF
}

run_test_functions
