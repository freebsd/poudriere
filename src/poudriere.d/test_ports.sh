#!/bin/sh

usage() {
	echo "poudriere testport -d directory [-cn] [-j jailname]"
	echo "-c run make config for the given port"
	echo "-j jailname run only on the given jail"
	echo "-n no custom prefix"
	exit 1
}

build_port() {
	msg "Building ${PKGNAME}"
	for PHASE in build install package deinstall
	do
		if [ "${PHASE}" = "deinstall" ]; then
			msg "Checking pkg_info"
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
			msg "Error running make ${PHASE}"
			[ "${PHASE}" = "package" ] && return 0
			msg "Cleaning up"
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
		JAILNAMES="${JAILNAMES} ${OPTARG}"
		;;
		*)
		usage
		;;
	esac
done

test -z ${PORTDIRECTORY} && usage
PORTNAME=`make -C ${PORTDIRECTORY} -VPKGNAME`

test -z "${JAILNAMES}" && JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`

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

	tee ${LOGS}/${PORTNAME}-${JAILNAME}.depends.log &
	TEEPID=$!
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} extract-depends \
		fetch-depends patch-depends build-depends lib-depends \
		| tee ${LOGS}/${PORTNAME}-${JAILNAME}.depends.log || err 1 "an error occur while building the dependencies"

# Package all newly build ports
	msg "Packaging all dependencies"
	for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1}'`; do
		[ -f ${PKGDIR}/All/${pkg}.tbz ] || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
	done

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
	msg "Building with flags: ${PORT_FLAGS}"
	msg "Cleaning workspace"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	[ $CONFIGSTR -eq 1 ] && jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} config

	if [ -d ${JAILBASE}${PREFIX} ]; then
		msg "Removing existing ${PREFIX}"
		[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX}
	fi

	find ${JAILBASE}${LOCALBASE}/ -type d | sed "s,^${JAILBASE}${LOCALBASE}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.before

	if build_port; then
		msg "Extra files and directories check"
		find ${JAILBASE}${PREFIX} ! -type d | \
		egrep -v "${JAILBASE}${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)" | \
		sed -e "s,^${JAILBASE}${PREFIX}/,,"

		find ${JAILBASE}${PREFIX}/ -type d | sed "s,^${JAILBASE}${PREFIX}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.after
		comm -13 ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
	fi

	msg "Installing from package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_add /tmp/${PKGNAME}.tbz
	msg "Deinstalling package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_delete ${PKGNAME}

	msg "Cleaning up"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean

	msg "Removing existing ${PREFIX} dir"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX} ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after
	rm -rf ${JAILBASE}${PKG_DBDIR}

	) 2>&1 | tee  ${LOGS}/${PORTNAME}-${JAILNAME}.build.log

	cleanup
	STATUS=0 #injail
done

