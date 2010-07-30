#!/bin/sh

usage() {
	echo "poudriere startJail -n name"
	exit 1
}

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	echo "$2"
	exit $1
}

test -f /usr/local/etc/poudriere.conf || err 1 "Unable to find /usr/local/etc/poudriere.conf"
. /usr/local/etc/poudriere.conf
. /etc/rc.subr
. /etc/defaults/rc.conf
test -z $ZPOOL && err 1 "ZPOOL variable is not set"
# Test if spool exists
zpool list $ZPOOL >/dev/null 2>&1 || err 1 "No such zpool : $ZPOOL"


while getopts "n:" FLAG; do
	case "$FLAG" in 
		n)
		NAME=$OPTARG
		;;
		*)
		usage
		;;
	esac
done

test -z $NAME && usage

jls -j $NAME >/dev/null 2>&1 || err 1 "No such jail: $NAME"

MNT=`zfs list -H $ZPOOL/poudriere/$NAME | awk '{ print $NF}'`
echo "====> Stopping jail"
jail -r $NAME
echo "====> Uounting devfs"
umount -f ${MNT}/dev
echo "====> Removing IP alias"
ifconfig $ETH inet $IP -alias
