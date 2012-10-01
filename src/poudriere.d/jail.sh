#!/bin/sh

usage() {
	echo "poudriere jail [parameters] [options]

Parameters:
    -c            -- create a jail
    -d            -- delete a jail
    -l            -- list all available jails
    -s            -- start a jail
    -k            -- kill (stop) a jail
    -u            -- update a jail
    -i            -- show informations

Options:
    -q            -- quiet (remove the header in list)
    -j jailname   -- Specifies the jailname
    -v version    -- Specifies which version of FreeBSD we want in jail
    -a arch       -- Indicates architecture of the jail: i386 or amd64
                     (Default: same as host)
    -f fs         -- FS name (tank/jails/myjail)
    -M mountpoint -- mountpoint
    -m method     -- when used with -c forces the method to use by default
                     \"ftp\", could also be \"svn\", \"svn+http\", \"svn+ssh\",
		     \"csup\" please note that with svn and csup the world
		     will be built. note that building from sources can use
		     src.conf and jail-src.conf from localbase/etc/poudriere.d
    -t version    -- version to upgrade to"
	exit 1
}

info_jail() {
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	nbb=$(zget stats_built|sed -e 's/ //g')
	nbf=$(zget stats_failed|sed -e 's/ //g')
	nbi=$(zget stats_ignored|sed -e 's/ //g')
	nbs=$(zget stats_skipped|sed -e 's/ //g')
	nbq=$(zget stats_queued|sed -e 's/ //g')
	tobuild=$((nbq - nbb - nbf - nbi - nbs))
	zfs list -H -o ${NS}:type,${NS}:name,${NS}:version,${NS}:arch,${NS}:stats_built,${NS}:stats_failed,${NS}:stats_ignored,${NS}:stats_skipped,${NS}:status,${NS}:method ${JAILFS}| \
		awk -v q="$nbq" -v tb="$tobuild" '/^rootfs/  {
			print "Jailname: " $2;
			print "FreeBSD version: " $3;
			print "FreeBSD arch: "$4;
			print "install/update method: "$10;
			print "Status: "$9;
			print "Packages built: "$5;
			print "Packages failed: "$6;
			print "Packages ignored: "$7;
			print "Packages skipped: "$8;
			print "Packages queued: "q;
			print "Packages to be built: "tb;
		}'
}

list_jail() {
	[ ${QUIET} -eq 0 ] && \
		printf '%-20s %-20s %-7s %-7s %-7s %-7s %-7s %-7s %-7s %s\n' "JAILNAME" "VERSION" "ARCH" "METHOD" "SUCCESS" "FAILED" "IGNORED" "SKIPPED" "QUEUED" "STATUS"
	zfs list -rt filesystem -H \
		-o ${NS}:type,${NS}:name,${NS}:version,${NS}:arch,${NS}:method,${NS}:stats_built,${NS}:stats_failed,${NS}:stats_ignored,${NS}:stats_skipped,${NS}:stats_queued,${NS}:status ${ZPOOL}${ZROOTFS} | \
		awk '$1 == "rootfs" { printf("%-20s %-20s %-7s %-7s %-7s %-7s %-7s %-7s %-7s %s\n",$2, $3, $4, $5, $6, $7, $8, $9, $10, $11) }'
}

delete_jail() {
	test -z ${JAILNAME} && usage
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs && \
		err 1 "Unable to remove jail ${JAILNAME}: it is running"

	msg_n "Removing ${JAILNAME} jail..."
	zfs destroy -r ${JAILFS}
	rmdir ${JAILMNT}
	rm -rf ${POUDRIERE_DATA}/packages/${JAILNAME}
	rm -rf ${POUDRIERE_DATA}/cache/${JAILNAME}
	rm -f ${POUDRIERE_DATA}/logs/*-${JAILNAME}.*.log
	rm -f ${POUDRIERE_DATA}/logs/bulk-${JAILNAME}.log
	rm -rf ${POUDRIERE_DATA}/logs/*/${JAILNAME}
	echo done
}

cleanup_new_jail() {
	msg "Error while creating jail, cleaning up." >&2
	delete_jail
}

update_jail() {
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs && \
		err 1 "Unable to remove jail ${JAILNAME}: it is running"

	METHOD=`zget method`
	if [ "${METHOD}" = "-" ]; then
		METHOD="ftp"
		zset method "${METHOD}"
	fi
	case ${METHOD} in
	ftp)
		JAILMNT=`jail_get_base ${JAILNAME}`
		jail_start
		jail -r ${JAILNAME} >/dev/null
		jrun 1
		if [ -z "${TORELEASE}" ]; then
			injail /usr/sbin/freebsd-update fetch install
		else
			yes | injail env PAGER=/bin/cat /usr/sbin/freebsd-update -r ${TORELEASE} upgrade install || err 1 "Fail to upgrade system"
			yes | injail env PAGER=/bin/cat /usr/sbin/freebsd-update install || err 1 "Fail to upgrade system"
			zset version "${TORELEASE}"
		fi
		zfs destroy -r ${JAILFS}@clean
		zfs snapshot ${JAILFS}@clean
		jail_stop
		;;
	csup)
		msg "Upgrading using csup"
		install_from_csup
		yes | make -C ${JAILMNT}/usr/src delete-old delete-old-libs DESTDIR=${JAILMNT}
		zfs destroy -r ${JAILFS}@clean
		zfs snapshot ${JAILFS}@clean
		;;
	svn*)
		install_from_svn
		yes | make -C ${JAILMNT} delete-old delete-old-libs DESTDIR=${JAILMNT}
		zfs destroy -r ${JAILFS}@clean
		zfs snapshot ${JAILFS}@clean
		;;
	allbsd)
		err 1 "Upgrade is not supported with allbsd, to upgrade, please delete and recreate the jail"
		;;
	*)
		err 1 "Unsupported method"
		;;
	esac

}

build_and_install_world() {
	export TARGET_ARCH=${ARCH}
	export SRC_BASE=${JAILMNT}/usr/src
	mkdir -p ${JAILMNT}/etc
	[ -f ${JAILMNT}/etc/src.conf ] && rm -f ${JAILMNT}/etc/src.conf
	[ -f ${POUDRIERED}/src.conf ] && cat ${POUDRIERED}/src.conf > ${JAILMNT}/etc/src.conf
	[ -f ${POUDRIERED}/${JAILMNT}-src.conf ] && cat ${POUDRIERED}/${JAILMNT}-src.conf >> ${JAILMNT}/etc/src.conf
	unset MAKEOBJPREFIX
	export __MAKE_CONF=/dev/null
	export SRCCONF=${JAILMNT}/etc/src.conf
	msg "Starting make buildworld"
	make -C ${JAILMNT}/usr/src buildworld ${MAKEWORLDARGS} || err 1 "Fail to build world"
	msg "Starting make installworld"
	make -C ${JAILMNT}/usr/src installworld DESTDIR=${JAILMNT} || err 1 "Fail to install world"
	make -C ${JAILMNT}/usr/src DESTDIR=${JAILMNT} distrib-dirs && \
	make -C ${JAILMNT}/usr/src DESTDIR=${JAILMNT} distribution
}

install_from_svn() {
	local UPDATE=0
	local proto
	[ -d ${JAILMNT}/usr/src ] && UPDATE=1
	mkdir -p ${JAILMNT}/usr/src
	case ${METHOD} in
	svn+http) proto="http" ;;
	svn+ssh) proto="svn+ssh" ;;
	svn) proto="svn" ;;
	esac
	if [ ${UPDATE} -eq 0 ]; then
		msg_n "Checking out the sources from svn..."
		svn -q co ${proto}://${SVN_HOST}/base/${VERSION} ${JAILMNT}/usr/src || err 1 "Fail "
		echo " done"
	else
		msg_n "Updating the sources from svn..."
		svn -q update ${JAILMNT}/usr/src || err 1 "Fail "
		echo " done"
	fi
	build_and_install_world
}

install_from_csup() {
	local UPDATE=0
	[ -d ${JAILMNT}/usr/src ] && UPDATE=1
	mkdir -p ${JAILMNT}/etc
	mkdir -p ${JAILMNT}/var/db
	mkdir -p ${JAILMNT}/usr
	[ -z ${CSUP_HOST} ] && err 2 "CSUP_HOST has to be defined in the configuration to use csup"
	if [ "${UPDATE}" -eq 0 ]; then
		echo "*default base=${JAILMNT}/var/db
*default prefix=${JAILMNT}/usr
*default release=cvs tag=${VERSION}
*default delete use-rel-suffix
src-all" > ${JAILMNT}/etc/supfile
	fi
	csup -z -h ${CSUP_HOST} ${JAILMNT}/etc/supfile || err 1 "Fail to fetch sources"
	build_and_install_world
}

install_from_ftp() {
	mkdir ${JAILMNT}/fromftp
	local URL BASEURL

	if [ ${VERSION%%.*} -lt 9 ]; then
		msg "Fetching sets for FreeBSD ${VERSION} ${ARCH}"
		case ${METHOD} in
		ftp) BASEURL="${FREEBSD_HOST}/pub/FreeBSD/releases/${ARCH}/" ;;
		allbsd) BASEURL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}" ;;
		esac
		URL="${BASEURL}/${VERSION}"
		DISTS="base dict src"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32"
		for dist in ${DISTS}; do
			fetch_file ${JAILMNT}/fromftp/ ${URL}/$dist/CHECKSUM.SHA256 || \
				err 1 "Fail to fetch checksum file"
			sed -n "s/.*(\(.*\...\)).*/\1/p" \
				${JAILMNT}/fromftp/CHECKSUM.SHA256 | \
				while read pkg; do
				[ ${pkg} = "install.sh" ] && continue
				# Let's retry at least one time
				fetch_file ${JAILMNT}/fromftp/ ${URL}/${dist}/${pkg}
			done
		done

		msg "Extracting sets:"
		for SETS in ${JAILMNT}/fromftp/*.aa; do
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
			cat ${JAILMNT}/fromftp/${SET}.* | \
				tar --unlink -xpf - -C ${JAILMNT}/${APPEND} || err 1 " Fail" && echo " done"
		done
	else
		case ${METHOD} in
		ftp) BASEURL="${FREEBSD_HOST}/pub/FreeBSD/releases/${ARCH}/${ARCH}" ;;
		allbsd) BASEURL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}" ;;
		esac
		URL="${BASEURL}/${VERSION}"
		DISTS="base.txz src.txz"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32.txz"
		for dist in ${DISTS}; do
			msg "Fetching ${dist} for FreeBSD ${VERSION} ${ARCH}"
			fetch_file ${JAILMNT}/fromftp/${dist} ${URL}/${dist}
			msg_n "Extracting ${dist}..."
			tar -xpf ${JAILMNT}/fromftp/${dist} -C  ${JAILMNT}/ || err 1 " fail" && echo " done"
		done
	fi

	msg_n "Cleaning up..."
	rm -rf ${JAILMNT}/fromftp/
	echo " done"
}

create_jail() {
	jail_exists ${JAILNAME} && err 2 "The jail ${JAILNAME} already exists"

	test -z ${VERSION} && usage

	if [ -z ${JAILMNT} ]; then
		[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"
		JAILMNT=${BASEFS}/jails/${JAILNAME}
	fi

	if [ -z ${JAILFS} ] ; then
		[ -z ${ZPOOL} ] && err 1 "Please provide a ZPOOL variable in your poudriere.conf"
		JAILFS=${ZPOOL}${ZROOTFS}/jails/${JAILNAME}
	fi

	case ${METHOD} in
	ftp)
		FCT=install_from_ftp
		;;
	allbsd)
		FCT=install_from_ftp
		ALLBSDVER=`fetch -qo - \
			https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/ | \
			sed -n "s,.*href=\"\(.*${VERSION}.*\)-JPSNAP/\".*,\1,p" | \
			sort -k 3 -t - -r | head -n 1 `
		if [ -z ${ALLBSDVER} ]; then
			err 1 "Unknown version $VERSION"
		fi

		OIFS=${IFS}
		IFS=-
		set -- ${ALLBSDVER}
		IFS=${OIFS}
		RELEASE="${ALLBSDVER}-JPSNAP/ftp"
		;;
	svn*)
		SVN=`which svn`
		test -z ${SVN} && err 1 "You need svn on your host to use svn method"
		case ${VERSION} in
			stable/*![0-9]*)
				err 1 "bad version number for stable version"
				;;
			release/*![0-9]*.[0-9].[0-9])
				err 1 "bad version number for release version"
				;;
			releng/*![0-9]*.[0-9])
				err 1 "bad version number for releng version"
				;;
			stable/*|head|release/*|releng/*.[0-9]) ;;
			*)
				err 1 "version with svn should be: head or stable/N or release/N or releng/N"
				;;
		esac
		FCT=install_from_svn
		;;
	csup)
		case ${VERSION} in
			.)
				;;
			RELENG_*![0-9]*_[0-9])
				err 1 "bad version number for RELENG"
				;;
			RELENG_*![0-9]*)
				err 1 "bad version number for RELENG"
				;;
			RELENG_*|.) ;;
			*)
				err 1 "version with svn should be: head or stable/N or release/N or releng/N"
				;;
		esac
		FCT=install_from_csup
		;;
	*)
		err 2 "Unknown method to create the jail"
		;;
	esac

	jail_create_zfs ${JAILNAME} ${VERSION} ${ARCH} ${JAILMNT} ${JAILFS}
	# Wrap the jail creation in a special cleanup hook that will remove the jail
	# if any error is encountered
	CLEANUP_HOOK=cleanup_new_jail
	zset method "${METHOD}"
	${FCT}
	eval `grep "^[RB][A-Z]*=" ${JAILMNT}/usr/src/sys/conf/newvers.sh `
	RELEASE=${REVISION}-${BRANCH}
	zset version "${RELEASE}"

	OSVERSION=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILMNT}/usr/include/sys/param.h`
	LOGIN_ENV=",UNAME_r=${RELEASE},UNAME_v=FreeBSD ${RELEASE},OSVERSION=${OSVERSION}"

	if [ "${ARCH}" = "i386" -a "${REALARCH}" = "amd64" ];then
		LOGIN_ENV="${LOGIN_ENV},UNAME_p=i386,UNAME_m=i386"
		cat > ${JAILMNT}/etc/make.conf << EOF
ARCH=i386
MACHINE=i386
MACHINE_ARCH=i386
EOF

	fi

	sed -i .back -e "s/:\(setenv.*\):/:\1${LOGIN_ENV}:/" ${JAILMNT}/etc/login.conf
	cap_mkdb ${JAILMNT}/etc/login.conf
	pwd_mkdb -d ${JAILMNT}/etc/ -p ${JAILMNT}/etc/master.passwd

	cat >> ${JAILMNT}/etc/make.conf << EOF
USE_PACKAGE_DEPENDS=yes
BATCH=yes
WRKDIRPREFIX=/wrkdirs
EOF

	mkdir -p ${JAILMNT}/usr/ports
	mkdir -p ${JAILMNT}/wrkdirs
	mkdir -p ${POUDRIERE_DATA}/logs

	jail -U root -c path=${JAILMNT} command=/sbin/ldconfig -m /lib /usr/lib /usr/lib/compat

	zfs snapshot ${JAILFS}@clean
	unset CLEANUP_HOOK
	msg "Jail ${JAILNAME} ${VERSION} ${ARCH} is ready to be used"
}

ARCH=`uname -m`
REALARCH=${ARCH}
START=0
STOP=0
LIST=0
DELETE=0
CREATE=0
QUIET=0
INFO=0
UPDATE=0

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

while getopts "j:v:a:z:m:n:f:M:sdklqciut:" FLAG; do
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
			JAILFS=${OPTARG}
			;;
		M)
			JAILMNT=${OPTARG}
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
		u)
			UPDATE=1
			;;
		t)
			TORELEASE=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

METHOD=${METHOD:-ftp}
if [ -n "${JAILNAME}" ] && [ ${CREATE} -eq 0 ]; then
	JAILFS=`jail_get_fs ${JAILNAME}`
	JAILMNT=`jail_get_base ${JAILNAME}`
fi


[ $(( CREATE + LIST + STOP + START + DELETE + INFO + UPDATE )) -lt 1 ] && usage

case "${CREATE}${LIST}${STOP}${START}${DELETE}${INFO}${UPDATE}" in
	1000000)
		test -z ${JAILNAME} && usage
		create_jail
		;;
	0100000)
		list_jail
		;;
	0010000)
		test -z ${JAILNAME} && usage
		jail_stop
		;;
	0001000)
		export SET_STATUS_ON_START=0
		test -z ${JAILNAME} && usage
		jail_start
		jail -r ${JAILNAME} >/dev/null
		jrun 1
		;;
	0000100)
		test -z ${JAILNAME} && usage
		delete_jail
		;;
	0000010)
		test -z ${JAILNAME} && usage
		info_jail
		;;
	0000001)
		test -z ${JAILNAME} && usage
		update_jail
		;;
esac
