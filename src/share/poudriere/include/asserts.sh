_LINEINFO_FUNC_DATA='${LINEINFOSTACK:+${LINEINFOSTACK}:}${FUNCNAME:+${FUNCNAME}:}${LINENO}'
_LINEINFO_DATA="\${lineinfo-\$0}:${_LINEINFO_FUNC_DATA:?}"
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

# This function gets conditionally overwritten in post_getopts()
msg_assert_dev() {
	msg_assert "$@"
}

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
	local result="$1"
	local lineinfo="${TEST_CONTEXT:+"{${TEST_CONTEXT_PROGRESS} ${TEST_CONTEXT}} "}${2}"

	case "${result}" in
	TEST)
		shift 2
		msg_assert_dev "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_TEST-}%s${COLOR_RESET-}: %s\n" \
		    "$(getpid)" "${lineinfo}" "${result}" "$*")"
		;;
	OK)
		msg_assert_dev "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_OK-}%s${COLOR_RESET-}\n" \
		    "$(getpid)" "${lineinfo}" "${result}")"
		;;
	FAIL)
		case "${ASSERT_CONTINUE:-0}" in
		1) result="${result} (continuing)" ;;
		esac
		if [ "$#" -lt 4 ]; then
			shift 2
			msg_assert "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_FAIL-}%s${COLOR_RESET-}: %s\n" \
			    "$(getpid)" "${lineinfo}" "${result}" "$*")"
			return
		fi
		local expected="$3"
		local actual="$4"
		local INDENT
		shift 4
		INDENT=">>   "
		msg_assert "$(printf "%d> ${COLOR_LINEINFO-}%-4s${COLOR_RESET-} ${COLOR_ASSERT_FAIL-}%s${COLOR_RESET-}: %s\n${INDENT}expected '%s'\n${INDENT}actual   '%s'\n" \
			"$(getpid)" "${lineinfo}" "${result}" \
			"$(echo "$@" | cat -ev | sed '2,$s,^,	,')" \
			"$(echo "${expected}" | cat -ev | sed '2,$s,^,	,')" \
			"$(echo "${actual}" | cat -ev | sed '2,$s,^,	,')")"
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

_assert() {
	local -; set +x +e +u
	[ $# -ge 3 ] || eargs assert lineinfo expected actual
	local lineinfo="$1"
	local expected="$2"
	local actual="$3"
	shift 3

	aecho TEST "${lineinfo}" "'${expected}' == '${actual}'"
	case "${actual}" in
	"${expected}") ;;
	*)
		aecho FAIL "${lineinfo}" "${expected}" "${actual}" "$@"
		assert_failure
		;;
	esac
	aecho OK "${lineinfo}" #"${msg}: expected: '${expected}', actual: '${actual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert() { _assert "" "$@"; }
alias assert="_assert \"${_LINEINFO_DATA:?}\" "

_assert_case() {
	local -; set +x +e +u
	[ $# -ge 3 ] || eargs assert_case lineinfo expected actual
	local lineinfo="$1"
	local expected="$2"
	local actual="$3"
	shift 3
	local -

	aecho TEST "${lineinfo}" $'\n'"case \"${actual}\" in"$'\n'$'\t'"${expected})"
	set -f
	# shellcheck disable=SC2254
	case "${actual}" in
	${expected}) ;;
	*)
		aecho FAIL "${lineinfo}" "${expected}" "${actual}" "$@"
		assert_failure
		;;
	esac
	set +f
	aecho OK "${lineinfo}" #"${msg}: expected: '${expected}', actual: '${actual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_case() { _assert_case "" "$@"; }
alias assert_case="_assert_case \"${_LINEINFO_DATA:?}\" "

_assert_not() {
	local -; set +x +e +u
	[ $# -ge 3 ] || eargs assert_not lineinfo notexpected actual
	local lineinfo="$1"
	local notexpected="$2"
	local actual="$3"
	shift 3

	aecho TEST "${lineinfo}" "'${notexpected}' != '${actual}'"
	case "${actual}" in
	"${notexpected}")
		aecho FAIL "${lineinfo}" "!${notexpected}" "${actual}" "$@"
		assert_failure
		;;
	esac
	aecho OK "${lineinfo}" # "${msg}: notexpected: '${notexpected}', actual: '${actual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_not() { _assert_not "" "$@"; }
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
	local ret=0
	local expected actual

	getvar "${expected_name}" expected || expected="null"
	getvar "${actual_name}" actual || actual="null"

	echo "${expected}" |
	    tr ' ' '\n' | env LC_ALL=C sort |
            sed -e '/^$/d' > "${expected_tmp}"
	echo "${actual}" |
	    tr ' ' '\n' | env LC_ALL=C sort |
	    sed -e '/^$/d' > "${have_tmp}"
	cmp -s "${have_tmp}" "${expected_tmp}" || ret=$?
	if [ "${ret}" -ne 0 ]; then
		diff -u "${expected_tmp}" "${have_tmp}" >&${REDIRECTED_STDERR_FD:-2}
	fi

	rm -f "${have_tmp}" "${expected_tmp}"
	if [ "${ret}" -ne 0 ]; then
		aecho FAIL "${lineinfo}" "${reason}"
		assert_failure
	fi
	aecho OK "${lineinfo}" #"${msg}: expected: '${expected}', actual: '${actual}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_list() { _assert_list "" "$@"; }
alias assert_list="_assert_list \"${_LINEINFO_DATA:?}\" "

_assert_file_reg() {
	[ "$#" -ge 3 ] || eargs assert_file_reg 'expected-file|-' 'have-file'
	local -; set +x +e +u
	local lineinfo="$1"
	local expected="$2"
	local have="$3"
	local reason="${4-}"
	local ret=0

	if [ ! -r "${have}" ]; then
		aecho FAIL "${lineinfo}" "Have file is missing? ${have}"
		assert_failure
	fi

	case "${expected}" in
	-)
		expected=$(mktemp -ut assert_file.expected)
		cat > "${expected}"
		;;
	esac

	aecho TEST "${lineinfo}" "awk -f ${AWKPREFIX:?}/file_cmp_reg.awk '${expected}' '${have}'"
	awk -f "${AWKPREFIX:?}/file_cmp_reg.awk" "${expected}" "${have}" ||
	    ret="$?"
	reason="${reason:+${reason} -}
HAVE:
$(cat -nvet "${have}")
EXPECTED:
$(cat -nvet "${expected}")"
	if [ "${ret}" -ne 0 ]; then
		aecho FAIL "${lineinfo}" "${reason}"
		#diff -u "${expected}" "${have}" | cat -vet >&${REDIRECTED_STDERR_FD:-2}
		assert_failure
	else
		aecho OK "${lineinfo}"
		rm -f "${have}" "${expected}"
	fi
}
# This function may be called in "$@" contexts that do not use eval.
assert_file_reg() { _assert_file_reg "" "$@"; }
alias assert_file_reg="_assert_file_reg \"${_LINEINFO_DATA:?}\" "

_assert_file() {
	[ "$#" -ge 4 ] || eargs assert_file 'expected-file|-' 'have-file'
	local -; set +x +e +u
	local lineinfo="$1"
	local unordered="$2"
	local expected="$3"
	local have="$4"
	local reason="${5-}"
	local ret=0
	local havetmp havesave expectedtmp expectedsave

	if [ ! -r "${have}" ]; then
		aecho FAIL "${lineinfo}" "Have file is missing? ${have}"
		assert_failure
	fi

	case "${expected}" in
	-)
		expected=$(mktemp -ut assert_file.expected)
		cat | grep -v '^#' > "${expected}"
		;;
	esac

	if [ "${unordered}" -eq 1 ]; then
		havetmp=$(mktemp -ut have)
		sort -o "${havetmp}" "${have}"
		havesave="${have}"
		have="${havetmp}"
		expectedtmp=$(mktemp -ut expected)
		sort -o "${expectedtmp}" "${expected}"
		expectedsave="${expected}"
		expected="${expectedtmp}"
	fi

	aecho TEST "${lineinfo}" "diff -u '${expected}' '${have}'"
	cmp -s "${have}" "${expected}" || ret=$?
	reason="${reason:+${reason} -}
HAVE:
$(cat -nvet "${have}")
EXPECTED:
$(cat -nvet "${expected}")"
	if [ "${ret}" -ne 0 ]; then
		aecho FAIL "${lineinfo}" "${reason}"
		diff -u "${expected}" "${have}" | cat -vet >&${REDIRECTED_STDERR_FD:-2}
		if [ "${unordered}" -eq 1 ]; then
			rm -f "${havetmp}" "${expectedtmp}"
			have="${havesave}"
			expected="${expectedsave}"
		fi
		assert_failure
	else
		if [ "${unordered}" -eq 1 ]; then
			rm -f "${havetmp}" "${expectedtmp}"
			have="${havesave}"
			expected="${expectedsave}"
		fi
		aecho OK "${lineinfo}"
		rm -f "${have}" "${expected}"
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
	local expected="$2"
	shift 2
	local ret

	aecho TEST "${lineinfo}" "\$? == ${expected} cmd:" "$*"
	ret=0
	"$@" || ret=$?
	reason="Bad exit status: ${ret} cmd: $*"
	_assert "${lineinfo}" "${expected}" "${ret}" "Bad exit status: ${ret} cmd: $*${REASON:+ "$'\n'" ${REASON}}"
}
# This function may be called in "$@" contexts that do not use eval.
assert_ret() { _assert_ret "" "$@"; }
assert_true() { assert_ret 0 "$@"; }
alias assert_ret="_assert_ret \"${_LINEINFO_DATA:?}\" "
alias assert_true='assert_ret 0'

_assert_ret_not() {
	local -; set +x +e +u
	[ "$#" -ge 3 ] || eargs assert_ret_not not_expected_exit_status 'cmd ...'
	local lineinfo="$1"
	local expected="$2"
	shift 2
	local ret

	# [(1) will always return 1 on failure but 2 on an error.
	case "${expected}${1-}" in
	'0[')
		assert_ret 1 "$@"
		return
		;;
	esac

	aecho TEST "${lineinfo}" "\$? != ${expected} cmd:" "$*"
	ret=0
	"$@" || ret=$?
	_assert_not "${lineinfo}" "${expected}" "${ret}" "Bad exit status: ${ret} cmd: $*"
}
# This function may be called in "$@" contexts that do not use eval.
assert_ret_not() { _assert_ret_not "" "$@"; }
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
	local expected="$4"
	shift 4
	local out ret tmpfile

	aecho TEST "${lineinfo}" "'${expected}' == '\$($*)'"

	ret=0
	case "${expected}" in
	-)
		tmpfile="$(mktemp -ut assert_out)"
		(set_pipefail; set -e; "$@" ) < /dev/null > "${tmpfile}"
		ret="$?"
		_assert_file "${lineinfo}" "${unordered}" - "${tmpfile}"
		_assert "${lineinfo:?}" "${expected_ret}" "${ret}"
		return "${ret}"
		;;
	*)
		out="$(set_pipefail; set -e; "$@" | cat -vet)" || ret="$?"
		_assert "${lineinfo:?}" "${expected_ret}" "${ret}"
		;;
	esac
	case "${unordered:-0}" in
	1)
		assert \
		    "$(echo "${expected}" | LC_ALL=C sort)" \
		    "$(echo "${out}" | LC_ALL=C sort)" \
		    "Bad output: $*"
		;;
	0)
		assert "${expected}" "${out}" "Bad output: $*"
		;;
	esac
	return "${ret}"
	#aecho TEST "${lineinfo}" "'0' == '\$?'"
	#assert 0 "${ret}" "Bad exit status: ${ret} cmd: $*"
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
	local expected="$2"
	local reason="$3"
	local have_tmp=$(mktemp -t assert_stack)
	local expected_tmp=$(mktemp -t assert_stack)
	local ret=0
	local val

	val="$(getvar "${stack_var}")"
	echo "${val}" | tr ' ' '\n' | sort | sed -e '/^$/d' > "${have_tmp}"
	echo "${expected}" | tr ' ' '\n' | sort | sed -e '/^$/d' > \
	    "${expected_tmp}"
	cmp -s "${have_tmp}" "${expected_tmp}" || ret=$?
	if [ ${ret} -ne 0 ]; then
		comm "${have_tmp}" "${expected_tmp}" >&2
	fi

	rm -f "${have_tmp}" "${expected_tmp}"
	assert 0 "${ret}" \
		"${reason} -"$'\n'"Have:     '${val}'"$'\n'"Expected: '${expected}'"
}
# This function may be called in "$@" contexts that do not use eval.
assert_stack() { _assert_stack "" "$@"; }
alias assert_stack='stack_lineinfo _assert_stack '

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
			;;
		*)
			# This function may be called in "$@" contexts that do
			# not use eval.
			eval "dev_${aliasname}() { :; }"
			alias "dev_${aliasname}=# "
			;;
		esac
	done <<-EOF
	$(alias)
	EOF
}
setup_runtime_asserts
