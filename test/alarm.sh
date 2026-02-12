set -e
. ./common.sh
set +e

builtin_sleep() {
	if have_builtin sleep; then
		command sleep "$@" || return
		return
	fi
	local timeout="$1"
	local fifo ret readret _

	fifo="$(mktemp -ut builtin_sleep)" || return 99
	if ! mkfifo "${fifo:?}"; then
		rm -f "${fifo:?}"
		msg_warn "builtin_sleep: mkfifo"
		return 99
	fi
	if ! exec 5<>"${fifo:?}"; then
		rm -f "${fifo:?}"
		msg_warn "builtin_sleep: redirect"
		return 99
	fi
	ret=0
	readret=0
	{
		read -t "${timeout}" _ || readret="$?"
		case "${readret}" in
		142)
			# Was this a timeout from read -t or our SIGALRM
			# handler?
			case "${_GOTALRM:+set}" in
			set) ;;
			*)
				# This function is emulating "sleep" so
				# this timeout is expected as valid.
				readret=0
				;;
			esac
		esac
	} < "${fifo:?}" || ret="$?"
	case "${ret}" in
	0) ret="${readret}" ;;
	esac
	rm -f "${fifo:?}"
	return "${ret}"
}

add_test_function test_alarm_unfired
test_alarm_unfired() {
	assert_true alarm 2
	assert_true alarm
	assert_ret 0 builtin_sleep 4
}

add_test_function test_alarm_fired
test_alarm_fired() {
	assert_true alarm 2
	assert_runs_less_than 4 assert_ret 142 \
	    expect_error_on_stderr builtin_sleep 6
	assert_ret 142 alarm
}

add_test_function test_alarm_fired_rearm_fired
test_alarm_fired_rearm_fired() {
	test_alarm_fired
	# the cleanup ret is lost
	# rearm rather than cleanup
	assert_true alarm 3
	assert_runs_between 2 5 assert_ret 142 \
	    expect_error_on_stderr builtin_sleep 7
	assert_ret 142 alarm
}

add_test_function test_alarm_fired_rearm_unfired
test_alarm_fired_rearm_unfired() {
	test_alarm_fired
	# the cleanup ret is lost
	# rearm rather than cleanup
	assert_true alarm 3
	assert_ret 0 alarm
}

add_test_function test_alarm_zero
test_alarm_zero() {
	assert_ret 124 alarm 0
}

add_test_function test_alarm_child_alarm
test_alarm_child_alarm() {
	test_alarm_fired
	foo() {
		assert_true test_alarm_fired
	}
	assert_true spawn_job foo
	assert_not '' "${spawn_job}"
	assert_true assert_runs_less_than 8 \
	    timed_wait_and_kill_job 10 "${spawn_job}"
}

run_test_functions
