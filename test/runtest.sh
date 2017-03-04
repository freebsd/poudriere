#! /bin/sh

: ${SH:=$(procstat -f $$ | awk '$3 == "text" { print $10 }')}
: ${TIMEOUT:=30}

exec /usr/bin/timeout ${TIMEOUT} ../timestamp ${SH} "$@"
