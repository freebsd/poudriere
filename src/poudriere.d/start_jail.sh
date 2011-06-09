#!/bin/sh

usage() {
	echo "poudriere startjail parameters"
cat <<EOF

Parameters:
    -j name     -- Start the given jail
EOF
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

zfs list ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 "No such jail"

test -z ${IP} && err 1 "No IP defined for poudriere"

if [ "${USE_LOOPBACK}" = "yes" ]; then
        LOOP=0
        while :; do
		LOOP=$(( LOOP += 1))
		ifconfig lo${LOOP} create > /dev/null 2>&1 && break
        done
	msg "Adding loopback lo${LOOP}"
        ifconfig lo${LOOP} inet ${IP} > /dev/null 2>&1
else
        /usr/sbin/jls ip4.addr | egrep "^${IP}$" > /dev/null && err 2 "Configured IP is already in use by another jail."
	test -z ${ETH} && err 1 "No ethernet device defined for poudriere"
fi

MNT=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${NAME}`
msg "Mounting devfs"
devfs_mount_jail "${MNT}/dev"
msg "Mounting /proc"
[ ! -d ${MNT}/proc ] && mkdir ${MNT}/proc
mount -t procfs proc ${MNT}/proc
msg "Mounting linuxfs"
[ ! -d ${MNT}/compat/linux/proc ] && mkdir -p ${MNT}/compat/linux/proc
[ ! -d ${MNT}/compat/linux/sys ] && mkdir -p ${MNT}/compat/linux/sys
mount -t linprocfs linprocfs ${MNT}/compat/linux/proc
mount -t linsysfs linsysfs ${MNT}/compat/linux/sys
if [ ! "${USE_LOOPBACK}" = "yes" ]; then
	msg "Adding IP alias"
	ifconfig ${ETH} inet ${IP} alias > /dev/null 2>&1
fi
msg "Starting jail ${NAME}"
jail -c persist name=${NAME} path=${MNT} host.hostname=${NAME} ip4.addr=${IP} \
allow.sysvipc allow.raw_sockets allow.socket_af allow.mount
