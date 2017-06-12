#! /bin/sh

: ${SH:=$(procstat -f $$ | awk '$3 == "text" { print $10 }')}
case "$1" in
bulk*.sh)
	: ${TIMEOUT:=3600}
	;;
esac
: ${TIMEOUT:=90}

[ -t 0 ] && export FORCE_COLORS=1

exec /usr/bin/timeout ${TIMEOUT} ../timestamp ${SH} "$@"
