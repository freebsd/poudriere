#!/bin/sh

usage() {
	echo "poudriere genpkg -d directory [-c] [-j jailname]"
	echo "-c run make config for the given port"
	echo "-j jailname run only on the given jail"
	exit 1
}

outside_portsdir() {
	PORTROOT=`dirname $1`
	PORTROOT=`dirname ${PORTROOT}`
	test "${PORTROOT}" = `realpath ${PORTSDIR}` && return 1
	return 0
}

cleanup() {
	outside_portsdir ${PORTDIRECTORY} && umount ${PORTDIRECTORY}
	umount ${MNT}/usr/ports/packages
	umount ${MNT}/usr/ports
	test -n "${MFSSIZE}" && {
		MDUNIT=`mount | egrep "${MNT}/*/wrkdirs" | awk '{ print $1 }' | sed -e "s,/dev/md,,g"`
		umount ${MNT}/wrkdirs
		mdconfig -d -u ${MDUNIT}
	}
	/bin/sh ${SCRIPTPREFIX}/stop_jail.sh -n ${JAILNAME}
}

sig_handler() {
	if [ ${STATUS} -eq 1 ]; then
		msg "Signal caught, cleaning up and exiting"
		cleanup
		exit 0
	fi
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "d:cnj:" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR=1
		;;
		d)
		PORTDIRECTORY=`realpath ${OPTARG}`
		;;
		j)
		zfs list ${ZPOOL}/poudriere/${OPTARG} >/dev/null 2>&1 || err 1 "No such jail: ${OPTARG}"
		JAILNAMES="${OPTARG}"
		;;
		*)
		usage
		;;
	esac
done

STATUS=0 # out of jail #

trap sig_handler SIGINT SIGTERM SIGKILL

test -z ${PORTDIRECTORY} && usage
PORTNAME=`make -C ${PORTDIRECTORY} -VPKGNAME`

test -z ${JAILNAMES} && JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`

for JAILNAME in ${JAILNAMES}; do
	MNT=`zfs list -H ${ZPOOL}/poudriere/${JAILNAME} | awk '{ print $NF}'`
	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -n ${JAILNAME}
	STATUS=1 #injail
	mount -t nullfs ${PORTSDIR} ${MNT}/usr/ports
	test -d ${MNT}/usr/ports/packages || mkdir ${MNT}/usr/ports/packages
	mount -t nullfs ${POUDRIERE_DATA}/packages/${JAILNAME} ${MNT}/usr/ports/packages

	test -n "${MFSSIZE}" && mdmfs -M -S -o async -s ${MFSSIZE} md ${MNT}/wrkdirs

	if [ -n "${CUSTOMCONFIG}" ]; then
		test -f ${CUSTOMCONFIG} && cat ${CUSTOMCONFIG} >> ${MNT}/etc/make.conf
	fi

	if outside_portsdir ${PORTDIRECTORY}; then
		mkdir -p ${MNT}/${PORTDIRECTORY}
		mount -t nullfs ${PORTDIRECTORY} ${MNT}/${PORTDIRECTORY}
	fi

	msg "Populating LOCALBASE"
	jexec -U root ${JAILNAME} /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p /usr/local >/dev/null

	(
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} extract-depends fetch-depends patch-depends build-depends lib-depends
# Package all newly build ports
	msg "Packaging all dependencies"
	for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1}'`; do
		test -f ${POUDRIERE_DATA}/packages/${JAILNAME}/All/${pkg}.tbz || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
	done
	) 2>&1 | tee ${LOGS}/${PORTNAME}-${JAILNAME}.depends.pkg.log

	(
	PKGNAME=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VPKGNAME`

	msg "Cleaning workspace"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean

	if jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} install; then
		msg "Packaging ${PORTNAME}"
		jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${PORTNAME} /usr/ports/packages/All/${PORTNAME}.tbz
	fi

	msg "Cleaning up"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	) 2>&1 | tee  ${LOGS}/${PORTNAME}-${JAILNAME}.pkg.log

	cleanup
	STATUS=0 #injail
done
