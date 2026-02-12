_LINEINFO_FUNC_DATA='${LINEINFOSTACK:+${LINEINFOSTACK}:}${FUNCNAME:+${FUNCNAME}:}${LINENO}'
_LINEINFO_DATA="\${lineinfo:-\$0}:${_LINEINFO_FUNC_DATA:?}"
alias stack_lineinfo="LINEINFOSTACK=\"${_LINEINFO_FUNC_DATA:?}\" "
if ! type err >/dev/null 2>&1; then
	# This function may be called in "$@" contexts that do not use eval.
	# eval is used here to avoid existing alias parsing issues.
	eval 'err() { _err "" "$@"; }'
	alias err="_err \"${_LINEINFO_DATA:?}\" ";
fi

if ! type msg_assert >/dev/null 2>&1; then
msg_assert() {
	local COLOR_ARROW

	case "$(type msg >/dev/null 2>&1)" in
	"msg is a shell function")
		COLOR_ARROW="${COLOR_WARN}" \
		    msg "${COLOR_WARN}${DEV_ASSERT:+Dev }Assert${COLOR_RESET-}: $@"
		;;
	*)
		echo "${DEV_ASSERT:+Dev }Assert: $@"
		;;
	esac
}
fi

_err() {
	set +e +u +x
	local lineinfo="${1}"
	local status="${2-1}"
	shift 2
	echo "Early Error: ${lineinfo:+${lineinfo}:}$*" >&2
	exit "${status}"
}

aecho() {
	local -; set +x +e +u
	[ $# -ge 2 ] || eargs aecho result lineinfo expected actual
	local _aresult="$1"
	local lineinfo="${TEST_CONTEXT:+"{${TEST_CONTEXT_PROGRESS} ${TEST_CONTEXT}} "}${2}"

	case "${_aresult}" in
	TEST*)
		shift 2
		if [ "${IN_TEST:-0}" -eq 1 ] || msg_level dev; then
			msg_assert "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_TEST-}%s${COLOR_RESET-}: %s\n" \
			    "$(getpid)" "${lineinfo}" "${_aresult}" "$*")"
		fi
		;;
	OK)
		if [ "${IN_TEST:-0}" -eq 1 ] || msg_level dev; then
			msg_assert "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_OK-}%s${COLOR_RESET-}\n" \
			    "$(getpid)" "${lineinfo}" "${_aresult}")"
		fi
		;;
	FAIL)
		case "${ASSERT_CONTINUE:-0}" in
		1) _aresult="${_aresult} (continuing)" ;;
		esac
		if [ "$#" -lt 4 ]; then
			shift 2
			msg_assert "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_FAIL-}%s${COLOR_RESET-}: %s\n" \
			    "$(getpid)" "${lineinfo}" "${_aresult}" "$*")"
			return
		fi
		local _aexpected="$3"
		local _aactual="$4"
		local INDENT
		shift 4
		INDENT=">>   "
		msg_assert "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_FAIL-}%s${COLOR_RESET-}: %s\n${INDENT}expected '%s'\n${INDENT}actual   '%s'\n" \
			"$(getpid)" "${lineinfo}" "${_aresult}" \
			"$(echo "$@" | cat -ev | sed '2,$s,^,	,')" \
			"$(echo "${_aexpected}" | cat -ev | sed '2,$s,^,	,')" \
			"$(echo "${_aactual}" | cat -ev | sed '2,$s,^,	,')")"
		;;
	*)
		;;
	esac >&${REDIRECTED_STDERR_FD:-${OUTPUT_REDIRECTED_STDERR:-2}}

	_DID_ASSERTS=1
}

_assert_failure() {
	[ "$#" -eq 0 ] || eargs _assert_failure

	EXITVAL=$((${EXITVAL:-0} + 1))
	if [ "${ASSERT_CONTINUE:-0}" -eq 1 ]; then
		return 0
	elif [ "${IN_TEST:-0}" -eq 0 ]; then
		_err "" "${EX_SOFTWARE:?}" "Assertion failure"
	else
		exit "${EXITVAL}"
	fi
}
alias assert_failure='_assert_failure; return'

_assert_compare() {
	local -; set +x +e +u
	[ $# -ge 4 ] || eargs _assert_compare lineinfo test_op expected actual
	local lineinfo="$1"
	local test_op="$2"
	local _aexpected="$3"
	local _aactual="$4"
	local test_str
	shift 4

	# All of the other aechos show expected FIRST so we have to flip
	# around the comparison for display.
	# comparison is actual <test_op> expected
	# string is expected (mirror)<test_op> actual
	case "${test_op}" in
	"-le") test_str=">=" ;;
	"-lt")  test_str=">" ;;
	"-ge") test_str="<=" ;;
	"-gt")  test_str="<" ;;
	*) err 1 "invalid test_op=${test_op}" ;;
	esac

	aecho TEST "${lineinfo}" "'${_aexpected}' ${test_str} '${_aactual}'"
	if [ "${_aactual}" ${test_op} "${_aexpected}" ]; then
		:
	else
		aecho FAIL "${lineinfo}" "${_aexpected}" "${_aactual}" "$@"
		assert_failure
	fi
	aecho OK "${lineinfo}" #"${msg}: expected: '${_aexpected}', actual: '${_aactual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_le() { _assert_compare "${lineinfo-}" "-le" "$@"; }
alias assert_le="_assert_compare \"${_LINEINFO_DATA:?}\" \"-le\" "
assert_lt() { _assert_compare "${lineinfo-}" "-lt" "$@"; }
alias assert_lt="_assert_compare \"${_LINEINFO_DATA:?}\" \"-lt\" "
assert_ge() { _assert_compare "${lineinfo-}" "-ge" "$@"; }
alias assert_ge="_assert_compare \"${_LINEINFO_DATA:?}\" \"-ge\" "
assert_gt() { _assert_compare "${lineinfo-}" "-gt" "$@"; }
alias assert_gt="_assert_compare \"${_LINEINFO_DATA:?}\" \"-gt\" "


_assert() {
	local -; set +x +e +u
	[ $# -ge 3 ] || eargs assert lineinfo expected actual
	local lineinfo="$1"
	local _aexpected="$2"
	local _aactual="$3"
	shift 3

	aecho TEST "${lineinfo}" "'${_aexpected}' == '${_aactual}'"
	case "${_aactual}" in
	"${_aexpected}") ;;
	*)
		aecho FAIL "${lineinfo}" "${_aexpected}" "${_aactual}" "$@"
		assert_failure
		;;
	esac
	aecho OK "${lineinfo}" #"${msg}: expected: '${_aexpected}', actual: '${_aactual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert() { _assert "${lineinfo-}" "$@"; }
alias assert="_assert \"${_LINEINFO_DATA:?}\" "

_assert_case() {
	local -; set +x +e +u
	[ $# -ge 3 ] || eargs assert_case lineinfo expected actual
	local lineinfo="$1"
	local _aexpected="$2"
	local _aactual="$3"
	shift 3
	local -

	aecho TEST "${lineinfo}" $'\n'"case \"${_aactual}\" in"$'\n'$'\t'"${_aexpected})"
	set -f
	# shellcheck disable=SC2254
	case "${_aactual}" in
	${_aexpected}) ;;
	*)
		aecho FAIL "${lineinfo}" "${_aexpected}" "${_aactual}" "$@"
		assert_failure
		;;
	esac
	set +f
	aecho OK "${lineinfo}" #"${msg}: expected: '${_aexpected}', actual: '${_aactual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_case() { _assert_case "${lineinfo-}" "$@"; }
alias assert_case="_assert_case \"${_LINEINFO_DATA:?}\" "

_assert_not() {
	local -; set +x +e +u
	[ $# -ge 3 ] || eargs assert_not lineinfo notexpected actual
	local lineinfo="$1"
	local notexpected="$2"
	local _aactual="$3"
	shift 3

	aecho TEST "${lineinfo}" "'${notexpected}' != '${_aactual}'"
	case "${_aactual}" in
	"${notexpected}")
		aecho FAIL "${lineinfo}" "!${notexpected}" "${_aactual}" "$@"
		assert_failure
		;;
	esac
	aecho OK "${lineinfo}" # "${msg}: notexpected: '${notexpected}', actual: '${_aactual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_not() { _assert_not "${lineinfo-}" "$@"; }
alias assert_not="_assert_not \"${_LINEINFO_DATA:?}\" "

_assert_list() {
	local -; set +x +e +u
	[ "$#" -ge 3 ] || eargs assert_list expected_list_name actual_list_name '[reason]'
	local lineinfo="$1"
	local expected_name="$2"
	local actual_name="$3"
	local reason="$4"
	local have_tmp=$(mktemp -t actual.${actual_name})
	local expected_tmp=$(mktemp -t expected.${expected_name})
	local _al_ret=0
	local _aexpected _aactual

	getvar "${expected_name}" _aexpected || _aexpected="null"
	getvar "${actual_name}" _aactual || _aactual="null"

	{
		echo "${_aexpected}" |
		    tr ' ' '\n' | LC_ALL=C sort |
		    sed -e '/^$/d'
	} > "${expected_tmp}"
	{
		echo "${_aactual}" |
		    tr ' ' '\n' | LC_ALL=C sort |
		    sed -e '/^$/d'
	} > "${have_tmp}"
	cmp -s "${have_tmp}" "${expected_tmp}" || _al_ret=$?
	if [ "${_al_ret}" -ne 0 ]; then
		{ diff -u "${expected_tmp}" "${have_tmp}"; } \
		    >&${REDIRECTED_STDERR_FD:-2}
	fi

	rm -f "${have_tmp}" "${expected_tmp}"
	if [ "${_al_ret}" -ne 0 ]; then
		aecho FAIL "${lineinfo}" "${reason}"
		assert_failure
	fi
	aecho OK "${lineinfo}" #"${msg}: expected: '${_aexpected}', actual: '${_aactual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_list() { _assert_list "${lineinfo-}" "$@"; }
alias assert_list="_assert_list \"${_LINEINFO_DATA:?}\" "

_assert_file_reg() {
	[ "$#" -ge 3 ] || eargs assert_file_reg 'expected-file|-' 'have-file'
	local -; set +x +e +u
	local lineinfo="$1"
	local _aexpected="$2"
	local have="$3"
	local reason="${4-}"
	local _afg_ret=0

	if [ ! -r "${have}" ]; then
		aecho FAIL "${lineinfo}" "Have file is missing? ${have}"
		assert_failure
	fi

	case "${_aexpected}" in
	-)
		_aexpected=$(mktemp -ut assert_file.expected)
		{ cat; } > "${_aexpected}"
		;;
	esac

	aecho TEST "${lineinfo}" "awk -f ${AWKPREFIX:?}/file_cmp_reg.awk '${_aexpected}' '${have}'"
	awk -f "${AWKPREFIX:?}/file_cmp_reg.awk" "${_aexpected}" "${have}" ||
	    _afg_ret="$?"
	reason="$(\
	    printf "%s%s\nHAVE:\n%s\nEXPECTED:\n%s\n" \
	    "${reason}" \
	    "${reason:+ -}" \
	    "$(cat -nvet "${have}")" \
	    "$(cat -nvet "${_aexpected}")" \
	)"
	if [ "${_afg_ret}" -ne 0 ]; then
		aecho FAIL "${lineinfo}" "${reason}"
		#diff -u "${_aexpected}" "${have}" | cat -vet >&${REDIRECTED_STDERR_FD:-2}
		assert_failure
	else
		aecho OK "${lineinfo}"
		rm -f "${have}" "${_aexpected}"
	fi
}
# This function may be called in "$@" contexts that do not use eval.
assert_file_reg() { _assert_file_reg "${lineinfo-}" "$@"; }
alias assert_file_reg="_assert_file_reg \"${_LINEINFO_DATA:?}\" "

_assert_file() {
	[ "$#" -ge 4 ] || eargs assert_file 'expected-file|-' 'have-file'
	local -; set +x +e +u
	local lineinfo="$1"
	local unordered="$2"
	local _aexpected="$3"
	local _ahave="$4"
	local reason="${5-}"
	local _af_ret=0
	local havetmp havesave expectedtmp expectedsave

	case "${_ahave}" in
	-)
		_ahave=$(mktemp -ut assert_file.have)
		{ grep -v '^#'; } > "${_ahave}"
		;;
	*)
		if [ ! -r "${_ahave}" ]; then
			aecho FAIL "${lineinfo}" "Have file is missing?" \
			    "${_ahave}"
			assert_failure
		fi
		;;
	esac
	case "${_aexpected}" in
	-)
		_aexpected=$(mktemp -ut assert_file.expected)
		{ grep -v '^#'; } > "${_aexpected}"
		;;
	*)
		if [ ! -r "${_aexpected}" ]; then
			aecho FAIL "${lineinfo}" "Expected file is missing?" \
			    "${_aexpected}"
			assert_failure
		fi
		;;
	esac

	if [ "${unordered}" -eq 1 ]; then
		havetmp=$(mktemp -ut have)
		sort -o "${havetmp}" "${_ahave}"
		havesave="${_ahave}"
		_ahave="${havetmp}"
		expectedtmp=$(mktemp -ut expected)
		sort -o "${expectedtmp}" "${_aexpected}"
		expectedsave="${_aexpected}"
		_aexpected="${expectedtmp}"
	fi

	aecho TEST "${lineinfo}" "diff -u '${_aexpected}' '${_ahave}'"
	cmp -s "${_ahave}" "${_aexpected}" || _af_ret=$?
	reason="${reason:+${reason} -}
HAVE:
$(cat -nvet "${_ahave}")
EXPECTED:
$(cat -nvet "${_aexpected}")"
	if [ "${_af_ret}" -ne 0 ]; then
		aecho FAIL "${lineinfo}" "${reason}"
		{ diff -u "${_aexpected}" "${_ahave}" | cat -vet; } \
		    >&${REDIRECTED_STDERR_FD:-2}
		if [ "${unordered}" -eq 1 ]; then
			rm -f "${havetmp}" "${expectedtmp}"
			_ahave="${havesave}"
			_aexpected="${expectedsave}"
		fi
		assert_failure
	else
		if [ "${unordered}" -eq 1 ]; then
			rm -f "${havetmp}" "${expectedtmp}"
			_ahave="${havesave}"
			_aexpected="${expectedsave}"
		fi
		aecho OK "${lineinfo}"
		rm -f "${_ahave}" "${_aexpected}"
	fi
}
# This function may be called in "$@" contexts that do not use eval.
assert_file() { _assert_file "" 0 "$@"; }
assert_file_unordered() { _assert_file_unordered "" 1 "$@"; }
alias assert_file="_assert_file \"${_LINEINFO_DATA:?}\" 0 "
alias assert_file_unordered="_assert_file \"${_LINEINFO_DATA:?}\" 1 "

_assert_ret() {
	local -; set +x +e +u
	[ "$#" -ge 3 ] || eargs assert_ret expected_exit_status 'cmd ...'
	local lineinfo="$1"
	local _aexpected="$2"
	shift 2
	local _ar_ret reason

	aecho TEST "${lineinfo}" "\$? == ${_aexpected} cmd:" "$*"
	_ar_ret=0
	"$@" || _ar_ret=$?
	reason="Bad exit status: ${_ar_ret} cmd: $*"
	_assert "${lineinfo}" "${_aexpected}" "${_ar_ret}" "${reason}${REASON:+ "$'\n'" ${REASON}}"
}
# This function may be called in "$@" contexts that do not use eval.
assert_ret() { _assert_ret "${lineinfo-}" "$@"; }
assert_true() { assert_ret 0 "$@"; }
alias assert_ret="_assert_ret \"${_LINEINFO_DATA:?}\" "
alias assert_true='assert_ret 0'

_assert_ret_not() {
	local -; set +x +e +u
	[ "$#" -ge 3 ] || eargs assert_ret_not not_expected_exit_status 'cmd ...'
	local lineinfo="$1"
	local _aexpected="$2"
	shift 2
	local _arn_ret

	# [(1) will always return 1 on failure but 2 on an error.
	case "${_aexpected}${1-}" in
	'0[')
		assert_ret 1 "$@"
		return
		;;
	esac

	aecho TEST "${lineinfo}" "\$? != ${_aexpected} cmd:" "$*"
	_arn_ret=0
	"$@" || _arn_ret=$?
	_assert_not "${lineinfo}" "${_aexpected}" "${_arn_ret}" "Bad exit status: ${_arn_ret} cmd: $*"
}
# This function may be called in "$@" contexts that do not use eval.
assert_ret_not() { _assert_ret_not "${lineinfo-}" "$@"; }
assert_false() { assert_ret_not 0 "$@"; }
alias assert_ret_not="_assert_ret_not \"${_LINEINFO_DATA:?}\" "
alias assert_false='assert_ret_not 0'

_assert_out() {
	local -; set +x +u +e
	[ "$#" -ge 4 ] ||
	    eargs assert_out expected_ret expected command '[args]'
	local lineinfo="$1"
	local unordered="$2"
	local expected_ret="$3"
	local _aexpected="$4"
	shift 4
	local out _ao_ret tmpfile

	aecho TEST "${lineinfo}" "'${_aexpected}' == '\$($*)'"

	_ao_ret=0
	case "${_aexpected}" in
	-)
		tmpfile="$(mktemp -ut assert_out)"
		(set_pipefail; set -e; "$@" ) < /dev/null > "${tmpfile}"
		_ao_ret="$?"
		_assert_file "${lineinfo}" "${unordered}" - "${tmpfile}"
		_assert "${lineinfo:?}" "${expected_ret}" "${_ao_ret}"
		return "${_ao_ret}"
		;;
	*)
		out="$(set_pipefail; set -e; "$@" | cat -vet)" || _ao_ret="$?"
		_assert "${lineinfo:?}" "${expected_ret}" "${_ao_ret}"
		;;
	esac
	case "${unordered:-0}" in
	1)
		assert \
		    "$(echo "${_aexpected}" | LC_ALL=C sort)" \
		    "$(echo "${out}" | LC_ALL=C sort)" \
		    "Bad output: $*"
		;;
	0)
		assert "${_aexpected}" "${out}" "Bad output: $*"
		;;
	esac
	return "${_ao_ret}"
	#aecho TEST "${lineinfo}" "'0' == '\$?'"
	#assert 0 "${_ao_ret}" "Bad exit status: ${_ao_ret} cmd: $*"
}
# This function may be called in "$@" contexts that do not use eval.
assert_out() { _assert_out "" 0 "$@"; }
assert_out_unordered() { _assert_out "" 1 "$@"; }
alias assert_out="_assert_out \"${_LINEINFO_DATA:?}\" 0 "
alias assert_out_unordered="_assert_out \"${_LINEINFO_DATA:?}\" 1 "

_assert_stack() {
	local -; set +x +u
	[ "$#" -ge 2 ] || eargs assert_stack stack_var expected_value '[reason]'
	local stack_var="$1"
	local _aexpected="$2"
	local reason="$3"
	local have_tmp=$(mktemp -t assert_stack)
	local expected_tmp=$(mktemp -t assert_stack)
	local _as_ret=0
	local val

	val="$(getvar "${stack_var}")"
	{ echo "${val}" | tr ' ' '\n' | sort | sed -e '/^$/d'; } > "${have_tmp}"
	{ echo "${_aexpected}" | tr ' ' '\n' | sort | sed -e '/^$/d'; } > \
	    "${expected_tmp}"
	cmp -s "${have_tmp}" "${expected_tmp}" || _as_ret=$?
	if [ ${_as_ret} -ne 0 ]; then
		{ comm "${have_tmp}" "${expected_tmp}"; } >&2
	fi

	rm -f "${have_tmp}" "${expected_tmp}"
	assert 0 "${_as_ret}" \
		"${reason} -"$'\n'"Have:     '${val}'"$'\n'"Expected: '${_aexpected}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_stack() { _assert_stack "${lineinfo-}" "$@"; }
alias assert_stack='stack_lineinfo _assert_stack '

_assert_runs_le() {
	local -; set +x +e +u
	[ "$#" -ge 3 ] || eargs assert_runs_le seconds 'cmd ...'
	local lineinfo="$1"
	local within="$2"
	shift 2
	local _arle_ret start now duration reason

	aecho TEST "${lineinfo}" "runs within ${within} seconds cmd: $*"
	start="$(clock -monotonic)"
	_arle_ret=0
	"$@" || _arle_ret=$?
	now="$(clock -monotonic)"
	duration="$((now - start))"
	if [ "${duration}" -gt "${within}" ]; then
		reason="Took longer than ${within} seconds. Took ${duration} seconds. cmd: $*"
	fi
	aecho TEST_FINISH "${lineinfo}" "ran in ${duration} seconds ret=${_arle_ret} cmd: $*"
	_assert_compare "${lineinfo}" "-le" "${within}" "${duration}" "${reason}${REASON:+ "$'\n'" ${REASON}}"
}
# This function may be called in "$@" contexts that do not use eval.
assert_runs_le() { _assert_runs_le "${lineinfo-}" "$@"; }
alias assert_runs_le="_assert_runs_le \"${_LINEINFO_DATA:?}\" "
assert_runs_shorter_than() { assert_runs_le "$@"; }
alias assert_runs_shorter_than='assert_runs_le '
assert_runs_less_than() { assert_runs_le "$@"; }
alias assert_runs_less_than='assert_runs_le '
assert_runs_within() { assert_runs_shorter_than "$@"; }
alias assert_runs_within='assert_runs_shorter_than '

_assert_runs_ge() {
	local -; set +x +e +u
	[ "$#" -ge 3 ] || eargs assert_runs_ge seconds 'cmd ...'
	local lineinfo="$1"
	local within_ge="$2"
	shift 2
	local _arge_ret start now duration reason

	aecho TEST "${lineinfo}" "runs at_least ${within_ge} seconds cmd: $*"
	start="$(clock -monotonic)"
	_arge_ret=0
	"$@" || _arge_ret=$?
	now="$(clock -monotonic)"
	duration="$((now - start))"
	if [ "${duration}" -gt "${within_ge}" ]; then
		reason="Took shorter than ${within_ge} seconds. Took ${duration} seconds. cmd: $*"
	fi
	aecho TEST_FINISH "${lineinfo}" "ran in ${duration} seconds ret=${_arge_ret} cmd: $*"
	_assert_compare "${lineinfo}" "-ge" "${within_ge}" "${duration}" "${reason}${REASON:+ "$'\n'" ${REASON}}"
	return "${_arge_ret}"
}
# This function may be called in "$@" contexts that do not use eval.
assert_runs_ge() { _assert_runs_ge "${lineinfo-}" "$@"; }
alias assert_runs_ge="_assert_runs_ge \"${_LINEINFO_DATA:?}\" "
assert_runs_longer_than() { assert_runs_ge "$@"; }
alias assert_runs_longer_than='assert_runs_ge '
assert_runs_greather_than() { assert_runs_ge "$@"; }
alias assert_runs_greather_than='assert_runs_ge '

_assert_runs_between() {
	local -; set +x +e +u
	[ "$#" -ge 4 ] || eargs assert_runs_between seconds_start seconds_end 'cmd ...'
	local lineinfo="$1"
	local secs_start="$2"
	local secs_end="$3"
	shift 3
	local _arb_ret start now duration reason

	aecho TEST "${lineinfo}" "runs between ${secs_start}-${secs_end} seconds cmd: $*"
	start="$(clock -monotonic)"
	_arb_ret=0
	"$@" || _arb_ret=$?
	now="$(clock -monotonic)"
	duration="$((now - start))"
	aecho TEST_FINISH "${lineinfo}" "ran in ${duration} seconds ret=${_arb_ret} cmd: $*"
	reason="Took shorter than ${secs_start} seconds. Took ${duration} seconds. cmd: $*"
	_assert_compare "${lineinfo}" "-ge" "${secs_start}" "${duration}" "${reason}${REASON:+ "$'\n'" ${REASON}}"
	reason="Took longer than ${secs_end} seconds. Took ${duration} seconds. cmd: $*"
	_assert_compare "${lineinfo}" "-le" "${secs_end}" "${duration}" "${reason}${REASON:+ "$'\n'" ${REASON}}"
	return "${_arb_ret}"
}
# This function may be called in "$@" contexts that do not use eval.
assert_runs_between() { _assert_runs_between "${lineinfo-}" "$@"; }
alias assert_runs_between="_assert_runs_between \"${_LINEINFO_DATA:?}\" "

setup_runtime_asserts() {
	local -; set +x
	local aliasname _ IFS

	while IFS='=' read -r aliasname _; do
		case "${aliasname}" in
		assert*) ;;
		*) continue ;;
		esac

		case "${USE_DEBUG:-no}" in
		yes)
			# This function may be called in "$@" contexts that do
			# not use eval.
			eval "dev_${aliasname}() { local DEV_ASSERT=1; ${aliasname} \"\$@\"; }"
			alias "dev_${aliasname}=DEV_ASSERT=1 ${aliasname} "
			use_debug() { return 0; }
			;;
		*)
			# This function may be called in "$@" contexts that do
			# not use eval.
			eval "dev_${aliasname}() { :; }"
			# See post_getopts() for use of nop().
			alias "dev_${aliasname}=nop "
			use_debug() { return 1; }
			;;
		esac
	done <<-EOF
	$(alias)
	EOF
}
setup_runtime_asserts
