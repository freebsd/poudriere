#!/bin/sh
set -e

usage() {
	echo "poudriere pbi parameters [options]

Parameters:
    -d pbidir   -- Directory for the pbi metadata files

Options:
    -j name     -- Run only inside the given jail
    -l path     -- Localbase
    -p tree     -- Specify on which portstree we work
    -r          -- Create real pbi"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
REAL=0
PTNAME="default"

while getopts "l:j:p:rd:" FLAG; do
	case "${FLAG}" in
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
		d)
			PBIDIRECTORY=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

test -f ${PBIDIRECTORY}/pbi.conf || usage
. ${PBIDIRECTORY}/pbi.conf
ORIGIN=${PBI_MAKEPORT}
test -z ${ORIGIN} && usage
test -z ${MYBASE} && usage

test -z "${JAILNAMES}" && JAILNAMES=`jail_ls`

for JAILNAME in ${JAILNAMES}; do
	LBASENAME=$(echo ${MYBASE} | sed -e "s|/|_|g")
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}-${LBASENAME}

	jail_start ${JAILNAME}

	prepare_jail
	mkdir -p ${JAILBASE}/pbi
	mount -t nullfs ${PBIDIRECTORY} ${JAILBASE}/pbi

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
		ABI=`/usr/local/sbin/pkg -j ${JAILNAME} -vv | awk '/^abi/ { print $2 }'`
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
name:  ${PBI_PROGNAME}
version: ${PKGNAME##*-}
prefix: ${MYBASE}
origin: pbi/${ORIGIN}
www: ${PBI_PROGWEB:-unknown}
maintainer: ${PBI_PROGAUTHOR:-unknown}
comment: ${COMMENT:-none}
arch: ${ABI}
desc: |-
  This is a test
files:
" >> ${JAILBASE}/+MANIFEST
		cat  ${JAILBASE}/+MANIFEST
		sort ${JAILBASE}/files >> ${JAILBASE}/+MANIFEST
		echo "directories:" >> ${JAILBASE}/+MANIFEST
		sort -r ${JAILBASE}/dirs >> ${JAILBASE}/+MANIFEST
		sed -i '' -e "/^[ \t]*$/d" ${JAILBASE}/+MANIFEST
		/usr/local/sbin/pkg create -m ${JAILBASE}/ -r ${JAILBASE} ${PKGNAME}
	else
		injail tar cfJ /data.txz -s ",${MYBASE},,g" `awk '{ printf("%s ", $0) } END { printf("\n") }' ${JAILBASE}/files`
		mkdir ${JAILBASE}/head
		echo ${PBI_PROGNAME} > ${JAILBASE}/head/pbi_name
		echo ${PKGNAME##*-} > ${JAILBASE}/head/pbi_version
		echo ${PBI_PROGAUTHOR:-unknown} > ${JAILBASE}/head/pbi_author
		echo ${PBI_PROGWEB:-unknown} > ${JAILBASE}/head/pbi_web
		echo ${ABI} > ${JAILBASE}/head/pbi_arch
		wc -l ${JAILBASE}/files | awk '{ print $1 }' > ${JAILBASE}/head/pbi_archive_count
		injail uname -r > ${JAILBASE}/head/pbi_fbsdver
		echo ${MYBASE} > ${JAILBASE}/head/pbi_defaultpath
		date "+%Y%m%d %H%M%S" > ${JAILBASE}/head/pbi_mdate
		sha256 -q ${JAILBASE}/data.txz > ${JAILBASE}/head/pbi_archivesum
		[ -e "${JAILBASE}/pbi/resources/gui_banner.png" ] && cp ${JAILBASE}/pbi/resources/gui_banner.png ${JAILBASE}/head/top_banner.png
		[ -e "${JAILBASE}/pbi/resources/gui_sidebanner.png" ] && cp ${JAILBASE}/pbi/resources/gui_banner.png ${JAILBASE}/head/side-banner.png
		if [ -n "${PBI_PROGICON}" -a -e "${JAILBASE}/pbi/resources/${PBI_PROGICON}" ]; then
			cp "${JAILBASE}/pbi/resources/${PBI_PROGICON}" "${PBI_HEADERDIR}/pbi_icon.${PBI_PROGICON##*.}"
		fi
		injail tar cjf /head.tbz -C head .
		injail cat /head.tbz > ${JAILBASE}/${PKGNAME}.pbi
		echo -e "\n_PBI_ICON_" >> ${JAILBASE}/${PKGNAME}.pbi
		injail cat /pbi/resources/${PBI_PROGICON} >> ${JAILBASE}/${PKGNAME}.pbi
		echo -e "\n_PBI_ARCHIVE_" >> ${JAILBASE}/${PKGNAME}.pbi
		injail cat /data.txz >> ${JAILBASE}/${PKGNAME}.pbi
		mv ${JAILBASE}/${PKGNAME}.pbi .
	fi

	zfs rollback ${JAILFS}@prepkg
	log_stop ${LOGS}/pbi${PKGNAME}-${JAILNAME}.log

	cleanup
done
