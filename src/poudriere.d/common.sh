#!/bin/sh

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\"" >&2
	fi
	[ ${STATUS} -eq 1 ] && cleanup
	echo "$2" >&2
	exit $1
}

msg_n() {
	echo -n "====>> $1"
}

msg() {
	echo "====>> $1"
}

sig_handler() {
	if [ ${STATUS} -eq 1 ]; then
		msg "Signal caught, cleaning up and exiting"
		cleanup
	fi
	return ${STATUS}
}

jail_exists() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name | \
		egrep -q "^rootfs[[:space:]]$1$" && return 0
	return 1
}

jail_runs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	[ -e /var/run/poudriere-${1}.lock ] && return 0
	return 1
}

jail_get_base() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name,mountpoint | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_version() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name,poudriere:version | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_fs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name,name | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_zpool_version() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	FS=`jail_get_fs $1`
	ZVERSION=$(zpool get version ${FS%%/*} | awk '/^'${FS%%/*}'/ { print $3 }')
	echo $ZVERSION
}

jail_ls() {
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name | \
		awk '/^rootfs/ { print $2 }'
}

port_exists() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name,name | \
		egrep -q "^ports[[:space:]]$1" && return 0
	return 1
}

port_get_base() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name,mountpoint | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

port_get_fs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -rH -o poudriere:type,poudriere:name,name | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

fetch_file() {
	fetch -o $1 $2 || fetch -o $1 $2
}

jail_create_zfs() {
	[ $# -ne 5 ] && err 1 "Fail: wrong number of arguments"
	NAME=$1
	VERSION=$2
	ARCH=$3
	JAILBASE=$( echo $4 | sed -e "s,//,/,g")
	FS=$5
	msg_n "Creating ${NAME} fs..."
	zfs create -p \
		-o poudriere:type=rootfs \
		-o poudriere:name=${NAME} \
		-o poudriere:version=${VERSION} \
		-o poudriere:arch=${ARCH} \
		-o mountpoint=${JAILBASE} ${FS} || err 1 " Fail" && echo " done"
}

jail_start() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	NAME=$1
	jail_exists ${NAME} || err 1 "No such jail: ${NAME}"
	jail_runs ${NAME} && err 1 "jail already running: ${NAME}"
	touch /var/run/poudriere-${NAME}.lock
	UNAME_r=`jail_get_version ${NAME}`
	export UNAME_r
	UNAME_v="FreeBSD ${UNAME_r}"
	export UNAME_v
	MNT=`jail_get_base ${NAME}`
	JAILMNT=${MNT}
	export JAILMNT

	. /etc/rc.subr
	. /etc/defaults/rc.conf

	msg "Mounting devfs"
	devfs_mount_jail "${MNT}/dev"
	msg "Mounting /proc"
	[ ! -d ${MNT}/proc ] && mkdir ${MNT}/proc
	mount -t procfs proc ${MNT}/proc
	msg "Mounting linuxfs"
	[ ! -d ${MNT}/compat/linux/proc ] && mkdir -p ${MNT}/compat/linux/proc
	[ ! -d ${MNT}/compat/linux/sys ] && mkdir -p ${MNT}/compat/linux/sys
	mount -t linprocfs linprocfs ${MNT}/compat/linux/proc
	mount -t linsysfs linsysfs ${MNT}/compat/linux/sys
	test -n "${RESOLV_CONF}" && cp -v "${RESOLV_CONF}" "${MNT}/etc/"
	msg "Starting jail ${NAME}"
}

jail_stop() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	NAME=${1}
	jail_runs ${NAME} || err 1 "No such jail running: ${NAME}"

	JAILBASE=`jail_get_base ${NAME}`
	msg "Stopping jail"
	rm -f /var/run/poudriere-${NAME}.lock
	msg "Umounting file systems"
	for MNT in $( mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do umount -f ${MNT}
	done

	if [ -n "${MFSSIZE}" ]; then
		MDUNIT=$(mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 ~ /\/dev\/md/ ) { sub(/\/dev\/md/, "", $1); print $1 }}')
		umount ${JAILBASE}/wrkdirs
		mdconfig -d -u ${MDUNIT}
	fi
	zfs rollback ${ZPOOL}/poudriere/${NAME}@clean
}

port_create_zfs() {
	[ $# -ne 3 ] && err 2 "Fail: wrong number of arguments"
	NAME=$1
	MNT=$( echo $2 | sed -e 's,//,/,g')
	FS=$3
	msg_n "Creating ${NAME} fs..."
	zfs create -p \
		-o mountpoint=${MNT} \
		-o poudriere:type=ports \
		-o poudriere:name=${NAME} \
		${FS} || err 1 " Fail" && echo " done"
		
}

cleanup() {
	[ -e ${PIPE} ] && rm -f ${PIPE}
	FS=`jail_get_fs ${JAILNAME}`
	[ -f ${deplist} ] && rm -f ${deplist}
	zfs destroy ${FS}@prepkg 2>/dev/null || :
	zfs destroy ${FS}@prebuild 2>/dev/null || :
	jail_stop ${JAILNAME}
}

injail() {
	chroot -u root ${JAILMNT} env UNAME_v="${UNAME_v}" UNAME_r="${UNAME_r}" $@
}

sanity_check_pkgs() {
	[ ! -d ${PKGDIR}/Latest ] && return
	[ ! -d ${PKGDIR}/All ] && return
	[ -z "$(ls -A ${PKGDIR}/Latest)" ] && return
	for pkg in ${PKGDIR}/Latest/*.${EXT}; do
		realpkg=$(realpath $pkg)
		if [ ! -e $realpkg ]; then
			msg "Deleting stale symlinks ${pkg##*/}"
			find ${PKGDIR}/ -name ${pkg##*/} -delete
			continue
		fi

		if [ "${EXT}" = "tbz" ]; then
			for dep in $(pkg_info -qr $pkg | awk '{ print $2 }'); do
				if [ ! -e ${PKGDIR}/All/$dep.${EXT} ]; then
					msg "Deleting ${realpkg##*/}: missing dependencies"
					rm -f ${realpkg}
					find ${PKGDIR}/ -name ${pkg##*/} -delete
					break
				fi
			done
		else
			for dep in $(pkg info -qdF $pkg); do
				if [ ! -e ${PKGDIR}/All/$dep.${EXT} ]; then
					msg "Deleting ${realpkg##*/}: missing dependencies"
					rm -f ${realpkg}
					find ${PKGDIR}/ -name ${pkg##*/} -delete
					break
				fi
			done
		fi
	done
}

build_pkg() {
	local port=$1
	local portdir="/usr/ports/${port}"
	test -d ${JAILBASE}/${portdir} || {
		msg "No such port ${port}"
		return 1
	}
	local LATEST_LINK=$(injail make -C ${portdir} -VLATEST_LINK)
	local PKGNAME=$(injail make -C ${portdir} -VPKGNAME)

	# delete older one if any
	if [ -e ${PKGDIR}/Latest/${LATEST_LINK}.${EXT} ]; then
		PKGNAME_PREV=$(realpath ${PKGDIR}/Latest/${LATEST_LINK}.${EXT})
		if [ "${PKGNAME_PREV##*/}" = "${PKGNAME}.${EXT}" ]; then
			msg "$PKGNAME already packaged skipping"
			return 2
		else
			msg "Deleting previous version of ${port}"
			find ${PKGDIR}/ -name ${PKGNAME_PREV##*/} -delete
			find ${PKGDIR}/ -name ${LATEST_LINK}.${EXT} -delete
			sanity_check_pkgs
		fi
	fi

	if [ -e ${PKGDIR}/All/${PKGNAME}.${EXT} ]; then
		msg "$PKGNAME already packaged skipping"
		return 2
	fi

	msg "Cleaning up wrkdir"
	rm -rf ${JAILBASE}/wrkdirs/*

	msg "Building ${port}"
	injail make -C ${portdir} fetch-depends extract-depends patch-depends build-depends lib-depends
	injail make -C ${portdir} clean package
	if [ $? -eq 0 ]; then
		STATS_BUILT=$(($STATS_BUILT + 1))
		return 0
	else
		STATS_FAILED=$(($STATS_FAILED + 1))
		FAILED_PORTS="$FAILED_PORTS ${port}"
		return 1
	fi
}

list_deps() {
	[ -z ${1} ] && return 0
	LIST="BUILD_DEPENDS EXTRACT_DEPENDS LIB_DEPENDS PATCH_DEPENDS FETCH_DEPENDS RUN_DEPENDS"
	MAKEARGS=""
	for key in $LIST; do
		MAKEARGS="${MAKEARGS} -V${key}"
	done
	injail make -C ${1} $MAKEARGS | sed -e "s,[[:graph:]]*/usr/ports/,,g" | \
		tr ' ' '\n' | egrep -v ".*:.*" | sort -u
}

process_deps() {
	tmplist=$1
	deplist=$2
	tmplist2=$3
	local port=$4
	local PORTDIRECTORY="/usr/ports/${port}"
	egrep -q "^$port$" ${tmplist} && return
	echo $port >> ${tmplist}
	deps=0
	local m
	for m in `list_deps ${PORTDIRECTORY}`; do
		process_deps "${tmplist}" "${deplist}" "${tmplist2}" "$m"
		echo $m $port >> ${deplist}
		deps=1
	done
	if [ $deps -eq 0 ] ;then
		echo $port >> ${tmplist2}
	fi
}

prepare_ports() {
	tmplist=`mktemp /tmp/orderport.XXXXXX`
	deplist=`mktemp /tmp/orderport2.XXXXX`
	tmplist2=`mktemp /tmp/orderport3.XXXXX`
	touch ${tmplist}
	if [ -z "${LISTPORTS}" ]; then
		for port in `grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}`; do
			process_deps "${tmplist}" "${deplist}" "$tmplist2" "${port}"
		done
	else
		for port in ${LISTPORTS}; do
			process_deps "${tmplist}" "${deplist}" "$tmplist2" "${port}"
		done
	fi
	tsort ${deplist} | while read port; do
		egrep -q "^${port}$" ${tmplist2} || echo $port >> ${tmplist2}
	done
	cat ${tmplist2}
	rm -f ${tmplist} ${tmplist2}
}

prepare_jail() {
	export PACKAGE_BUILDING=yes
	POUDRIERE_PORTSDIR=`port_get_base ${PTNAME}`/ports
	[ -z "${JAILBASE}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${POUDRIERE_PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

	mount -t nullfs ${POUDRIERE_PORTSDIR} ${JAILBASE}/usr/ports || err 1 "Failed to mount the ports directory "

	[ -d ${POUDRIERE_PORTSDIR}/packages ] || mkdir -p ${POUDRIERE_PORTSDIR}/packages
	[ -d ${PKGDIR}/All ] || mkdir -p ${PKGDIR}/All

	mount -t nullfs ${PKGDIR} ${JAILBASE}/usr/ports/packages || err 1 "Failed to mount the packages directory "
	if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
		[ -d ${JAILBASE}/usr/ports/distfiles ] || mkdir -p ${JAILBASE}/usr/ports/distfiles
		mount -t nullfs ${DISTFILES_CACHE} ${JAILBASE}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
	fi

	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILBASE}/wrkdirs
	[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILBASE}/wrkdirs

	if [ -d ${SCRIPTPREFIX}/../../etc/poudriere.d ]; then
		[ -f ${SCRIPTPREFIX}/../../etc/poudriere.d/make.conf ] && cat ${SCRIPTPREFIX}/../../etc/poudriere.d/make.conf >> ${JAILBASE}/etc/make.conf
		[ -f ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-make.conf ] && cat ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-make.conf >> ${JAILBASE}/etc/make.conf
	fi

	if [ -d ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-options ]; then
		mount -t nullfs ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-options ${JAILBASE}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	elif [ -d ${SCRIPTPREFIX}/../../etc/poudriere.d/options ]; then
		mount -t nullfs ${SCRIPTPREFIX}/../../etc/poudriere.d/options ${JAILBASE}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	fi

	msg "Populating LOCALBASE"
	injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p /usr/local >/dev/null
}

RESOLV_CONF=""
STATUS=0 # out of jail #

test -f ${SCRIPTPREFIX}/../../etc/poudriere.conf || err 1 "Unable to find ${SCRIPTPREFIX}/../../etc/poudriere.conf"
. ${SCRIPTPREFIX}/../../etc/poudriere.conf

test -z ${ZPOOL} && err 1 "ZPOOL variable is not set"

trap sig_handler SIGINT SIGTERM SIGKILL EXIT

PIPE=/tmp/poudriere$$.pipe
LOGS="${POUDRIERE_DATA}/logs"


# Test if spool exists
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool : ${ZPOOL}"
ZVERSION=$(zpool get version ${ZPOOL} | awk '/^'${ZPOOL}'/ { print $3 }')
