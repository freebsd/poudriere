VERBOSE=0
set -e
FORCE_COLORS=1
. ./common.sh
set +e

COLOR_DEV=
COLOR_DEBUG=

TIMESTAMP_LOGS=no
POUDRIERE_BUILD_TYPE=bulk
MASTERNAME=$(echo "${SCRIPTPATH}" | tr '[./]' '_')_logging
NO_ELAPSED_IN_MSG=1
# Don't show $(getpid) in error msgs
USE_DEBUG=no

logging_setup() {
	unset tpid log_start_job
	unset expect_pids
	TIMESTAMP_LOGS=no
	expect_pids=0
	expect_pids_port="${expect_pids}"
	case "${PORT_TEE:?}" in
	1) expect_pids_port=1 ;;
	esac
	colored="${COLOR_RED:?}x${COLOR_RESET:?}"
	colored_arrow_error="${COLOR_ERROR:?}=>> ${COLOR_RESET:?}"
	colored_error="${COLOR_ERROR:?}Error:${COLOR_RESET:?} "
	colored_arrow_warn="${COLOR_WARN:?}=>> ${COLOR_RESET:?}"
	colored_warn="${COLOR_WARN:?}Warning:${COLOR_RESET:?} "
	my_builder_id="01"
	colorize_job_id COLOR_JOBID "${my_builder_id}"
	colored_jobid="[${COLOR_JOBID:?}${my_builder_id}${COLOR_RESET}] "
	colored_reset="${COLOR_RESET:?}"
	case "${PORT_TEE:?}" in
	1)
		port_tee=1
		port_no_tee=
		;;
	0)
		port_tee=
		port_no_tee=1
		;;
	esac
}

logging_teardown() {
	if [ -n "${port-}" ]; then
		rm -f "${port}"
		unset port
	fi
}

set_test_contexts - logging_setup logging_teardown <<-EOF
prefix ""
TIMESTAMP_LOGS no
PORT_TEE 1 0
EOF

check_pids() {
	if [ "$#" -eq 0 ] || [ -z "$1" ]; then
		msg_warn "check_pids called without a pid?" 2>&${REDIRECTED_STDERR_FD:-2}
		return 1
	fi
	#sleep 0.1
	kill -0 $* 2>&${REDIRECTED_STDERR_FD:-2}
}

# - job_msg() only ever goes to the bulk TTY
# - msg_error() without MY_BUILDER_ID is for testport. Error is sent to TTY stderr.
# - msg_error() with MY_BUILDER_ID sends the error to the current stderr AND
#   duplicates it to job_msg(). In this case if we are teeing then the TTY
#   stdout will get a duplicated copy of the message. That's not a real case
#   but is an artifact of the test matrix here.
# - Teeing always sends stderr to stdout.

TEE_SLEEP_TIME="0.5"
{
while get_test_context; do
	capture_output_simple bulk bulk_stderr
	echo test0
	echo err0 >&2

	msg "bulk-message-pre-port"
	msg_error "bulk-error-pre-port"
	msg_warn "bulk-warn-pre-port"

	PORT_NAME="port-${TEST_CONTEXT_NUM}"
	assert_ret 0 log_start ${prefix:+-P "port:"} "${PORT_NAME}" ${PORT_TEE}
	if [ "${expect_pids_port}" -eq 1 ]; then
		assert_not "null" "${log_start_job-null}"
		assert_ret 0 check_pids "${log_start_job}"
	else
		assert "null" "${log_start_job-null}"
	fi
	_logfile port "${PORT_NAME}"
	assert_ret 0 [ -r "${port}" ]
	echo "port-test1${colored}"
	echo "port-err1${colored}" >&2	# log_start sends 2>&1
	msg_warn "port-warn1${colored}"
	if [ "${PORT_TEE}" -eq 1 ]; then
		# Give a chance for tee to flush before we write directly
		# to the parent.
		sleep "${TEE_SLEEP_TIME}"
	fi
	MY_BUILDER_ID=${my_builder_id} job_msg "job msg to bulk${colored}x${colored_reset}"
	MY_BUILDER_ID=${my_builder_id} msg_error "job error from port for port stderr and bulk stdout"
	msg_error "error from port only for bulk stderr"
	redirect_to_bulk echo console-port-test1
	redirect_to_bulk echo console-port-test1-err >&2
	if [ "${expect_pids_port}" -eq 1 ]; then
		tpid="$(jobid "%${log_start_job:?}")"
		assert 0 "$?"
		assert_ret 0 check_pids "${tpid}"
	fi
	echo "port-test2${colored}"
	echo "port-err2${colored}" >&2 # log_start sends 2>&1
	if [ "${PORT_TEE}" -eq 1 ]; then
		# Give a chance for tee to flush before we write directly
		# to the parent.
		sleep "${TEE_SLEEP_TIME}"
	fi
	MY_BUILDER_ID=${my_builder_id} msg_error "job error-post from port for port stderr and bulk stdout"
	msg_error "error-post from port only for bulk stderr"
	if [ "${expect_pids_port}" -eq 1 ]; then
		tpid="$(jobid "%${log_start_job:?}")"
		assert 0 "$?"
		assert_ret 0 check_pids "${tpid}"
	fi
	assert_ret 0 log_stop "${PORT_NAME}"
	assert_ret 0 [ -r "${port}" ]
	assert "0" "${OUTPUT_REDIRECTED-null}"

	msg "message-post from bulk"
	msg_error "error-post from bulk"
	msg_warn "warn-post from bulk"

	capture_output_simple_stop

	# Check without ordering mattering to avoid test races with stdout/stderr
	assert_file_unordered - "${port}" <<-EOF
	${prefix:+port: }port-test1${colored}
	${prefix:+port: }port-err1${colored}
	${prefix:+port: }=>> Error: job error from port for port stderr and bulk stdout
	${prefix:+port: }port-test2${colored}
	${prefix:+port: }${colored_arrow_warn}${colored_warn}port-warn1${colored}${colored_reset}
	${prefix:+port: }port-err2${colored}
	${prefix:+port: }=>> Error: job error-post from port for port stderr and bulk stdout
	EOF

	# Check without ordering mattering to avoid test races with stdout/stderr
	assert_file_unordered - "${bulk}" <<-EOF
	${prefix:+bulk: }test0
	${prefix:+bulk: }=>> bulk-message-pre-port
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }port-test1${colored}
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }port-err1${colored}
	${prefix:+bulk: }=>> ${colored_reset}${colored_jobid}job msg to bulk${colored}x${colored_reset}${colored_reset}
	${prefix:+bulk: }${colored_arrow_error}${colored_jobid}${colored_error}job error from port for port stderr and bulk stdout${colored_reset}
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }=>> Error: job error from port for port stderr and bulk stdout
	${prefix:+bulk: }console-port-test1
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }port-test2${colored}
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }port-err2${colored}
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }${colored_arrow_warn}${colored_warn}port-warn1${colored}${colored_reset}
	${prefix:+bulk: }${colored_arrow_error}${colored_jobid}${colored_error}job error-post from port for port stderr and bulk stdout${colored_reset}
	${port_no_tee:+#}${prefix:+bulk: }${prefix:+port: }=>> Error: job error-post from port for port stderr and bulk stdout
	${prefix:+bulk: }=>> message-post from bulk
	EOF

	# Check without ordering mattering to avoid test races with stdout/stderr
	assert_file_unordered - "${bulk_stderr}" <<-EOF
	err0
	${prefix:+bulk: }${colored_arrow_error}${colored_error}bulk-error-pre-port${colored_reset}
	${prefix:+bulk: }${colored_arrow_warn}${colored_warn}bulk-warn-pre-port${colored_reset}
	${prefix:+bulk: }${colored_arrow_error}${colored_error}error from port only for bulk stderr${colored_reset}
	${prefix:+bulk: }console-port-test1-err
	${prefix:+bulk: }${colored_arrow_error}${colored_error}error-post from port only for bulk stderr${colored_reset}
	${prefix:+bulk: }${colored_arrow_error}${colored_error}error-post from bulk${colored_reset}
	${prefix:+bulk: }${colored_arrow_warn}${colored_warn}warn-post from bulk${colored_reset}
	EOF
done
}

exit 0
