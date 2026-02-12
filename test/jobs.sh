# This test is testing very specific formats because get_job_id() depends on it.
set +e
. ./common.sh
set -e
set -m

TMP="$(mktemp -ut jobs)"

# jobs -l but trim out the 30/64 col whitespace excess
get_jobs() {
	[ "$#" -eq 1 ] || eargs getjobs file
	local file="$1"
	local -

	set +m
	jobs -l > "${file}"
	sed -i '' -e 's, *$,,' "${file}"
}

jobs_with_statuses_stdout() {
	local jobs job status

	unset jobs
	while jobs_with_statuses jobs job status -- "$@"; do
		echo "${job:?} ${status:?}"
	done
}

jobs_with_statuses_pids_stdout() {
	local jobs job status pids

	unset jobs
	while jobs_with_statuses jobs job status pids -- "$@"; do
		echo "${job:?} ${status:?} ${pids:?}"
	done
}

pwait_racy() {
	local allpids pid state pids IFS -

	set +m
	# pwait uses kevent to watch for exiting processes. If it attaches
	# during process exit, it sends the event immediately. Then it is
	# possible for wait(WNOHANG) to not reap the process yet since it
	# is *still exiting*.
	# This is not a real code problem just a test problem since I want
	# to capture "Terminated", etc, without causing a "Done" or reaped
	# status. In real code pwait would be followed by wait without
	# WNOHANG.
	pwait -v "$@"
	allpids="$*"
	set -f
	while [ -n "${allpids:+set}" ]; do
		set -- ${allpids}
		IFS=,
		pids="$*"
		unset IFS
		while read -r pid state; do
			echo "READ pid=${pid} state=${state}" >&2
			case "${pid}" in
			""|"ERR") unset allpids ;;
			"PID") continue ;;
			esac
			case "${state}" in
			Z)
				list_remove allpids "${pid}"
				;;
			esac
		done <<-EOF
		$(ps -o pid,state -p "$@" || echo "ERR $?")
		EOF
	done
}

noterm() {
	local -
	set +m
	trap '' TERM
	"$@"
}

multiple_children() {
	sleep 20
}

# spawn_job and get_job_id and get_job_status
add_test_function test_jobs_1
test_jobs_1() {
	local sleep1_pid sleep2_pid sleep3_pid status
	local sleep1_jobid sleep2_jobid sleep3_jobid

	assert_true spawn_job sleep 50
	assert "1" "${spawn_jobid}"
	assert "%1" "${spawn_job}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true spawn_job_protected sleep 40
	assert "2" "${spawn_jobid}"
	sleep2_pid="$!"
	echo "sleep2_pid= $!"

	assert_true spawn_job sleep 30
	assert "3" "${spawn_jobid}"
	sleep3_pid="$!"
	echo "sleep3_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Running
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF

	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep1_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_ret 0 kill %1
	assert_runs_shorter_than 5 assert_true pwait_racy "${sleep1_pid}"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Terminated
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF

	assert_true get_job_status "%1" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep1_pid}" status
	assert "Terminated" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_runs_shorter_than 1 assert_ret 143 wait %1

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_true spawn_job sleep 1
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"
	assert_true get_job_id "${sleep1_pid}" sleep1_jobid
	assert 1 "${sleep1_jobid}"

	assert_runs_shorter_than 5 assert_true pwait_racy "${sleep1_pid}"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Done
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF

	assert_true jobs_with_statuses_stdout > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
	EOF
	assert_true jobs_with_statuses_pids_stdout > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done ${sleep1_pid}
	%2 Running ${sleep2_pid}
	%3 Running ${sleep3_pid}
	EOF

	assert_true jobs_with_statuses_stdout %1 %2 %3 > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
	EOF

	assert_true jobs_with_statuses_stdout %1 %3 > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%3 Running
	EOF

	assert_true jobs_with_statuses_stdout %2 > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%2 Running
	EOF

	assert_true get_job_status "%1" status
	assert "Done" "${status}"
	assert_true get_job_status "${sleep1_pid}" status
	assert "Done" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_true get_job_id "${sleep1_pid}" sleep1_jobid
	assert 1 "${sleep1_jobid}"
	assert_runs_shorter_than 1 assert_ret 0 wait %1

	assert_false get_job_id "${sleep1_pid}" sleep1_jobid 2>/dev/null

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_true get_job_id "${sleep2_pid}" sleep2_jobid
	assert 2 "${sleep2_jobid}"

	assert_true get_job_id "${sleep3_pid}" sleep3_jobid
	assert 3 "${sleep3_jobid}"
	assert_ret 0 kill "%${sleep3_jobid}"
	assert_runs_shorter_than 5 assert_true pwait_racy "${sleep3_pid}"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2] + ${sleep2_pid} Running
	[3]   ${sleep3_pid} Terminated
	EOF

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Terminated" "${status}"

	assert_true get_job_id "${sleep2_pid}" sleep2_jobid
	assert 2 "${sleep2_jobid}"
	assert_true kill -9 "%${sleep2_jobid}"
	assert_runs_shorter_than 5 assert_true pwait_racy "${sleep2_pid}"

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Killed" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Killed" "${status}"
	assert_true get_job_status "%3" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Terminated" "${status}"
	assert_runs_shorter_than 3 assert_ret 137 wait "%${sleep2_jobid}"

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "%2" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep2_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%3" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Terminated" "${status}"

	assert_runs_shorter_than 3 assert_ret 143 wait %"${sleep3_jobid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
}

# spawn_job and get_job_id and get_job_status, with piped jobs
add_test_function test_jobs_2
test_jobs_2() {
	assert_runs_shorter_than 10 _test_jobs_2
}
_test_jobs_2() {
	local sleep1_pid sleep2_pid sleep3_pid status
	local sleep1_jobid sleep2_jobid sleep3_jobid

	assert_true sleep 50 | sleep 50 | sleep 50 &
	assert_true get_job_id "$!" spawn_jobid
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true sleep 40 | sleep 40 &
	assert_true get_job_id "$!" spawn_jobid
	assert "2" "${spawn_jobid}"
	sleep2_pid="$!"
	echo "sleep2_pid= $!"

	assert_true sleep 30 | sleep 30 &
	assert_true get_job_id "$!" spawn_jobid
	assert "3" "${spawn_jobid}"
	sleep3_pid="$!"
	echo "sleep3_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Running
	      [0-9]+
	      ${sleep1_pid}
	\[2\] - [0-9]+ Running
	      ${sleep2_pid}
	\[3\] \+ [0-9]+ Running
	      ${sleep3_pid}
	EOF

	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep1_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_ret 0 kill %1
	assert_true pwait_racy "${sleep1_pid}"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Terminated
	      [0-9]+
	      ${sleep1_pid}
	\[2\] - [0-9]+ Running
	      ${sleep2_pid}
	\[3\] \+ [0-9]+ Running
	      ${sleep3_pid}
	EOF

	assert_true get_job_status "%1" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep1_pid}" status
	assert "Terminated" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_ret 143 wait %1

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[2\] - [0-9]+ Running
	      ${sleep2_pid}
	\[3\] \+ [0-9]+ Running
	      ${sleep3_pid}
	EOF

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_true sleep 1 | sleep 1 | sleep 1 &
	assert_true get_job_id "$!" spawn_jobid
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"
	assert_true get_job_id "${sleep1_pid}" sleep1_jobid
	assert 1 "${sleep1_jobid}"

	assert_true pwait_racy "${sleep1_pid}"

	assert_true get_jobs "${TMP}"
	# Done|Running due to pwait_racy not being good enough
	assert_file_reg - "${TMP}" <<-EOF
	\[1\] \+?  [0-9]+ (Done|Running)
	      [0-9]+
	      ${sleep1_pid}
	\[2\] -? [0-9]+ Running
	      ${sleep2_pid}
	\[3\] [-+] [0-9]+ Running
	      ${sleep3_pid}
	EOF

	assert_true jobs_with_statuses_stdout > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
	EOF
	local job1_pids job2_pids job3_pids

	job1_pids="$(jobid %1)"
	job2_pids="$(jobid %2)"
	job3_pids="$(jobid %3)"
	assert_true jobs_with_statuses_pids_stdout > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done ${job1_pids}
	%2 Running ${job2_pids}
	%3 Running ${job3_pids}
	EOF

	assert_true get_job_status "%1" status
	assert "Done" "${status}"
	assert_true get_job_status "${sleep1_pid}" status
	assert "Done" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_true get_job_id "${sleep1_pid}" sleep1_jobid
	assert 1 "${sleep1_jobid}"
	assert_ret 0 wait %1

	assert_false get_job_id "${sleep1_pid}" sleep1_jobid 2>/dev/null

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[2\] - [0-9]+ Running
	      ${sleep2_pid}
	\[3\] \+ [0-9]+ Running
	      ${sleep3_pid}
	EOF

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Running" "${status}"

	assert_true get_job_id "${sleep2_pid}" sleep2_jobid
	assert 2 "${sleep2_jobid}"

	assert_true get_job_id "${sleep3_pid}" sleep3_jobid
	assert 3 "${sleep3_jobid}"
	assert_ret 0 kill "%${sleep3_jobid}"
	assert_true pwait_racy "${sleep3_pid}"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[2\] \+ [0-9]+ Running
	      ${sleep2_pid}
	\[3\]   [0-9]+ Terminated
	      ${sleep3_pid}
	EOF

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Running" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Running" "${status}"
	assert_true get_job_status "%3" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Terminated" "${status}"

	assert_true get_job_id "${sleep2_pid}" sleep2_jobid
	assert 2 "${sleep2_jobid}"
	assert_true kill -9 "%${sleep2_jobid}"
	assert_true pwait_racy "${sleep2_pid}"

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%2" status
	assert "Killed" "${status}"
	assert_true get_job_status "${sleep2_pid}" status
	assert "Killed" "${status}"
	assert_true get_job_status "%3" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Terminated" "${status}"
	assert_ret 137 wait "%${sleep2_jobid}"

	assert_false get_job_status "%1" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep1_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "%2" status 2>/dev/null
	assert "" "${status}"
	assert_false get_job_status "${sleep2_pid}" status 2>/dev/null
	assert "" "${status}"
	assert_true get_job_status "%3" status
	assert "Terminated" "${status}"
	assert_true get_job_status "${sleep3_pid}" status
	assert "Terminated" "${status}"

	assert_ret 143 wait %"${sleep3_jobid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
}

# kill_jobs
add_test_function test_jobs_3
test_jobs_3() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid

	assert_true sleep 30 | sleep 30 &
	assert_true get_job_id "$!" spawn_jobid
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job noterm sleep 30
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"
	assert_true spawn_job sleep 30
	sleep3_pid="$!"
	sleep3_jobid="${spawn_jobid}"
	echo "sleep3_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Running
	      ${sleep1_pid}
	\[2\] - ${sleep2_pid} Running
	\[3\] \+ ${sleep3_pid} Running
	EOF
	assert_ret 137 kill_jobs 1 %1 %2
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[3] + ${sleep3_pid} Running
	EOF
	assert_ret 143 kill_jobs 1 %3
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	# assert_false expect_error_on_stderr kill -0 %"${sleep1_jobid}"
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep2_jobid}"
	assert_ret 127 wait %"${sleep2_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep3_jobid}"
	assert_ret 127 wait %"${sleep3_jobid}"
}

# kill_jobs (different ordering)
add_test_function test_jobs_4
test_jobs_4() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid

	assert_true spawn_job sleep 30
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job noterm sleep 30
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"
	assert_true spawn_job sleep 30
	sleep3_pid="$!"
	sleep3_jobid="${spawn_jobid}"
	echo "sleep3_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Running
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF
	assert_ret 137 kill_jobs 1 %2 %1
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[3] + ${sleep3_pid} Running
	EOF
	assert_ret 143 kill_jobs 1 %3
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	# assert_false expect_error_on_stderr kill -0 %"${sleep1_jobid}"
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep2_jobid}"
	assert_ret 127 wait %"${sleep2_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep3_jobid}"
	assert_ret 127 wait %"${sleep3_jobid}"
}

# pwait_jobs on single-proc jobs
add_test_function test_jobs_5
test_jobs_5() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid
	local stdout stderr

	assert_true spawn_job sleep 10
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job sleep 15
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"
	assert_true spawn_job sleep 10
	sleep3_pid="$!"
	sleep3_jobid="${spawn_jobid}"
	echo "sleep3_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Running
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF
	assert_runs_shorter_than 3 assert_ret 124 pwait_jobs -t 1 %1 %2 %3
	# Ideally we'd have 9-15 but give a +/-2 for races.
	assert_runs_between 7 17 assert_ret 0 pwait_jobs -t 15 %1 %3
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Done
	[2] + ${sleep2_pid} Running
	[3]   ${sleep3_pid} Done
	EOF
	# Done jobs should return immediately from pwait without errors.
	capture_output_simple stdout stderr
	assert_runs_within 7 assert_ret 0 pwait_jobs %1 %3
	capture_output_simple_stop
	assert_file - "${stdout}" <<-EOF
	EOF
	assert_file - "${stderr}" <<-EOF
	EOF
	assert_ret 0 wait %1
	assert_ret 0 wait %3
	assert_runs_shorter_than 7 assert_ret 0 pwait_jobs %2
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2]   ${sleep2_pid} Done
	EOF
	assert_ret 0 wait %2
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
}

# pwait_jobs on multi-proc jobs
add_test_function test_jobs_6
test_jobs_6() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid
	local stdout stderr

	assert_true sleep 10 | sleep 10 &
	assert_true get_job_id "$!" spawn_jobid
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job multiple_children
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"
	assert_true spawn_job sleep 10
	sleep3_pid="$!"
	sleep3_jobid="${spawn_jobid}"
	echo "sleep3_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Running
	      ${sleep1_pid}
	\[2\] - ${sleep2_pid} Running
	\[3\] \+ ${sleep3_pid} Running
	EOF
	assert_ret 124 pwait_jobs -t 1 %1 %2 %3
	assert_ret 0 pwait_jobs -t 15 %1 %3
	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Done
	      ${sleep1_pid}
	\[2\] \+ ${sleep2_pid} Running
	\[3\]   ${sleep3_pid} Done
	EOF
	# Done jobs should return immediately from pwait without errors.
	capture_output_simple stdout stderr
	assert_runs_shorter_than 3 assert_ret 0 pwait_jobs %1 %3
	capture_output_simple_stop
	assert_file - "${stdout}" <<-EOF
	EOF
	assert_file - "${stderr}" <<-EOF
	EOF
	assert_ret 0 wait %1
	assert_ret 0 wait %3
	assert_runs_longer_than 8 assert_ret 0 pwait_jobs %2
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2]   ${sleep2_pid} Done
	EOF
	assert_ret 0 wait %2
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	assert_false pgrep -l -g "${sleep2_pid}" >&2
}

# kill_all_jobs
add_test_function test_jobs_7
test_jobs_7() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid

	assert_true spawn_job sleep 30
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job sleep 30
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] - ${sleep1_pid} Running
	[2] + ${sleep2_pid} Running
	EOF
	assert_ret 143 kill_all_jobs
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	# assert_false expect_error_on_stderr kill -0 %"${sleep1_jobid}"
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep2_jobid}"
	assert_ret 127 wait %"${sleep2_jobid}"
}

# kill_all_jobs
add_test_function test_jobs_8
test_jobs_8() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid

	assert_true sleep 30 | sleep 30 &
	assert_true get_job_id "$!" spawn_jobid
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job noterm multiple_children
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"
	assert_true spawn_job sleep 30
	sleep3_pid="$!"
	sleep3_jobid="${spawn_jobid}"
	echo "sleep3_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Running
	      ${sleep1_pid}
	\[2\] - ${sleep2_pid} Running
	\[3\] \+ ${sleep3_pid} Running
	EOF
	assert_runs_shorter_than 7 assert_ret 137 kill_all_jobs 5
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	# assert_false expect_error_on_stderr kill -0 %"${sleep1_jobid}"
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false pgrep -l -g "${sleep1_pid}" >&2
	assert_false expect_error_on_stderr kill -0 %"${sleep2_jobid}"
	assert_ret 127 wait %"${sleep2_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep3_jobid}"
	assert_ret 127 wait %"${sleep3_jobid}"
}

# kill_job
add_test_function test_jobs_9
test_jobs_9() {
	local sleep1_pid sleep2_pid sleep3_pid
	local sleep1_jobid sleep2_jobid sleep3_jobid
	local sleep4_pid sleep4_jobid

	assert_true sleep 30 | sleep 40 &
	assert_true get_job_id "$!" spawn_jobid
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"

	assert_true spawn_job noterm eval "sleep 30 | sleep 40"
	sleep2_pid="$!"
	sleep2_jobid="${spawn_jobid}"
	echo "sleep2_pid= $!"

	assert_true spawn_job sleep 30
	sleep3_pid="$!"
	sleep3_jobid="${spawn_jobid}"
	echo "sleep3_pid= $!"

	assert_true spawn_job noterm multiple_children
	sleep4_pid="$!"
	sleep4_jobid="${spawn_jobid}"
	echo "sleep4_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Running
	      ${sleep1_pid}
	\[2\]   ${sleep2_pid} Running
	\[3\] - ${sleep3_pid} Running
	\[4\] \+ ${sleep4_pid} Running
	EOF

	assert_runs_between 0 3 assert_ret 143 kill_job 1 "${sleep1_pid}"
	# assert_false expect_error_on_stderr kill -0 %"${sleep1_jobid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2]   ${sleep2_pid} Running
	[3] - ${sleep3_pid} Running
	[4] + ${sleep4_pid} Running
	EOF

	# Because SIGINT is blocked we should fall back to SIGKILL.
	assert_runs_between 0 3 assert_ret 137 kill_job 1 "${sleep2_pid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep2_jobid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[3] - ${sleep3_pid} Running
	[4] + ${sleep4_pid} Running
	EOF

	# Check %job compat
	assert_runs_between 0 3 assert_ret 143 kill_job 1 %"${sleep3_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep3_jobid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[4] + ${sleep4_pid} Running
	EOF

	assert_runs_between 0 3 assert_ret 137 kill_job 1 %"${sleep4_jobid}"
	assert_false expect_error_on_stderr kill -0 %"${sleep4_jobid}"
	assert_false pgrep -l -g "${sleep4_pid}" >&2
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF

	assert_true spawn_job sleep 30
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF
	assert_true kill %1
	assert_runs_shorter_than 5 assert_true pwait_racy "${sleep1_pid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Terminated
	EOF
	# Should not kill but only collect status. See Dev log.
	assert_runs_between 0 3 assert_ret 143 kill_job 1 %"${sleep1_jobid}"
	# assert_false expect_error_on_stderr kill -0 %"${sleep1_jobid}"
}

# timed_wait_and_kill_job
add_test_function test_jobs_10
test_jobs_10() {
	local sleep1_pid sleep2_pid sleep3_pid

	assert_true spawn_job eval "sleep 5; exit 7"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_runs_shorter_than 12 assert_ret 7 timed_wait_and_kill_job 10 %1

	assert_true spawn_job eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_runs_shorter_than 12 assert_ret 0 timed_wait_and_kill_job 10 %1

	assert_true spawn_job eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_runs_shorter_than 3 assert_ret 143 timed_wait_and_kill_job 1 %1

	assert_true spawn_job noterm eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_runs_shorter_than 3 assert_ret 137 timed_wait_and_kill_job 1 %1

	assert_true spawn_job noterm eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_runs_shorter_than 12 assert_ret 0 timed_wait_and_kill_job 10 %1
}

# timed_wait_and_kill_job with piped job.
add_test_function test_jobs_11
test_jobs_11() {
	local sleep1_pid sleep2_pid sleep3_pid status
	local sleep1_pgid
	local stdout stderr

	assert_true sleep 15 | sleep 5 &
	assert_true get_job_id "$!" spawn_jobid
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"
	sleep1_pgid="$(jobs -p "%1")"
	assert_not "${sleep1_pid}" "${sleep1_pgid}"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\] \+ ${sleep1_pgid} Running
	      ${sleep1_pid}
	EOF
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	capture_output_simple stdout stderr
	assert_runs_shorter_than 19 assert_ret 0 \
	    timed_wait_and_kill_job 17 "%1"
	capture_output_simple_stop
	assert_file - "${stdout}" <<-EOF
	EOF
	assert_file - "${stderr}" <<-EOF
	EOF
	assert_runs_shorter_than 3 assert_ret 127 wait %1
}


# timed_wait_and_kill_job with piped job. Based on checking last pid in pipe
# This test is mostly validating the expected behavior before testing
# timed_wait_and_kill_job.
add_test_function test_jobs_12
test_jobs_12() {
	local sleep1_pid sleep2_pid sleep3_pid status
	local sleep1_pgid
	local use_timed_wait="${1:-0}"
	local stdout stderr

	assert_true sleep 15 | sleep 5 &
	assert_true get_job_id "$!" spawn_jobid
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"
	sleep1_pgid="$(jobs -p "%1")"
	assert_not "${sleep1_pid}" "${sleep1_pgid}"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\] \+ ${sleep1_pgid} Running
	      ${sleep1_pid}
	EOF
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	# Because $! is the last pid it will return...
	assert_runs_between 3 7 assert_true pwait -t 7 "${sleep1_pid}"
	# But because there's still procs running in the job it should be
	# "Running"
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	if [ "${use_timed_wait}" -eq 1 ]; then
		# Wait without kill
		assert_true kill -0 "${sleep1_pgid}"
		# assert_false expect_error_on_stderr kill -0 "${sleep1_pid}"
		capture_output_simple stdout stderr
		assert_runs_shorter_than 14 assert_ret 0 \
		    timed_wait_and_kill_job 12 "%1"
		capture_output_simple_stop
		assert_file - "${stdout}" <<-EOF
		EOF
		assert_file - "${stderr}" <<-EOF
		EOF
		assert_runs_shorter_than 3 assert_ret 127 wait %1
	elif [ "${use_timed_wait}" -eq 2 ]; then
		# Wait with kill
		assert_true kill -0 "${sleep1_pgid}"
		# assert_false expect_error_on_stderr kill -0 "${sleep1_pid}"
		capture_output_simple stdout stderr
		# This is killing the 'sleep 15' and should result in a TERM
		# after timeout.
		if set -o | grep -q "pipefail.*on"; then
			# With pipefail we get the proper TERM due to
			# 'sleep 15' timing out.
			assert_runs_shorter_than 5 assert_ret 143 \
			    timed_wait_and_kill_job 3 "%1"
		else
			# Without pipefail we get the exit status of 'sleep 5'
			# which is 0.
			assert_runs_shorter_than 5 assert_ret 0 \
			    timed_wait_and_kill_job 3 "%1"
		fi
		capture_output_simple_stop
		assert_file - "${stdout}" <<-EOF
		EOF
		assert_file - "${stderr}" <<-EOF
		EOF
		assert_runs_shorter_than 3 assert_ret 127 wait %1
	else
		kill -TERM -- -${sleep1_pgid}
		# Wait a moment, but don't collect
		assert_runs_shorter_than 3 assert_true hide_stderr \
		    pwait_racy "${sleep1_pid}"
		# Now let checkzombies() run
		assert_true get_job_status "%1" status
		assert "Done" "${status}"
		assert_runs_shorter_than 3 assert_ret 0 wait %1
	fi
}

# Same as test_jobs_11() but with timed_wait_and_kill_job _waiting_
add_test_function test_jobs_13
test_jobs_13() {
	test_jobs_12 1
}

# Same as test_jobs_11() but with timed_wait_and_kill_job _killing_
add_test_function test_jobs_14
test_jobs_14() {
	test_jobs_12 2
}

# Same as test_jobs_11() but with timed_wait_and_kill_job _killing_ and pipefail
add_test_function test_jobs_15
test_jobs_15() {
	local -
	set_pipefail
	test_jobs_12 2
}

# Mostly same as test_jobs_11().
# timed_wait_and_kill_job with piped job. Based on checking leader pid in pipe
# This test is mostly validating the expected behavior before testing
# timed_wait_and_kill_job.
add_test_function test_jobs_16
test_jobs_16() {
	local sleep1_pid sleep2_pid sleep3_pid status
	local sleep1_pgid
	local use_timed_wait="${1:-0}"
	local stdout stderr

	assert_true sleep 5 | sleep 15 &
	assert_true get_job_id "$!" spawn_jobid
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"
	sleep1_pgid="$(jobs -p "%1")"
	assert_not "${sleep1_pid}" "${sleep1_pgid}"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\] \+ ${sleep1_pgid} Running
	      ${sleep1_pid}
	EOF
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	# Wait on the first pid
	assert_runs_between 3 7 assert_true pwait -t 7 "${sleep1_pgid}"
	# But because there's still procs running in the job it should be
	# "Running"
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	if [ "${use_timed_wait}" -eq 1 ]; then
		# Wait without kill
		# assert_false expect_error_on_stderr kill -0 "${sleep1_pgid}"
		assert_true kill -0 "${sleep1_pid}"
		capture_output_simple stdout stderr
		assert_runs_shorter_than 12 assert_ret 0 \
		    timed_wait_and_kill_job 13 "%1"
		capture_output_simple_stop
		assert_file - "${stdout}" <<-EOF
		EOF
		assert_file - "${stderr}" <<-EOF
		EOF
	elif [ "${use_timed_wait}" -eq 2 ]; then
		# Wait with kill
		# assert_false expect_error_on_stderr kill -0 "${sleep1_pgid}"
		assert_true kill -0 "${sleep1_pid}"
		capture_output_simple stdout stderr
		# This is killing the 'sleep 15' and should result in a TERM.
		# after timeout.
		assert_runs_shorter_than 5 assert_ret 143 \
		    timed_wait_and_kill_job 3 "%1"
		capture_output_simple_stop
		assert_file - "${stdout}" <<-EOF
		EOF
		assert_file - "${stderr}" <<-EOF
		EOF
		assert_runs_shorter_than 1 assert_ret 127 wait %1
	else
		# kill -TERM ${sleep1_pid}
		# Wait a moment, but don't collect
		assert_runs_shorter_than 12 assert_true pwait_racy "${sleep1_pid}"
		# Now let checkzombies() run
		assert_true get_job_status "%1" status
		assert "Done" "${status}"
		assert_runs_shorter_than 1 assert_ret 0 wait %1
	fi
}

# Same as test_jobs_16() but with timed_wait_and_kill_job _waiting_
add_test_function test_jobs_17
test_jobs_17() {
	test_jobs_16 1
}

# Same as test_jobs_15() but with timed_wait_and_kill_job _killing_
add_test_function test_jobs_18
test_jobs_18() {
	test_jobs_16 2
}

# Same as test_jobs_16() but with timed_wait_and_kill_job _killing_ and pipefail
add_test_function test_jobs_19
test_jobs_19() {
	local -
	set_pipefail
	test_jobs_16 2
}

# Same as test_jobs_11() but kill's the last pid at the end and gets a
# Terminated.
# This test is mostly validating the expected behavior before testing
add_test_function test_jobs_20
test_jobs_20() {
	local sleep1_pid sleep2_pid sleep3_pid status
	local sleep1_pgid

	assert_true sleep 5 | sleep 15 &
	assert_true get_job_id "$!" spawn_jobid
	assert "1" "${spawn_jobid}"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"
	sleep1_pgid="$(jobs -p "%1")"
	assert_not "${sleep1_pid}" "${sleep1_pgid}"

	assert_true get_jobs "${TMP}"
	assert_file_reg - "${TMP}" <<-EOF
	\[1\] \+ ${sleep1_pgid} Running
	      ${sleep1_pid}
	EOF
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	# Wait on the first pid
	assert_runs_between 3 7 assert_true pwait -t 7 "${sleep1_pgid}"
	# But because there's still procs running in the job it should be
	# "Running"
	assert_true get_job_status "%1" status
	assert "Running" "${status}"
	kill -TERM ${sleep1_pid}
	# Wait a moment, but don't collect
	assert_runs_shorter_than 12 assert_true pwait_racy "${sleep1_pid}"
	# Now let checkzombies() run
	assert_true get_job_status "%1" status
	assert "Terminated" "${status}"
	assert_runs_shorter_than 1 assert_ret 143 wait %1
}

run_test_functions
