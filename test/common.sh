echo "getpid: $$" >&2

_test_framework_err() {
	set +e +u +x
	case "${TEST_OVERRIDE_ERR:-1}" in
	0)
		_err "$@"
		return
		;;
	esac
	local lineinfo="${1}"
	local status="${2-1}"
	shift 2
	case "${ERRORS_ARE_FATAL:-1}" in
	1)
		echo "Test Framework Error: ${lineinfo:+${lineinfo}:}$*" |
		    tee "${ERR_CHECK}" >&${REDIRECTED_STDERR_FD:-2}
		case "${TEST_HARD_ERROR:-1}" in
		1) exit "99" ;;
		# Aliasing and subshells can end up here via catch_err()
		*) exit "${status}" ;;
		esac
		;;
	esac
	CAUGHT_ERR_STATUS="${status}"
	CAUGHT_ERR_MSG="$*"
	return "${status}"
}
if ! type err >/dev/null 2>&1; then
	# This function may be called in "$@" contexts that do not use eval.
	# eval is used here to avoid existing alias parsing issues.
	eval 'err() { _test_framework_err "" "$@"; }'
	alias err='_test_framework_err "${lineinfo-$0}:${LINEINFOSTACK:+${LINEINFOSTACK}:}${FUNCNAME:+${FUNCNAME}:}${LINENO}" '
fi

# Duplicated from src/share/poudriere/util.sh because it is too early to
# include that file.
write_atomic_cmp() {
	local dest="$1"
	local tmp ret

	ret=0
	tmp="$(TMPDIR="${dest%/*}" mktemp -t ${dest##*/})" ||
		err $? "write_atomic_cmp unable to create tmpfile in ${dest%/*}"
	cat > "${tmp}" || ret=$?
	if [ "${ret}" -ne 0 ]; then
		rm -f "${tmp}"
		return "${ret}"
	fi

	if ! cmp -s "${dest}" "${tmp}"; then
		rename "${tmp}" "${dest}"
	else
		unlink "${tmp}"
	fi
}

CMD="${0##*/}"
IN_TEST=1
USE_DEBUG=yes
SCRIPTPATH="${SCRIPTPREFIX}/${CMD}"
: ${SCRIPTNAME:=runtest.sh}
: ${BASEFS:=/var/tmp/poudriere/test}
POUDRIERE_ETC="${BASEFS}/etc"
: ${HTML_JSON_UPDATE_INTERVAL:=15}

if [ ${_DID_TMPDIR:-0} -eq 0 ]; then
	# Some tests will assert that TMPDIR is empty on exit
	if [ "${TMPDIR%%/poudriere/test/*}" = "${TMPDIR}" ]; then
		: ${TMPDIR:=/tmp}
		TMPDIR=${TMPDIR:+${TMPDIR}}/poudriere/test
	fi
	mkdir -p ${TMPDIR}
	: ${DISTFILES_CACHE:="${TMPDIR}/distfiles"}
	mkdir -p "${DISTFILES_CACHE}"
	export TMPDIR
	TMPDIR=$(mktemp -d)
	export TMPDIR
	# This file may be included again
	_DID_TMPDIR=1
	POUDRIERE_TMPDIR="${TMPDIR}"
	cd "${POUDRIERE_TMPDIR}"
	echo "TMPDIR: ${POUDRIERE_TMPDIR}" >&2
fi
ERR_CHECK="$(mktemp -ut err)"

mkdir -p ${POUDRIERE_ETC}/poudriere.d ${POUDRIERE_ETC}/run
rm -f "${POUDRIERE_ETC}/poudriere.conf"
write_atomic_cmp "${POUDRIERE_ETC}/poudriere.d/poudriere.conf" << EOF
NO_ZFS=yes
BASEFS=${BASEFS}
DISTFILES_CACHE=${DISTFILES_CACHE:?}
USE_TMPFS=all
USE_PROCFS=no
USE_FDESCFS=no
NOLINUX=yes
# jail -c options
NO_LIB32=yes
NO_SRC=yes
SHARED_LOCK_DIR="${POUDRIERE_ETC}/run"
IMMUTABLE_BASE=nullfs
HTML_JSON_UPDATE_INTERVAL=${HTML_JSON_UPDATE_INTERVAL:?}
${URL_BASE:+URL_BASE="${URL_BASE}"}
$(env | grep -q 'CCACHE_STATIC_PREFIX' && { env | awk '/^CCACHE/ {print "export " $0}'; } || :)
EOF
write_atomic_cmp "${POUDRIERE_ETC}/poudriere.d/make.conf" << EOF
# For tests
PKG_NOCOMPRESS=		t
PKG_COMPRESSION_FORMAT=	tar

# For using embedded ports tree
DEFAULT_VERSIONS+=	ssl=base
ALLOW_UNSUPPORTED_SYSTEM=yes
lang_python39_UNSET=	LIBMPDEC
WARNING_WAIT=		0
DEV_WARNING_WAIT=	0
EOF

: ${VERBOSE:=${PVERBOSE:-1}}
: ${PARALLEL_JOBS:=2}

msg() {
	echo "$@"
}

msg_debug() {
	if [ ${VERBOSE} -le 1 ]; then
		msg_debug() { :; }
		return 0
	fi
	msg "[DEBUG] $@" >&${REDIRECTED_STDERR_FD:-2}
}

msg_warn() {
	msg "[WARN] $@" >&${REDIRECTED_STDERR_FD:-2}
}

msg_dev() {
	if [ ${VERBOSE} -le 2 ]; then
		msg_dev() { :; }
		return 0
	fi
	msg "[DEV] $@" >&${REDIRECTED_STDERR_FD:-2}
}

msg_assert() {
	msg "$@"
}

rm() {
	local arg

	for arg in "$@"; do
		case "${arg}" in
		/) err 99 "Tried to rm /" ;;
		/COPYRIGHT|/bin) err 99 "Tried to rm /*" ;;
		esac
	done

	command rm "$@"
}

sorted() {
	if [ "$#" -eq 0 ]; then
		return 0
	fi
	echo "$@" | tr ' ' '\n' | LC_ALL=C sort -u | sed -e '/^$/d' |
	    paste -s -d ' ' -
}

catch_err() {
	#local ERRORS_ARE_FATAL CRASHED
	local TEST_HARD_ERROR
	local ret -

	#ERRORS_ARE_FATAL=0
	TEST_HARD_ERROR=0
	set +e
	( set -e; "$@" )
	ret="$?"
	case "${ret}" in
	0)
		# Be sure an err wasn't called
		;;
	esac
	case "${ret}" in
	0)
		unset CAUGHT_ERR_MSG CAUGHT_ERR_STATUS
		;;
	*)
		CAUGHT_ERR_STATUS="${ret}"
		case "${TEST_OVERRIDE_ERR:-1}" in
		1)
			read_file CAUGHT_ERR_MSG "${ERR_CHECK}" ||
			    err "${EX_SOFTWARE}" "catch_err: Failed to read ${ERR_CHECK}"
			unlink "${ERR_CHECK}"
			ERR_CHECK="$(mktemp -ut err)"
			;;
		*)
			CAUGHT_ERR_MSG="core error"
			;;
		esac
		;;
	esac
	return "${ret}"
}

capture_output_simple() {
	local my_stdout_return="$1"
	local my_stderr_return="$2"
	local _my_stdout _my_stdout_log
	local _my_stderr _my_stderr_log
	local -

	if [ -n "${REDIRECTED_STDERR_FD-}" ]; then
		err 99 "capture_output_simple called nested"
	fi

	case "${my_stdout_return:+set}" in
	set)
		_my_stdout=$(mktemp -ut stdout.pipe)
		_my_stdout_log=$(mktemp -ut stdout)
		echo "Capture stdout logs to ${_my_stdout_log}" >&2
		exec 6>&1
		mkfifo "${_my_stdout}"
		set -m
		_spawn_wrapper tee "${_my_stdout_log}" >&6 < "${_my_stdout}" &
		get_job_id "$!" my_stdout_job
		set +m
		exec > "${_my_stdout}"
		unlink "${_my_stdout}"
		setvar "${my_stdout_return}" "${_my_stdout_log}"
		;;
	*)
		unset _my_stdout _my_stdout_log
		;;
	esac
	case "${my_stderr_return:+set}" in
	set)
		_my_stderr=$(mktemp -ut stderr.pipe)
		_my_stderr_log=$(mktemp -ut stderr)
		echo "Capture stderr logs to ${_my_stderr_log}" >&2
		exec 7>&2
		REDIRECTED_STDERR_FD=7
		mkfifo "${_my_stderr}"
		set -m
		_spawn_wrapper tee "${_my_stderr_log}" >&7 < "${_my_stderr}" &
		get_job_id "$!" my_stderr_job
		set +m
		exec 2> "${_my_stderr}"
		unlink "${_my_stderr}"
		setvar "${my_stderr_return}" "${_my_stderr_log}"
		;;
	*)
		unset _my_stderr _my_stderr_log
		;;
	esac
}

capture_output_simple_stop() {
	if [ -z "${REDIRECTED_STDERR_FD-}" ]; then
		return
	fi
	unset REDIRECTED_STDERR_FD
	case "${my_stdout_job:+set}" in
	set)
		exec 1>&6 6>&-
		timed_wait_and_kill_job 1 "%${my_stdout_job:?}" || :
		unset my_stdout_job
		;;
	esac
	case "${my_stderr_job:+set}" in
	set)
		exec 2>&7 7>&-
		timed_wait_and_kill_job 1 "%${my_stderr_job:?}" || :
		unset my_stderr_job
		;;
	esac
}

expand_test_contexts() {
	[ "$#" -eq 1 ] || eargs expand_test_contexts test_contexts_file
	local test_contexts_file="$1"

	case "${test_contexts_file}" in
	-) unset test_contexts_file ;;
	esac
	cat ${test_contexts_file:+"${test_contexts_file}"} | awk '
	function nest(varidx, nestlevel, combostr, n, i, pvar) {
		pvar = varsd[varidx]
		if (combostr && varidx == varn && nestlevel == varn) {
			print combostr
			return
		}

		for (n = varidx + 1; n <= varn; n++) {
			for (i = 0; i < combocount[pvar]; i++) {
				nest(n, nestlevel + 1, combostr ? (combostr " " combos[pvar, i]) : combos[pvar, i])
			}
		}
	}
	BEGIN {
		varn = 0
	}
	/^#/ { next }
	{
		var = $1
		varsd[varn] = var
		varn++
		combosidx = 0
		for (i = 2; i <= NF; i++) {
			if ($i ~ /^".*"$/) {
				value = substr($i, 2, length($i) - 2)
			} else if ($i ~ /^"/) {
				value = substr($i, 2, length($i) - 1)
				while (i != NF) {
					i++
					if ($i ~ /"$/) {
						value = value FS substr($i, 1,
						    length($i) - 1)
						    break
					} else {
						value = value FS $i
					}
				}
			} else {
				value = $i
			}
			combos[var, combosidx] = sprintf("%s=\"%s\";", var, value)
			combosidx++
		}
		combocount[var] = combosidx
	}
	END {
		nest(0, 0)
	}
	'
}

# set_test_contexts setup_str teardown_str <<env matrix
set_test_contexts() {
	[ "$#" -eq 3 ] || eargs set_test_contexts env_file setup_str teardown_str
	TEST_CONTEXTS="${1}"
	TEST_SETUP="${2}"
	TEST_TEARDOWN="${3}"
	local func_var func

	case "${TEST_CONTEXTS}" in
	-)
		TEST_CONTEXTS="$(mktemp -ut test_contexts)"
		expand_test_contexts - > "${TEST_CONTEXTS}" ||
		    err "${EX_DATAERR}" "Failed to expand test contexts"
		if [ ! -s "${TEST_CONTEXTS}" ]; then
			# If somehow no data is expanded we need at least 1
			# test case.
			echo ":" > "${TEST_CONTEXTS}"
		fi
		;;
	*)
		if [ ! -r "${TEST_CONTEXTS}" ]; then
			err "${EX_USAGE}" "set_test_contexts: test_context file unreadable: ${TEST_CONTEXTS}"
		fi
		;;
	esac
	for func_var in TEST_SETUP TEST_TEARDOWN; do
		getvar "${func_var}" func || func=
		case "${func:+set}" in
		set)
			if ! type "${func}" >/dev/null 2>&1; then
				err "${EX_USAGE}" "set_test_contexts: ${func_var} '${func}' missing"
			fi
			;;
		esac

	done
	TEST_CONTEXTS_TOTAL="$(grep -v '^#' "${TEST_CONTEXTS}" | wc -l)"
	TEST_CONTEXTS_TOTAL="${TEST_CONTEXTS_TOTAL##* }"
	: ${ASSERT_CONTINUE:=0}
	case "${TEST_CONTEXTS_NUM_CHECK:+set}" in
	set)
		echo "${TEST_CONTEXTS_TOTAL}"
		_DID_ASSERTS=1
		exit 0
		;;
	esac
}

get_test_context() {
	local IFS _line
	local -

	case "${TEST_CONTEXTS-}" in
	"")
		err "${EX_USAGE}" "Must call set_test_contexts with env to set"
		;;
	esac
	unset TEST_CONTEXT
	case "${TEST_CONTEXTS_DATA+set}" in
	set)
		if [ "${TEST_CONTEXT_RAN:-0}" -eq 1 ]; then
			if [ -n "${TEST_TEARDOWN-}" ]; then
				msg "Running teardown: ${TEST_TEARDOWN}" >&${REDIRECTED_STDERR_FD:-2}
				eval ${TEST_TEARDOWN} >&${REDIRECTED_STDERR_FD:-2}
			fi
			TEST_CONTEXT_RAN=0
		fi
		;;
	*)
		case "${TEST_NUMS:+set}" in
		set)
			msg "Only testing contexts: ${TEST_NUMS}" >&${REDIRECTED_STDERR_FD:-2}
			;;
		esac
		TEST_CONTEXT_NUM=0
		msg "Opening: ${TEST_CONTEXTS}" >&${REDIRECTED_STDERR_FD:-2}
		TEST_CONTEXTS_DATA=
		TEST_CONTEXTS_LINENO=0
		while IFS= mapfile_read_loop "${TEST_CONTEXTS}" _line; do
			hash_set TEST_CONTEXTS_DATA "${TEST_CONTEXTS_LINENO}" \
			    "${_line}"
			TEST_CONTEXTS_LINENO="$((TEST_CONTEXTS_LINENO + 1))"
		done
		TEST_CONTEXTS_LINENO=0
		;;
	esac
	while :; do
		if ! hash_get TEST_CONTEXTS_DATA "${TEST_CONTEXTS_LINENO}" \
		    TEST_CONTEXT; then
			unset IFS
			unset TEST_CONTEXT
			unset TEST_CONTEXT_NUM
			unset TEST_CONTEXTS_LINENO
			TEST_CONTEXTS_DATA=
			unset TEST_CONTEXTS_TOTAL
			unset TEST_CONTEXT_PROGRESS
			unset TEST_CONTEXT_RAN
			return 1
		fi
		TEST_CONTEXTS_LINENO="$((TEST_CONTEXTS_LINENO + 1))"
		case "${TEST_CONTEXT}" in
		"#"*) continue ;;
		esac
		break
	done
	set +f
	TEST_CONTEXT_NUM=$((TEST_CONTEXT_NUM + 1))
	TEST_CONTEXT_PROGRESS="${TEST_CONTEXT_NUM}/${TEST_CONTEXTS_TOTAL}"
	case " ${TEST_NUMS-null} " in
	" null ") ;;
        *" ${TEST_CONTEXT_NUM} "*) ;;
	*) continue ;;
	esac
	msg "Testing context ${TEST_CONTEXT_PROGRESS} with ${TEST_CONTEXT}" >&${REDIRECTED_STDERR_FD:-2}
	eval ${TEST_CONTEXT}
	if [ -n "${TEST_SETUP-}" ]; then
		msg "Running setup: ${TEST_SETUP}" >&${REDIRECTED_STDERR_FD:-2}
		eval ${TEST_SETUP} >&${REDIRECTED_STDERR_FD:-2}
	fi
	TEST_CONTEXT_RAN=1
}

cleanup() {
	ret="$?"
	msg "Cleaning up" >&"${REDIRECTED_STDERR_FD:-2}"
	capture_output_simple_stop
	parallel_shutdown || :
	if [ "${ret}" -ne 0 ] && [ -n "${LOG_START_LASTFILE-}" ] &&
	    [ -s "${LOG_START_LASTFILE}" ]; then
		echo "Log captured data not seen:" >&2
		cat "${LOG_START_LASTFILE}" >&2
	fi
	case "${TEST_CONTEXTS:+set}" in
	set)
		rm -f "${TEST_CONTEXTS}"
		;;
	esac
	case "${OVERLAYSDIR:+set}" in
	set)
		rm -f "${OVERLAYSDIR}"
		;;
	esac
	if type test_cleanup >/dev/null 2>&1; then
		test_cleanup
	fi
	# Avoid recursively cleaning up here
	trap - EXIT
	trap '' PIPE INT INFO HUP TERM
	msg_dev "cleanup($1)" >&2
	case $(jobs) in
	"") ;;
	*)
		jobs -l >&2
		echo "Jobs are still running!" >&1
		EXITVAL=$((EXITVAL + 1))
		;;
	esac
	kill_all_jobs 20
	if [ ${_DID_TMPDIR:-0} -eq 1 ] && \
	    [ "${TMPDIR%%/poudriere/test/*}" != "${TMPDIR}" ]; then
		if [ -d "${TMPDIR}" ] && ! dirempty "${TMPDIR}"; then
			echo "${TMPDIR} was not empty on exit!" >&2
			find "${TMPDIR}" -ls >&2
			case "${EXITVAL:-0}" in
			0) ret=1 ;;
			esac
			if [ -e "${ERR_CHECK-}" ]; then
				cat "${ERR_CHECK}" >&2
			fi
		else
			rm -rf "${TMPDIR}"
		fi
	fi
	msg_dev "exit()" >&2
	case "${BOOTSTRAP_ONLY:-0}" in
	0)
		case "${_DID_ASSERTS:-0}" in
		1) ;;
		*)
			echo "Error: Failed to run any asserts?!" >&2
			EXITVAL=1
			;;
		esac
		;;
	esac
	if [ "${EXITVAL:-0}" -gt 1 ]; then
		echo "${EXITVAL} failures detected!" >&2
	fi
	case "${ret}" in
	0) ret="${EXITVAL:-0}" ;;
	esac
	echo "Exiting with status: ${ret}" >&2
	case "${TEST_NUMS:+set}" in
	set)
		# Mimic build-aux/test-driver for TEST_CONTEXTS_PARALLEL
		case "${ret}" in
		0) res="PASS" ;;
		77) res="SKIP" ;;
		99) res="ERROR" ;;
		*) res="FAIL" ;;
		esac
		echo "${res} ${SCRIPTNAME} TEST_NUMS=${TEST_NUMS} (exit status: ${ret})" >&2
	esac
	return "${ret}"
}

. ${SCRIPTPREFIX}/common.sh
post_getopts

setup_traps cleanup

msg_debug "getpid: $$"

if [ -r "${abs_top_srcdir}/.git" ] &&
    git_get_hash_and_dirty "${abs_top_srcdir}" git_hash git_dirty; then
	msg "Source git hash: ${git_hash} modified: ${git_dirty}"
fi >&2
