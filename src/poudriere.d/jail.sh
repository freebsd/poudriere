#!/bin/sh

usage() {
	echo "poudriere jail [parameters] [options]

Parameters:
    -c            -- create a jail
    -d            -- delete a jail
    -l            -- list all available jails
    -s            -- start a jail
    -k            -- kill (stop) a jail
    -i            -- show informations
 
Options:
    -q            -- quiet (remove the header in list)
    -j jailname   -- Specifies the jailname
    -v version    -- Specifies which version of FreeBSD we want in jail
    -a arch       -- Indicates architecture of the jail: i386 or amd64
                     (Default: same as host)
    -m method     -- Method used to create jail, specify NONE if you want
                     to use your home made jail
                     (Default: FTP)
    -f fs         -- FS name (tank/jails/myjail)
    -M mountpoint -- mountpoint"
	exit 1
}

info_jail() {
	test -z ${JAILNAME} && usage
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	JAILFS=`jail_get_fs ${JAILNAME}`
	nbb=$(zfs_get poudriere:stats_built)
	nbf=$(zfs_get poudriere:stats_failed)
	nbq=$(zfs_get poudriere:stats_queued)
	tobuild=$((nbq - nbb - nbf))
	zfs list -H -o poudriere:type,poudriere:name,poudriere:version,poudriere:arch,poudriere:stats_built,poudriere:stats_failed,poudriere:status ${JAILFS}| \
		awk -v q="$nbq" -v tb="$tobuild" '/^rootfs/  {
			print "Jailname: " $2;
			print "FreeBSD Version: " $3;
			print "FreeBSD arch: "$4;
			print "Status: ", $7;
			print "Nb packages built: "$5;
			print "Nb packages failed: "$6;
			print "Nb packages queued: "q;
			print "Nb packages to be built: "tb;
		}'
}

list_jail() {
	[ ${QUIET} -eq 0 ] && \
		printf '%-20s %-13s %-7s %-7s %-7s %-7s %s\n' "JAILNAME" "VERSION" "ARCH" "SUCCESS" "FAILED" "QUEUED" "STATUS"
	zfs list -Hd1 -o poudriere:type,poudriere:name,poudriere:version,poudriere:arch,poudriere:stats_built,poudriere:stats_failed,poudriere:stats_queued,poudriere:status ${ZPOOL}/poudriere | \
		awk '/^rootfs/ { printf("%-20s %-13s %-7s %-7s %-7s %-7s %s\n",$2, $3, $4, $5, $6, $7, $8) }'
}

delete_jail() {
	test -z ${JAILNAME} && usage
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} && \
		err 1 "Unable to remove jail ${JAILNAME}: it is running"

	JAILBASE=`jail_get_base ${JAILNAME}`
	FS=`jail_get_fs ${JAILNAME}`
	msg_n "Removing ${JAILNAME} jail..."
	zfs destroy -r ${FS}
	rmdir ${JAILBASE}
	rm -rf ${POUDRIERE_DATA}/packages/${JAILNAME}
	rm -f ${POUDRIERE_DATA}/logs/*-${JAILNAME}.*.log
	rm -f ${POUDRIERE_DATA}/logs/bulk-${JAILNAME}.log
	echo done
}

cleanup_new_jail() {
	delete_jail
	rm -rf ${JAILBASE}/fromftp
}

create_jail() {
	jail_exists ${JAILNAME} && err 2 "The jail ${JAILNAME} already exists"

	test -z ${VERSION} && usage

	if [ -z ${JAILBASE} ]; then
		[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"
		JAILBASE=${BASEFS}/jails/${JAILNAME}
	fi

	if [ -z ${FS} ] ; then
		[ -z ${ZPOOL} ] && err 1 "Please provide a ZPOOL variable in your poudriere.conf"
		FS=${ZPOOL}/poudriere/${JAILNAME}
	fi

	jail_create_zfs ${JAILNAME} ${VERSION} ${ARCH} ${JAILBASE} ${FS}
	mkdir ${JAILBASE}/fromftp
	CLEANUP_HOOK=cleanup_new_jail

	if [ ${VERSION%%.*} -lt 9 ]; then
		msg "Fetching sets for FreeBSD ${VERSION} ${ARCH}"
		FTPURL="ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}"
		DISTS="base dict src"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32"
		for dist in ${DISTS}; do
			PKGS=`echo "ls *.??"| ftp -aV ${FTPURL}/$dist/ | awk '/-r.*/ {print $NF}'`
			[ -z ${PKGS} ] && err 1 "Could not find distribution on ${FTPURL}/dist"
			for pkg in ${PKGS}; do
				[ ${pkg} = "install.sh" ] && continue
				# Let's retry at least one time
				fetch_file ${JAILBASE}/fromftp/ ${FTPURL}/${dist}/${pkg}
			done
		done

		msg "Extracting sets:"
		for SETS in ${JAILBASE}/fromftp/*.aa; do
			SET=`basename $SETS .aa`
			echo -e "\t- $SET...\c"
			case ${SET} in
				s*)
					APPEND="usr/src"
					;;
				*)
					APPEND=""
					;;
			esac
			cat ${JAILBASE}/fromftp/${SET}.* | \
				tar --unlink -xpf - -C ${JAILBASE}/${APPEND} || err 1 " Fail" && echo " done"
		done
	else
		FTPURL="ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${ARCH}/${VERSION}"
		DISTS="base.txz src.txz"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32.txz"
		for dist in ${DISTS}; do
			msg "Fetching ${dist} for FreeBSD ${VERSION} ${ARCH}"
			fetch_file ${JAILBASE}/fromftp/${dist} ${FTPURL}/${dist}
			msg_n "Extracting ${dist}..."
			tar -xpf ${JAILBASE}/fromftp/${dist} -C  ${JAILBASE}/ || err 1 " fail" && echo " done"
		done
	fi

	msg_n "Cleaning up..."
	rm -rf ${JAILBASE}/fromftp/
	echo " done"

	OSVERSION=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILBASE}/usr/include/sys/param.h`
	LOGIN_ENV=",UNAME_r=${VERSION},UNAME_v=FreeBSD ${VERSION},OSVERSION=${OSVERSION}"

	if [ "${ARCH}" = "i386" -a "${REALARCH}" = "amd64" ];then
		LOGIN_ENV="${LOGIN_ENV},UNAME_p=i386,UNAME_m=i386"
		cat > ${JAILBASE}/etc/make.conf << EOF
ARCH=i386
MACHINE=i386
MACHINE_ARCH=i386
EOF

	fi

	sed -i .back -e "s/:\(setenv.*\):/:\1${LOGIN_ENV}:/" ${JAILBASE}/etc/login.conf
	cap_mkdb ${JAILBASE}/etc/login.conf
	pwd_mkdb -d ${JAILBASE}/etc/ -p ${JAILBASE}/etc/master.passwd

	cat >> ${JAILBASE}/etc/make.conf << EOF
USE_PACKAGE_DEPENDS=yes
BATCH=yes
PACKAGE_BUILDING=yes
WRKDIRPREFIX=/wrkdirs
EOF

	mkdir -p ${JAILBASE}/usr/ports
	mkdir -p ${JAILBASE}/wrkdirs
	mkdir -p ${POUDRIERE_DATA}/logs

	jail -U root -c path=${JAILBASE} command=/sbin/ldconfig -m /lib /usr/lib /usr/lib/compat
#	chroot -u root ${JAILBASE} /sbin/ldconfig  -m /lib /usr/lib /usr/lib/compat

	zfs snapshot ${FS}@clean
	msg "Jail ${JAILNAME} ${VERSION} ${ARCH} is ready to be used"
}

ARCH=`uname -m`
REALARCH=${ARCH}
METHOD="FTP"
START=0
STOP=0
LIST=0
DELETE=0
CREATE=0
QUIET=0
INFO=0

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

while getopts "j:v:a:z:m:n:f:M:sdklqci" FLAG; do
	case "${FLAG}" in
		j)
			JAILNAME=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			if [ "${REALARCH}" != "amd64" -a "${REALARCH}" != ${OPTARG} ]; then
				err 1 "Only amd64 host can choose another architecture"
			fi
			ARCH=${OPTARG}
			;;
		m)
			METHOD=${OPTARG}
			;;
		f)
			FS=${OPTARG}
			;;
		M)
			JAILBASE=${OPTARG}
			;;
		s)
			START=1
			;;
		k)
			STOP=1
			;;
		l)
			LIST=1
			;;
		c)
			CREATE=1
			;;
		d)
			DELETE=1
			;;
		q)
			QUIET=1
			;;
		i)
			INFO=1
			;;
		*)
			usage
			;;
	esac
done

[ $(( CREATE + LIST + STOP + START + DELETE + INFO)) -lt 1 ] && usage

case "${CREATE}${LIST}${STOP}${START}${DELETE}${INFO}" in
	100000)
		create_jail
		;;
	010000)
		list_jail
		;;
	001000)
		jail_stop ${JAILNAME}
		;;
	000100)
		export SET_STATUS_ON_START=0
		jail_start ${JAILNAME}
		;;
	000010)
		delete_jail
		;;
	000001)
		info_jail ${JAILNAME}
		;;
esac
