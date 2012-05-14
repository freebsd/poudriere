#!/bin/sh
set -e

usage() {
	echo "poudriere pbi parameters [options]

Parameters:
    -o origin   -- Specify an origin in the portstree

Options:
    -j name     -- Run only inside the given jail
    -l:         -- Localbase
    -p tree     -- Specify on which portstree we work"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh
NOPREFIX=0
PTNAME="default"

while getopts "o:l:j:p:" FLAG; do
	case "${FLAG}" in
		o)
			ORIGIN=${OPTARG}
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAMES="${JAILNAMES} ${OPTARG}"
			;;
		p)
			PTNAME=${OPTARG}
			;;
		l)
			MYBASE=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

test -z ${ORIGIN} && usage
test -z ${MYBASE} && usage

test -z "${JAILNAMES}" && JAILNAMES=`jail_ls`

for JAILNAME in ${JAILNAMES}; do
	LBASENAME=$(echo ${MYBASE} | sed -e "s|/|_|g")
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}-${LBASENAME}

	jail_start ${JAILNAME}
	ZVERSION=`jail_get_zpool_version ${JAILNAME}`

	prepare_jail
	echo "LOCALBASE=${MYBASE}" >> ${JAILBASE}/etc/make.conf
	echo "WITH_PKGNG=yes" >> ${JAILBASE}/etc/make.conf

	PORTDIRECTORY=/usr/ports/${ORIGIN}
	LISTPORTS=$(list_deps ${PORTDIRECTORY} )
	LISTPORTS="${LISTPORTS} ${ORIGIN}"
	prepare_ports
	zfs snapshot ${JAILFS}@prepkg
	export LOCALBASE=${MYBASE}
	for port in ${queue}; do
		build_pkg ${port} || {
			[ $? -eq 2 ] && continue
		}
		zfs rollback -r ${JAILFS}@prepkg
	done
	zfs rollback ${JAILFS}@prepkg
	PKGNAME=`injail make -C ${PORTDIRECTORY} -VPKGNAME`
	log_start ${LOGS}/pbi-${PKGNAME}-${JAILNAME}.log
	echo pkg -j ${JAILNAME} add /usr/ports/packages/All/${PKGNAME}.${EXT}
	/usr/local/sbin/pkg -j ${JAILNAME} add /usr/ports/packages/All/${PKGNAME}.${EXT}
	zfs diff -FH ${JAILFS}@prepkg ${JAILFS}  | \
		while read mod type path; do
			PPATH=`echo "$path" | sed -e "s,^${JAILBASE},," -e "s,^${LOCALBASE}/,,"`
			case $mod$type in
				+/)
					case "${PPATH}" in
						/*) continue ;;
						*)
							echo "  ${LOCALBASE}/${PPATH}: n" >> ${JAILBASE}/dirs
							;;
					esac
					;;
				+*)	case "${PPATH}" in
						/*) continue ;;
						*.h|*.a) continue ;;
						*)
							SUM=`test -f ${JAILBASE}/${LOCALBASE}/${PPATH} && sha256 -q ${JAILBASE}/${LOCALBASE}/${PPATH} || echo '-'`
							echo "  ${LOCALBASE}/${PPATH}: ${SUM}" >> ${JAILBASE}/files
							;;
					esac
					;;
			esac
		done
	echo "
name:  ${PKGNAME%-*}
version: ${PKGNAME##*-}
prefix: ${MYBASE}
origin: pbi/${PKGNAME}
www: unknown
maintainer: pbimaster@pcbsd.org
comment: none
arch: freebsd:9:x86:32
desc: |-
  This is a test
files:
" >> ${JAILBASE}/+MANIFEST
	sort ${JAILBASE}/files >> ${JAILBASE}/+MANIFEST
	echo "directories:" >> ${JAILBASE}/+MANIFEST
	sort -r ${JAILBASE}/dirs >> ${JAILBASE}/+MANIFEST
	sed -i '' -e "/^[ \t]*$/d" ${JAILBASE}/+MANIFEST
	cat ${JAILBASE}/+MANIFEST
	/usr/local/sbin/pkg create -m ${JAILBASE}/ -r ${JAILBASE} ${PKGNAME}

	zfs rollback ${JAILFS}@prepkg
	log_stop ${LOGS}/pbi${PKGNAME}-${JAILNAME}.log

	cleanup
done
