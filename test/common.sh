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
		echo "Test FrameworkError: ${lineinfo:+${lineinfo}:}$*" |
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
local_write_atomic_cmp() {
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

generate_data() {
	ps uaxwd | egrep -v '(grep|Error)'
}

CMD="${0##*/}"
IN_TEST=1
USE_DEBUG=yes
SCRIPTPATH="${SCRIPTPREFIX}/${CMD}"
: ${SCRIPTNAME:=runtest.sh}
: "${BASEFS:="/var/tmp/poudriere/test/worktrees/${am_abs_top_srcdir:?}"}"
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
local_write_atomic_cmp "${POUDRIERE_ETC}/poudriere.d/poudriere.conf" << EOF
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
: "\${IMMUTABLE_BASE:=nullfs}"
HTML_JSON_UPDATE_INTERVAL=${HTML_JSON_UPDATE_INTERVAL:?}
${URL_BASE:+URL_BASE="${URL_BASE}"}
$(env | grep -q 'CCACHE_STATIC_PREFIX' && { env | awk '/^CCACHE/ {print "export " $0}'; } || :)
EOF
local_write_atomic_cmp "${POUDRIERE_ETC}/poudriere.d/make.conf" << EOF
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

FORCE_COLORS=1
. ${SCRIPTPREFIX}/common.sh
post_getopts

sorted() {
	if [ "$#" -eq 0 ]; then
		return 0
	fi
	echo "$@" | tr ' ' '\n' | LC_ALL=C sort -u | sed -e '/^$/d' |
	    paste -s -d ' ' -
}

catch_err() {
	expect_error_on_stderr _catch_err "$@"
}
_catch_err() {
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
			CAUGHT_ERR_MSG="$(cat "${ERR_CHECK}")"
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

wait_for_file() {
	local maxtime_orig="$1"
	local file="$2"
	local timeout dir start

	dirname "${file:?}" dir
	timeout="${maxtime_orig:?}"
	case "${maxtime_orig}" in
	0) unset maxtime_orig ;;
	*) start="$(clock -monotonic)" ;;
	esac
	until [ -e "${file:?}" ]; do
		${maxtime_orig:+timeout "${timeout}"} \
		    dirwatch -n "${dir:?}" ||
		    return
		case "${maxtime_orig:+set}" in
		set)
			if ! adjust_timeout "${maxtime_orig:?}" "${start-}" \
			    timeout; then
				msg_error "wait_for_file: Timeout" \
				    "waiting for ${file:?}"
				return 124
			fi
			;;
		esac
		sleep "0.$(randint 20)"
	done
}

: "${READY_FILE:=condchan}"
cond_timedwait() {
	local maxtime_orig="$1"
	local which="${2-}"
	local reason="${3-}"
	local timeout file dir ret got_reason time_start

	timeout="${maxtime_orig:?}"
	case "${maxtime_orig}" in
	0) unset maxtime_orig ;;
	*) time_start="$(clock -monotonic)" ;;
	esac
	assert "${POUDRIERE_TMPDIR:?}" "${PWD}"
	dir="${READY_FILE:?}${which:+.${which}}"
	file="${dir:?}/cv"
	assert_true mkdir -p "${dir:?}"
	ret=0
	# dirwatch may return when the .tmpfile is written before
	# renamed to the actual file. So a 2nd attempt may be needed.
	until [ -e "${file:?}" ]; do
		${maxtime_orig:+timeout "${timeout}"} \
		    dirwatch -n "${dir:?}" ||
		    ret="$?"
		adjust_timeout "${maxtime_orig}" "${time_start-}" timeout ||
		    ret="$?"
		case "${ret}.${timeout-}" in
		124.*|0.0)
			msg_error "cond_timedwait: Timeout waiting for" \
			    "signal" \
			    "${which:+which='${which}' }" \
			    "${reason:+reason='${reason}' }"
			return "${ret}"
			;;
		0.*) ;;
		*) err 1 "cond_timedwait: dirwatch ret=${ret}" ;;
		esac
	done
	assert_true [ -e "${file:?}" ]
	read_file got_reason "${file:?}" || got_reason=
	echo "${which:+${which} }sent signal: ${got_reason}" >&2
	assert "${reason}" "${got_reason}" "READY FILE reason"
	assert_true unlink "${file:?}"
	# assert_true rmdir "${dir}"
}

cond_signal() {
	[ $# -ge 0 ] || eargs cond_signal '[-f]' '[which]' '[reason]'
	local noclobber flag OPTIND=1

	noclobber=1
	while getopts "f" flag; do
		case "${flag}" in
		f) noclobber= ;;
		*) err "${EX_USAGE:-64}" "cond_signal: Invalid flag" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -ge 0 ] || eargs cond_signal '[-f]' '[which]' '[reason]'
	local which="${1-}"
	local reason="${2-}"
	local file dir

	assert "${POUDRIERE_TMPDIR:?}" "${PWD}"
	dir="${READY_FILE:?}${which:+.${which}}"
	# Store as a single file in a dedicated directory so dirwatch
	# can wakeup on it.
	assert_true mkdir -p "${dir:?}"
	file="${dir:?}/cv"
	case "${reason:+set}" in
	set)
		# Likely noclobber failure if this fails.
		# Using 'noclobber' to make log clearer.
		assert_true ${noclobber:+noclobber} \
		    write_atomic "${file:?}" "${reason}"
		;;
	*)
		local -

		case "${noclobber:+set}" in
		set)
			set -C # noclobber
			;;
		esac
		: > "${file:?}" || return
		;;
	esac
}

time_bounded_loop() {
	[ $# -eq 2 ] || eargs time_bounded_loop tmpvar timeout
	local tbl_tmpvar="$1"
	local tbl_timeout_orig="$2"
	local tbl_idx tbl_start tbl_now tbl_timeout

	getvar "${tbl_tmpvar:?}" tbl_idx || unset tbl_idx
	case "${tbl_idx:+set}" in
	set)
		hash_get tbl_start "${tbl_idx}" tbl_start ||
		    err 1 "time_bounded_loop: hash_get tbl_start"
		hash_get tbl_timeout "${tbl_idx}" tbl_timeout ||
		    err 1 "time_bounded_loop: hash_get tbl_timeout"
		;;
	*)
		tbl_idx="$(randint 10000000)"
		setvar "${tbl_tmpvar:?}" "${tbl_idx:?}" ||
		    err 1 "time_bounded_loop: setvar ${tbl_tmpvar}"
		tbl_start="$(clock -monotonic)"
		hash_set tbl_start "${tbl_idx}" "${tbl_start}"
		;;
	esac

	if ! adjust_timeout "${tbl_timeout_orig:?}" "${tbl_start:?}" \
	    tbl_timeout; then
		hash_unset tbl_timeout "${tbl_idx}"
		hash_unset tbl_start "${tbl_idx}"
		unset "${tbl_tmpvar}"
		return 124
	fi
	hash_set tbl_timeout "${tbl_idx}" "${tbl_timeout}"
}

_teer() {
	[ $# -eq 2 ] || eargs _teer tee_file stdin_fifo
	local tee_file="$1"
	local stdin_fifo="$2"

	{ tee "${tee_file:?}"; } < "${stdin_fifo:?}"
}

capture_output_simple() {
	local my_stdout_return="$1"
	local my_stderr_return="$2"
	local cmd="${3:-_teer}"
	shift 2
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
		exec 5>&1
		mkfifo "${_my_stdout}"
		spawn_job "${cmd:?}" "${_my_stdout_log}" "${_my_stdout}" >&5
		my_stdout_job="${spawn_jobid:?}"
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
		exec 6>&2
		REDIRECTED_STDERR_FD=6
		mkfifo "${_my_stderr}"
		spawn_job "${cmd:?}" "${_my_stderr_log}" "${_my_stderr}" >&6
		my_stderr_job="${spawn_jobid:?}"
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
		exec 1>&5 5>&-
		timed_wait_and_kill_job 1 "%${my_stdout_job:?}" || :
		unset my_stdout_job
		;;
	esac
	case "${my_stderr_job:+set}" in
	set)
		exec 2>&6 6>&-
		timed_wait_and_kill_job 1 "%${my_stderr_job:?}" || :
		unset my_stderr_job
		;;
	esac
}

# see test/test_contexts_expand.sh
expand_test_contexts() {
	[ "$#" -eq 1 ] || eargs expand_test_contexts test_contexts_file
	local test_contexts_file="$1"

	case "${test_contexts_file}" in
	-) unset test_contexts_file ;;
	esac
	awk '
	function printperlinesvar(group, var) {
		for (i = 0; i < values_perline_cnt[group, var]; i++) {
			printed = 0
			for (inner_group in groups) {
				# Loop on each of my values
				output = values_perline[group, var, i]
				if (have_combos[inner_group]) {
					printed = 1
					nest(inner_group, 0, 0, output)
				}
			}
			if (printed == 0) {
				print output
			}
		}
	}
	function printperlines(group) {
		for (n = 0; n < perlinesgroupsvars_cnt[group]; n++) {
			var = perlinesgroupsvars[group, n]
			printperlinesvar(group, var)
		}
	}
	function nest(group, varidx, nestlevel, combostr, n, i, pvar) {
		pvar = combovars[group, varidx]
		if (combostr && varidx == have_combos[group] &&
		    nestlevel == have_combos[group]) {
			print combostr
			return
		}
		# nest pure combos
		for (n = varidx + 1; n <= have_combos[group]; n++) {
			for (i = 0; i < combocount[group, pvar]; i++) {
				nest(group, n, nestlevel + 1,
				    combostr ? \
				    (combostr " " values_combos[group, pvar, i]) : \
				    values_combos[group, pvar, i])
			}
		}
	}
	function process_value(var, argn) {
		if ($argn ~ /^".*"$/) {
			value = substr($argn, 2, length($argn) - 2)
		} else if ($argn ~ /^"/) {
			value = substr($argn, 2, length($argn) - 1)
			while (argn != NF) {
				argn++
				if ($argn ~ /"$/) {
					value = value FS substr($argn, 1,
					    length($argn) - 1)
					    break
				} else {
					value = value FS $argn
				}
			}
		} else {
			value = $argn
		}
		result[0] = sprintf("%s=\"%s\";", var, value)
		result[1] = argn
	}
	function processline(group, var, first_arg, do_combo) {
		groups[group] = 1
		if (!varn[group]) {
			varn[group] = 0
		}
		varsd[group, varn[group]] = var
		varn[group]++
		# This _matches_ old vard/varn usage.
		allvars[allvars_cnt] = var
		allvars_cnt++
		if (do_combo) {
			if (!have_combos[group]) {
				have_combos[group] = 0
			}
			combovars[group, have_combos[group]] = var
			have_combos[group]++
			if (!values_combos_cnt[group, var]) {
				values_combos_cnt[group, var] = 0
			}
		} else {
			if (!perlinesgroupsvars_cnt[group]) {
			    perlinesgroupsvars_cnt[group] = 0
			}
			perlinesgroupsvars[group,
			    perlinesgroupsvars_cnt[group]] = var
			perlinesgroupsvars_cnt[group]++
			if (!values_perline_cnt[group, var]) {
				values_perline_cnt[group, var] = 0
			}
		}
		for (i = first_arg; i <= NF; i++) {
			process_value(var, i)
			output = result[0]
			i = result[1]
			if (do_combo) {
				values_combos[group, var,
				    values_combos_cnt[group, var]] = output
				values_combos_cnt[group, var]++
			} else {
				values_perline[group, var,
				    values_perline_cnt[group, var]] = output
				values_perline_cnt[group, var]++
			}
		}
		if (do_combo) {
			combocount[group, var] = values_combos_cnt[group, var]
		}
	}
	BEGIN {
		unique_groups = 0
		allvars_cnt = 0
	}
	/^#/ { next }
	/=.*;/ {
		# This is a pre-expanded line. Print as is.
		print
		next
	}
	# Outer loop vars; they combinatorially expand over each group.
	# These lines will never combine with another "-" line regardless of
	# trying to name it a group.
	# One level above the group expansions.
	# Like "copying" the test into another file and changing how the
	# test is ran rather than the values being tested.
	# see test_expand_everything() for clear example.
	/^-/ {
		group = $1
		var = $2
		have_perlines = 1
		processline(group, var, 3, 0)
		next
	}
	# Groups are sets that combinatorially expand.
	# All "+$groupname" lines are grouped by group named "$groupname".
	# All "+" lines will be treated as individual unique groups.
	# Using different groups can make sense if you want to logically group
	# independent test variables that do not need to expand against
	# other variables.
	# See test_expand_2_groups() for a clear example.
	/^\+/ {
		group = $1
		# If there is no group name specified then it creates a new
		# unique group.
		if (group == "+") {
			group = "+unique" unique_groups
			unique_groups++
		}
		var = $2
		processline(group, var, 3, 1)
		next
	}
	# Same as "+_default"
	{
		var = $1
		group = "_default"
		processline(group, var, 2, 1)
	}
	END {
		if (have_perlines == 0) {
			for (group in groups) {
				nest(group, 0, 0)
			}
		} else {
			for (group in groups) {
				if (!perlinesgroupsvars_cnt[group]) {
					continue
				}
				printperlines(group)
			}
		}
	}
	' ${test_contexts_file:+"${test_contexts_file}"} | sort -u
}

add_test_function() {
	[ $# -eq 1 ] || eargs add_test_context function

	TESTFUNCS="${TESTFUNCS:+${TESTFUNCS} }$1"
}

list_test_functions() {
	local func

	case "${TESTFUNCS+set}" in
	set) ;;
	*) return 0 ;;
	esac

	for func in ${TESTFUNCS}; do
		echo -n "${func} "
	done
	echo
}

_pre_test_env_compare() {
	_PRE_TEST_ENV="$(mktemp -t set)"
	_DID_ASSERTS=0
	# allow vfork
	set | { awk -F= '{print $1}'; } > "${_PRE_TEST_ENV:?}"
	_PRE_TEST_TMPFILES="$(mktemp -t tmpfile)"
	# allow vfork
	{ find "${POUDRIERE_TMPDIR:?}"; } > "${_PRE_TEST_TMPFILES:?}"
}

_post_test_env_compare() {
	local _did_asserts

	_did_asserts="${_DID_ASSERTS:-0}"
	assert_not 0 "${_DID_ASSERTS:?}" "Test ran no asserts?"
	clean_allowed_tmpfiles
	assert_file "${_PRE_TEST_TMPFILES:?}" - "leaked tmpfiles" <<-EOF
	$(find "${POUDRIERE_TMPDIR:?}")
	EOF
	unset _PRE_TEST_TMPFILES
	assert_file "${_PRE_TEST_ENV:?}" - "leaked locals" <<-EOF
	$({
		set | awk -F= '{print $1}' | while read varname; do
			case "${varname:?}" in
			_PRE_TEST_ENV) ;;
			_did_asserts|_PRE_TEST_*) continue ;;
			esac
			echo "${varname:?}"
		done
	})
	EOF
	unset _PRE_TEST_ENV
	_DID_ASSERTS="${_did_asserts:?}"
	unset _PRE_TEST_DID_ASSERTS
}

_test_env_allowed_leaked_vars() {
	echo spawn_jobid spawn_job spawn_pgid spawn_pid
	echo FUNCNAME
	echo CAUGHT_ERR_STATUS CAUGHT_ERR_MSG
	echo TMP TMP1 TMP2 TMP3 TMPD TMPD2 TMPD3
	echo MAX
	echo _mapfile_cat_file_lines_read _mapfile_cat_lines_read
	echo _read_file_lines_read
	echo _readlines_lines_read
	echo _relpath_common _relpath_common_dir1 _relpath_common_dir2
	echo _gsub
	echo _crit_caught_HUP _crit_caught_INT \
	    _crit_caught_TERM _crit_caught_PIPE \
	    _crit_caught_INFO \
	    _CRITSNEST
}

# Hide some common test environment that is okay to leak.
_run_test_function() {
	local allowed_leaked_vars
	local -

	allowed_leaked_vars="$(_test_env_allowed_leaked_vars)"
	set -o noglob
	local ${allowed_leaked_vars}
	set +o noglob

	FUNCNAME="" "$@"
}

run_test_functions() {
	[ $# -eq 0 ] || eargs run_test_functions
	local rtf_ret rtf_assert
	local _PRE_TEST_TMPFILES _PRE_TEST_ENV

	case "${TESTFUNCS+set}" in
	set) ;;
	*) err 99 "run_test_functions: no add_test_function() called" ;;
	esac

	set_test_contexts - '' '' <<-EOF
	TESTFUNC $(list_test_functions)
	EOF
	while get_test_context; do
		_pre_test_env_compare
		_DID_ASSERTS=0
		rtf_ret=0
		_run_test_function "${TESTFUNC:?}" || rtf_ret="$?"
		rtf_assert="${_DID_ASSERTS:?}"
		assert 0 "${rtf_ret:?}" "${TESTFUNC:?}() return value"
		assert_not 0 "${rtf_assert:?}" "Test ran no asserts"
		unset rtf_assert rtf_ret
		_post_test_env_compare
	done
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

_get_next_context() {
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
	TEST_CONTEXT_NUM=$((TEST_CONTEXT_NUM + 1))
	TEST_CONTEXT_PROGRESS="${TEST_CONTEXT_NUM}/${TEST_CONTEXTS_TOTAL}"
}

get_test_context() {
	local IFS _line
	local -

	case "${TEST_CONTEXTS-}" in
	"")
		err "${EX_USAGE}" "Must call set_test_contexts with env to set"
		;;
	esac
	case "${TEST_CONTEXT_RAN-}" in
	1)
		# _post_test_env_compare
		;;
	esac
	while :; do
		_get_next_context || return
		case " ${TEST_NUMS-null} " in
		" null ") ;;
		*" ${TEST_CONTEXT_NUM} "*) ;;
		*) continue ;;
		esac
		break
	done
	msg "Testing context ${TEST_CONTEXT_PROGRESS} with ${TEST_CONTEXT}" >&${REDIRECTED_STDERR_FD:-2}
	set -o noglob
	eval ${TEST_CONTEXT}
	if [ -n "${TEST_SETUP-}" ]; then
		msg "Running setup: ${TEST_SETUP}" >&${REDIRECTED_STDERR_FD:-2}
		eval ${TEST_SETUP} >&${REDIRECTED_STDERR_FD:-2}
	fi
	TEST_CONTEXT_RAN=1
	# _pre_test_env_compare
}

clean_allowed_tmpfiles() {
	find "${POUDRIERE_TMPDIR:?}/" \
	    \( \
	    -name "lock-*.flock" -o \
	    -name "lock-*.pid" \
	    \) -type f -delete
	find "${POUDRIERE_TMPDIR:?}/" \
	    -name "lock-*" \
	    -type d -empty -delete
	find "${POUDRIERE_TMPDIR:?}/" \
	    \( \
	    -name "${READY_FILE:?}" -o \
	    -name "${READY_FILE:?}.*" \
	    \) -delete
}

cleanup() {
	ret="$?"
	msg "Cleaning up" >&"${REDIRECTED_STDERR_FD:-2}"
	capture_output_simple_stop
	parallel_shutdown || :
	if [ "${ret}" -ne 0 ] && [ -n "${LOG_START_LASTFILE-}" ] &&
	    [ -s "${LOG_START_LASTFILE}" ]; then
		echo "Log captured data not seen:" >&2
		# allow vfork
		{ cat "${LOG_START_LASTFILE}"; } >&2
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
		echo "Jobs are still running!" >&2
		jobs -l >&2
		EXITVAL=$((EXITVAL + 1))
		;;
	esac
	kill_all_jobs 20
	if [ ${_DID_TMPDIR:-0} -eq 1 ] && \
	    [ "${TMPDIR%%/poudriere/test/*}" != "${TMPDIR}" ]; then
		clean_allowed_tmpfiles
		if [ -d "${TMPDIR}" ] && ! dirempty "${TMPDIR}"; then
			echo "${TMPDIR} was not empty on exit!" >&2
			# allow vfork
			{ find "${TMPDIR}" -ls; } >&2
			case "${EXITVAL:-0}" in
			0) ret=1 ;;
			esac
			if [ -e "${ERR_CHECK-}" ]; then
				# allow vfork
				{ cat "${ERR_CHECK}"; } >&2
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
		0) res="${COLOR_SUCCESS:?}PASS" ;;
		77) res="${COLOR_SKIP}SKIP" ;;
		99) res="${COLOR_ERROR}ERROR" ;;
		*) res="${COLOR_WARN}FAIL" ;;
		esac
		echo "${res}${COLOR_RESET} ${SCRIPTNAME} TEST_NUMS=${TEST_NUMS} (exit status: ${ret})" >&2
	esac
	return "${ret}"
}

_sed_error() {
	[ $# -ge 2 ] || eargs _sed_error _ignored stdin_fifo
	local stdin_fifo="$2"

	exec < "${stdin_fifo:?}"
	sed -e 's,Error:,ExpectedError:,'
}


expect_error_on_stderr() {
	local -; set +e
	local ret _hack

	ret=0
	# This hacks capture_output_simple to redirect stderr to _sed_error
	capture_output_simple "" _hack _sed_error
	# allow vfork
	{ "$@"; } || ret="$?"
	# We can't _assert_ that there is an error as some calls won't actually
	# get 'Error:' with SH=/bin/sh. It's not that important to ensure
	# stderr has stuff, it's more about causing a FAIL if 'Error:' is
	# unexpectedly seen in a log.
	capture_output_simple_stop
	return "${ret}"
}

setup_traps cleanup
set -T

msg_debug "getpid: $$"
case "${TEST_CONTEXTS_NUM_CHECK:+set}" in
set) ;;
*)
	if [ -r "${am_abs_top_srcdir:?}/.git" ] &&
	    git_get_hash_and_dirty "${am_abs_top_srcdir:?}" 0 \
	    git_hash git_dirty; then
		msg "Source git hash: ${git_hash} modified: ${git_dirty}"
	fi >&2
	shash_remove_var "git_tree_dirty" 2>/dev/null || :
	setproctitle "runtest ${0}${TEST_NUMS:+ TEST_NUMS=${TEST_NUMS}} (${git_hash})"
	unset git_hash git_dirty
	;;
esac
