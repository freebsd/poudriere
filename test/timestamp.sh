. ./common.sh

trap '' SIGINFO

STDOUT=$(mktemp -ut poudriere)
STDERR=$(mktemp -ut poudriere)

(
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
)
assert 0 "$?"

# Prefix changing
(
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
)
assert 0 "$?"

# Prefix changing
(
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
)
assert 0 "$?"

(
	TIME_START=$(clock -monotonic -nsec)
	sleep 3.1 >/dev/null 2>&1
	TIME_START=${TIME_START} timestamp \
	    sh -c 'echo start' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	cat > "${STDOUT}".expected <<-EOF
	[00:00:03] start
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
)
assert 0 "$?"

(
	TIME_START=$(clock -monotonic -nsec)
	sleep 3.1 >/dev/null 2>&1
	TIME_START=${TIME_START} timestamp -t \
	    sh -c 'echo start' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	cat > "${STDOUT}".expected <<-EOF
	[00:00:03] (00:00:00) start
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
)
assert 0 "$?"

(
	TIME_START=$(clock -monotonic -nsec)
	sleep 3.1 >/dev/null 2>&1
	TIME_START=${TIME_START} timestamp -t \
	    sh -c 'echo start; sleep 3.1 >/dev/null 2>&1; echo end' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	cat > "${STDOUT}".expected <<-EOF
	[00:00:03] (00:00:00) start
	[00:00:06] (00:00:03) end
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
)
assert 0 "$?"

# durations
(
	TIME_START=$(clock -monotonic -nsec)
	TIME_START=${TIME_START} timestamp -t \
	    sh -c 'echo start;(sleep 3.1 >/dev/null 2>&1; echo bg; sleep 3.1 >/dev/null 2>&1; echo done) & echo hi' \
	    >${STDOUT} 2>${STDERR}
	assert 0 $? "$0:${LINENO}: incorrect exit status"

	cat > "${STDOUT}".expected <<-EOF
	[00:00:00] (00:00:00) start
	[00:00:00] (00:00:00) hi
	[00:00:03] (00:00:03) bg
	[00:00:06] (00:00:03) done
	EOF
	diff -u "${STDOUT}.expected" "${STDOUT}"
	assert 0 $? "$0:${LINENO}: stdout output mismatch"

	cat > "${STDERR}".expected <<-EOF
	EOF
	diff -u "${STDERR}.expected" "${STDERR}"
	assert 0 $? "$0:${LINENO}: stderr output mismatch"
)
assert 0 "$?"

rm -f ${STDOUT}* ${STDERR}*
