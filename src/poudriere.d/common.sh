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
	jls -qj ${1} name > /dev/null 2>&1 && return 0
	return 1
}

jail_running_base() {
	[ $# -ne 1 ] && err 1 "Fail: wrong nomber of arguments"
	jls -qj ${1} path
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
	zpool list -H -oversion ${FS%%/*}
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
	zfs rollback -r ${ZPOOL}/poudriere/${NAME}@clean
	touch /var/run/poudriere-${NAME}.lock
	UNAME_r=`jail_get_version ${NAME}`
	export UNAME_r
	UNAME_v="FreeBSD ${UNAME_r}"
	export UNAME_v
	MNT=`jail_get_base ${NAME}`

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
	jail -c persist name=${NAME} ip4=disable ip6=disable path=${MNT} host.hostname=${NAME} \
		allow.sysvipc allow.mount allow.socket_af allow.raw_sockets
}

jail_stop() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	NAME=${1}
	jail_runs ${NAME} || err 1 "No such jail running: ${NAME}"

	JAILBASE=`jail_get_base ${NAME}`
	msg "Stopping jail"
	jail -r ${NAME}
	msg "Umounting file systems"
	for MNT in $( mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do
		umount -f ${MNT}
	done

	if [ -n "${MFSSIZE}" ]; then
		MDUNIT=$(mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 ~ /\/dev\/md/ ) { sub(/\/dev\/md/, "", $1); print $1 }}')
		umount ${JAILBASE}/wrkdirs
		mdconfig -d -u ${MDUNIT}
	fi
	zfs rollback -r ${ZPOOL}/poudriere/${NAME}@clean
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
	zfs destroy ${FS}@prepkg 2>/dev/null || :
	zfs destroy ${FS}@prebuild 2>/dev/null || :
	jail_stop ${JAILNAME}
}

injail() {
	jexec -U root ${JAILNAME} $@
}

delete_pkg() {
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
		find ${PKGDIR}/ -name ${PKGNAME_PREV##*/} -delete
		find ${PKGDIR}/ -name ${LATEST_LINK}.${EXT} -delete
	fi
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

build_port() {
	PORTDIR=$1
	msg "Fetch distfiles"
	#fetch_distfiles ${PORTDIR}
	msg "Building ${PKGNAME}"
	for PHASE in fetch extract patch configure build install package deinstall; do
		zfs set "poudriere:status=${PHASE}:${PORTDIR##/usr/ports/}" ${JAILFS}
		if [ "${PHASE}" = "fetch" ]; then
			jail -r ${JAILNAME}
			jail -c persist name=${NAME} ip4=inherit ip6=inherit path=${MNT} host.hostname=${NAME} \
				allow.sysvipc allow.mount allow.socket_af allow.raw_sockets
		fi
		[ "${PHASE}" = "build" -a $ZVERSION -ge 28 ] && zfs snapshot ${JAILFS}@prebuild
		if [ -n "${PORTTESTING}" -a "${PHASE}" = "deinstall" ]; then
			msg "Checking shared library dependencies"
			if [ ${PKGNG} -eq 0 ]; then
				PLIST="/var/db/pkg/${PKGNAME}/+CONTENTS"
				grep -v "^@" ${JAILBASE}${PLIST} | \
					sed -e "s,^,${PREFIX}/," | \
					xargs injail ldd 2>&1 | \
					grep -v "not a dynamic executable" | \
					awk ' /=>/{ print $3 }' | sort -u
			else
				injail pkg query "%Fp" ${PKGNAME} | \
					xargs injail ldd 2>&1 | \
					grep -v "not a dynamic executable" | \
					awk '/=>/ { print $3 }' | sort -u
			fi
		fi
		injail env ${PKGENV} ${PORT_FLAGS} make -C ${1} ${PHASE} || return 1

		if [ "${PHASE}" = "fetch" ]; then
			jail -r ${JAILNAME}
			jail -c persist name=${NAME} ip4.addr=1.2.3.4 ip6=disable path=${MNT} host.hostname=${NAME} \
				allow.sysvipc allow.mount allow.socket_af allow.raw_sockets
		fi
		if [ -n "${PORTTESTING}" -a  "${PHASE}" = "deinstall" ]; then
			msg "Checking for extra files and directories"
			zfs set "poudriere:status=fscheck:${PORTDIR##/usr/ports/}" ${JAILFS}
			if [ $ZVERSION -lt 28 ]; then
				find ${JAILBASE}${PREFIX} ! -type d | \
					sed -e "s,^${JAILBASE}${PREFIX}/,," | sort

				find ${JAILBASE}${PREFIX}/ -type d | sed "s,^${JAILBASE}${PREFIX}/,," | sort > ${JAILBASE}${PREFIX}.PLIST_DIRS.after
				comm -13 ${JAILBASE}${PREFIX}.PLIST_DIRS.before ${JAILBASE}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
			else
				local BASE=$(jail_running_base ${JAILNAME})
				FILES=$(mktemp ${BASE}/tmp/files.XXXXXX)
				DIRS=$(mktemp ${BASE}/tmp/dirs.XXXXXX)
				DIE=0
				zfs diff -FH ${JAILFS}@prebuild ${JAILFS} | \
					while read mod type path; do
					PPATH=`echo "$path" | sed -e "s,^${JAILBASE},," -e "s,^${PREFIX}/,," -e "s,^share/${PORTNAME},%%DATADIR%%," -e "s,^etc,%%ETCDIR%%,"`
					DIE=1
					case $mod$type in
						+/) echo "@dirrmtry ${PPATH}" >> ${DIRS} ;;
						+*) echo "${PPATH}" >> ${FILES} ;;
						-*)
							[ "${PPATH}" = "var/run/ld-elf.so.hints" ] && continue
							msg "!!!MISSING!!!: ${PPATH}"
							;;
						M/) continue ;;
						M*)
							[ "${PPATH}" = "/var/db/pkg/local.sqlite" ] && continue
							[ "${PPATH}" = "%%ETCDIR%%/spwd.db" ] && continue
							[ "${PPATH}" = "%%ETCDIR%%/pwd.db" ] && continue
							[ "${PPATH}" = "%%ETCDIR%%/passwd" ] && continue
							[ "${PPATH}" = "%%ETCDIR%%/master.passwd" ] && continue
							[ "${PPATH}" = "%%ETCDIR%%/shell" ] && continue
							[ "${PPATH}" = "%%ETCDIR%%/shell" ] && continue
							msg "!!!MODIFIED!!!: ${PPATH}"
							;;
					esac
					#egrep -v "[\+|M][[:space:]]*${JAILBASE}${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)" | \
					#egrep -v "[\+|M|-][[:space:]]*${JAILBASE}/wrkdirs" | \
					#egrep -v "/var/db/pkg" | \
					#egrep -v "/var/run/ld-elf.so.hints" | \
					#egrep -v "[\+|M][[:space:]]*${JAILBASE}/tmp/pkgs" | while read type path; do
				done
				if [ $DIE -eq 1 ]; then
					sort ${FILES}
					sort -r ${DIRS}
					rm ${FILES} ${DIRS}
					zfs destroy ${JAILFS}@prebuild || :
					return 1
				fi
				rm ${FILES} ${DIRS}
			fi
		fi
	done
	zfs set "poudriere:status=idle:" ${JAILFS}
	zfs destroy ${JAILFS}@prebuild || :
	return 0
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
	injail make -C ${portdir} pkg-depends fetch-depends extract-depends \
		patch-depends build-depends lib-depends | tee -a \
		${LOGS}/${JAILNAME}-${PKGNAME}-builddepends.log
	injail make -C ${portdir} clean
	set +e
	build_port ${portdir} | tee -a ${LOGS}/${JAILNAME}-${PKGNAME}-buildport.log
	if [ $? -eq 0 ]; then
		STATS_BUILT=$(($STATS_BUILT + 1))
		return 0
	else
		STATS_FAILED=$(($STATS_FAILED + 1))
		FAILED_PORTS="$FAILED_PORTS ${port}"
		return 1
	fi
	set -e
}

list_deps() {
	[ -z ${1} ] && return 0
	LIST="PKG_DEPENDS BUILD_DEPENDS EXTRACT_DEPENDS LIB_DEPENDS PATCH_DEPENDS FETCH_DEPENDS RUN_DEPENDS"
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
	if [ $deps -eq 0 ]; then
		echo $port >> ${tmplist2}
	fi
}

prepare_ports() {
	local base=$(jail_running_base ${JAILNAME})
	tmplist=$(mktemp ${base}/tmp/orderport.XXXXXX)
	deplist=$(mktemp ${base}/tmp/orderport2.XXXXX)
	tmplist2=$(mktemp ${base}/tmp/orderport3.XXXXX)
	touch ${tmplist}
	if [ -z "${LISTPORTS}" ]; then
		if [ -n "${LISTPKGS}" ]; then
			for port in `grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}`; do
				process_deps "${tmplist}" "${deplist}" "$tmplist2" "${port}"
			done
		fi
	else
		for port in ${LISTPORTS}; do
			process_deps "${tmplist}" "${deplist}" "$tmplist2" "${port}"
		done
	fi
	tsort ${deplist} | while read port; do
		egrep -q "^${port}$" ${tmplist2} || echo $port >> ${tmplist2}
	done
	cat ${tmplist2}
}

prepare_jail() {
	export PACKAGE_BUILDING=yes
	PORTSDIR=`port_get_base ${PTNAME}`/ports
	POUDRIERED=${SCRIPTPREFIX}/../../etc/poudriere.d
	[ -z "${JAILBASE}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

	mount -t nullfs ${PORTSDIR} ${JAILBASE}/usr/ports || err 1 "Failed to mount the ports directory "

	[ -d ${PORTSDIR}/packages ] || mkdir -p ${PORTSDIR}/packages
	[ -d ${PKGDIR}/All ] || mkdir -p ${PKGDIR}/All

	mount -t nullfs ${PKGDIR} ${JAILBASE}/usr/ports/packages || err 1 "Failed to mount the packages directory "
	if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
		[ -d ${JAILBASE}/usr/ports/distfiles ] || mkdir -p ${JAILBASE}/usr/ports/distfiles
		mount -t nullfs ${DISTFILES_CACHE} ${JAILBASE}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
	fi

	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILBASE}/wrkdirs
	[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILBASE}/wrkdirs

	[ -f ${POUDRIERED}/make.conf ] && cat ${POUDRIERED}/make.conf >> ${JAILBASE}/etc/make.conf
	[ -f ${POUDRIERED}/${JAILNAME}-make.conf ] && cat ${POUDRIERED}/${JAILNAME}-make.conf >> ${JAILBASE}/etc/make.conf

	if [ -d ${POUDRIERED}/${JAILNAME}-options ]; then
		mount -t nullfs ${POUDRIERED}/${JAILNAME}-options ${JAILBASE}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	elif [ -d ${POUDRIERED}/options ]; then
		mount -t nullfs ${POUDRIERED}/options ${JAILBASE}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
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
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
ZVERSION=$(zpool list -H -oversion ${ZPOOL})
