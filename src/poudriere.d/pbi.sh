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
			JAILNAME="${OPTARG}"
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

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

LBASENAME=$(echo ${MYBASE} | sed -e "s|/|_|g")
PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}-${LBASENAME}

JAILMNT=`jail_get_base ${JAILNAME}`
JAILFS=`jail_get_fs ${JAILNAME}`

export POUDRIERE_BUILD_TYPE=pbi

jail_start

prepare_jail
mkdir -p ${JAILMNT}/pbi
mount -t nullfs ${PBIDIRECTORY} ${JAILMNT}/pbi

echo "LOCALBASE=${MYBASE}" >> ${JAILMNT}/etc/make.conf
echo "WITH_PKGNG=yes" >> ${JAILMNT}/etc/make.conf

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
PKGNAME=$(cache_get_pkgname ${ORIGIN})
WWW=`awk '/^WWW/ { print $2 }' ${PORTDIRECTORY}/pkg-descr`
COMMENT=`injail make -C ${PORTDIRECTORY} -VCOMMENT`
log_start $(log_path)/${PKGNAME}.log
echo pkg -j ${JAILNAME} add /usr/ports/packages/All/${PKGNAME}.${EXT}
/usr/local/sbin/pkg -j ${JAILNAME} add /usr/ports/packages/All/${PKGNAME}.${EXT}
if [ $REAL -eq 0 ]; then
	ABI=`/usr/local/sbin/pkg -j ${JAILNAME} -vv | awk '/^abi/ { print $2 }'`
else
	ABI=`injail uname -m`
fi
zfs diff -FH ${JAILFS}@prepkg ${JAILFS}  | \
		while read mod type path; do
		PPATH=`echo "$path" | sed -e "s,^${JAILMNT},," -e "s,^${LOCALBASE}/,,"`
		case $mod$type in
			+/)
				case "${PPATH}" in
					/*) continue ;;
					*)
						echo "  ${LOCALBASE}/${PPATH}: n" >> ${JAILMNT}/dirs
						;;
				esac
				;;
			+*)	case "${PPATH}" in
					/*) continue ;;
					*.h|*.a|*.la) continue ;;
					*)
						if [ $REAL -eq 0 ]; then
							SUM=`test -f ${JAILMNT}/${LOCALBASE}/${PPATH} && sha256 -q ${JAILMNT}/${LOCALBASE}/${PPATH} || echo '-'`
							echo "  ${LOCALBASE}/${PPATH}: ${SUM}" >> ${JAILMNT}/files
						else
							echo "${LOCALBASE}/${PPATH}" >> ${JAILMNT}/files
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
" >> ${JAILMNT}/+MANIFEST
	cat  ${JAILMNT}/+MANIFEST
	sort ${JAILMNT}/files >> ${JAILMNT}/+MANIFEST
	echo "directories:" >> ${JAILMNT}/+MANIFEST
	sort -r ${JAILMNT}/dirs >> ${JAILMNT}/+MANIFEST
	sed -i '' -e "/^[ \t]*$/d" ${JAILMNT}/+MANIFEST
	/usr/local/sbin/pkg create -m ${JAILMNT}/ -r ${JAILMNT} ${PKGNAME}
else
	injail tar cfJ /data.txz -s ",${MYBASE},,g" `awk '{ printf("%s ", $0) } END { printf("\n") }' ${JAILMNT}/files`
	mkdir ${JAILMNT}/head
	echo ${PBI_PROGNAME} > ${JAILMNT}/head/pbi_name
	echo ${PKGNAME##*-} > ${JAILMNT}/head/pbi_version
	echo ${PBI_PROGAUTHOR:-unknown} > ${JAILMNT}/head/pbi_author
	echo ${PBI_PROGWEB:-unknown} > ${JAILMNT}/head/pbi_web
	echo ${ABI} > ${JAILMNT}/head/pbi_arch
	wc -l ${JAILMNT}/files | awk '{ print $1 }' > ${JAILMNT}/head/pbi_archive_count
	injail uname -r > ${JAILMNT}/head/pbi_fbsdver
	echo ${MYBASE} > ${JAILMNT}/head/pbi_defaultpath
	date "+%Y%m%d %H%M%S" > ${JAILMNT}/head/pbi_mdate
	sha256 -q ${JAILMNT}/data.txz > ${JAILMNT}/head/pbi_archivesum
	[ -e "${JAILMNT}/pbi/resources/gui_banner.png" ] && cp ${JAILMNT}/pbi/resources/gui_banner.png ${JAILMNT}/head/top_banner.png
	[ -e "${JAILMNT}/pbi/resources/gui_sidebanner.png" ] && cp ${JAILMNT}/pbi/resources/gui_banner.png ${JAILMNT}/head/side-banner.png
	if [ -n "${PBI_PROGICON}" -a -e "${JAILMNT}/pbi/resources/${PBI_PROGICON}" ]; then
		cp "${JAILMNT}/pbi/resources/${PBI_PROGICON}" "${PBI_HEADERDIR}/pbi_icon.${PBI_PROGICON##*.}"
	fi
	injail tar cjf /head.tbz -C head .
	injail cat /head.tbz > ${JAILMNT}/${PKGNAME}.pbi
	echo -e "\n_PBI_ICON_" >> ${JAILMNT}/${PKGNAME}.pbi
	injail cat /pbi/resources/${PBI_PROGICON} >> ${JAILMNT}/${PKGNAME}.pbi
	echo -e "\n_PBI_ARCHIVE_" >> ${JAILMNT}/${PKGNAME}.pbi
	injail cat /data.txz >> ${JAILMNT}/${PKGNAME}.pbi
	mv ${JAILMNT}/${PKGNAME}.pbi .
fi

zfs rollback ${JAILFS}@prepkg
log_stop $(log_path)/${PKGNAME}.log

cleanup
