: "${TIMEOUT_BIN:=timeout}"
: "${TIMEOUT_FOREGROUND=--foreground}"

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
		# checkzombies() needed for poudriere sh
		jobs >/dev/null
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
			timeout="${TIMEOUT_BIN:?} --foreground --preserve-status -s SIGALRM 2"
		fi
		# There is a race with checking for "this" job above and waiting
		# on the job server for a job. 142 below will recheck for "this"
		# job on timeout.
		mg_job="$({
			${timeout} \
			    dd if="${JOB_PIPE_R}" bs=1 count=1 2>"${dd_stderr}"
		})"
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
	AM_TESTS_FD_STDERR|\
	MAKEFLAGS|\
	CCACHE*|\
	PATH|\
	PWD|\
	TIMEOUT|\
	KEEP_OLD_PACKAGES_COUNT|KEEP_LOGS_COUNT|LOGCLEAN_WAIT|\
	PARALLEL_JOBS|\
	TEST_NUMS|ASSERT_CONTINUE|TEST_CONTEXTS_PARALLEL|\
	URL_BASE|\
	PVERBOSE|VERBOSE|\
	SH_DISABLE_VFORK|TIMESTAMP|TIMESTAMP_FLAGS|TRUSS|TIMEOUT_BIN|\
	TIMEOUT_KILL_TIMEOUT|TIMEOUT_TRUSS_MULTIPLIER|TIMEOUT_KILL_SIGNAL|\
	TIMEOUT_SAN_MULTIPLIER|TIMEOUT_SH_MULTIPLIER|\
	HTML_JSON_UPDATE_INTERVAL|\
	TESTS_SKIP_BUILD|\
	TESTS_SKIP_LONG|\
	TESTS_SKIP_BULK|\
	TMPDIR|\
	MALLOC_CONF|\
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
: "${LOGCLEAN_WAIT:=5}"
export LOGCLEAN_WAIT

case "${TEST##*/}" in
prep.sh) : "${DEF_TIMEOUT:=250}" ;;
*-build-quick*.sh) : "${DEF_TIMEOUT:=120}" ;;
bulk*build*.sh|testport*build*.sh) : "${DEF_TIMEOUT:=400}" ;;
critical_section_inherit.sh) : "${DEF_TIMEOUT:=20}" ;;
shellcheck.sh) : "${DEF_TIMEOUT:=90}" ;;
esac
: "${DEF_TIMEOUT:=60}"
case "${TEST##*/}" in
bulk*.sh|testport*.sh|distclean*.sh|options*.sh)
	# Bump anything touching logclean
	DEF_TIMEOUT="$((DEF_TIMEOUT + (LOGCLEAN_WAIT * 1)))"
	;;
esac
case "${TEST##*/}" in
*-build-quick*.sh) ;;
bulk*.sh|testport*.sh|distclean*.sh|options*.sh)
	# The heavy load of bulk asserts need some extra time.
	: "${BULK_EXTRA_TIME:=30}"
	DEF_TIMEOUT="$((DEF_TIMEOUT + BULK_EXTRA_TIME))"
	;;
esac
# Multiply on incremental builds
case "${TEST##*/}" in
*-inc-*.sh)
	: "${BULK_INCREMENTAL_MULTIPLIER:=2}"
	DEF_TIMEOUT="$((DEF_TIMEOUT * BULK_INCREMENTAL_MULTIPLIER))"
	;;
esac
# Boost by the sanitizer multiplier depending on build in Makefile.am
: "${TIMEOUT_SAN_MULTIPLIER:=1}"
DEF_TIMEOUT="$((DEF_TIMEOUT * TIMEOUT_SAN_MULTIPLIER))"
: "${TIMEOUT_KILL_TIMEOUT=30}"
: "${TIMEOUT_TRUSS_MULTIPLIER:=6}"
case "${TRUSS-}" in
"")
	;;
*)
	DEF_TIMEOUT="$((DEF_TIMEOUT * TIMEOUT_TRUSS_MULTIPLIER))"
	TIMEOUT_KILL_TIMEOUT="${TIMEOUT_KILL_TIMEOUT:-$((TIMEOUT_KILL_TIMEOUT * TIMEOUT_TRUSS_MULTIPLIER))}"
	;;
esac
TIMEOUT_KILL="${TIMEOUT_KILL_TIMEOUT:+-k ${TIMEOUT_KILL_TIMEOUT}}"
: "${TIMEOUT_KILL_SIGNAL:=SIGTERM}"
TIMEOUT_KILL="${TIMEOUT_KILL:+${TIMEOUT_KILL} }${TIMEOUT_KILL_SIGNAL:+-s ${TIMEOUT_KILL_SIGNAL} }"
case "${SH}" in
/bin/sh)
	# It's about 4.6 times slower.
	: "${TIMEOUT_SH_MULTIPLIER:=6}"
	DEF_TIMEOUT="$((DEF_TIMEOUT * TIMEOUT_SH_MULTIPLIER))"
	;;
esac
: "${TIMEOUT:=${DEF_TIMEOUT:?}}"
if [ -n "${TESTS_SKIP_BUILD-}" ]; then
	case "${TEST##*/}" in
	*-build-quick*.sh) ;;
	*-build*)
		exit 77
		;;
	esac
fi
if [ -n "${TESTS_SKIP_LONG-}" ]; then
	case "${TEST##*/}" in
	*build*-inc-*.sh|bulk-flavor-ignore-all.sh|bulk-overlay-all.sh)
		exit 77
		;;
	esac
fi
if [ -n "${TESTS_SKIP_BULK-}" ]; then
	case "${TEST##*/}" in
	*-build-quick*.sh) ;;
	testport-*.sh|bulk-*.sh)
		exit 77
		;;
	esac
fi

# TIMESTAMP_FLAGS="-s us -t"
: "${TIMESTAMP_FLAGS:=-t}"
: "${TIMESTAMP=${LIBEXECPREFIX}/timestamp ${TIMESTAMP_FLAGS} -1stdout: -2stderr:}"

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
	set -x
	case "${TRUSS-}" in
	"") ;;
	*)
		# With truss use --foreground to prevent process reaper and
		# ptrace deadlocking.
		TIMEOUT_FOREGROUND="--foreground"
		;;
	esac
	setproctitle "poudriere runtest: $(get_log_name)"
	{
		TEST_START="$(clock -monotonic)"
		echo "Test started: $(date)"
		# hide set -x
	} >&2 2>/dev/null
	case "${AM_TESTS_FD_STDERR}" in
	4) ;;
	*)
		echo "runtest: Expected ${AM_TESTS_FD_STDERR} == 4" >&2
		exit 99
		;;
	esac
	lockf -T -t 0 -k "$(get_log_name).lock" \
	    ${TIMEOUT_BIN:?} -v ${TIMEOUT_FOREGROUND} ${TIMEOUT_KILL} ${TIMEOUT} \
	    ${TIMESTAMP} \
	    env \
	    ${SH_DISABLE_VFORK:+SH_DISABLE_VFORK=1} \
	    THISDIR="${THISDIR}" \
	    SH="${SH}" \
	    ${TRUSS:+truss -ae -f -s256 -o "$(get_log_name).truss"} \
	    "${SH}" "${TEST}" 4>&- || ret="$?"
	{
		# "Error: (pid) cmd" is an sh command error.
		# "Error: [pid] ..." is err().
		if [ "${ret}" -eq 0 ]; then
			case "${TEST##*/}" in
			bulk-bad-dep-pkgname.sh|\
			bulk-build-*crashed-builder*.sh|\
			bulk-build-specific-bad-flavor.sh|\
			bulk-flavor-nonexistent.sh|\
			bulk-flavor-specific-dep-and-specific-listed-nonexistent.sh|\
			bulk-flavor-specific-dep-nonexistent.sh|\
			distclean-badorigin.sh|\
			err_catch.sh|\
			err_catch_framework.sh|\
			logging.sh|\
			options-badorigin.sh|\
			testport-all-flavors-failure.sh|\
			testport-build-porttesting.sh|\
			testport-default-all-flavors-failure.sh|\
			testport-specific-bad-flavor-failure.sh|\
			"END") ;;
			*)
				echo -n "Checking for unhandled errors... "
				if egrep \
				    ' Error: ' \
				    "$(get_log_name)" |
				    sed -e 's,Error:,UnhandledError:,' |
				    grep -v 'Build failed' |
				    grep -v 'sleep:.*about.*second' |
				    grep -v 'Another logclean is busy'; then
					ret=99
					echo "UNHANDLED ERROR DETECTED"
				else
					echo " done"
				fi
				;;
			esac
		fi
		TEST_END="$(clock -monotonic)"
		echo "Test ended: $(date) -- duration: $((TEST_END - TEST_START))s"
		echo "Log: $(get_log_name)"
		echo "Test: ${TEST}"
		case "${TRUSS:+set}" in
		set)
			echo "Truss: $(get_log_name).truss"
			;;
		esac
		times
		# hide set -x
	} >&2 2>/dev/null
	case "${make_job:+set}" in
	set)
		make_returnjob "${make_job}"
		;;
	esac
	return "${ret}"
}

_wait() {
	[ "$#" -ge 0 ] || eargs _wait '[%job|pid...]'
	local wret ret pid

	if [ "$#" -eq 0 ]; then
		return 0
	fi

	ret=0
	for pid in "$@"; do
		while :; do
			wret=0
			wait "${pid}" || wret="$?"
			case "${wret}" in
			157) # SIGINFO [EINTR]
				continue
				;;
			0) ;;
			*) ret="${wret}" ;;
			esac
			# msg_dev "Job ${pid} collected ret=${wret}"
			break
		done
	done

	return "${ret}"
}

case "$(type pwait)" in
"pwait is a shell builtin")
	PWAIT_BUILTIN=1
	;;
esac
# Wrapper to fix SIGINFO [EINTR], -t 0, and assert on errors.
pwait() {
	[ "$#" -ge 1 ] || eargs pwait '[pwait flags]' pids
	local OPTIND=1 flag
	local ret oflag tflag timeout time_start now vflag

	tflag=
	while getopts "ot:v" flag; do
		case "${flag}" in
		o) oflag=1 ;;
		t) tflag="${OPTARG}" ;;
		v) vflag=1 ;;
		*) err 1 "pwait: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))

	[ "$#" -ge 1 ] || eargs pwait '[pwait flags]' pids
	case "${tflag}" in
	0) tflag="0.00001" ;;
	esac
	case "${tflag}" in
	"") ;;
	*.*) timeout="${tflag}" ;;
	*) time_start="$(clock -monotonic)" ;;
	esac
	while :; do
		# Adjust timeout
		case "${tflag}" in
		""|*.*) ;;
		*)
			now="$(clock -monotonic)"
			timeout="$((tflag - (now - time_start)))"
			case "${timeout}" in
			"-"*) timeout=0 ;;
			esac
			;;
		esac
		ret=0
		command pwait \
		    ${tflag:+-t "${timeout}"} \
		    ${vflag:+-v} ${oflag:+-o} \
		    "$@" || ret="$?"
		case "${ret}" in
		# Read again on SIGINFO interrupts
		157) continue ;;
		esac
		break
	done
	case "${ret}" in
	124|0) return "${ret}" ;;
	esac
	err "${EX_SOFTWARE:-70}" "pwait: timeout=${timeout} pids=${pids} ret=${ret}"
}

collectpids() {
	local timeout="$1"
	local pids_copy tries max
	local now start

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
	until [ -z "${pids:+set}" ] || [ "${tries}" -eq "${max}" ]; do
		if [ "${gotinfo}" -eq 1 ]; then
			echo "+ Waiting on pids: ${pids} timeout: ${timeout}" >&2
			gotinfo=0
		fi
		pwait -o -t "${timeout}" ${pids} >/dev/null 2>&1 || :
		pids_copy="${pids}"
		pids=
		now="$(clock -monotonic)"
		for pid in ${pids_copy}; do
			# checkzombies() needed for poudriere sh
			jobs >/dev/null
			if kill -0 "${pid}" 2>/dev/null; then
				pids="${pids:+${pids} }${pid}"
				continue
			fi
			getvar "pid_num_${pid}" pid_test_context_num
			pret=0
			_wait "${pid}" || pret="$?"
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
			getvar "pid_test_start_${pid}" start
			printf \
			    "%s TEST_NUM=%2d pid=%-5d %4ds exited %-3d - %s: %s\n" \
			    "${exit_type}" \
			    "${pid_test_context_num}" \
			    "${pid}" \
			    "$((now - start))" \
			    "${pret}" \
			    "$(TEST_CONTEXT_NUM="${pid_test_context_num}" get_log_name)" \
			    "${result}"
			JOBS="$((JOBS - 1))"
			TEST_CONTEXTS_FINISHED="$((TEST_CONTEXTS_FINISHED + 1))"
			set_job_title
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
	set +m

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

if ! type setproctitle >/dev/null 2>&1; then
setproctitle() {
	:
}
fi

if ! type getvar >/dev/null 2>&1; then
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
fi

if ! type getpid >/dev/null 2>&1; then
getpid() {
	sh -c 'echo $PPID'
}
fi

raise() {
	local sig="$1"

	kill -"${sig}" "$(getpid)"
}

setreturnstatus() {
	[ $# -eq 1 ] || eargs setreturnstatus ret
	local ret="$1"

	# This case is because the callers cannot do any conditional checks.
	case "${ret-}" in
	[0-9]*) return "${ret}" ;;
	esac
	return 0
}

# Need to cleanup some stuff before calling traps.
_trap_pre_handler() {
	_ERET="$?"
	unset IFS
	set +u
	set +e
	trap '' PIPE INT INFO HUP TERM
	return "${_ERET}"
}
# {} is used to avoid set -x SIGPIPE
alias trap_pre_handler='{ _trap_pre_handler; } 2>/dev/null'
setup_traps() {
	[ "$#" -eq 0 ] || [ "$#" -eq 1 ] || eargs setup_traps '[exit_handler]'
	local exit_handler="${1-}"
	local sig

	for sig in INT HUP PIPE TERM; do
		trap "trap_pre_handler; sig_handler ${sig}${exit_handler:+ \"${exit_handler}\"}" "${sig}"
	done
	case "${exit_handler:+set}" in
	set)
		trap "trap_pre_handler; ${exit_handler}" EXIT
		;;
	esac
	gotinfo=0
	trap 'siginfo_handler' INFO
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
	local -; set +e
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
	done >&${AM_TESTS_FD_STDERR:-2}
	gotinfo=1
}

sig_handler() {
	local sig="$1"
	local exit_handler="${2-}"
	local ret

	trap - EXIT
	ret="${sig_ret}"
	case "${exit_handler:+set}" in
	set)
		local sig_ret

		case "${sig}" in
		TERM) sig_ret=$((128 + 15)) ;;
		INT)  sig_ret=$((128 + 2)) ;;
		HUP)  sig_ret=$((128 + 1)) ;;
		PIPE) sig_ret=$((128 + 13)) ;;
		*)    sig_ret= ;;
		esac
		sig_ret="$(($(kill -l "${sig}") + 128))"
		# Ensure the handler sees the real status
		# Don't wrap around if/case/etc.
		setreturnstatus "${sig_ret-}"
		"${exit_handler}" || ret="$?"
		;;
	esac
	trap - "${sig}"
	# A handler may have changed the status, but if not raise.
	if [ "${ret}" -gt 128 ]; then
		raise "$(kill -l "${ret}")"
	else
		exit "${ret}"
	fi
}

set_job_title() {
	setproctitle "poudriere runtest jobd tests=${TEST_CONTEXTS_FINISHED}/${TEST_CONTEXTS_TOTAL} jobs=${JOBS} elapsed=$(($(clock -monotonic) - TEST_SUITE_START)): $(TEST_CONTEXT_NUM= get_log_name)"
}

# This is only used if not using make jobserver from ${MAKEFLAGS}
: ${TEST_CONTEXTS_PARALLEL:=4}
TEST_CONTEXTS_FINISHED=0
TEST_SUITE_START="$(clock -monotonic)"

if [ "${TEST_CONTEXTS_PARALLEL}" -gt 1 ] &&
    egrep -q '(get_test_context|run_test_functions)' "${TEST}"; then
	{
		echo "Test suite started: $(date)"
		# hide set -x
	} >&2 2>/dev/null
	cleanup() {
		local ret="$?"
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
		exit "${ret}"
	}
	setup_traps cleanup
	exec 9>/dev/null
	for fd in 9 2; do
		ret=0
		TEST_CONTEXTS_TOTAL="$(env \
		    TEST_CONTEXTS_NUM_CHECK=yes \
		    THISDIR="${THISDIR}" \
		    SH="${SH}" \
		    VERBOSE=0 \
		    "${SH}" "${TEST}" 2>&"${fd}")" || ret="$?"
		case "${ret}" in
		77) exit 77 ;;
		esac
	done
	exec 9>&-
	case "${TEST_CONTEXTS_TOTAL}" in
	[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]) ;;
	*)
		echo "TEST_CONTEXTS_TOTAL is bogus value '${TEST_CONTEXTS_TOTAL}'" >&2
		exit 99
		;;
	esac
	JOBS=0
	set_job_title
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
			printf "Logging %s with TEST_NUM=%${num_width}d/%${num_width}d to %s\n" \
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
			set_job_title
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

setup_traps
trap 'siginfo_handler' INFO
pids="$$"
setvar "pid_test_start_$$" "$(clock -monotonic)"
setvar "pid_test_$$" "$(format_siginfo "this" "${TEST}" "1" "1" "$(get_log_name)")"
set -T
runtest
