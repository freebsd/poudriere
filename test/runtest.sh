#! /bin/sh

: ${SH:=$(procstat -f $$ | awk '$3 == "text" { print $10 }')}
: ${TIMEOUT:=30}

prefix_timestamp_pipe() {
	exec ../timestamp
}
stdout=$(mktemp -ut runtest.stdout)
mkfifo "${stdout}"
stderr=$(mktemp -ut runtest.stderr)
mkfifo "${stderr}"
../timestamp < "${stdout}" &
pids="${pids}${pids:+ }$!"
../timestamp < "${stderr}" >&2 &
pids="${pids}${pids:+ }$!"

# Pass log through fd so we can remove the fifos right away to avoid
# leftovers; no traps needed.
exec 3>"${stdout}" 4>"${stderr}"
rm -f "${stdout}" "${stderr}" >/dev/null 2>&1 || :
ret=0
/usr/bin/timeout ${TIMEOUT} ${SH} "$@" >&3 2>&4 || ret=$?
exec 3>&- 4>&-
kill -9 ${pids} >/dev/null 2>&1 || :
exit ${ret}
