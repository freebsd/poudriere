#!/bin/sh

usage() {
	echo "poudriere testport -d directory [-cn] [-j jailname]"
	echo "-c run make config for the given port"
	echo "-j jailname run only on the given jail"
	echo "-n no custom prefix"
	exit 1
}

outside_portsdir() {
	PORTROOT=`dirname $1`
	PORTROOT=`dirname ${PORTROOT}`
	test "${PORTROOT}" = `realpath ${PORTSDIR}` && return 1
	return 0
}

build_port() {
	echo "===>> Building ${PKGNAME}"
	for PHASE in build install package deinstall
	do
		if [ "${PHASE}" = "deinstall" ]; then
			echo "===>> Checking pkg_info"
			PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} /usr/sbin/pkg_info ${PKGNAME}
			PLIST="${PKG_DBDIR}/${PKGNAME}/+CONTENTS"
			if [ -r ${JAILBASE}${PLIST} ]; then
				echo "===>> Checking shared library dependencies"
				grep -v "^@" ${JAILBASE}${PLIST} | \
				sed -e "s,^,${PREFIX}/," | \
				xargs jexec -U root ${JAILNAME} ldd 2>&1 | \
				grep -v "not a dynamic executable" | \
				grep '=>' | awk '{ print $3;}' | sort -u
			fi
		fi
		jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} ${PORT_FLAGS} ${PHASE} PKGREPOSITORY=/tmp PACKAGES=/tmp
		if [ $? -gt 0 ]; then
			echo "===>> Error running make ${PHASE}"
			[ "${PHASE}" = "package" ] && return 0
			echo "===>> Cleaning up"
			[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX}
			rm -rf ${JAILBASE}${PKG_DBDIR}
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

while getopts "d:cnj:" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR=1
		;;
		d)
		PORTDIRECTORY=`realpath ${OPTARG}`
		;;
		n)
		NOPREFIX=1
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
	JAILBASE=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}

	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -n ${JAILNAME} || err 1 "Failed to start jail."
	STATUS=1 #injail

	prepare_jail

	if outside_portsdir ${PORTDIRECTORY}; then
		mkdir -p ${JAILBASE}/${PORTDIRECTORY}
		mount -t nullfs ${PORTDIRECTORY} ${JAILBASE}/${PORTDIRECTORY}
	fi

	(
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} extract-depends fetch-depends patch-depends build-depends lib-depends

# Package all newly build ports
	echo "===>> Packaging all dependencies"

	for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1}'`; do
		[ -f ${PKGDIR}/All/${pkg}.tbz || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
	done
	) 2>&1 | tee ${LOGS}/${PORTNAME}-${JAILNAME}.depends.log

	(
	PKGNAME=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VPKGNAME`
	PKG_DBDIR=`jexec -U root ${JAILNAME} mktemp -d -t pkg_db`
	LOCALBASE=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VLOCALBASE`
	if [ ${NOPREFIX} -eq 1 ]; then
		PREFIX=${LOCALBASE}
	else
		PREFIX="${BUILDROOT:-/tmp}/`echo ${PKGNAME} | tr '[,+]' _`"
	fi
	PORT_FLAGS="PREFIX=${PREFIX} PKG_DBDIR=${PKG_DBDIR} NO_DEPENDS=yes"
	echo "===>> Building with flags: ${PORT_FLAGS}"
	echo "===>> Cleaning workspace"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	[ $CONFIGSTR -eq 1 ] && jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} config

	if [ -d ${JAILBASE}${PREFIX} ]; then
		echo "===>> Removing existing ${PREFIX}"
		[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX}
	fi

	find ${JAILBASE}${LOCALBASE}/ -type d | sed "s,^${JAILBASE}${LOCALBASE}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.before

	build_port

	if [ $? -eq 0 ]; then
		echo "===>> Extra files and directories check"
		find ${JAILBASE}${PREFIX} ! -type d | \
		egrep -v "${JAILBASE}${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)" | \
		sed -e "s,^${JAILBASE}${PREFIX}/,,"

		find ${JAILBASE}${PREFIX}/ -type d | sed "s,^${JAILBASE}${PREFIX}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.after
		comm -13 ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
	fi

	echo "===>> Installing from package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_add /tmp/${PKGNAME}.tbz
	echo "===>> Deinstalling package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_delete ${PKGNAME}

	echo "===>> Cleaning up"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean

	echo "===>> Removing existing ${PREFIX} dir"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX} ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after
	rm -rf ${JAILBASE}${PKG_DBDIR}

	) 2>&1 | tee  ${LOGS}/${PORTNAME}-${JAILNAME}.build.log

	cleanup
	STATUS=0 #injail
done

