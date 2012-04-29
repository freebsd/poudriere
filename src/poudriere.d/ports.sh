#!/bin/sh

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

# test if there is any args
usage() {
	echo "poudriere ports [parameters] [options]

Parameters:
    -c            -- create a portstree
    -d            -- delete a portstree
    -u            -- update a portstree
    -l            -- lists all available portstrees
    -q            -- quiet (remove the header in list)

Options:
    -F            -- when used with -c, only create the needed ZFS
                     filesystems and directories, but do not populare
                     them.
    -p tree       -- specifies on which portstree we work. If not
                     specified, work on a portstree called \"default\".
    -f fs         -- FS name (tank/jails/myjail)
    -M mountpoint -- mountpoint"

	exit 1
}

CREATE=0
FAKE=0
UPDATE=0
DELETE=0
LIST=0
QUIET=0
while getopts "cFudlp:qf:M:" FLAG; do
	case "${FLAG}" in
		c)
			CREATE=1
			;;
		F)
			FAKE=1
			;;
		u)
			UPDATE=1
			;;
		p)
			PTNAME=${OPTARG}
			;;
		d)
			DELETE=1
			;;
		l)
			LIST=1
			;;
		q)
			QUIET=1
			;;
		f)
			FS=${OPTARG}
			;;
		M)
			PTBASE=${OPTARG}
			;;
		*)
			usage
		;;
	esac
done

[ $(( CREATE + UPDATE + DELETE + LIST )) -lt 1 ] && usage

PTNAME=${PTNAME:-default}

if [ ${LIST} -eq 1 ]; then
	[ $QUIET -eq 0 ] && echo "PORTSTREE"
	zfs list -d1 -o poudriere:type,poudriere:name ${ZPOOL}/poudriere | awk '/ports/ {print $2 }'
else
	test -z "${PTNAME}" && usage
fi
if [ ${CREATE} -eq 1 ]; then
	# test if it already exists
	port_exists ${PTNAME} && err 2 "The ports tree ${PTNAME} already exists"
	test -z ${PTBASE} && PTBASE=${BASEFS:=/usr/local/poudriere}/ports/${PTNAME}
	test -z ${FS} && FS=${ZPOOL}/poudriere/ports-${PTNAME}
	port_create_zfs ${PTNAME} ${PTBASE} ${FS}
	mkdir ${PTBASE}/ports
	if [ $FAKE -eq 0 ]; then
		if [ -n "${CSUP_HOST}" ]; then
			mkdir ${PTBASE}/db
			echo "*default prefix=${PTBASE}
*default base=${PTBASE}/db
*default release=cvs tag=.
*default delete use-rel-suffix
ports-all" > ${PTBASE}/csup
			csup -z -h ${CSUP_HOST} ${PTBASE}/csup || {
					zfs destroy ${FS}
					err 1 " Fail"
			}
		else
			mkdir ${PTBASE}/snap
			msg "Extracting portstree \"${PTNAME}\"..."
			/usr/sbin/portsnap -d ${PTBASE}/snap -p ${PTBASE}/ports fetch extract || \
			/usr/sbin/portsnap -d ${PTBASE}/snap -p ${PTBASE}/ports fetch extract || \
			{
				zfs destroy ${FS}
				err 1 " Fail"
			}
		fi
	fi
fi

if [ ${DELETE} -eq 1 ]; then
	/sbin/mount -t nullfs | /usr/bin/grep -q "${PTNAME}/ports on" \
		&& err 1 "Ports tree \"${PTNAME}\" is already used."
	port_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
	msg "Deleting portstree \"${PTNAME}\""
	zfs destroy -r $(port_get_fs ${PTNAME})
fi

if [ ${UPDATE} -eq 1 ]; then
	/sbin/mount -t nullfs | /usr/bin/grep -q "${PTNAME}/ports on" \
		&& err 1 "Ports tree \"${PTNAME}\" is already used."
	PTBASE=$(port_get_base ${PTNAME})
	msg "Updating portstree \"${PTNAME}\""
	if [ -n "${CSUP_HOST}" ]; then
		[ -d ${PTBASE}/db ] || mkdir ${PTBASE}/db
			echo "*default prefix=${PTBASE}
*default base=${PTBASE}/db
*default release=cvs tag=.
*default delete use-rel-suffix
ports-all" > ${PTBASE}/csup
		csup -z -h ${CSUP_HOST} ${PTBASE}/csup
	else
		/usr/sbin/portsnap -d ${PTBASE}/snap -p ${PTBASE}/ports fetch update
	fi
fi
