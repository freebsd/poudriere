#!/bin/sh
set -e

usage() {
	echo "poudriere testport parameters [options]

Parameters:
    -d path     -- Specify on which port we work
    -o origin   -- Specify an origin in the portstree

Options:
    -c          -- Run make config for the given port
    -j name     -- Run only inside the given jail
    -n          -- No custom prefix
    -p tree     -- Specify on which portstree we work"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh
NOPREFIX=0
PTNAME="default"
EXT="tbz"
PKG_ADD=pkg_add
PKG_DELETE=pkg_delete
LOGS=${POUDRIERE_DATA}/logs

while getopts "d:o:cnj:p:" FLAG; do
	case "${FLAG}" in
		c)
			CONFIGSTR=1
			;;
		d)
			HOST_PORTDIRECTORY=`realpath ${OPTARG}`
			;;
		o)
			ORIGIN=${OPTARG}
			;;
		n)
			NOPREFIX=1
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
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

test -z ${HOST_PORTDIRECTORY} && test -z ${ORIGIN} && usage

if [ -z ${ORIGIN} ]; then
	PORTDIRECTORY=`basename ${HOST_PORTDIRECTORY}`
else
	HOST_PORTDIRECTORY=`port_get_base ${PTNAME}`/ports/${ORIGIN}
	PORTDIRECTORY="/usr/ports/${ORIGIN}"
fi

PKGNAME=`make -C ${HOST_PORTDIRECTORY} -VPKGNAME`
PORTNAME=`make -C ${HOST_PORTDIRECTORY} -VPORTNAME`

test -z "${JAILNAMES}" && JAILNAMES=`jail_ls`

for JAILNAME in ${JAILNAMES}; do
	PKGNG=0
	JAILBASE=`jail_get_base ${JAILNAME}`
	JAILFS=`jail_get_fs ${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}


	jail_start ${JAILNAME}
	ZVERSION=`jail_get_zpool_version ${JAILNAME}`
	STATUS=1 #injail

	prepare_jail

	grep -q ^WITH_PKGNG ${JAILBASE}/etc/make.conf && PKGNG=1
	if [ ${PKGNG} -eq 1 ]; then
		EXT=txz
		PKG_ADD="pkg add"
		PKG_DELETE="pkg delete -y -f"
	fi

	if [ -z ${ORIGIN} ]; then
		mkdir -p ${JAILBASE}/${PORTDIRECTORY}
		mount -t nullfs ${HOST_PORTDIRECTORY} ${JAILBASE}/${PORTDIRECTORY}
	fi

	if [ "${USE_PORTLINT}" = "yes" ]; then
		[ ! -x `which portlint` ] && err 2 "First install portlint if you want USE_PORTLINT to work as expected"
		set +e
		msg "Portlint check"
		cd ${JAILBASE}/${PORTDIRECTORY} && portlint -C | tee -a ${LOGS}/${PKGNAME}-${JAILNAME}.portlint.log
		set -e
	fi
	LISTPORTS=$(list_deps ${PORTDIRECTORY} )
	prepare_ports
	zfs snapshot ${JAILFS}@prepkg
	queue=$(zfs get -H -o value poudriere:queue ${JAILFS})
	for port in ${queue}; do
		build_pkg ${port} || {
			[ $? -eq 2 ] && continue
		}
		zfs rollback -r ${JAILFS}@prepkg
	done
	zfs destroy -r ${JAILFS}@prepkg
	injail make -C ${PORTDIRECTORY} pkg-depends extract-depends \
		fetch-depends patch-depends build-depends lib-depends \
		run-depends

	PKGNAME=`injail make -C ${PORTDIRECTORY} -VPKGNAME`
	LOCALBASE=`injail make -C ${PORTDIRECTORY} -VLOCALBASE`
	PREFIX=${LOCALBASE}
	[ ${NOPREFIX} -ne 1 ] && PREFIX="${BUILDROOT:-/tmp}/`echo ${PKGNAME} | tr '[,+]' _`"
	PORT_FLAGS="NO_DEPENDS=yes PREFIX=${PREFIX}"
	msg "Building with flags: ${PORT_FLAGS}"
	msg "Cleaning workspace"
	injail make -C ${PORTDIRECTORY} clean
	[ $CONFIGSTR -eq 1 ] && injail make -C ${PORTDIRECTORY} config

	if [ -d ${JAILBASE}${PREFIX} ]; then
		msg "Removing existing ${PREFIX}"
		[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX}
	fi

	msg "Populating PREFIX"
	mkdir -p ${JAILBASE}${PREFIX}
	injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${PREFIX} >/dev/null

	[ $ZVERSION -lt 28 ] && \
		find ${JAILBASE}${LOCALBASE}/ -type d | sed "s,^${JAILBASE}${LOCALBASE}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.before

	PKGENV="PACKAGES=/tmp/pkgs PKGREPOSITORY=/tmp/pkgs"
	PORTTESTING=yes
	log_start ${LOGS}/testport-${PKGNAME}-${JAILNAME}.log
	build_port ${PORTDIRECTORY}

	msg "Installing from package"
	injail ${PKG_ADD} /tmp/pkgs/${PKGNAME}.${EXT}
	msg "Deinstalling package"
	injail ${PKG_DELETE} ${PKGNAME}

	msg "Cleaning up"
	injail make -C ${PORTDIRECTORY} clean

	msg "Removing existing ${PREFIX} dir"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX} ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after
	log_stop ${LOGS}/testport-${PKGNAME}-${JAILNAME}.log

	cleanup
	STATUS=0 #injail
done
