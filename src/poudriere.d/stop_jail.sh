#!/bin/sh

usage() {
	echo "poudriere stopjail -j jailname"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

. /etc/rc.subr
. /etc/defaults/rc.conf


while getopts "j:" FLAG; do
	case "${FLAG}" in
		j)
		NAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

jls -j ${NAME} >/dev/null 2>&1 || err 1 "No such jail: ${NAME}"

MNT=`zfs list -H ${ZPOOL}/poudriere/${NAME} | awk '{ print $NF}'`
msg "Stopping jail"
jail -r ${NAME}
msg "Unmounting devfs"
umount -f ${MNT}/dev
if [ "${USE_LOOPBACK}" = "yes" ]; then
	LOOP=0
	while :; do
		LOOP=$(( LOOP += 1))
		if ifconfig lo${LOOP} | grep ${IP} > /dev/null 2>&1 ; then
			msg "Removing loopback lo${LOOP}"
			ifconfig lo${LOOP} destroy && break
		fi
	done
else
	msg "Removing IP alias ${NAME}"
	ifconfig ${ETH} inet ${IP} -alias
fi
zfs rollback ${ZPOOL}/poudriere/${NAME}@clean
