#!/bin/sh
set -e

usage() {
	echo "poudriere testport parameters [options]"
cat <<EOF

Parameters:
    -d path     -- Specify on which port we work
    -o origin   -- Specify an origin in the portstree

Options:
    -c          -- Run make config for the given port
    -j name     -- Run only inside the given jail
    -n          -- No custom prefix
    -p tree     -- Specify on which portstree we work
EOF
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

	exec 3>&1 4>&2
	[ ! -e ${PIPE} ] && mkfifo ${PIPE}
	tee ${LOGS}/${PKGNAME}-${JAILNAME}.depends.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1
	if [ "${USE_PORTLINT}" = "yes" ]; then
		[ ! -x `which portlint` ] && err 2 "First install portlint if you want USE_PORTLINT to work as expected"
		set +e
		msg "Portlint check"
		cd ${JAILBASE}/${PORTDIRECTORY} && portlint -C | tee -a ${LOGS}/${PKGNAME}-${JAILNAME}.portlint.log
		set -e
	fi
	# First sanity check the installed packages
	msg "Sanity checking the available packages"
	sanity_check_pkgs
	LISTPORTS=$(list_deps ${PORTDIRECTORY} )
	zfs snapshot ${JAILFS}@prepkg
	msg "Calculating ports order and dependencies"
	for port in `prepare_ports`; do
		build_pkg ${port} || {
			[ $? -eq 2 ] && continue
		}
		zfs rollback ${JAILFS}@prepkg
	done
	zfs destroy ${JAILFS}@prepkg
	injail make -C ${PORTDIRECTORY} pkg-depends extract-depends \
		fetch-depends patch-depends build-depends lib-depends \
		run-depends

	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid

	exec 3>&1 4>&2
	tee ${LOGS}/${PKGNAME}-${JAILNAME}.build.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1
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
	build_port ${PORTDIRECTORY}

	#msg "Extra files and directories check"
	#if [ $ZVERSION -lt 28 ]; then
	#	find ${JAILBASE}${PREFIX} ! -type d | \
	#		sed -e "s,^${JAILBASE}${PREFIX}/,," | sort

	#	find ${JAILBASE}${PREFIX}/ -type d | sed "s,^${JAILBASE}${PREFIX}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.after
	#	comm -13 ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
	#else
	#	FILES=`mktemp /tmp/files.XXXXXX`
	#	DIRS=`mktemp /tmp/dirs.XXXXXX`
	#	MODIFS=`mktemp /tmp/modifs.XXXXXX`
	#	zfs diff ${JAILFS}@prebuild ${JAILFS} | \
	#	egrep -v "[\+|M][[:space:]]*${JAILBASE}${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)" | \
	#	egrep -v "[\+|M|-][[:space:]]*${JAILBASE}/wrkdirs" | \
	#	egrep -v "/var/db/pkg" | \
	#	egrep -v "/var/run/ld-elf.so.hints" | \
	#	egrep -v "[\+|M][[:space:]]*${JAILBASE}/tmp/pkgs" | while read type path; do
	#		PPATH=`echo "$path" | sed -e "s,^${JAILBASE},," -e "s,^${PREFIX}/,," -e "s,^share/${PORTNAME},%%DATADIR%%," -e "s,^etc,%%ETCDIR%%,"`
	#		if [ $type = "+" ]; then
	#			if [ -d $path ]; then
	#				echo "@dirrmtry ${PPATH}" >> ${DIRS}
	#			else
	#				echo "${PPATH}" >> ${FILES}
	#			fi
	#		elif [ $type = "-" ]; then
	#			msg "!!!MISSING!!!: ${PPATH}"
	#			echo "${PPATH}" >> ${MODIFS}
	#		else
	#			[ -d $path ] && continue
	#			msg "WARNING: ${PPATH} has been modified"
	#			echo "${PPATH}" >> ${MODIFS}
	#		fi
	#	done
	#	sort ${FILES} > ${FILES}.sort
	#	sort ${MODIFS} > ${MODIFS}.sort
	#	comm -23 ${FILES}.sort ${MODIFS}.sort
	#	sort -r ${DIRS}
	#	rm ${FILES} ${DIRS} ${MODIFS} ${FILES}.sort ${MODIFS}.sort

	#	zfs destroy ${JAILFS}@prebuild || :
	#fi

	msg "Installing from package"
	injail ${PKG_ADD} /tmp/pkgs/${PKGNAME}.${EXT}
	msg "Deinstalling package"
	injail ${PKG_DELETE} ${PKGNAME}

	msg "Cleaning up"
	injail make -C ${PORTDIRECTORY} clean

	msg "Removing existing ${PREFIX} dir"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILBASE}${PREFIX} ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after

	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid

	cleanup
	STATUS=0 #injail
done
