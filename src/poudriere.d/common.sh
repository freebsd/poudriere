#!/bin/sh

# zfs namespace
ns="poudriere"
IPS="$(sysctl -n kern.features.inet 2>/dev/null || echo 0)$(sysctl -n kern.features.inet6 2>/dev/null || echo 0)"

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	[ ${STATUS} -eq 1 ] && cleanup
	echo "$2" >&2
	[ -n ${CLEANUP_HOOK} ] && ${CLEANUP_HOOK}
	exit $1
}

msg_n() { echo -n "====>> $1"; }
msg() { echo "====>> $1"; }

eargs() {
	case $# in
	0) err 1 "No aruments expected" ;;
	1) err 1 "1 argument expected: $1" ;;
	*) err 1 "$# arguments expected: $@";;
	esac
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
	[ $# -ne 1 ] && eargs zfsproperty
	[ -z "${JAILFS}" ] && err 1 "No JAILFS defined"
	zfs get -H -o value ${1} ${JAILFS}
}

zfs_set() {
	[ $# -ne 2 ] && eargs zfsproperty value
	[ -z "${JAILFS}" ] && err 1 "No JAILFS defined"
	zfs set $1="$2" ${JAILFS}
}

port_set_method() {
	[ $# -ne 2 ] && eargs value fsname
	zfs set ${NS}:method="$2" ${1}
}

port_get_method() {
	[ $# -ne 1 ] && eargs jailname
	zfs get -H -o value "${NS}:method" $1
}

jail_status() {
	[ $# -ne 1 ] && eargs jailname
	zfs_set ${NS}:status "$1"
}

sig_handler() {
	# Only run the handler once, don't re-run on EXIT
	if [ -z "${CAUGHT_SIGNAL}" ]; then
		export CAUGHT_SIGNAL=1
		if [ ${STATUS} -eq 1 ]; then
			msg "Signal caught, cleaning up and exiting"
			cleanup
		fi
	fi
	exit
}

jail_exists() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name ${ZPOOL}/poudriere | \
		egrep -q "^rootfs[[:space:]]$1$" && return 0
	return 1
}

jail_runs() {
	[ $# -ne 1 ] && eargs jailname
	jls -qj ${1} name > /dev/null 2>&1 && return 0
	return 1
}

jail_running_base() {
	[ $# -ne 1 ] && eargs jailname
	jls -qj ${1} path
}

jail_get_base() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}/poudriere | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_version() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name,${NS}:version ${ZPOOL}/poudriere | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_fs() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name,name ${ZPOOL}/poudriere | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_zpool_version() {
	[ $# -ne 1 ] && eargs jailname
	FS=`jail_get_fs $1`
	zpool list -H -oversion ${FS%%/*}
}

jail_ls() {
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name ${ZPOOL}/poudriere | \
		awk '/^rootfs/ { print $2 }'
}

port_exists() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name,name ${ZPOOL}/poudriere | \
		egrep -q "^ports[[:space:]]$1" && return 0
	return 1
}

port_get_base() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}/poudriere | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

port_get_fs() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -t filesystem -Hd1 -o ${NS}:type,${NS}:name,name ${ZPOOL}/poudriere | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

fetch_file() {
	[ $# -ne 2 ] && eargs destination source
	fetch -p -o $1 $2 || fetch -p -o $1 $2
}

jail_create_zfs() {
	[ $# -ne 5 ] && eargs name version arch mountpoint fs
	local name=$1
	local version=$2
	local arch=$3
	local mnt=$( echo $4 | sed -e "s,//,/,g")
	local fs=$5
	msg_n "Creating ${name} fs..."
	zfs create -p \
		-o ${NS}:type=rootfs \
		-o ${NS}:name=${name} \
		-o ${NS}:version=${version} \
		-o ${NS}:arch=${arch} \
		-o mountpoint=${mnt} ${fs} || err 1 " Fail" && echo " done"
}

jail_run() {
	[ $# -ne 3 ] && eargs jname jpath network
	local jname=$1
	local jpath=$2
	local network=$3
	local ipargs
	if [ ${NETWORK} -eq 0 ]; then
		case $IPS in
		01) ipargs="ip6.addr=::1" ;;
		10) ipargs="ip4.addr=127.0.0.1" ;;
		11) ipargs="ip4.addr=127.0.0.1 ip6.addr=::1" ;;
		esac
	else
		case $IPS in
		01) ipargs="ip6=inherit" ;;
		10) ipargs="ip4=inherit" ;;
		11) ipargs="ip4=inherit ip6=inherit" ;;
		esac
	fi
	jail -c persist name=${jname} ${ipargs} path=${jpath} host.hostname=${jname} \
		allow.sysvipc allow.mount allow.socket_af allow.raw_sockets allow.chflags

}
jail_start() {
	[ $# -ne 1 ] && earsg jailname
	NAME=$1
	export JAILBASE=`jail_get_base ${NAME}`
	export JAILFS=`jail_get_fs ${NAME}`

	local NEEDFS="linprocfs linsysfs nullfs procfs"
	[ -n "${USE_TMPFS}" ] && NEEDFS="${NEEDFS} tmpfs"
	for fs in ${NEEDFS}; do
		lsvfs $fs >/dev/null 2>&1 || kldload $fs
	done
	sysctl -n compat.linux.osrelease >/dev/null 2>&1 || kldload linux
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
	mkdir -p ${MNT}/proc
	mount -t procfs proc ${MNT}/proc
	msg "Mounting linuxfs"
	mkdir -p ${MNT}/compat/linux/proc
	mkdir -p ${MNT}/compat/linux/sys
	mount -t linprocfs linprocfs ${MNT}/compat/linux/proc
	mount -t linsysfs linsysfs ${MNT}/compat/linux/sys
	test -n "${RESOLV_CONF}" && cp -v "${RESOLV_CONF}" "${MNT}/etc/"
	msg "Starting jail ${NAME}"
	jailrun ${NAME} ${MNT} 0
	# Only set STATUS=1 if not turned off
	# jail -s should not do this or jail will stop on EXIT
	[ ${SET_STATUS_ON_START-1} -eq 1 ] && export STATUS=1
}

jail_stop() {
	[ $# -ne 1 ] && eargs jailname
	local name=${1}
	local jailbase=`jail_get_base ${name}`
	local jailfs=`jail_get_fs ${name}`
	jail_runs ${name} || err 1 "No such jail running: ${name}"
	jail_status "stop:"

	msg "Stopping jail"
	jail -r ${name}
	msg "Umounting file systems"
	for mnt in $( mount | awk -v mnt="${jailbase}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do
		umount -f ${mnt}
	done

	if [ -n "${MFSSIZE}" ]; then
		local mdunit=$(mount | awk -v mnt="${jailbase}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 ~ /\/dev\/md/ ) { sub(/\/dev\/md/, "", $1); print $1 }}')
		if [ -n "$mdunit" ]; then
			umount ${jailbase}/wrkdirs
			mdconfig -d -u ${mdunit}
		fi
	fi
	zfs rollback -r ${ZPOOL}/poudriere/${name}@clean
	jail_status "idle:"
	export STATUS=0
}

port_create_zfs() {
	[ $# -ne 3 ] && earsg name mountpoint fs
	local name=$1
	local mnt=$( echo $2 | sed -e 's,//,/,g')
	local fs=$3
	msg_n "Creating ${name} fs..."
	zfs create -p \
		-o mountpoint=${mnt} \
		-o ${NS}:type=ports \
		-o ${NS}:name=${name} \
		${ps} || err 1 " Fail" && echo " done"
}

cleanup() {
	# Prevent recursive cleanup on error
	if [ -n "${CLEANING_UP}" ]; then
		echo "Failure cleaning up. Giving up." >&2
		return
	fi
	export CLEANING_UP=1
	[ -e ${PIPE} ] && rm -f ${PIPE}
	[ -z "${JAILNAME}" ] && err 2 "Fail: Missing JAILNAME"
	local fs=`jail_get_fs ${JAILNAME}`
	zfs destroy ${fs}@prepkg 2>/dev/null || :
	zfs destroy ${fs}@prebuild 2>/dev/null || :
	jail_stop ${JAILNAME}
}

injail() {
	jexec -U root ${JAILNAME} $@
}

sanity_check_pkgs() {
	local ret=0
	[ ! -d ${PKGDIR}/All ] && return $ret
	[ -z "$(ls -A ${PKGDIR}/All)" ] && return $ret
	for pkg in ${PKGDIR}/All/*.${EXT}; do
		local depfile=${JAILBASE}/tmp/${pkg##*/}.deps
		if [ ! -f "${depfile}" ]; then
			if [ "${EXT}" = "tbz" ]; then
				pkg_info -qr ${pkg} | awk '{ print $2 }' > ${depfile}
			else
				pkg info -qdF $pkg > ${depfile}
			fi
		fi
		while read dep; do
			if [ ! -e "${PKGDIR}/All/${dep}.${EXT}" ]; then
				ret=1
				msg "Deleting ${pkg}: missing dependencies"
				rm -f ${pkg}
				break
			fi
		done < ${depfile}
	done

	return $ret
}

build_port() {
	[ $# -ne 1 ] && eargs portdir jailname
	local portdir=$1
	local jailname=$2
	local jailfs=`jail_get_fs ${jailname}`
	local jailbase=`jail_get_base ${jailname}`
	local targets="fetch checksum extract patch configure build install package"
	[ -n "${PORTTESTING}" ] && targets="${targets} deinstall"
	for phase in ${targets}; do
		zfs_set "${NS}:status" "${PHASE}:${portdir##/usr/ports/}"
		if [ "${phase}" = "fetch" ]; then
			jail -r ${jailname}
			jail_run ${jailname} ${jailbase} 1
		fi
		[ "${phase}" = "build" -a $ZVERSION -ge 28 ] && zfs snapshot ${jailfs}@prebuild
		if [ -n "${PORTTESTING}" -a "${phase}" = "deinstall" ]; then
			msg "Checking shared library dependencies"
			if [ ${PKGNG} -eq 0 ]; then
				PLIST="/var/db/pkg/${PKGNAME}/+CONTENTS"
				grep -v "^@" ${jailbase}${PLIST} | \
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
		injail env ${PKGENV} ${PORT_FLAGS} make -C ${portdir} ${phase} || return 1

		if [ "${phase}" = "checksum" ]; then
			jail -r ${jailname}
			jail_run ${jailname} ${jailbase} 0
		fi
		if [ -n "${PORTTESTING}" -a  "${phase}" = "deinstall" ]; then
			msg "Checking for extra files and directories"
			PREFIX=`injail make -C ${portdir} -VPREFIX`
			zfs_set "${NS}:status" "fscheck:${portdir##/usr/ports/}"
			if [ $ZVERSION -lt 28 ]; then
				find ${jailbase}${PREFIX} ! -type d | \
					sed -e "s,^${jailbase}${PREFIX}/,," | sort

				find ${jailbase}${PREFIX}/ -type d | sed "s,^${jailbase}${PREFIX}/,," | sort > ${jailbase}${PREFIX}.PLIST_DIRS.after
				comm -13 ${jailbase}${PREFIX}.PLIST_DIRS.before ${jailbase}${PREFIX}.PLIST_DIRS.after | sort -r | awk '{ print "@dirrmtry "$1}'
			else
				local portname=$(injail make -C ${portdir} -VPORTNAME)
				local add=$(mktemp ${jailbase}/tmp/add.XXXXXX)
				local add1=$(mktemp ${jailbase}/tmp/add1.XXXXXX)
				local del=$(mktemp ${jailbase}/tmp/del.XXXXXX)
				local del1=$(mktemp ${jailbase}/tmp/del1.XXXXXX)
				local mod=$(mktemp ${jailbase}/tmp/mod.XXXXXX)
				local mod1=$(mktemp ${jailbase}/tmp/mod1.XXXXXX)
				local die=0
				zfs diff -FH ${jailfs}@prebuild ${jailfs} | \
					while read mod type path; do
					local ppath=`echo "$path" | sed -e "s,^${jailbase},," -e "s,^${PREFIX}/,," -e "s,^share/${portname},%%DATADIR%%," -e "s,^etc,%%ETCDIR%%,"`
					case $mod$type in
						+*)
							case "${ppath}" in
								/var/db/pkg/local.sqlite) continue;;
								/var/run/ld-elf.so.hints) continue;;
								/tmp/*) continue;;
								/wrkdirs/*) continue;;
								share/nls/POSIX) continue;;
								share/nls/en_US.US-ASCII) continue;;
								*) echo "${ppath}" >> ${add};;
							esac
							;;
						-*)
							case "${ppath}" in
								/var/run/ld-elf.so.hints) continue;;
								/tmp/*) continue;;
								/wrkdirs/*) continue;;
								*) echo "${ppath}" >> ${del};;
							esac
							;;
						M/) continue;;
						M*)
							case "${ppath}" in
								/var/db/pkg/local.sqlite) continue;;
								/var/log/userlog) continue;;
								/etc/spwd.db) continue;;
								/etc/pwd.db) continue;;
								/etc/group) continue;;
								/etc/passwd) continue;;
								/etc/master.passwd) continue;;
								/etc/shells) continue;;
								*) echo "${ppath}" >> ${mod};;
							esac
							;;
					esac
				done
				sort ${add} > ${add1}
				sort ${del} > ${del1}
				sort ${mod} > ${mod1}
				comm -12 ${add1} ${del1} >> ${mod1}
				comm -23 ${add1} ${del1} > ${add}
				comm -13 ${add1} ${del1} > ${del}
				if [ -s "${add}" ]; then
					msg "Files or directories left over:"
					cat ${add}
				fi
				if [ -s "${del}" ]; then
					msg "Files or directories removed:"
					cat ${del}
				fi
				if [ -s "${mod}" ]; then
					msg "Files or directories modified:"
					cat ${mod1}
				fi
				rm -f ${add} ${add1} ${del} ${del1} ${mod} ${mod1}
			fi
		fi
	done
	jail -r ${jailbase}
	jail_run ${jailname} ${jailbase} 0
	zfs_set "${NS}:status" "idle:"
	zfs destroy ${jailfs}@prebuild || :
	return 0
}

build_pkg() {
	[ $# -ne 1 ] && eargs port
	local port=$1
	local portdir="/usr/ports/${port}"
	local build_failed=0

	# If this port is IGNORED, skip it
	# This is checked here instead of when building the queue
	# as the list may start big but become very small, so here
	# is a less-common check
	local ignore="$(injail make -C ${portdir} -VIGNORE)"
	if [ -n "$ignore" ]; then
		msg "Ignoring ${port}: $ignore"
		cnt=$(zfs_get ${NS}:stats_ignored)
		[ "$cnt" = "-" ] && cnt=0
		cnt=$(( cnt + 1))
		zfs_set "${NS}:stats_ignored" "$cnt"
		export ignored="${ignored} ${port}"
		return
	fi

	msg "Cleaning up wrkdir"
	rm -rf ${JAILBASE}/wrkdirs/*

	msg "Building ${port}"
	PKGNAME=$(injail make -C ${portdir} -VPKGNAME)
	log_start ${LOGS}/${JAILNAME}-${PTNAME}-${PKGNAME}.log

	zfs_set "${NS}:status" "depends:${port}"
	if ! injail make -C ${portdir} pkg-depends fetch-depends extract-depends \
		patch-depends build-depends lib-depends; then
		build_failed=1
	else
		# Only build if the depends built fine
		injail make -C ${portdir} clean
		if ! build_port ${portdir} ${JAILNAME}; then
			build_failed=1
		fi
	fi

	if [ ${build_failed} -eq 0 ]; then
		cnt=$(zfs_get ${NS}:stats_built)
		[ "$cnt" = "-" ] && cnt=0
		cnt=$(( cnt + 1))
		zfs_set "${NS}:stats_built" "$cnt"
		export built="${built} ${port}"
	else
		cnt=$(zfs_get ${NS}:stats_failed)
		[ "$cnt" = "-" ] && cnt=0
		cnt=$(( cnt + 1))
		zfs_set "${NS}:stats_failed" "$cnt"
		state=$(zfs_get ${NS}:status)
		export failed="${failed} ${state}"
	fi
	jail_status "idle:"
	log_stop ${LOGS}/${JAILNAME}-${PTNAME}-${PKGNAME}.log
}

list_deps() {
	[ $# -ne 1 ] && eargs directory
	local list="PKG_DEPENDS BUILD_DEPENDS EXTRACT_DEPENDS LIB_DEPENDS PATCH_DEPENDS FETCH_DEPENDS RUN_DEPENDS"
	local dir=$1
	local makeargs=""
	for key in $list; do
		makergs="${makeargs} -V${key}"
	done
	[ -d "${PORTSDIR}/${dir}" ] && dir="/usr/ports/${dir}"

	local pdeps
	local pn
	injail make -C ${dir} -VPKGNAME $makeargs | tr '\n' ' ' | \
		sed -e "s,[[:graph:]]*/usr/ports/,,g" -e "s,:[[:graph:]]*,,g" | while read pn pdeps; do
		[ -n "${cache}" ] && echo "${1} ${pn}" >> ${cache}
		for d in ${pdeps}; do
			echo $pdeps
		done | sort -u
	done
}

delete_old_pkgs() {
	local o
	local v
	local v2
	local compiled_options
	local current_options
	[ ! -d ${PKGDIR}/All ] && return 0
	[ -z "$(ls -A ${PKGDIR}/All)" ] && return 0
	for pkg in ${PKGDIR}/All/*.${EXT}; do
		test -e ${pkg} || continue
		if [ "${EXT}" = "tbz" ]; then
			o=`pkg_info -qo ${pkg}`
		else
			o=`pkg query -F ${pkg} "%o"`
		fi
		v=${pkg##*-}
		v=${v%.*}
		if [ ! -d "${JAILBASE}/usr/ports/${o}" ]; then
			msg "${o} does not exist anymore. Deleting stale ${pkg##*/}"
			rm -f ${pkg}
			continue
		fi
		v2=$(awk -v o=${o} ' { if ($1 == o) {print $2} }' ${cache})
		if [ -z "$v2" ]; then
			v2=`injail make -C /usr/ports/${o} -VPKGNAME`
			echo "${o} ${v2}" >> ${cache}
		fi
		v2=${v2##*-}
		if [ "$v" != "$v2" ]; then
			msg "Deleting old version: ${pkg##*/}"
			rm -f ${pkg}
			continue
		fi

		# Check if the compiled options match the current options from make.conf and /var/db/options
		if [ -n "${CHECK_CHANGED_OPTIONS}" -a "${CHECK_CHANGED_OPTIONS}" != "no" -a $PKGNG -eq 1 ]; then
			compiled_options=$(pkg query -F ${pkg} '%Ov %Ok' | awk '$1 == "on" {print $2}' | sort | tr '\n' ' ')
			current_options=$(injail make -C /usr/ports/${o} pretty-print-config | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
			if [ "${compiled_options}" != "${current_options}" ]; then
				msg "Options changed, deleting: ${pkg##*/}"
				if [ "${CHECK_CHANGED_OPTIONS}" = "verbose" ]; then
					msg "Pkg: ${compiled_options}"
					msg "New: ${current_options}"
				fi
				rm -f ${pkg}
				continue
			fi
		fi
	done
}

process_deps() {
	[ $# -ne 4 ] && eargs tmplist deplist tmplist2 port
	tmplist=$1
	deplist=$2
	tmplist2=$3
	local port=$4
	egrep -q "^$port$" ${tmplist} && return
	echo $port >> ${tmplist}
	deps=0
	local m
	for m in `list_deps ${port}`; do
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
	cache=$(mktemp ${base}/tmp/cache.XXXXX)
	touch ${cache}
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

	local pn
	msg "Caching missing port versions"
	while read port; do
		if ! egrep -q "^${port} " ${cache}; then
			pn=$(injail make -C /usr/ports/${port} -VPKGNAME)
			echo "${port} ${pn}" >> ${cache}
		fi
	done < ${tmplist2}

	jail_status "sanity:"

	if [ $SKIPSANITY -eq 0 ]; then
		msg "Sanity checking the repository"
		delete_old_pkgs

		while :; do
			sanity_check_pkgs && break
		done
	fi

	msg "Deleting stale symlinks"
	find -L ${PKGDIR} -type l -exec rm -vf {} +

	jail_status "cleaning:"
	msg "Cleaning the build queue"
	export LOCALBASE=${MYBASE:-/usr/local}
	while read p; do
		pn=$(awk -v o=${p} ' { if ($1 == o) {print $2} }' ${cache})
		[ ! -f "${PKGDIR}/All/${pn}.${EXT}" ] && queue="${queue} $p"
	done < ${tmplist2}

	rm -f ${tmplist2} ${deplist} ${tmplist}
	export queue
	export built=""
	export failed=""
	export ignored=""
	local nbq=0
	for a in ${queue}; do nbq=$((nbq + 1)); done
	zfs_set "${NS}:stats_queued" "${nbq}"
	zfs_set "${NS}:stats_built" "0"
	zfs_set "${NS}:stats_failed" "0"
	zfs_set "${NS}:stats_ignored" "0"
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

	if [ -n "${CCACHE_DIR}" -a -d "${CCACHE_DIR}" ]; then
		# Mount user supplied CCACHE_DIR into /var/cache/ccache
		msg "Mounting ccache from ${CCACHE_DIR}"
		mkdir -p ${JAILBASE}/var/cache/ccache || err 1 "Failed to create ccache directory "
		mount -t nullfs ${CCACHE_DIR} ${JAILBASE}/var/cache/ccache || err 1 "Failed to mount the ccache directory "
		export CCACHE_DIR=/var/cache/ccache
	fi

	mkdir -p ${PORTSDIR}/packages
	mkdir -p ${PKGDIR}/All

	mount -t nullfs ${PKGDIR} ${JAILBASE}/usr/ports/packages || err 1 "Failed to mount the packages directory "
	if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
		mkdir -p ${JAILBASE}/usr/ports/distfiles
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
