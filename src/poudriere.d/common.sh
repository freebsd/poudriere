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

log_start() {
	exec 3>&1 4>&2
	[ ! -e $1.pipe ] && mkfifo $1.pipe
	tee $1 < $1.pipe >&3 &
	export tpid=$!
	exec > $1.pipe 2>&1
}

log_stop() {
	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid
	rm -f $1.pipe
}

zfs_get() {
	[ $# -ne 1 ] && err 1 "Fail: need one argument"
	[ -z "${JAILFS}" ] && err 1 "No JAILFS defined"
	zfs get -H -o value ${1} ${JAILFS}
}

zfs_set() {
	[ $# -ne 2 ] && err 1 "Fail: need two arguments got $@"
	[ -z "${JAILFS}" ] && err 1 "No JAILFS defined"
	zfs set $1="$2" ${JAILFS}
}

status_get() {
	[ $# -ne 1 ] && err 1 "Fail: need one argument"
	cat /var/run/poudriere-${JAILNAME}-${1}
}

status_set() {
	[ $# -ne 2 ] && err 1 "Fail: need two arguments got $@"
	echo "$2" > /var/run/poudriere-${JAILNAME}-${1}
}

jail_status() {
	zfs_set poudriere:status "$1"
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
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name ${ZPOOL}/poudriere | \
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
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name,mountpoint ${ZPOOL}/poudriere | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_version() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name,poudriere:version ${ZPOOL}/poudriere | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_fs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name,name ${ZPOOL}/poudriere | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_zpool_version() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	FS=`jail_get_fs $1`
	zpool list -H -oversion ${FS%%/*}
}

jail_ls() {
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name ${ZPOOL}/poudriere | \
		awk '/^rootfs/ { print $2 }'
}

port_exists() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name,name ${ZPOOL}/poudriere | \
		egrep -q "^ports[[:space:]]$1" && return 0
	return 1
}

port_get_base() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name,mountpoint ${ZPOOL}/poudriere | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

port_get_fs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -t filesystem -Hd1 -o poudriere:type,poudriere:name,name ${ZPOOL}/poudriere | \
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
	export JAILBASE=`jail_get_base ${JAILNAME}`
	export JAILFS=`jail_get_fs ${NAME}`

	jail_exists ${NAME} || err 1 "No such jail: ${NAME}"
	jail_runs ${NAME} && err 1 "jail already running: ${NAME}"
	jail_status "start:"
	zfs rollback -r ${ZPOOL}/poudriere/${NAME}@clean
	touch /var/run/poudriere-${NAME}.lock
	export UNAME_r=`jail_get_version ${NAME}`
	export UNAME_v="FreeBSD ${UNAME_r}"
	MNT=`jail_get_base ${NAME}`

	. /etc/defaults/rc.conf

	msg "Mounting devfs"
	mount -t devfs devfs ${MNT}/dev
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
	export STATUS=1
}

jail_stop() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	NAME=${1}
	jail_runs ${NAME} || err 1 "No such jail running: ${NAME}"
	jail_status "stop:"

	msg "Stopping jail"
	jail -r ${NAME}
	msg "Umounting file systems"
	for MNT in $( mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do
		umount -f ${MNT}
	done

	if [ -n "${MFSSIZE}" ]; then
		MDUNIT=$(mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 ~ /\/dev\/md/ ) { sub(/\/dev\/md/, "", $1); print $1 }}')
		if [ -n "$MDUNIT" ]; then
			umount ${JAILBASE}/wrkdirs
			mdconfig -d -u ${MDUNIT}
		fi
	fi
	zfs rollback -r ${ZPOOL}/poudriere/${NAME}@clean
	jail_status "idle:"
	export STATUS=0
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
	local NO_LATEST_LINK=$(injail make -C ${portdir} -VNO_LATEST_LINK)

	# delete older one if any
	if [ -z "$NO_LATEST_LINK" ]; then
		local LATEST_LINK=$(injail make -C ${portdir} -VLATEST_LINK)
		if [ -e ${PKGDIR}/Latest/${LATEST_LINK}.${EXT} ]; then
			local PKGNAME_PREV=$(realpath ${PKGDIR}/Latest/${LATEST_LINK}.${EXT})
			find ${PKGDIR}/ -name ${PKGNAME_PREV##*/} -delete
			find ${PKGDIR}/ -name ${LATEST_LINK}.${EXT} -delete
		fi
	fi
}

sanity_check_pkgs() {
	ret=0
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
					ret=1
					msg "Deleting ${realpkg##*/}: missing dependencies"
					rm -f ${realpkg}
					find ${PKGDIR}/ -name ${pkg##*/} -delete
					break
				fi
			done
		else
			for dep in $(pkg info -qdF $pkg); do
				if [ ! -e ${PKGDIR}/All/$dep.${EXT} ]; then
					ret=1
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
		zfs_set "poudriere:status" "${PHASE}:${PORTDIR##/usr/ports/}"
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
			jail -c persist name=${NAME} ip4.addr=127.0.0.1 ip6=disable path=${MNT} host.hostname=${NAME} \
				allow.sysvipc allow.mount allow.socket_af allow.raw_sockets
		fi
		if [ -n "${PORTTESTING}" -a  "${PHASE}" = "deinstall" ]; then
			msg "Checking for extra files and directories"
			zfs_set "poudriere:status" "fscheck:${PORTDIR##/usr/ports/}"
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
					case $mod$type in
						+/) 
							case "${PPATH}" in
								/tmp/*) continue ;;
								*) echo "@dirrmtry ${PPATH}" >> ${DIRS} ;;
							esac
							;;
						+*)
							case "${PPATH}" in
								/var/db/pkg/local.sqlite) continue ;;
								/tmp/*) continue ;;
								/var/run/ld-elf.so.hints) continue ;;
								share/nls/POSIX) continue ;;
								share/nls/en_US.US-ASCII) continue ;;
								*) echo "${PPATH}" >> ${FILES} ;;
							esac
							;;
						-*)
							[ "${PPATH}" = "/var/run/ld-elf.so.hints" ] && continue
							msg "!!!MISSING!!!: ${PPATH}"
							;;
						M/) continue ;;
						M*)
							[ "${PPATH}" = "/var/db/pkg/local.sqlite" ] && continue
							[ "${PPATH}" = "/etc/spwd.db" ] && continue
							[ "${PPATH}" = "/etc/pwd.db" ] && continue
							[ "${PPATH}" = "/etc/passwd" ] && continue
							[ "${PPATH}" = "/etc/master.passwd" ] && continue
							[ "${PPATH}" = "/etc/shell" ] && continue
							[ "${PPATH}" = "/etc/shell" ] && continue
							msg "!!!MODIFIED!!!: ${PPATH}"
							;;
					esac
				done
				sort ${FILES}
				sort -r ${DIRS}
				rm ${FILES} ${DIRS}
			fi
		fi
	done
	zfs_set "poudriere:status" "idle:"
	zfs destroy ${JAILFS}@prebuild || :
	return 0
}

build_pkg() {
	local port=$1
	local portdir="/usr/ports/${port}"

	# If this port is IGNORED, skip it
	# This is checked here instead of when building the queue
	# as the list may start big but become very small, so here
	# is a less-common check
	local IGNORE="$(injail make -C ${portdir} -VIGNORE)"
	if [ -n "$IGNORE" ]; then
		msg "Ignoring ${port}: $IGNORE"
		return
	fi

	msg "Cleaning up wrkdir"
	rm -rf ${JAILBASE}/wrkdirs/*

	msg "Building ${port}"
	PKGNAME=$(injail make -C ${portdir} -VPKGNAME)
	log_start ${LOGS}/${JAILNAME}-${PTNAME}-${PKGNAME}.log
	injail make -C ${portdir} pkg-depends fetch-depends extract-depends \
		patch-depends build-depends lib-depends
	injail make -C ${portdir} clean
	if build_port ${portdir}; then
		cnt=$(zfs_get poudriere:stats_built)
		[ "$cnt" = "-" ] && cnt=0
		cnt=$(( cnt + 1))
		zfs_set "poudriere:stats_built" "$cnt"
		export built="${build} ${port}"
	else
		cnt=$(zfs_get poudriere:stats_failed)
		[ "$cnt" = "-" ] && cnt=0
		cnt=$(( cnt + 1))
		zfs_set "poudriere:stats_failed" "$cnt"
		state=$(zfs_get poudriere:status)
		buf="${buf} ${state}"
		export failed="${failed} ${state}"
	fi
	jail_status "idle:"
	log_stop ${LOGS}/${JAILNAME}-${PTNAME}-${PKGNAME}.log
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

check_pkg() {
	local port=$1
	local portdir="/usr/ports/${port}"
	test -d ${JAILBASE}/${portdir} || {
		msg "No such port ${port}"
		return 1
	}
	local NO_LATEST_LINK=$(injail make -C ${portdir} -VNO_LATEST_LINK)

	# delete older one if any
	if [ -z "$NO_LATEST_LINK" ]; then
		local LATEST_LINK=$(injail make -C ${portdir} -VLATEST_LINK)
		if [ -e ${PKGDIR}/Latest/${LATEST_LINK}.${EXT} ]; then
			local PKGNAME=$(injail make -C ${portdir} -VPKGNAME)
			local PKGNAME_PREV=$(realpath ${PKGDIR}/Latest/${LATEST_LINK}.${EXT})
			if [ "${PKGNAME_PREV##*/}" != "${PKGNAME}.${EXT}" ]; then
				msg "Deleting previous version of ${port}"
				find ${PKGDIR}/ -name ${PKGNAME_PREV##*/} -delete
				find ${PKGDIR}/ -name ${LATEST_LINK}.${EXT} -delete
			fi
		fi
	fi
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
	deplist=$(mktemp ${base}/tmp/orderport1.XXXXX)
	tmplist2=$(mktemp ${base}/tmp/orderport2.XXXXX)
	touch ${tmplist}
	msg "Calculating ports order and dependencies"
	jail_status "orderdeps:"
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

	jail_status "sanity:"
	msg "Sanity checking the repository"
	while read p; do
		check_pkg ${p}
	done < ${tmplist2}

	while :; do
		sanity_check_pkgs && break
	done

	jail_status "cleaning:"
	msg "Cleaning the build queue"
	export LOCALBASE=${MYBASE:-/usr/local}
	while read p; do
		local PKGNAME=$(injail make -C /usr/ports/${p} -VPKGNAME)
		[ ! -f ${PKGDIR}/All/${PKGNAME}.${EXT} ] && queue="${queue} $p"
	done < ${tmplist2}

	rm -f ${tmplist2} ${deplist} ${tmplist}
	export queue
	export built=""
	export failed=""
	zfs_set "poudriere:stats_built" "0"
	zfs_set "poudriere:stats_failed" "0"
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
	mkdir -p ${JAILBASE}/${MYBASE:-/usr/local}
	injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${MYBASE:-/usr/local} >/dev/null

	WITH_PKGNG=`injail make -C /usr/ports -VWITH_PKGNG`
	if [ -n "${WITH_PKGNG}" ]; then
		export PKGNG=1
		export EXT="txz"
		export PKG_ADD="${MYBASE:-/usr/local}/sbin/pkg add"
		export PKG_DELETE="${MYBASE:-/usr/local}/sbin/pkg delete -y -f"
	else
		export PKGNG=0
		export PKG_ADD=pkg_add
		export PKG_DELETE=pkg_delete
		export EXT="tbz"
	fi

	export LOGS=${POUDRIERE_DATA}/logs
}

RESOLV_CONF=""
STATUS=0 # out of jail #

test -f ${SCRIPTPREFIX}/../../etc/poudriere.conf || err 1 "Unable to find ${SCRIPTPREFIX}/../../etc/poudriere.conf"
. ${SCRIPTPREFIX}/../../etc/poudriere.conf

test -z ${ZPOOL} && err 1 "ZPOOL variable is not set"

trap sig_handler SIGINT SIGTERM SIGKILL EXIT

# Test if spool exists
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
ZVERSION=$(zpool list -H -oversion ${ZPOOL})
