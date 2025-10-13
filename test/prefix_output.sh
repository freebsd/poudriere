set -e
. ./common.sh
set +e

# Override common.sh msg_warn
msg_warn() {
	echo "$@" >&2
}

msg() {
	echo "$@"
}

test_output() {
	local ret="$1"

	echo "test stdout 1"
	echo "test stderr 1" >&2
	echo "test stdout 2"
	echo "test stderr 2" >&2
	return "${ret}"
}

# Test twice. With and Without timestamp util.
set_test_contexts - '' '' <<-EOF
USE_TIMESTAMP 0 1
EOF

while get_test_context; do
	OUTPUT=$(mktemp -ut poudriere)

	if [ "${USE_TIMESTAMP}" -eq 1 ]; then
		TS="[00:00:00] "
	fi

	# Basic output test with prefix_stderr_quick
	(
		have_pipefail || echo "SKIP: Shell does not support pipefail" >&2
		prefix_stderr_quick "STDERR" test_output 0 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr_quick test_output 0 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		test stdout 1
		test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr_quick stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		STDERR: test stderr 1
		STDERR: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr_quick stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# Basic output test with prefix_stdout
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_stdout "STDOUT" test_output 0 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stdout test_output 0 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDOUT: test stdout 1
		${TS}STDOUT: test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stdout stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		test stderr 1
		test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stdout stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# Basic output test with prefix_stderr
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_stderr "STDERR" test_output 0 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr test_output 0 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		test stdout 1
		test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDERR: test stderr 1
		${TS}STDERR: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# Basic output test with prefix_output
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_output "OUTPUT" test_output 0 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_output test_output 0 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}OUTPUT: test stdout 1
		${TS}OUTPUT: test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_output stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}OUTPUT: test stderr 1
		${TS}OUTPUT: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_output stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# Basic output test with chaining prefix_stderr and prefix_stdout
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_stderr "STDERR" prefix_stdout "STDOUT" test_output 0 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr+prefix_stdout test_output 0 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDOUT: test stdout 1
		${TS}STDOUT: test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr+prefix_stdout stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDERR: test stderr 1
		${TS}STDERR: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr+prefix_stdout stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# Now test exit statuses (pipefail and such)

	# Pipefail test with prefix_stderr_quick
	(
		have_pipefail || echo "SKIP: Shell does not support pipefail" >&2
		TIME_START=$(clock -monotonic -nsec)
		prefix_stderr_quick "STDERR" test_output 5 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 5 $? "ts=${USE_TIMESTAMP} prefix_stderr_quick test_output 5 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		test stdout 1
		test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr_quick/5 stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		STDERR: test stderr 1
		STDERR: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr_quick/5 stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# pipefail test with prefix_stdout
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_stdout "STDOUT" test_output 5 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 5 $? "ts=${USE_TIMESTAMP} prefix_stdout test_output 5 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDOUT: test stdout 1
		${TS}STDOUT: test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stdout/5 stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		test stderr 1
		test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stdout/5 stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# pipefail test with prefix_stderr
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_stderr "STDERR" test_output 5 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 5 $? "ts=${USE_TIMESTAMP} prefix_stderr test_output 5 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		test stdout 1
		test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr/5 stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDERR: test stderr 1
		${TS}STDERR: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr/5 stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# pipefail test with prefix_output
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_output "OUTPUT" test_output 5 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 5 $? "ts=${USE_TIMESTAMP} prefix_output test_output 5 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}OUTPUT: test stdout 1
		${TS}OUTPUT: test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_output/5 stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}OUTPUT: test stderr 1
		${TS}OUTPUT: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_output/5 stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"

	# pipefail test with chaining prefix_stderr and prefix_stdout
	(
		TIME_START=$(clock -monotonic -nsec)
		prefix_stderr "STDERR" prefix_stdout "STDOUT" test_output 5 \
		    > "${OUTPUT}" 2> "${OUTPUT}.stderr"
		assert 5 $? "ts=${USE_TIMESTAMP} prefix_stderr+prefix_stdout test_output 5 wrong exit status"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDOUT: test stdout 1
		${TS}STDOUT: test stdout 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr+prefix_stdout/5 stdout output should match"

		cat > "${OUTPUT}.expected" <<-EOF
		${TS}STDERR: test stderr 1
		${TS}STDERR: test stderr 2
		EOF
		diff -u "${OUTPUT}.expected" "${OUTPUT}.stderr"
		assert 0 $? "ts=${USE_TIMESTAMP} prefix_stderr+prefix_stdout/5 stderr output should match"
	)
	ret=$?
	cat "${OUTPUT}" || :
	cat "${OUTPUT}.stderr" >&2 || :
	assert 0 "${ret}"
	rm -f "${OUTPUT}" "${OUTPUT}.stderr" "${OUTPUT}.expected"
done
