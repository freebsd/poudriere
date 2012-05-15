#!/bin/sh
set -e

usage() {
	echo "poudriere pbi parameters [options]

Parameters:
    -o origin   -- Specify an origin in the portstree

Options:
    -j name     -- Run only inside the given jail
    -l:         -- Localbase
    -p tree     -- Specify on which portstree we work
    -m mail     -- Mail address of the maintainer
    -r          -- Create real pbi"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
REAL=0
PTNAME="default"

while getopts "o:l:j:p:rm:" FLAG; do
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
		r)
			REAL=1
			;;
		m)
			MAINTAINER=${OPTARG}
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
	WWW=`awk '/^WWW/ { print $2 }' ${PORTDIRECTORY}/pkg-descr`
	COMMENT=`injail make -C ${PORTDIRECTORY} -VCOMMENT`
	log_start ${LOGS}/pbi-${PKGNAME}-${JAILNAME}.log
	echo pkg -j ${JAILNAME} add /usr/ports/packages/All/${PKGNAME}.${EXT}
	/usr/local/sbin/pkg -j ${JAILNAME} add /usr/ports/packages/All/${PKGNAME}.${EXT}
	if [ $REAL -eq 0 ]; then
		ABI=`/usr/local/sbin/pkg -j ${JAILNAME} -v | awk '/^abi/ { print $2 }'`
	else
		ABI=`injail uname -m`
	fi
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
						*.h|*.a|*.la) continue ;;
						*)
							if [ $REAL -eq 0 ]; then
								SUM=`test -f ${JAILBASE}/${LOCALBASE}/${PPATH} && sha256 -q ${JAILBASE}/${LOCALBASE}/${PPATH} || echo '-'`
								echo "  ${LOCALBASE}/${PPATH}: ${SUM}" >> ${JAILBASE}/files
							else
								echo "${LOCALBASE}/${PPATH}" >> ${JAILBASE}/files
							fi
							;;
					esac
					;;
			esac
		done
	if [ $REAL -eq 0 ]; then
		echo "
name:  ${PKGNAME%-*}
version: ${PKGNAME##*-}
prefix: ${MYBASE}
origin: pbi/${ORIGIN}
www: ${WWW:-unknown}
maintainer: ${MAINTAINER:-unknown}
comment: ${COMMENT:-none}
arch: ${ABI}
desc: |-
  This is a test
files:
" >> ${JAILBASE}/+MANIFEST
		sort ${JAILBASE}/files >> ${JAILBASE}/+MANIFEST
		echo "directories:" >> ${JAILBASE}/+MANIFEST
		sort -r ${JAILBASE}/dirs >> ${JAILBASE}/+MANIFEST
		sed -i '' -e "/^[ \t]*$/d" ${JAILBASE}/+MANIFEST
		/usr/local/sbin/pkg create -m ${JAILBASE}/ -r ${JAILBASE} ${PKGNAME}
	else
		injail tar cfJ /data.txz -s ",${MYBASE},,g" `awk '{ printf("%s ", $0) } END { printf("\n") }' ${JAILBASE}/files`
		mkdir ${JAILBASE}/head
		echo ${PKGNAME%-*} > ${JAILBASE}/head/pbi_name
		echo ${PKGNAME##*-} > ${JAILBASE}/head/pbi_version
		echo ${MAINTAINER:-unknown} > ${JAILBASE}/head/pbi_author
		echo ${WWW:-unkown} > ${JAILBASE}/head/pbi_web
		echo ${ABI} > ${JAILBASE}/head/pbi_arch
		wc -l ${JAILBASE}/files | awk '{ print $1 }' > ${JAILBASE}/head/pbi_archive_count
		injail uname -r > ${JAILBASE}/head/pbi_fbsdver
		echo ${MYBASE} > ${JAILBASE}/head/pbi_defaultpath
		date "+%Y%m%d %H%M%S" > ${JAILBASE}/head/pbi_mdate
		sha256 -q ${JAILBASE}/data.txz > ${JAILBASE}/head/pbi_archivesum
		injail tar cjf /head.tbz -C head .
		injail cat /head.tbz > ${JAILBASE}/${PKGNAME}.pbi
		echo -e "\n_PBI_ICON_" >> ${JAILBASE}/${PKGNAME}.pbi
		# to fix
		touch ${JAILBASE}/icon.png
		injail cat /icon.png >> ${JAILBASE}/${PKGNAME}.pbi
		echo -e "\n_PBI_ARCHIVE_" >> ${JAILBASE}/${PKGNAME}.pbi
		injail cat /data.txz >> ${JAILBASE}/${PKGNAME}.pbi
		mv ${JAILBASE}/${PKGNAME}.pbi .
	fi

	zfs rollback ${JAILFS}@prepkg
	log_stop ${LOGS}/pbi${PKGNAME}-${JAILNAME}.log

	cleanup
done
