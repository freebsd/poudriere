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
                     filesystems and directories, but do not populate
                     them.
    -p tree       -- specifies on which portstree we work. If not
                     specified, work on a portstree called \"default\".
    -f fs         -- FS name (tank/jails/myjail)
    -M mountpoint -- mountpoint
    -m method     -- when used with -c, specify the method used to update the
                     tree by default it is portsnap, possible usage are
                     \"csup\", \"portsnap\", \"svn\", \"svn+http\", \"svn+ssh\""

	exit 1
}

CREATE=0
FAKE=0
UPDATE=0
DELETE=0
LIST=0
QUIET=0
while getopts "cFudlp:qf:M:m:" FLAG; do
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
			PTFS=${OPTARG}
			;;
		M)
			PTMNT=${OPTARG}
			;;
		m)
			METHOD=${OPTARG}
			;;
		*)
			usage
		;;
	esac
done

[ $(( CREATE + UPDATE + DELETE + LIST )) -lt 1 ] && usage

METHOD=${METHOD:-portsnap}
PTNAME=${PTNAME:-default}

case ${METHOD} in
csup)
	[ -z ${CSUP_HOST} ] && err 2 "CSUP_HOST has to be defined in the configuration to use csup"
	;;
portsnap);;
svn+http);;
svn+ssh);;
svn);;
*) usage;;
esac

if [ ${LIST} -eq 1 ]; then
	[ $QUIET -eq 0 ] && \
		printf '%-20s %-10s\n' "PORTSTREE" "METHOD"
	zfs list -t filesystem -H -o ${NS}:type,${NS}:name,${NS}:method | \
		awk '$1 == "ports" {printf("%-20s %-10s\n",$2,$3) }'
else
	test -z "${PTNAME}" && usage
fi
if [ ${CREATE} -eq 1 ]; then
	# test if it already exists
	port_exists ${PTNAME} && err 2 "The ports tree ${PTNAME} already exists"
	: ${PTMNT="${BASEFS:=/usr/local/poudriere}/ports/${PTNAME}"}
	: ${PTFS="${ZPOOL}/poudriere/ports/${PTNAME}"}
	port_create_zfs ${PTNAME} ${PTMNT} ${PTFS}
	mkdir ${PTMNT}/ports
	if [ $FAKE -eq 0 ]; then
		case ${METHOD} in
		csup)
			mkdir ${PTMNT}/db
			echo "*default prefix=${PTMNT}
*default base=${PTMNT}/db
*default release=cvs tag=.
*default delete use-rel-suffix
ports-all" > ${PTMNT}/csup
			csup -z -h ${CSUP_HOST} ${PTMNT}/csup || {
				zfs destroy ${PTFS}
				err 1 " Fail"
			}
			;;
		portsnap)
			mkdir ${PTMNT}/snap
			msg "Extracting portstree \"${PTNAME}\"..."
			/usr/sbin/portsnap -d ${PTMNT}/snap -p ${PTMNT}/ports fetch extract || \
			/usr/sbin/portsnap -d ${PTMNT}/snap -p ${PTMNT}/ports fetch extract || \
			{
				zfs destroy ${PTFS}
				err 1 " Fail"
			}
			;;
		svn*)
			case ${METHOD} in
			svn+http) proto="http" ;;
			svn+ssh) proto="svn+ssh" ;;
			svn) proto="svn" ;;
			esac

			msg_n "Checking out the ports tree..."
			svn -q co ${proto}://${SVN_HOST}/ports/head \
				${PTMNT}/ports || {
				zfs destroy ${PTFS}
				err 1 " Fail"
			}
			echo " done"
			;;
		esac
		pzset method ${METHOD}
	fi
fi

if [ ${DELETE} -eq 1 ]; then
	/sbin/mount -t nullfs | /usr/bin/grep -q "${PTNAME}/ports on" \
		&& err 1 "Ports tree \"${PTNAME}\" is currently mounted and being used."
	port_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
	msg "Deleting portstree \"${PTNAME}\""
	zfs destroy -r $(port_get_fs ${PTNAME})
fi

if [ ${UPDATE} -eq 1 ]; then
	/sbin/mount -t nullfs | /usr/bin/grep -q "${PTNAME}/ports on" \
		&& err 1 "Ports tree \"${PTNAME}\" is currently mounted and being used."
	PTMNT=$(port_get_base ${PTNAME})
	PTFS=$(port_get_fs ${PTNAME})
	msg "Updating portstree \"${PTNAME}\""
	METHOD=$(pzget method)
	if [ ${METHOD} = "-" ]; then
		METHOD=portsnap
		pzset method ${METHOD}
	fi
	case ${METHOD} in
	csup)
		[ -z ${CSUP_HOST} ] && err 2 "CSUP_HOST has to be defined in the configuration to use csup"
		mkdir -p ${PTMNT}/db
		echo "*default prefix=${PTMNT}
*default base=${PTMNT}/db
*default release=cvs tag=.
*default delete use-rel-suffix
ports-all" > ${PTMNT}/csup
		csup -z -h ${CSUP_HOST} ${PTMNT}/csup
		;;
	portsnap|"")
		PSCOMMAND=fetch
		[ -t 0 ] || PSCOMMAND=cron
		/usr/sbin/portsnap -d ${PTMNT}/snap -p ${PTMNT}/ports ${PSCOMMAND} update
		;;
	svn*)
		msg_n "Updating the ports tree..."
		svn -q update ${PTMNT}/ports
		echo " done"
		;;
	*)
		err 1 "Undefined upgrade method"
		;;
	esac
fi
