. ./common.sh

trap '' SIGINFO

STDOUT=$(mktemp -ut stdout)
STDERR=$(mktemp -ut stderr)

add_test_function test_timestamp_1
test_timestamp_1() {
	timestamp -T -1 stdout -2 stderr \
	    sh -c "echo stuff; echo errors>&2; echo more; echo 'more errors' >&2" \
	    >${STDOUT} 2>${STDERR}
	cat > "${STDOUT}".expected <<-EOF
	stdout stuff
	stdout more
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	stderr errors
	stderr more errors
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

# Prefix changing
add_test_function test_timestamp_2
test_timestamp_2() {
	timestamp -T -1 stdout -2 stderr \
	    sh -c "\
	    echo stuff; \
	    echo errors>&2; \
	    echo $'\001'PX:[blah]; \
	    echo errors>&2; \
	    echo $'\001'PXfalse; \
	    echo stuff; \
	    echo $'\001'PX:NEWPREFIX; \
	    echo end; \
	    " \
	    >${STDOUT} 2>${STDERR}
	one=$'\001'
	cat > "${STDOUT}".expected <<-EOF
	stdout stuff
	stdout ${one}PX:[blah]
	stdout ${one}PXfalse
	stdout stuff
	stdout ${one}PX:NEWPREFIX
	stdout end
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	stderr errors
	stderr errors
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

# Prefix changing
add_test_function test_timestamp_3
test_timestamp_3() {
	timestamp -D -T -1 stdout -2 stderr \
	    sh -c "\
	    echo stuff; \
	    echo errors>&2; \
	    echo $'\001'PX:[blah]; \
	    echo errors>&2; \
	    echo $'\001'PXfalse; \
	    echo stuff; \
	    echo $'\001'PX:NEWPREFIX; \
	    echo end; \
	    " \
	    >${STDOUT} 2>${STDERR}
	one=$'\001'
	cat > "${STDOUT}".expected <<-EOF
	stdout stuff
	[blah] ${one}PXfalse
	[blah] stuff
	NEWPREFIX end
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	stderr errors
	stderr errors
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

add_test_function test_timestamp_4
test_timestamp_4() {
	TIME_START=$(clock -monotonic -nsec)
	sleep 3.1 >/dev/null 2>&1
	TIME_START=${TIME_START} timestamp \
	    sh -c 'echo start' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	assert_file_reg - "${STDOUT}" <<-EOF
	\[00:00:0[345]\] start
	EOF

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

add_test_function test_timestamp_5
test_timestamp_5() {
	TIME_START=$(clock -monotonic -nsec)
	sleep 3.1 >/dev/null 2>&1
	TIME_START=${TIME_START} timestamp -t \
	    sh -c 'echo start' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	assert_file_reg - "${STDOUT}" <<-EOF
	\[00:00:0[345]\] \(00:00:00\) start
	EOF

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

add_test_function test_timestamp_6
test_timestamp_6() {
	TIME_START=$(clock -monotonic -nsec)
	sleep 3.1 >/dev/null 2>&1
	TIME_START=${TIME_START} timestamp -t \
	    sh -c 'echo start; sleep 3.1 >/dev/null 2>&1; echo end' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	assert_file_reg - "${STDOUT}" <<-EOF
	\[00:00:0[345]\] \(00:00:00\) start
	\[00:00:0[678]\] \(00:00:0[345]\) end
	EOF

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

# durations
add_test_function test_timestamp_7
test_timestamp_7() {
	TIME_START=$(clock -monotonic -nsec)
	TIME_START=${TIME_START} timestamp -t \
	    sh -c 'echo start;(sleep 3.1 >/dev/null 2>&1; echo bg; sleep 3.1 >/dev/null 2>&1; echo done) & echo hi' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	assert_file_reg - "${STDOUT}" <<-EOF
	\[00:00:00\] \(00:00:00\) start
	\[00:00:00\] \(00:00:00\) hi
	\[00:00:0[345]\] \(00:00:0[345]\) bg
	\[00:00:0[678]\] \(00:00:0[345]\) done
	EOF


	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
}

add_test_function test_timestamp_forwards_sigterm
test_timestamp_forwards_sigterm() {
	TMP="$(mktemp -ut timestamp_sigterm)"
	doit() {
		local TMP="$1"
		timestamp \
		    sh -c "echo \"${TMP}\"; trap 'echo 143>\"${TMP}\"' TERM; :>${READY_FILE:?}; sleep 20" \
		    >${STDOUT} 2>${STDERR}
	}
	assert_true spawn_job doit "${TMP}"
	assert_not '' "${spawn_pgid}"
	assert_true cond_timedwait 3
	# Must not use kill_job here as that would send SIGTERM to the
	# sh process as well. We are explicitly testing that timestamp
	# forwards the SIGTERM, and that it allows the child to finish
	# and exits cleanly.
	assert_runs_shorter_than 5 assert_ret 0 \
	    kill_and_wait 3 "${spawn_pgid}"
	assert_file_reg - "${STDERR}" <<-EOF
	timestamp: killing child pid [0-9]+ with SIGTERM
	EOF
	assert_file - "${STDOUT}" <<-EOF
	[00:00:00] ${TMP}
	EOF
	assert_file - "${TMP}" <<-EOF
	143
	EOF
}

run_test_functions

rm -f ${STDOUT}* ${STDERR}*
