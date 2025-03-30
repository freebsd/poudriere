set -e
. ./common.sh
set +e

set_pipefail

# pipe_func simulated with heredoc
{
	some_func() {
		set -x
		local max="$1"
		local start="$2"
		local n

		n="${start}"
		until [ "${n}" -eq "${max}" ]; do
			echo "${start} ${max} ${n} $((n - 1))"
			n=$((n + 1))
			# The sleep helps demonstrate the difference in
			# a heredoc and pipe_func() in the log.
			#sleep 1
		done
	}

	lines=0
	max=10
	start_lines=${lines}
	start_max=${max}
	unset tmp
	while mapfile_read_loop "/dev/stdin" cstart cmax n n_minus_1; do
		assert "${start_lines}" "${cstart}"
		assert "${start_max}" "${cmax}"
		assert_ret 0 [ "${n}" -le "${max}" ]
		assert "${lines}" "${n}" "n"
		assert "$((lines - 1))" "${n_minus_1}" "n_minus_1"
		lines=$((lines + 1))
	done <<-EOF
	$(some_func "$((lines + max))" "${lines}")
	EOF
	assert "${max}" "${lines}"
}

pipe_func_child_exit_success=27
# pipe_func
{
	some_func() {
		set -x
		local max="$1"
		local spaced_data="$2"
		local start="$3"
		local n

		assert "spaced data" "${spaced_data}"

		n="${start}"
		until [ "${n}" -eq "${max}" ]; do
			echo "${start} ${max} ${n} $((n - 1))"
			n=$((n + 1))
			# The sleep helps demonstrate the difference in
			# a heredoc and pipe_func() in the log.
			#sleep 1
		done
		exit ${pipe_func_child_exit_success}
	}

	lines=0
	max=10
	unset tmp
	start_lines=${lines}
	start_max=${max}
	#while pipe_func -H tmp \
	#    read n n_minus_1 -- \
	#    some_func "$((lines + max))" "${lines}"; do
	#The while loop method would work fine but loses the child exit
	# status which we need to ensure it passed its own asserts.
	while :; do
		ret=0
		pipe_func -H tmp read cstart cmax n n_minus_1 -- \
		    some_func "$((lines + max))" "spaced data" "${lines}" || ret="$?"
		case "${ret}" in
		0) ;;
		# EOF
		"${pipe_func_child_exit_success}") break ;;
		*)
			assert "${pipe_func_child_exit_success}" "${ret}" "child exit status should be ${pipe_func_child_exit_success}"
			;;
		esac

		assert "${start_lines}" "${cstart}"
		assert "${start_max}" "${cmax}"
		assert_ret 0 [ "${n}" -le "${max}" ]
		assert "${lines}" "${n}" "n"
		assert "$((lines - 1))" "${n_minus_1}" "n_minus_1"
		lines=$((lines + 1))
	done
	assert "${max}" "${lines}"
}

# pipe_func with computed handle
{
	some_func() {
		set -x
		local max="$1"
		local spaced_data="$2"
		local start="$3"
		local n

		assert "spaced data" "${spaced_data}"

		n="${start}"
		until [ "${n}" -eq "${max}" ]; do
			echo "${start} ${max} ${n} $((n - 1))"
			n=$((n + 1))
			# The sleep helps demonstrate the difference in
			# a heredoc and pipe_func() in the log.
			#sleep 1
		done
		exit ${pipe_func_child_exit_success}
	}

	lines=0
	max=10
	start_lines=${lines}
	start_max=${max}
	#The while loop method would work fine but loses the child exit
	# status which we need to ensure it passed its own asserts.
	while :; do
		ret=0
		# With a computed handle we must ensure the passed in
		# params are static.
		pipe_func read cstart cmax n n_minus_1 -- \
		    some_func "${start_max}" "spaced data" "${start_lines}" || ret="$?"
		case "${ret}" in
		0) ;;
		# EOF
		"${pipe_func_child_exit_success}") break ;;
		*)
			assert "${pipe_func_child_exit_success}" "${ret}" "child exit status should be ${pipe_func_child_exit_success}"
			;;
		esac

		assert "${start_lines}" "${cstart}"
		assert "${start_max}" "${cmax}"
		assert_ret 0 [ "${n}" -le "${max}" ]
		assert "${lines}" "${n}" "n"
		assert "$((lines - 1))" "${n_minus_1}" "n_minus_1"
		lines=$((lines + 1))
	done
	assert "${max}" "${lines}"
}

if mapfile_supports_multiple_read_handles; then
# pipe_func nested
{

	some_func() {
		local max="$1"
		local start="$2"
		local n

		n="${start}"
		until [ "${n}" -eq "${max}" ]; do
			echo "${start} ${max} ${n} $((n - 1))"
			n=$((n + 1))
		done
	}

	lines=0
	max=10
	start_lines=${lines}
	start_max=${max}
	unset tmp
	while pipe_func -H tmp \
	    read cstart cmax n n_minus_1 -- \
	    some_func "$((lines + max))" "${lines}"; do
		assert "${start_lines}" "${cstart}"
		assert "${start_max}" "${cmax}"
		assert_ret 0 [ "${n}" -le "${max}" ]
		assert "${lines}" "${n}" "n"
		assert "$((lines - 1))" "${n_minus_1}" "n_minus_1"
		lines=$((lines + 1))

		nested_lines=0
		nested_max=10
		nested_start_lines=${nested_lines}
		nested_start_max=${nested_max}
		while pipe_func -H nested_tmp \
		    read nested_cstart nested_cmax nested_n nested_n_minus_1 -- \
		    some_func "$((nested_lines + nested_max))" "${nested_lines}"; do
			assert "${nested_start_lines}" "${nested_cstart}"
			assert "${nested_start_max}" "${nested_cmax}"
			assert_ret 0 [ "${nested_n}" -le "${nested_max}" ]
			assert "${nested_lines}" "${nested_n}" "nested n"
			assert "$((nested_lines - 1))" "${nested_n_minus_1}" "nested n_minus_1"
			nested_lines=$((nested_lines + 1))
		done
		assert "${nested_max}" "${nested_lines}" "nested count"

	done
	assert "${max}" "${lines}"
}

# pipe_func nested with computed handle
{

	some_func() {
		local max="$1"
		local start="$2"
		local n

		n="${start}"
		until [ "${n}" -eq "${max}" ]; do
			echo "${start} ${max} ${n} $((n - 1))"
			n=$((n + 1))
		done
	}

	lines=0
	max=10
	start_lines=${lines}
	start_max=${max}
	while pipe_func \
	    read cstart cmax n n_minus_1 -- \
	    some_func "${start_max}" "${start_lines}"; do
		assert "${start_lines}" "${cstart}"
		assert "${start_max}" "${cmax}"
		assert_ret 0 [ "${n}" -le "${max}" ]
		assert "${lines}" "${n}" "n"
		assert "$((lines - 1))" "${n_minus_1}" "n_minus_1"
		lines=$((lines + 1))

		nested_lines=0
		nested_max=10
		nested_start_lines=${nested_lines}
		nested_start_max=${nested_max}
		unset nested
		# XXX: The nested has the same params so needs a handle
		while pipe_func -H nested \
		    read nested_cstart nested_cmax nested_n nested_n_minus_1 -- \
		    some_func "${nested_start_max}" "${nested_start_lines}"; do
			assert "${nested_start_lines}" "${nested_cstart}"
			assert "${nested_start_max}" "${nested_cmax}"
			assert_ret 0 [ "${nested_n}" -le "${nested_max}" ]
			assert "${nested_lines}" "${nested_n}" "nested n"
			assert "$((nested_lines - 1))" "${nested_n_minus_1}" "nested n_minus_1"
			nested_lines=$((nested_lines + 1))
		done
		assert "${nested_max}" "${nested_lines}" "nested count"

	done
	assert "${max}" "${lines}"
}
fi
