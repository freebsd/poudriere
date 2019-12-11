#! /bin/sh

set -e
. common.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/parallel.sh
. ${SCRIPTPREFIX}/include/util.sh
set +e

# Override common.sh msg_warn
msg_warn() {
	echo "$@" >&2
}

test_output() {
	local ret="$1"

	echo "test stdout 1"
	echo "test stderr 1" >&2
	echo "test stdout 2"
	echo "test stderr 2" >&2
	return "${ret}"
}

OUTPUT=$(mktemp -ut poudriere)
ret=0

# Test twice. With and Without timestamp util.
USE_TIMESTAMP=0
until [ "${USE_TIMESTAMP}" -eq 2 ]; do

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
	) || ret=1

	# Basic output test with prefix_stdout
	(
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
	) || ret=2

	# Basic output test with prefix_stderr
	(
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
	) || ret=3

	# Basic output test with prefix_output
	(
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
	) || ret=4

	# Basic output test with chaining prefix_stderr and prefix_stdout
	(
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
	) || ret=5

	# Now test exit statuses (pipefail and such)

	# Pipefail test with prefix_stderr_quick
	(
		have_pipefail || echo "SKIP: Shell does not support pipefail" >&2
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
	) || ret=6

	# pipefail test with prefix_stdout
	(
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
	) || ret=7

	# pipefail test with prefix_stderr
	(
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
	) || ret=8

	# pipefail test with prefix_output
	(
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
	) || ret=9

	# pipefail test with chaining prefix_stderr and prefix_stdout
	(
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
	) || ret=10

	USE_TIMESTAMP=$((USE_TIMESTAMP + 1))
done

rm "${OUTPUT}" "${OUTPUT}.stderr" "${OUTPUT}.expected"
exit "${ret}"
