#!/bin/sh

usage() {
	echo "poudriere testport -d directory [-c]"
	echo "-c run make config for the given port"
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

		echo "====>> Signal caught, cleaning up and exiting"
		cleanup
		exit 0
	fi
}

build_port() {
	echo "===>> Building ${PKGNAME}"
	for PHASE in build install package deinstall
	do
		if [ "${PHASE}" = "deinstall" ]; then
			echo "===>> Checking pkg_info"
			PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} /usr/sbin/pkg_info ${PKGNAME}
			PLIST="${PKG_DBDIR}/${PKGNAME}/+CONTENTS"
			if [ -r ${MNT}${PLIST} ]; then
				echo "===>> Checking shared library dependencies"
				grep -v "^@" ${MNT}${PLIST} | \
				sed -e "s,^,${PREFIX}/," | \
				xargs jexec -U root ${JAILNAME} ldd 2>&1 | \
				grep -v "not a dynamic executable" | \
				grep '=>' | awk '{ print $3;}' | sort -u
			fi
		fi
		jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} ${PORT_FLAGS} ${PHASE} PKGREPOSITORY=/tmp PACKAGES=/tmp
		if [ $? -gt 0 ]; then
			echo "===>> Error running make ${PHASE}"
			if [ "${PHASE}" = "package" ]; then
				echo "===>> Files currently installed in PREFIX"
				test -d ${MNT}${PREFIX} && find ${MNT}${PREFIX} ! - type d | \
				egrep -v "${MNT}${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)" | \
				sed -e "s,^${MNT}${PREFIX}/,,"
			fi
			echo "===>> Cleaning up"
			[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${MNT}${PREFIX}
			rm -rf ${MNT}${PKG_DBDIR}
			return 1
		fi
	done
	return 0
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "d:c" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR=1
		;;
		d)
		PORTDIRECTORY=`realpath ${OPTARG}`
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
for JAILNAME in `zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`; do
	MNT=`zfs list -H ${ZPOOL}/poudriere/${JAILNAME} | awk '{ print $NF}'`
	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -n ${JAILNAME}
	STATUS=1 #injail
	mount -t nullfs ${PORTSDIR} ${MNT}/usr/ports
	mount -t nullfs ${POUDRIERE_DATA}/packages/${JAILNAME} ${MNT}/usr/ports/packages

	test -n "${MFSSIZE}" && mdmfs -M -S -o async -s ${MFSSIZE} md ${MNT}/wrkdirs

	if [ -n "${CUSTOMCONFIG}" ]; then
		test -f ${CUSTOMCONFIG} && cat ${CUSTOMCONFIG} >> ${MNT}/etc/make.conf
	fi

	if outside_portsdir ${PORTDIRECTORY}; then
		mkdir -p ${MNT}/${PORTDIRECTORY}
		mount -t nullfs ${PORTDIRECTORY} ${MNT}/${PORTDIRECTORY}
	fi

	echo "===>> Populating LOCALBASE"
	jexec -U root ${JAILNAME} /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p /usr/local >/dev/null

	(
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} extract-depends fetch-depends patch-depends build-depends lib-depends
# Package all newly build ports
	echo "===>> Packaging all dependencies"
	for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1}'`; do
		test -f ${POUDRIERE_DATA}/packages/${JAILNAME}/All/${pkg}.tbz || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
	done
	) 2>&1 | tee ${LOGS}/${PORTNAME}-${JAILNAME}.depends.log

	(
	PKGNAME=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VPKGNAME`
	PKG_DBDIR=`jexec -U root ${JAILNAME} mktemp -d -t pkg_db`
	LOCALBASE=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VLOCALBASE`
	PREFIX="${BUILDROOT:-/tmp}/`echo ${PKGNAME} | tr '[,+]' _`"
	PORT_FLAGS="PREFIX=${PREFIX} PKG_DBDIR=${PKG_DBDIR} NO_DEPENDS=yes"
	echo "===>> Building with flags: ${PORT_FLAGS}"
	echo "===>> Cleaning workspace"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	[ $CONFIGSTR -eq 1 ] && jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} config

	if [ -d ${MNT}${PREFIX} ]; then
		echo "===>> Removing existing ${PREFIX}"
		[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${MNT}${PREFIX}
	fi

	build_port
	if [ $? -eq 0 ]; then
		echo "===>> Extra files and directories check"
		find ${MNT}${PREFIX} ! -type d | \
		egrep -v "${MNT}${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)" | \
		sed -e "s,^${MNT}${PREFIX}/,,"

		find ${MNT}${LOCALBASE}/ -type d | sed "s,^${MNT}${LOCALBASE}/,," | sort > ${MNT}${PREFIX}.PLIST_DIRS.before
		find ${MNT}${PREFIX}/ -type d | sed "s,^${MNT}${PREFIX}/,," | sort > ${MNT}${PREFIX}.PLIST_DIRS.after
		comm -13 ${MNT}${PREFIX}.PLIST_DIRS.before ${MNT}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
	fi

	echo "===>> Installing from package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_add /tmp/${PKGNAME}.tbz
	echo "===>> Deinstalling package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_delete ${PKGNAME}

	echo "===>> Cleaning up"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean

	echo "===>> Removing existing ${PREFIX} dir"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${MNT}${PREFIX} ${MNT}${PREFIX}.PLIST_DIRS.before ${MNT}${PREFIX}.PLIST_DIRS.after
	rm -rf ${MNT}${PKG_DBDIR}

	) 2>&1 | tee  ${LOGS}/${PORTNAME}-${JAILNAME}.build.log

	cleanup
	STATUS=0 #injail
done

