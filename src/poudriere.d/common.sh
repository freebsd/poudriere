#!/bin/sh

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	echo "$2"
	exit $1
}

test -f /usr/local/etc/poudriere.conf || err 1 "Unable to find /usr/local/etc/poudriere.conf"
. /usr/local/etc/poudriere.conf

test -z $ZPOOL && err 1 "ZPOOL variable is not set"

# Test if spool exists
zpool list $ZPOOL >/dev/null 2>&1 || err 1 "No such zpool : $ZPOOL"
