#! /bin/sh

: ${SH:=$(procstat -f $$ | awk '$3 == "text" { print $10 }')}
: ${TIMEOUT:=90}

exec /usr/bin/timeout ${TIMEOUT} ../timestamp ${SH} "$@"
