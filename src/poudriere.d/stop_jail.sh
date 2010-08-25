#!/bin/sh

usage() {
	echo "poudriere stopjail -n name"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname $SCRIPTPATH`
. ${SCRIPTPREFIX}/common.sh

. /etc/rc.subr
. /etc/defaults/rc.conf


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
zfs rollback $ZPOOL/poudriere/${NAME}@clean
