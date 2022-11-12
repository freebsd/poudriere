_LINEINFO_FUNC_DATA='${LINEINFOSTACK:+${LINEINFOSTACK}:}${FUNCNAME:+${FUNCNAME}:}${LINENO}'
_LINEINFO_DATA="\${lineinfo-\$0}:${_LINEINFO_FUNC_DATA:?}"
alias stack_lineinfo="LINEINFOSTACK=\"${_LINEINFO_FUNC_DATA:?}\" "

aecho() {
	local -; set +x +e +u
	[ $# -ge 2 ] || eargs aecho result lineinfo expected actual
	local result="$1"
	local lineinfo="${TEST_CONTEXT:+"{${TEST_CONTEXT_PROGRESS} ${TEST_CONTEXT}} "}${2}"

	case "${result}" in
	TEST)
		shift 2
		printf "%d> %-4s %s: %s\n" "$(getpid)" "${lineinfo}" "${result}" "$*"
		;;
	OK)
		printf "%d> %-4s %s\n" "$(getpid)" "${lineinfo}" "${result}"
		;;
	FAIL)
		case "${ASSERT_CONTINUE:-0}" in
		1) result="${result} (continuing)" ;;
		esac
		if [ "$#" -lt 4 ]; then
			shift 2
			printf "%d> %-4s %s: %s\n" "$(getpid)" "${lineinfo}" \
			    "${result}" "$*"
			return
		fi
		local expected="$3"
		local actual="$4"
		local INDENT
		shift 4
		INDENT=">>   "
		printf "%d> %-4s %s: %s\n${INDENT}expected '%s'\n${INDENT}actual   '%s'\n" \
			"$(getpid)" "${lineinfo}" "${result}" \
			"$(echo "$@" | cat -ev | sed '2,$s,^,	,')" \
			"$(echo "${expected}" | cat -ev | sed '2,$s,^,	,')" \
			"$(echo "${actual}" | cat -ev | sed '2,$s,^,	,')"
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
		return 1
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
alias assert="_assert \"${_LINEINFO_DATA:?}\" "

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
alias assert_list="_assert_list \"${_LINEINFO_DATA:?}\" "

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
	_assert "${lineinfo}" "${expected}" "${ret}" "Bad exit status: ${ret} cmd: $*"
}
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
alias assert_ret_not="_assert_ret_not \"${_LINEINFO_DATA:?}\" "
alias assert_false='assert_ret_not 0'

_assert_out() {
	local -; set +x +u
	[ "$#" -ge 2 ] || eargs assert_out expected command '[args]'
	local lineinfo="$1"
	local expected="$2"
	shift 2
	local out ret

	aecho TEST "${lineinfo}" "'${expected}' == '\$($*)'"
	ret=0
	out="$(set -e; "$@")" || ret="$?"
	assert "${expected}" "${out}" "Bad output: $*"
	aecho TEST "${lineinfo}" "'0' == '\$?'"
	assert 0 "${ret}" "Bad exit status: ${ret} cmd: $*"
}
alias assert_out="_assert_out \"${_LINEINFO_DATA:?}\" "
