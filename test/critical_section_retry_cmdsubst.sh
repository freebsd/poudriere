set -e
. ./common.sh
set +e

# first make sure that critical_retry_cmdsubst runs cmdsubsts appropriately.
add_test_function test_critical_retry_cmdsubst_works
test_critical_retry_cmdsubst_works() {
	local x

	x=
	assert_false catch_err critical_retry_cmdsubst x "$(echo test; exit 0)"
	assert "" "${x}"
	x=
	assert_true critical_retry_cmdsubst x "\$(echo \"1  2 \"; exit 0)"
	assert "1  2 " "${x}"
	x=
	assert_ret 5 critical_retry_cmdsubst x "\$(exit 5)"
	assert "" "${x}"
	assert_ret 0 critical_retry_cmdsubst x "\$(exit 0)"
	assert "" "${x}"
	assert_ret 0 critical_retry_cmdsubst x "\$(exit 0)"
	assert "" "${x}"
	assert_ret 0 critical_retry_cmdsubst x "\$(echo test)"
	assert "test" "${x}"
	x=
	assert_ret 5 critical_retry_cmdsubst x "\$(echo test; exit 5)"
	assert "test" "${x}"
	x=
	assert_ret 0 critical_retry_cmdsubst x \
	    "\$(echo test | tr '[[:lower:]]' '[[:upper:]]')"
	assert "TEST" "${x}"
	x=
	assert_ret 5 critical_retry_cmdsubst x \
	    "\$(echo test | tr '[[:lower:]]' '[[:upper:]]'; exit 5)"
	assert "TEST" "${x}"
	x=
	local -
	set +o pipefail
	assert_ret 0 critical_retry_cmdsubst x \
	    "\$({ echo test; exit 5; } | tr '[[:lower:]]' '[[:upper:]]')"
	assert "TEST" "${x}"
	set -o pipefail
	assert_ret 5 critical_retry_cmdsubst x \
	    "\$({ echo test; exit 5; } | tr '[[:lower:]]' '[[:upper:]]')"
	assert "TEST" "${x}"
}

# now make sure it prevents the bug it is intending to prevent.

add_test_function test_critical_retry_cmdsubst_basic
test_critical_retry_cmdsubst_basic() {
	foo() {
		local x

		critical_retry_cmdsubst x "\$(exit 5)"
		return
	}
	assert_ret 5 foo
	critical_start
	assert_ret 5 foo
	critical_end
	assert_ret 5 foo
}

add_test_function test_critical_retry_cmdsubst_no_critical_section
test_critical_retry_cmdsubst_no_critical_section() {
	foo() {
		local x

		set -x
		assert 0 "${_CRITSNEST:-0}"
		ret=0
		x=stale
		critical_retry_cmdsubst x \
		    "\$(sleep 5;echo done;exit 0)" || ret="$?"
		echo "${ret}" > "${TMP:?}"
		echo "${x}" > "${TMP:?}.out"
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
	assert_false [ -e "${TMP}.out" ]
}

# This one just validates the problem being addressed by everything in this
# file but logically makes sense at this position.
add_test_function test_critical_section
test_critical_section() {
	foo() {
		local x

		set -x
		assert 0 "${_CRITSNEST:-0}"
		critical_start
		ret=0
		# This will get killed and exit 143 with /bin/sh
		# but poudriere-sh will exit 0.
		x=stale
		x="$(sleep 5;echo done;exit 0)" || ret="$?"
		echo "${ret}" > "${TMP:?}"
		echo "${x}" > "${TMP:?}.out"
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
		# blank value is substituted
		assert_file - "${TMP}.out" <<-EOF
		
		EOF
		;;
	*)	# poudriere-sh blocks signals in critical_start
		assert_file - "${TMP}" <<-EOF
		0
		EOF
		assert_file - "${TMP}.out" <<-EOF
		done
		EOF
	esac
}

add_test_function test_critical_retry_cmdsubst_critical_section
test_critical_retry_cmdsubst_critical_section() {
	foo() {
		local x

		set -x
		assert 0 "${_CRITSNEST:-0}"
		critical_start
		ret=0
		x=stale
		critical_retry_cmdsubst x \
		    "\$(sleep 5;echo done;exit 0)" || ret="$?"
		echo "${ret}" > "${TMP:?}"
		echo "${x}" > "${TMP:?}.out"
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
	assert_file - "${TMP}.out" <<-EOF
	done
	EOF
}

run_test_functions
