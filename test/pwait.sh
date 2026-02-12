set -e
. ./common.sh
set +e

add_test_function pwait_timeout_zero
pwait_timeout_zero() {
	assert_runs_less_than 2 assert_ret 124 pwait -t 0 1
}

add_test_function pwait_timeout_decimal
pwait_timeout_decimal() {
	assert_runs_between 2 5 assert_ret 124 pwait -t 2.5 1
}

add_test_function pwait_timeout_adjusts_on_eintr
pwait_timeout_adjusts_on_eintr() {
	local gotinfo killer_job

	siginfo_killer() {
		local max n

		setproctitle "siginfo_killer"
		max=100
		n=0
		until [ "${n}" -eq "${max}" ]; do
			n="$((n + 1))"
			kill -INFO -- "$1"
			sleep 0.1
		done
	}
	assert_true spawn_job siginfo_killer "$(getpid)"
	killer_job="${spawn_job:?}"
	trap 'gotinfo=1' INFO
	assert_runs_between 2 5 assert_ret 124 pwait -t 2.5 1
	assert_ret 143 kill_job 2 "${killer_job:?}"
	trap - INFO
}

run_test_functions
