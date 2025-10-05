: "${TIMEOUT_BIN:=timeout}"

THIS_JOB=0
make_returnjob() {
	local mr_job="$1"

	#echo "RETURN JOB ${mr_job}" >&2
	case "${mr_job}" in
	"this")
		THIS_JOB=0
		return 0
		;;
	esac

	case "${JOB_PIPE_W:+set}" in
	set)
		echo -n "${mr_job:?}" >>"${JOB_PIPE_W:?}"
		;;
	esac
}
# make_getjob outvar
make_getjob() {
	local job_outvar="$1"
	local job_pipe job_fd
	local ret mg_job
	local dd_stderr dd_err timeout

	case "${MAKEFLAGS:+set}" in
	set) ;;
	*)
		setvar "${job_outvar}" ""
		if [ "${JOBS}" -le "${TEST_CONTEXTS_PARALLEL}" ]; then
			return 0
		fi
		return 1
		;;
	esac
	case "${JOB_PIPE_R:+set}" in
	set) ;;
	*)
		case "${MAKEFLAGS}" in
		*"--jobserver-auth=fifo:/"*)
			job_pipe="$(echo "${MAKEFLAGS}" |
			    grep -o -- '--jobserver-auth=fifo:/[^ ]*' |
			    sed -e 's,.*:,,')"
			JOB_PIPE_R="${job_pipe}"
			JOB_PIPE_W="${job_pipe}"
			JOB_PIPE_BLOCKING=0
			;;
		*"-J "[0-9]*)
			job_fd="$(echo "${MAKEFLAGS}" |
			    grep -o -- '-J [0-9]*,[0-9]*' |
			    sed -e 's,-J ,,' -e 's#,# #')"
			JOB_PIPE_W="/dev/fd/${job_fd##* }"
			JOB_PIPE_R="/dev/fd/${job_fd%% *}"
			JOB_PIPE_BLOCKING=0
			;;
		*"--jobserver-auth="[0-9]*)
			job_fd="$(echo "${MAKEFLAGS}" |
			    grep -o -- '--jobserver-auth=[0-9]*,[0-9]*' |
			    sed -e 's,--jobserver-auth=,,' -e 's#,# #')"
			JOB_PIPE_W="/dev/fd/${job_fd##* }"
			JOB_PIPE_R="/dev/fd/${job_fd%% *}"
			JOB_PIPE_BLOCKING=1
			;;
		*)
			unset MAKEFLAGS
			return 1
			;;
		esac
	esac
	case "${JOB_PIPE_W}" in
	"/dev/fd/"*)
		if ! mount | grep -q fdescfs; then
			echo "fdescfs required for make jobserver support." >&2
			exit 99
		fi
		;;
	esac

	dd_stderr="$(mktemp -ut runtest)"
	while :; do
		timeout=
		if [ "${THIS_JOB}" -eq 0 ] ||
		    ! kill -0 "${THIS_JOB}" 2>/dev/null ||
		    pwait -o -t "0.1" "${THIS_JOB}" >/dev/null 2>&1; then
			# This runtest.sh runner itself was given a job.
			# Use it before asking the jobserver for more.
			collectpids "0.1" || :
			THIS_JOB=1
			mg_job="this"
			#echo "GOT JOB ${mg_job}" >&2
			setvar "${job_outvar}" "${mg_job}"
			return 0
		elif [ "${THIS_JOB}" -ne 0 ]; then
			timeout="${TIMEOUT_BIN:?} --preserve-status -s SIGALRM 2"
		fi
		# There is a race with checking for "this" job above and waiting
		# on the job server for a job. 142 below will recheck for "this"
		# job on timeout.
		mg_job="$(${timeout} \
			  dd if="${JOB_PIPE_R}" bs=1 count=1 2>"${dd_stderr}")"
		ret="$?"
		read dd_err < "${dd_stderr}" || dd_err=
		rm -f "${dd_stderr}"
		case "${ret}" in
		0) ;;
		142)
			# Recheck for "this" job being done.
			continue
			;;
		*)
			case "${JOB_PIPE_BLOCKING}" in
			1)
				# Detect EAGAIN; it is not really blocking.
				case "${dd_err}" in
				*"${JOB_PIPE_R}"*"Resource temporarily unavailable")
					sleep 0.2
					continue
					;;
				esac
				echo "Job server read error ${ret}" >&2
				exit 99
				;;
			0)
				sleep 1
				continue
				;;
			esac
			;;
		esac
		#echo "GOT JOB ${mg_job}" >&2
		setvar "${job_outvar}" "${mg_job}"
		ret=0
		break
	done
	rm -f "${dd_stderr}"
	return "${ret}"
}
set -e
set -u

# Need to trim environment of anything that may taint our top-level port var
# fetching.
while read var; do
	case "${var}" in
	am_abs_top_builddir|\
	am_abs_top_srcdir|\
	am_srcdir|\
	am_bindir|\
	am_pkglibexecdir|\
	am_pkgdatadir|\
	am_VPATH|\
	am_check|am_installcheck|\
	MAKEFLAGS|\
	CCACHE*|\
	PATH|\
	PWD|\
	TIMEOUT|\
	KEEP_OLD_PACKAGES_COUNT|KEEP_LOGS_COUNT|\
	PARALLEL_JOBS|\
	TEST_NUMS|ASSERT_CONTINUE|TEST_CONTEXTS_PARALLEL|\
	URL_BASE|\
	PVERBOSE|VERBOSE|\
	SH_DISABLE_VFORK|TIMESTAMP|TRUSS|TIMEOUT_BIN|\
	HTML_JSON_UPDATE_INTERVAL|\
	TESTS_SKIP_BUILD|\
	TESTS_SKIP_LONG|\
	TESTS_SKIP_BULK|\
	TMPDIR|\
	SH) ;;
	*)
		unset "${var}"
		;;
	esac
done <<-EOF
$(env | cut -d= -f1)
EOF

TEST=$(realpath "$1")
: ${am_check:=0}
: ${am_installcheck:=0}

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/sbin:/usr/local/bin:${PATH}"

if [ "${am_check}" -eq 1 ] &&
	[ "${am_installcheck}" -eq 0 ]; then
	LIBEXECPREFIX="${am_abs_top_builddir}"
	export SCRIPTPREFIX="${am_abs_top_srcdir}/src/share/poudriere"
	export POUDRIEREPATH="poudriere"
	export PATH="${LIBEXECPREFIX}:${PATH}"
elif [ "${am_check}" -eq 1 ] &&
	[ "${am_installcheck}" -eq 1 ]; then
	LIBEXECPREFIX="${am_pkglibexecdir}"
	export SCRIPTPREFIX="${am_pkgdatadir}"
	#export POUDRIEREPATH="${am_bindir}/poudriere"
	export POUDRIEREPATH="poudriere"
	export PATH="${am_bindir}:${LIBEXECPREFIX}:${PATH}"
else
	if [ -z "${am_abs_top_srcdir-}" ]; then
		: ${am_VPATH:="$(realpath "${0%/*}")"}
		am_abs_top_srcdir="$(realpath "${am_VPATH}/..")"
		am_abs_top_builddir="${am_abs_top_srcdir}"
	fi
	LIBEXECPREFIX="${am_abs_top_builddir}"
	export SCRIPTPREFIX="${am_abs_top_srcdir}/src/share/poudriere"
	export POUDRIEREPATH="${am_abs_top_builddir}/poudriere"
	export PATH="${LIBEXECPREFIX}:${PATH}"
fi
if [ -z "${LIBEXECPREFIX-}" ]; then
	echo "ERROR: Could not determine POUDRIEREPATH" >&2
	exit 99
fi
: ${am_VPATH:=.}
: ${SH:=sh}
if [ "${SH}" = "sh" ]; then
	SH="${LIBEXECPREFIX}/sh"
fi

BUILD_DIR="${PWD}"
# source dir
THISDIR=${am_VPATH}
THISDIR="$(realpath "${THISDIR}")"
cd "${THISDIR}"

case "${1##*/}" in
prep.sh) : ${TIMEOUT:=1800} ;;
bulk*build*.sh|testport*build*.sh) : ${TIMEOUT:=1800} ;;
# Bump anything touching logclean
bulk*.sh|testport*.sh|distclean*.sh|options*.sh) : ${TIMEOUT:=500} ;;
critical_section_inherit.sh) : ${TIMEOUT:=20} ;;
locked_mkdir.sh) : ${TIMEOUT:=120} ;;
jobs.sh) : ${TIMEOUT:=300} ;;
esac
: ${TIMEOUT:=90}
case "${TRUSS-}" in
"") ;;
*) TIMEOUT=$((TIMEOUT * 3)) ;;
esac
TIMEOUT_KILL="-k 30"
if [ -n "${TESTS_SKIP_BUILD-}" ]; then
	case "${1##*/}" in
	*-build*)
		exit 77
		;;
	esac
fi
if [ -n "${TESTS_SKIP_LONG-}" ]; then
	case "${1##*/}" in
	jobs.sh)
		exit 77
		;;
	esac
fi
if [ -n "${TESTS_SKIP_BULK-}" ]; then
	case "${1##*/}" in
	testport-*.sh|bulk-*.sh)
		exit 77
		;;
	esac
fi
: ${TIMESTAMP="${LIBEXECPREFIX}/timestamp" -t -1stdout: -2stderr:}

[ "${am_check}" -eq 0 ] && [ -t 0 ] && export FORCE_COLORS=1
exec < /dev/null

echo "Using SH=${SH}" >&2

rm -f "${TEST}.log.truss"

get_log_name() {
	echo "${TEST}${TEST_CONTEXT_NUM:+-${TEST_CONTEXT_NUM}}.log"
}

runtest() {
	local make_job="${1-}"
	local - ret

	ret=0
	set +eu

	unset MAKEFLAGS
	export TEST_NUMS
	# With truss use --foreground to prevent process reaper and ptrace deadlocking.
	set -x
	case "${TRUSS-}" in
	"") ;;
	*)
		# Let truss finish draining when receiving a signal.
		# Only do this for truss as otherwise some tests will not
		# be able to modify the signals for their own purposes.
		trap '' INT PIPE TERM HUP
		;;
	esac
	{
		TEST_START="$(clock -monotonic)"
		echo "Test started: $(date)"
		# hide set -x
	} >&2 2>/dev/null
	${TIMEOUT_BIN:?} -v ${TRUSS:+--foreground} ${TIMEOUT_KILL} ${TIMEOUT} \
	    ${TIMESTAMP} \
	    env \
	    ${SH_DISABLE_VFORK:+SH_DISABLE_VFORK=1} \
	    THISDIR="${THISDIR}" \
	    SH="${SH}" \
	    lockf -k "$(get_log_name).lock" \
	    ${TRUSS:+truss -ae -f -s512 -o "$(get_log_name).truss"} \
	    "${SH}" "${TEST}" || ret="$?"
	{
		TEST_END="$(clock -monotonic)"
		echo "Test ended: $(date) -- duration: $((TEST_END - TEST_START))s"
		# hide set -x
	} >&2 2>/dev/null
	case "${make_job:+set}" in
	set)
		make_returnjob "${make_job}"
		;;
	esac
	return "${ret}"
}

collectpids() {
	local timeout="$1"
	local pids_copy tries max

	case "${pids:+set}" in
	set) ;;
	*) return 0 ;;
	esac

	# Try a few times depending on the timeout and reduce it each try.
	case "${timeout}" in
	*.*)
		max="${timeout%.*}"
		max="$((max + 1))"
		;;
	*) max="${timeout}" ;;
	esac
	tries=0
	echo "Waiting on pids: ${pids} timeout: ${timeout}" >&2
	until [ -z "${pids:+set}" ] || [ "${tries}" -eq "${max}" ]; do
		pwait -o -t "${timeout}" ${pids} >/dev/null 2>&1 || :
		pids_copy="${pids}"
		pids=
		for pid in ${pids_copy}; do
			if kill -0 "${pid}" 2>/dev/null; then
				pids="${pids:+${pids} }${pid}"
				continue
			fi
			getvar "pid_num_${pid}" pid_test_context_num
			pret=0
			wait "${pid}" || pret="$?"
			MAIN_RET="$((MAIN_RET + pret))"
			case "${pret}" in
			0)
				result="OK"
				;;
			*)
				result="FAIL"
				;;
			esac
			exit_type=
			case "${pret}" in
			0) exit_type="PASS" ;;
			*) exit_type="FAIL" ;;
			esac
			printf \
			    "%s TEST_CONTEXT_NUM=%d pid=%-5d exited %-3d - %s: %s\n" \
			    "${exit_type}" \
			    "${pid_test_context_num}" \
			    "${pid}" \
			    "${pret}" \
			    "$(TEST_CONTEXT_NUM="${pid_test_context_num}" get_log_name)" \
			    "${result}"
			JOBS="$((JOBS - 1))"
			case "${VERBOSE:+set}.${exit_type}" in
			set.FAIL)
				cat "$(TEST_CONTEXT_NUM="${pid_test_context_num}" get_log_name)"
				;;
			esac
		done
		tries="$((tries + 1))"
		case "${timeout}" in
		*.*) ;;
		*)
			timeout="$((timeout - 1))"
			;;
		esac
	done
	if [ -z "${pids:+set}" ]; then
		return 0
	fi
	return 1
}

_spawn_wrapper() {
	case $- in
	*m*)	# Job control
		# Don't stop processes if they try using TTY.
		trap '' SIGTTIN
		trap '' SIGTTOU
		;;
	*)	# No job control
		# Reset SIGINT to the default to undo POSIX's SIG_IGN in
		# 2.11 "Signals and Error Handling". This will ensure no
		# foreground process is left around on SIGINT.
		if [ ${SUPPRESS_INT:-0} -eq 0 ]; then
			trap - INT
		fi
		;;
	esac

	"$@"
}

spawn() {
	_spawn_wrapper "$@" &
}

spawn_job() {
	local -
	set -m
	spawn "$@"
}

if ! type setvar >/dev/null 2>&1; then
setvar() {
	[ $# -eq 2 ] || eargs setvar variable value
	local _setvar_var="$1"
	shift
	local _setvar_value="$*"

	read -r "${_setvar_var?}" <<-EOF
	${_setvar_value}
	EOF
}
fi

getvar() {
	local _getvar_var="$1"
	local _getvar_var_return="${2-}"
	local ret _getvar_value

	eval "_getvar_value=\${${_getvar_var}-gv__null}"

	case "${_getvar_value}" in
	gv__null)
		_getvar_value=
		ret=1
		;;
	*)
		ret=0
		;;
	esac

	case "${_getvar_var_return-}" in
	""|-)
		echo "${_getvar_value}"
		;;
	*)
		setvar "${_getvar_var_return}" "${_getvar_value}"
		;;
	esac

	return ${ret}
}

getpid() {
	sh -c 'echo $PPID'
}

raise() {
	local sig="$1"

	kill -"${sig}" "$(getpid)"
}

setup_traps() {
	[ "$#" -eq 1 ] || eargs setup_traps exit_handler
	local exit_handler="$1"
	local sig

	for sig in INT HUP PIPE TERM; do
		trap "sig_handler ${sig} ${exit_handler}" "${sig}"
	done
	trap "${exit_handler}" EXIT
	# hide set -x
	trap '{ siginfo_handler; } 2>/dev/null' INFO
}

format_siginfo() {
	local make_job="$1"
	local test_name="$2"
	local test_num="$3"
	local total_tests="$4"
	local log="$5"

	case "${make_job}" in
	this) ;;
	*)
		make_job="make"
		;;
	esac

	printf "%4s %02d/%02d %s %s\n" "${make_job}" "${test_num}" \
	    "${total_tests}" "${test_name}" "${log}"
}

siginfo_handler() {
	case "${pids-}" in
	"") return ;;
	esac
	local pid duration start now test_data

	now="$(clock -monotonic)"
	# Note sorting this nicely won't do much as runtest.sh (this file)
	# is ran in separate jobs by make.
	for pid in ${pids}; do
		getvar "pid_test_start_${pid}" start
		duration="$((now - start))"
		getvar "pid_test_${pid}" test_data
		printf "pid %05d %3ds %s\n" "${pid}" "${duration}" "${test_data}"
	done >&4
}

sig_handler() {
	local sig="$1"
	local exit_handler="$2"

	set +e +u
	unset IFS
	trap '' PIPE INT INFO HUP TERM
	trap - EXIT
	"${exit_handler}"
	trap - "${sig}"
	raise "${sig}"
}

: ${TEST_CONTEXTS_PARALLEL:=4}

if [ "${TEST_CONTEXTS_PARALLEL}" -gt 1 ] &&
    grep -q get_test_context "${TEST}"; then
	{
		TEST_SUITE_START="$(clock -monotonic)"
		echo "Test suite started: $(date)"
		# hide set -x
	} >&2 2>/dev/null
	cleanup() {
		local jobs

		exec >/dev/null 2>&1
		jobs="$(jobs -p)"
		case "${jobs:+set}" in
		set)
			for pgid in ${jobs}; do
				kill -STOP -"${pgid}" || :
				kill -TERM -"${pgid}" || :
				kill -CONT -"${pgid}" || :
			done
			;;
		esac
	}
	setup_traps cleanup
	TEST_CONTEXTS_TOTAL="$(env \
	    TEST_CONTEXTS_NUM_CHECK=yes \
	    THISDIR="${THISDIR}" \
	    SH="${SH}" \
	    VERBOSE=0 \
	    "${SH}" "${TEST}" 2>/dev/null)"
	case "${TEST_CONTEXTS_TOTAL}" in
	[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]) ;;
	*)
		echo "TEST_CONTEXTS_TOTAL is bogus value '${TEST_CONTEXTS_TOTAL}'" >&2
		exit 99
		;;
	esac
	JOBS=0
	MAIN_RET=0
	case "${TEST_CONTEXTS_TOTAL}" in
	[0-9]) num_width="01" ;;
	[0-9][0-9]) num_width="02" ;;
	[0-9][0-9][0-9]) num_width="03" ;;
	[0-9][0-9][0-9][0-9]) num_width="04" ;;
	*) num_width="05" ;;
	esac
	case "${TEST_NUMS-null}" in
	null)
		TEST_CONTEXT_NUM=1
		until [ "${TEST_CONTEXT_NUM}" -gt "${TEST_CONTEXTS_TOTAL}" ]; do
			logname="$(get_log_name)"
			rm -f "${logname}"
			TEST_NUMS="${TEST_NUMS:+${TEST_NUMS} }${TEST_CONTEXT_NUM}"
			TEST_CONTEXT_NUM=$((TEST_CONTEXT_NUM + 1))
		done
		;;
	esac
	until [ -z "${TEST_NUMS:+set}${pids:+set}" ]; do
		if [ -n "${TEST_NUMS:+set}" ] && make_getjob make_job; then
			TEST_CONTEXT_NUM="${TEST_NUMS%% *}"
			case "${TEST_NUMS}" in
			*" "*)
				TEST_NUMS="${TEST_NUMS#* }"
				;;
			*)
				TEST_NUMS=
				;;
			esac
			logname="$(get_log_name)"
			printf "Logging %s with TEST_CONTEXT_NUM=%${num_width}d/%${num_width}d to %s\n" \
			    "${TEST}" \
			    "${TEST_CONTEXT_NUM}" \
			    "${TEST_CONTEXTS_TOTAL}" \
			    "${logname}" >&2
			job_test_nums="${TEST_CONTEXT_NUM}"
			TEST_NUMS="${job_test_nums}" \
			    spawn_job runtest "${make_job}" > "${logname}" 2>&1
			case "${make_job}" in
			"this")
				THIS_JOB="$!"
				#echo "THIS_JOB=$!"
				;;
			esac
			setvar "pid_test_$!" "$(format_siginfo "${make_job}" \
			    "${TEST}" "${TEST_CONTEXT_NUM}" \
			    "${TEST_CONTEXTS_TOTAL}" "${logname}")"
			setvar "pid_test_start_$!" "$(clock -monotonic)"
			pids="${pids:+${pids} }$!"
			JOBS="$((JOBS + 1))"
			setvar "pid_num_$!" "${TEST_CONTEXT_NUM}"
			continue
		fi
		collectpids 5 || :
	done
	{
		TEST_SUITE_END="$(clock -monotonic)"
		echo "Test suite ended: $(date) -- duration: $((TEST_SUITE_END - TEST_SUITE_START))s"
		# hide set -x
	} >&2 2>/dev/null
	exit "${MAIN_RET}"
fi

# hide set -x
trap '{ siginfo_handler; } 2>/dev/null' INFO
pids="$$"
setvar "pid_test_start_$$" "$(clock -monotonic)"
setvar "pid_test_$$" "$(format_siginfo "this" "${TEST}" "1" "1" "$(get_log_name)")"
set -T
runtest
