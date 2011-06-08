#!/bin/sh
set -e

usage() {
	echo "poudriere testport -d directory [-cn] [-j jailname] [-p portstree]"
	echo "-c run make config for the given port"
	echo "-j jailname: run only on the given jail"
	echo "-n no custom prefix"
	echo "-p portstree: specify on which portstree we work"
	exit 1
}

build_port() {
	msg "Building ${PKGNAME}"
	jexec -U root ${JAILNAME} mkdir -p /tmp/pkgs
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
		jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} ${PORT_FLAGS} ${PHASE} PKGREPOSITORY=/tmp/pkgs PACKAGES=/tmp/pkgs
		if [ "${PHASE}" = "build" ]; then
			msg "Installing run dependencies"
			jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} run-depends
			msg "Packaging all run dependencies"
			for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1}'`; do
				[ -f ${PKGDIR}/All/${pkg}.tbz ] || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
			done
			[ $ZVERSION -ge 28 ] && zfs snapshot ${ZPOOL}/poudriere/${JAILNAME}@prebuild
		fi
	done
	return 0
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh
NOPREFIX=0
PTNAME="default"

while getopts "d:cnj:p:" FLAG; do
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
		p)
		PTNAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${PORTDIRECTORY} && usage
HOST_PORTDIRECTORY=${PORTDIRECTORY}
PORTNAME=`make -C ${PORTDIRECTORY} -VPKGNAME`

test -z "${JAILNAMES}" && JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }' | grep -v ports-`

for JAILNAME in ${JAILNAMES}; do
	JAILBASE=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}

	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -j ${JAILNAME}
	STATUS=1 #injail

	prepare_jail

	TEMP=${JAILBASE}${PORTDIRECTORY}
	if [ ${#TEMP} -ge 87 ]; then
		PORTDIRECTORY="${PORTNAME}"
		if [ ${#PORTDIRECTORY} -ge 87 ]; then
			PORTDIRECTORY="a"
		fi
	fi
	if outside_portsdir ${PORTDIRECTORY}; then
		mkdir -p ${JAILBASE}/${PORTDIRECTORY}
		mount -t nullfs ${HOST_PORTDIRECTORY} ${JAILBASE}/${PORTDIRECTORY}
		
	fi

	exec 3>&1 4>&2
	[ ! -e ${PIPE} ] && mkfifo ${PIPE}
	tee ${LOGS}/${PORTNAME}-${JAILNAME}.depends.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1
	if [ "${USE_PORTLINT}" = "yes" ]; then
		if [ -x `which portlint` ]; then
			set +e
			msg "Portlint check"
			cd ${JAILBASE}/${PORTDIRECTORY} && portlint -a | tee -a ${LOGS}/${PORTNAME}-${JAILNAME}.portlint.log
			set -e
		else
			err 2 "First install portlint if you want USE_PORTLINT to work as expected"
		fi
	fi
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} extract-depends \
		fetch-depends patch-depends build-depends lib-depends

# Package all newly build ports
	msg "Packaging all dependencies" | tee -a ${LOGS}/${PORTNAME}-${JAILNAME}.depends.log
	for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1}'`; do
		[ -f ${PKGDIR}/All/${pkg}.tbz ] || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
	done
	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid

	exec 3>&1 4>&2
	tee ${LOGS}/${PORTNAME}-${JAILNAME}.build.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1
	PKGNAME=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VPKGNAME`
	PKG_DBDIR=`jexec -U root ${JAILNAME} mktemp -d -t pkg_db`
	LOCALBASE=`jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VLOCALBASE`
	if [ ${NOPREFIX} -eq 1 ]; then
		PREFIX=${LOCALBASE}
	else
		PREFIX="${BUILDROOT:-/tmp}/`echo ${PKGNAME} | tr '[,+]' _`"
	fi
	PORT_FLAGS="NO_DEPENDS=yes PREFIX=${PREFIX} PKG_DBDIR=${PKG_DBDIR}"
	msg "Building with flags: ${PORT_FLAGS}"
	msg "Cleaning workspace"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean
	[ $CONFIGSTR -eq 1 ] && jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} config

	if [ -d ${JAILBASE}${PREFIX} ]; then
		msg "Removing existing ${PREFIX}"
		[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX}
	fi

	msg "Populating PREFIX"
	mkdir ${JAILBASE}${PREFIX}
	jexec -U root ${JAILNAME} /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${PREFIX} >/dev/null

	if [ $ZVERSION -lt 28 ]; then
		find ${JAILBASE}${LOCALBASE}/ -type d | sed "s,^${JAILBASE}${LOCALBASE}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.before
	fi

	build_port

	msg "Extra files and directories check"
	if [ $ZVERSION -lt 28 ]; then
		find ${JAILBASE}${PREFIX} ! -type d | \
			sed -e "s,^${JAILBASE}${PREFIX}/,,"

		find ${JAILBASE}${PREFIX}/ -type d | sed "s,^${JAILBASE}${PREFIX}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.after
		comm -13 ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
	else
		zfs diff ${ZPOOL}/poudriere/${JAILNAME}@prebuild \
		${ZPOOL}/poudriere/${JAILNAME} | \
		egrep -v "[\+|M][[:space:]]*${JAILBASE}/tmp/pkgs" | while read type path; do
			if [ $type = "+" ]; then
				[ -d $path ] && echo -n "@dirrmtry "
				echo "$path" | sed -e "s,^${JAILBASE},," -e "s,^${PREFIX}/,,"
			else
				[ -d $path ] && continue
				msg "WARNING: $path has been modified"
			fi
		done
		zfs destroy ${ZPOOL}/poudriere/${JAILNAME}@prebuild || :
	fi

	msg "Installing from package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_add /tmp/pkgs/${PKGNAME}.tbz
	msg "Deinstalling package"
	PKG_DBDIR=${PKG_DBDIR} jexec -U root ${JAILNAME} pkg_delete ${PKGNAME}

	msg "Cleaning up"
	jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean

	msg "Removing existing ${PREFIX} dir"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX} ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after
	rm -rf ${JAILBASE}${PKG_DBDIR}

	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid

	cleanup
	STATUS=0 #injail
done

