#!/bin/sh
set -e

usage() {
	echo "poudriere genpkg -d directory [-c] [-j jailname] [-p portstree]"
	echo "-c run make config for the given port"
	echo "-j <jailname> run only on the given jail"
	echo "-p <portstree> use portstree \"portstree\""
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
PTNAME="default"
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "d:cnj:p:" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR=1
		;;
		d)
		PORTDIRECTORY=`realpath ${OPTARG}`
		;;
		j)
		zfs list ${ZPOOL}/poudriere/${OPTARG} >/dev/null 2>&1 || err 1 "No such jail: ${OPTARG}"
		JAILNAMES="${JAILNAMES} ${OPTARG}"
		;;
		p)
			PTNAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${PORTDIRECTORY} && usage
PORTNAME=`make -C ${PORTDIRECTORY} -VPKGNAME`

test -z ${JAILNAMES} && JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`

for JAILNAME in ${JAILNAMES}; do
	JAILBASE=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}
	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -j ${JAILNAME}

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
