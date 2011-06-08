#!/bin/sh

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	[ ${STATUS} -eq 1 ] && cleanup
	echo "$2"
	exit $1
}

msg_n() {
	echo -n "====>> $1"
}

msg() {
	echo "====>> $1"
}

sig_handler() {
	if [ ${STATUS} -eq 1 ]; then
		msg "Signal caught, cleaning up and exiting"
		cleanup
	fi
	return ${STATUS}
}

cleanup() {
	[ -e ${PIPE} ] && rm -f ${PIPE}
	zfs destroy ${ZPOOL}/poudriere/${JAILNAME}@bulk 2>/dev/null || :
	for MNT in $( mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /devfs/ && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do
		umount -f ${MNT}
	done

	if [ "${MFSSIZE}" ]; then
		MDUNIT=$(mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 ~ /\/dev\/md/ ) { sub(/\/dev\/md/, "", $1); print $1 }}')
		umount ${JAILBASE}/wrkdirs
		mdconfig -d -u ${MDUNIT}
	fi

	/bin/sh ${SCRIPTPREFIX}/stop_jail.sh -j ${JAILNAME}
}

prepare_jail() {
	zfs list -r ${ZPOOL}/poudriere/ports-${PTNAME} >/dev/null 2>&1 || err 2 "No such ports tree ${PTNAME}"
	PORTSDIR="$(zfs list -rH ${ZPOOL}/poudriere/ports-${PTNAME} | awk '{ print $NF }')/ports"
	[ -z "${JAILBASE}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

	mount -t nullfs ${PORTSDIR} ${JAILBASE}/usr/ports || err 1 "Failed to mount the ports directory "

	[ -d ${PORTSDIR}/packages ] || mkdir -p ${PORTSDIR}/packages
	[ -d ${PKGDIR}/All ] || mkdir -p ${PKGDIR}/All

	mount -t nullfs ${PKGDIR} ${JAILBASE}/usr/ports/packages || err 1 "Failed to mount the packages directory "

	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILBASE}/wrkdirs
	[ -n "${USR_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILBASE}/wrkdirs

	if [ -d /usr/local/etc/poudriere.d ]; then
		[ -f /usr/local/etc/poudriere.d/make.conf ] && cat /usr/local/etc/poudriere.d/make.conf >> ${JAILBASE}/etc/make.conf
		[ -f /usr/local/etc/poudriere.d/${JAILNAME}-make.conf ] && cat /usr/local/etc/poudriere.d/${JAILNAME}-make.conf >> ${JAILBASE}/etc/make.conf
	fi

	msg "Populating LOCALBASE"
	jexec -U root ${JAILNAME} /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p /usr/local >/dev/null
}

outside_portsdir() {
	PORTROOT=`dirname $1`
	PORTROOT=`dirname ${PORTROOT}`
	test "${PORTROOT}" = `realpath ${PORTSDIR}` && return 1
	return 0
}


test -f /usr/local/etc/poudriere.conf || err 1 "Unable to find /usr/local/etc/poudriere.conf"
. /usr/local/etc/poudriere.conf

test -z ${ZPOOL} && err 1 "ZPOOL variable is not set"

trap sig_handler SIGINT SIGTERM SIGKILL EXIT

PIPE=/tmp/poudriere.pipe
STATUS=0 # out of jail #
LOGS="${POUDRIERE_DATA}/logs"


# Test if spool exists
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool : ${ZPOOL}"
ZVERSION=$(zpool get version ${ZPOOL} | awk '/^'${ZPOOL}'/ { print $3 }')
