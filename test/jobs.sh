# This test is testing very specific formats because get_job_id() depends on it.
set +e
. ./common.sh
set -e

TMP="$(mktemp -ut jobs)"

# jobs -l but trim out the 30/64 col whitespace excess
get_jobs() {
	[ "$#" -eq 1 ] || eargs getjobs file
	local file="$1"

	jobs -l > "${file}"
	sed -i '' -e 's, *$,,' "${file}"
}

pwait_racy() {
	local allpids pid state pids IFS -

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
	trap '' TERM
	"$@"
}

multiple_children() {
	sleep 30
}

# spawn_job and get_job_id and get_job_status
{
	assert_true spawn_job sleep 50
	assert "1" "${spawn_jobid}"
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
	assert_true pwait_racy "${sleep1_pid}"

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

	assert_ret 143 wait %1

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

	assert_true pwait_racy "${sleep1_pid}"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Done
	[2] - ${sleep2_pid} Running
	[3] + ${sleep3_pid} Running
	EOF

	jobs_with_statuses "$(jobs)" > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
	EOF
	cat > "${TMP}" <<-EOF
	$(jobs_with_statuses "$(jobs)")
	EOF
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
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
	assert_true pwait_racy "${sleep3_pid}"

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

# spawn_job and get_job_id and get_job_status, with piped jobs
{
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
	assert_file_reg - "${TMP}" <<-EOF
	\[1\]   [0-9]+ Done
	      [0-9]+
	      ${sleep1_pid}
	\[2\] - [0-9]+ Running
	      ${sleep2_pid}
	\[3\] \+ [0-9]+ Running
	      ${sleep3_pid}
	EOF

	jobs_with_statuses "$(jobs)" > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
	EOF
	cat > "${TMP}" <<-EOF
	$(jobs_with_statuses "$(jobs)")
	EOF
	assert_file - "${TMP}" <<-EOF
	%1 Done
	%2 Running
	%3 Running
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
{
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
	assert_false kill -0 %"${sleep1_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false kill -0 %"${sleep2_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep2_jobid}"
	assert_false kill -0 %"${sleep3_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep3_jobid}"
}

# kill_jobs (different ordering)
{
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
	assert_false kill -0 %"${sleep1_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false kill -0 %"${sleep2_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep2_jobid}"
	assert_false kill -0 %"${sleep3_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep3_jobid}"
}

# pwait_jobs on single-proc jobs
{
	assert_true spawn_job sleep 10
	sleep1_pid="$!"
	sleep1_jobid="${spawn_jobid}"
	echo "sleep1_pid= $!"
	assert_true spawn_job sleep 50
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
	assert_ret 124 pwait_jobs -t 1 %1 %2 %3
	assert_ret 0 pwait_jobs -t 15 %1 %3
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Done
	[2] + ${sleep2_pid} Running
	[3]   ${sleep3_pid} Done
	EOF
	# Done jobs should return immediately from pwait without errors.
	capture_output_simple stdout stderr
	assert_ret 0 pwait_jobs %1 %3
	capture_output_simple_stop
	assert_file - "${stdout}" <<-EOF
	EOF
	assert_file - "${stderr}" <<-EOF
	EOF
	assert_ret 0 wait %1
	assert_ret 0 wait %3
	assert_ret 0 pwait_jobs %2
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
{
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
	assert_ret 0 pwait_jobs %1 %3
	capture_output_simple_stop
	assert_file - "${stdout}" <<-EOF
	EOF
	assert_file - "${stderr}" <<-EOF
	EOF
	assert_ret 0 wait %1
	assert_ret 0 wait %3
	assert_ret 0 pwait_jobs %2
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
{
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
	assert_false kill -0 %"${sleep1_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false kill -0 %"${sleep2_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep2_jobid}"
}

# kill_all_jobs
{
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
	assert_ret 137 kill_all_jobs
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	EOF
	assert_false kill -0 %"${sleep1_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep1_jobid}"
	assert_false pgrep -l -g "${sleep1_pid}" >&2
	assert_false kill -0 %"${sleep2_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep2_jobid}"
	assert_false kill -0 %"${sleep3_jobid}" 2>/dev/null
	assert_ret 127 wait %"${sleep3_jobid}"
}

# kill_job
{
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

	assert_ret 143 kill_job 1 "${sleep1_pid}"
	assert_false kill -0 %"${sleep1_jobid}" 2>/dev/null
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[2]   ${sleep2_pid} Running
	[3] - ${sleep3_pid} Running
	[4] + ${sleep4_pid} Running
	EOF

	# Because SIGINT is blocked we should fall back to SIGKILL.
	assert_ret 137 kill_job 1 "${sleep2_pid}"
	assert_false kill -0 %"${sleep2_jobid}" 2>/dev/null
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[3] - ${sleep3_pid} Running
	[4] + ${sleep4_pid} Running
	EOF

	# Check %job compat
	assert_ret 143 kill_job 1 %"${sleep3_jobid}"
	assert_false kill -0 %"${sleep3_jobid}" 2>/dev/null
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[4] + ${sleep4_pid} Running
	EOF

	assert_ret 137 kill_job 1 %"${sleep4_jobid}"
	assert_false kill -0 %"${sleep4_jobid}" 2>/dev/null
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
	assert_true pwait_racy "${sleep1_pid}"
	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1]   ${sleep1_pid} Terminated
	EOF
	# Should not kill but only collect status. See Dev log.
	assert_ret 143 kill_job 1 %"${sleep1_jobid}"
	assert_false kill -0 %"${sleep1_jobid}" 2>/dev/null
}

# timed_wait_and_kill_job
{
	assert_true spawn_job eval "sleep 5; exit 7"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_ret 7 timed_wait_and_kill_job 10 %1

	assert_true spawn_job eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_ret 0 timed_wait_and_kill_job 10 %1

	assert_true spawn_job eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_ret 143 timed_wait_and_kill_job 1 %1

	assert_true spawn_job noterm eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_ret 137 timed_wait_and_kill_job 1 %1

	assert_true spawn_job noterm eval "sleep 5"
	sleep1_pid="$!"
	echo "sleep1_pid= $!"

	assert_true get_jobs "${TMP}"
	assert_file - "${TMP}" <<-EOF
	[1] + ${sleep1_pid} Running
	EOF

	assert_ret 0 timed_wait_and_kill_job 10 %1
}
