#!/bin/sh

usage() {
	echo "poudriere startjail -n name"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

. /etc/rc.subr
. /etc/defaults/rc.conf

while getopts "n:" FLAG; do
	case "${FLAG}" in 
		n)
		NAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

zfs list ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 "No such jail"

test -z ${IP} && err 1 "No IP defined for poudriere"
test -z ${ETH} && err 1 "No ethernet device defined for poudriere"

MNT=`zfs list -H ${ZPOOL}/poudriere/${NAME} | awk '{ print $NF}'`
msg "Mounting devfs"
devfs_mount_jail "${MNT}/dev"
msg "Adding IP alias"
ifconfig ${ETH} inet ${IP} alias
msg "Starting jail ${NAME}"
jail -c persist name=${NAME} path=${MNT} host.hostname=${NAME} ip4.addr=${IP}
