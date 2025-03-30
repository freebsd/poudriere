set -e
. ./common.sh
set +e

LOCKBASE=$(mktemp -dt poudriere.locked_mkdir)

assert_pid() {
	local lineno="$1"
	local lock="$2"
	local epid="$3"
	local extra="$4"
	local pid

	[ -f "${lock}.pid" ]
	assert 0 $? "${lineno}:${LINENO}: ${lock}.pid should exist ${extra}"
	# cat for adding newline
	pid=$(cat "${lock}.pid")
	assert 0 $? "${lineno}:${LINENO}: ${lock}.pid should be readable ${extra}"
	assert "${epid}" "${pid}" "${lineno}:${LINENO}: ${lock}.pid doesn't match expected pid ${extra}"
}
