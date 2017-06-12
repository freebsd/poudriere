#! /bin/sh

: ${SH:=$(procstat -f $$ | awk '$3 == "text" { print $10 }')}
: ${TIMEOUT:=90}

[ -t 0 ] && export FORCE_COLORS=1

exec /usr/bin/timeout ${TIMEOUT} ../timestamp ${SH} "$@"
