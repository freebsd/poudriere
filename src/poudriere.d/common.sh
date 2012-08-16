#!/bin/sh

# zfs namespace
NS="poudriere"
IPS="$(sysctl -n kern.features.inet 2>/dev/null || (sysctl -n net.inet 1>/dev/null 2>&1 && echo 1) || echo 0)$(sysctl -n kern.features.inet6 2>/dev/null || (sysctl -n net.inet6 1>/dev/null 2>&1 && echo 1) || echo 0)"

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
	local logfile=$1

	# Make sure directory exists
	mkdir -p ${logfile%/*}

	exec 3>&1 4>&2
	[ ! -e ${logfile}.pipe ] && mkfifo ${logfile}.pipe
	tee ${logfile} < ${logfile}.pipe >&3 &
	export tpid=$!
	exec > ${logfile}.pipe 2>&1

	# Remove fifo pipe file right away to avoid orphaning it.
	# The pipe will continue to work as long as we keep
	# the FD open to it.
	rm -f ${logfile}.pipe
}

log_path() {
	echo "${LOGS}/${BUILD_TYPE}/${JAILNAME%-job-*}/${PTNAME}"
}

buildlog_start() {
	local portdir=$1

	echo "build started at $(date)"
	echo "port directory: ${portdir}"
	echo "building for: $(injail uname -rm)"
	echo "maintained by: $(injail make -C ${portdir} maintainer)"
	echo "Makefile ident: $(injail ident ${portdir}/Makefile|sed -n '2,2p')"

	echo "---Begin Environment---"
	injail env ${PKGENV} ${PORT_FLAGS}
	echo "---End Environment---"
	echo ""
	echo "---Begin OPTIONS List---"
	injail make -C ${portdir} showconfig
	echo "---End OPTIONS List---"
}

buildlog_stop() {
	local portdir=$1

	echo "build of ${portdir} ended at $(date)"
}

log_stop() {
	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid
}

zget() {
	[ $# -ne 1 ] && eargs property
	zfs get -H -o value ${NS}:${1} ${JAILFS}
}

zset() {
	[ $# -ne 2 ] && eargs property value
	zfs set ${NS}:$1="$2" ${JAILFS}
}

pzset() {
	[ $# -ne 2 ] && eargs property value
	zfs set ${NS}:$1="$2" ${PTFS}
}

pzget() {
	[ $# -ne 1 ] && eargs property
	zfs get -H -o value ${NS}:${1} ${PTFS}
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
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name ${ZPOOL}/poudriere | \
		awk -v n=$1 'BEGIN { ret = 1 } $1 == "rootfs" && $2 == n { ret = 0; } END { exit ret }' && return 0
	return 1
}

jail_runs() {
	[ $# -ne 0 ] && eargs
	jls -qj ${JAILNAME} name > /dev/null 2>&1 && return 0
	return 1
}

jail_get_base() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}/poudriere | \
		awk -v n=$1 '$1 == "rootfs" && $2 == n  { print $3 }'
}

jail_get_version() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,${NS}:version ${ZPOOL}/poudriere | \
		awk -v n=$1 '$1 == "rootfs" && $2 == n { print $3 }'
}

jail_get_fs() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,name ${ZPOOL}/poudriere | \
		awk -v n=$1 '$1 == "rootfs" && $2 == n { print $3 }'
}

port_exists() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,name ${ZPOOL}/poudriere | \
		awk -v n=$1 'BEGIN { ret = 1 } $1 == "ports" && $2 == n { ret = 0; } END { exit ret }' && return 0
	return 1
}

port_get_base() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}/poudriere | \
		awk -v n=$1 '$1 == "ports" && $2 == n { print $3 }'
}

port_get_fs() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,name ${ZPOOL}/poudriere | \
		awk -v n=$1 '$1 == "ports" && $2 == n { print $3 }'
}

get_data_dir() {
	local data
	if [ -n "${POUDRIERE_DATA}" ]; then
		echo ${POUDRIERE_DATA}
		return
	fi
	data=$(zfs list -rt filesystem -H -o ${NS}:type,mountpoint ${ZPOOL}/poudriere | awk '$1 == "data" { print $2 }' | head -n 1)
	if [ -n "${data}" ]; then
		echo $data
		return
	fi
	zfs create -p -o ${NS}:type=data \
		-o mountpoint=${BASEFS}/data \
		${ZPOOL}/poudriere/data
	echo "${BASEFS}/data"
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

jrun() {
	[ $# -ne 1 ] && eargs network
	local network=$1
	local ipargs
	if [ ${network} -eq 0 ]; then
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
	jail -c persist name=${JAILNAME} ${ipargs} path=${JAILMNT} \
		host.hostname=${JAILNAME} allow.sysvipc allow.mount \
		allow.socket_af allow.raw_sockets allow.chflags
}

jail_start() {
	[ $# -ne 0 ] && earsg
	local NEEDFS="linprocfs linsysfs nullfs procfs"
	[ -n "${USE_TMPFS}" ] && NEEDFS="${NEEDFS} tmpfs"
	for fs in ${NEEDFS}; do
		lsvfs $fs >/dev/null 2>&1 || kldload $fs
	done
	sysctl -n compat.linux.osrelease >/dev/null 2>&1 || kldload linux
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs && err 1 "jail already running: ${JAILNAME}"
	zset status "start:"
	zfs rollback -R ${JAILFS}@clean

	msg "Mounting devfs"
	mount -t devfs devfs ${JAILMNT}/dev
	msg "Mounting /proc"
	mkdir -p ${JAILMNT}/proc
	mount -t procfs proc ${JAILMNT}/proc
	msg "Mounting linuxfs"
	mkdir -p ${JAILMNT}/compat/linux/proc
	mkdir -p ${JAILMNT}/compat/linux/sys
	mount -t linprocfs linprocfs ${JAILMNT}/compat/linux/proc
	mount -t linsysfs linsysfs ${JAILMNT}/compat/linux/sys
	test -n "${RESOLV_CONF}" && cp -v "${RESOLV_CONF}" "${JAILMNT}/etc/"
	msg "Starting jail ${JAILNAME}"
	jrun 0
	# Only set STATUS=1 if not turned off
	# jail -s should not do this or jail will stop on EXIT
	[ ${SET_STATUS_ON_START-1} -eq 1 ] && export STATUS=1
}

jail_stop() {
	[ $# -ne 0 ] && eargs
	jail_runs || err 1 "No such jail running: ${JAILNAME}"
	zset status "stop:"

	jail -r ${JAILNAME}
	# Shutdown all builders
	for j in $(jot -w %02d ${PARALLEL_JOBS}); do
		jail -r ${JAILNAME}-job-${j} >/dev/null 2>&1 || :
	done
	msg "Umounting file systems"
	for mnt in $( mount | awk -v mnt="${JAILMNT}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do
		umount -f ${mnt}
	done

	if [ -n "${MFSSIZE}" ]; then
		# umount the ${JAILMNT}/build/$jobno/wrkdirs
		mount | grep "/dev/md.*${JAILMNT}/build" | while read mnt; do
			local dev=`echo $mnt | awk '{print $1}'`
			if [ -n "$dev" ]; then
				umount $dev
				mdconfig -d -u $dev
			fi
		done
		# umount the $JAILMNT/wrkdirs
		local dev=`mount | grep "/dev/md.*${JAILMNT}" | awk '{print $1}'`
		if [ -n "$dev" ]; then
			umount $dev
			mdconfig -d -u $dev
		fi
	fi
	zfs rollback -R ${JAILFS}@clean
	zset status "idle:"
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
		${fs} || err 1 " Fail" && echo " done"
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
	for pid in ${JAILMNT}/*.pid; do
		pkill -15 -F ${pid} >/dev/null 2>&1 || :
	done
	wait
	zfs destroy ${JAILFS}@prepkg 2>/dev/null || :
	zfs destroy ${JAILFS}@prebuild 2>/dev/null || :
	jail_stop
}

injail() {
	jexec -U root ${JAILNAME} $@
}

sanity_check_pkgs() {
	local ret=0
	[ ! -d ${PKGDIR}/All ] && return $ret
	[ -z "$(ls -A ${PKGDIR}/All)" ] && return $ret
	for pkg in ${PKGDIR}/All/*.${EXT}; do
		local depfile=${JAILMNT}/tmp/${pkg##*/}.deps
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
	[ $# -ne 1 ] && eargs portdir
	local portdir=$1
	local port=${portdir##/usr/ports/}
	local targets="fetch checksum extract patch configure build install package"
	local name=$(cache_get_pkgname ${port})
	local options

	[ -n "${PORTTESTING}" ] && targets="${targets} deinstall"
	for phase in ${targets}; do
		zset status "${phase}:${port}"
		if [ "${phase}" = "fetch" ]; then
			jail -r ${JAILNAME}
			jrun 1
		fi
		[ "${phase}" = "build" -a $ZVERSION -ge 28 ] && zfs snapshot ${JAILFS}@prebuild
		if [ -n "${PORTTESTING}" -a "${phase}" = "deinstall" ]; then
			msg "Checking shared library dependencies"
			if [ ${PKGNG} -eq 0 ]; then
				PLIST="/var/db/pkg/${PKGNAME}/+CONTENTS"
				grep -v "^@" ${JAILMNT}${PLIST} | \
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

		# If creating a pkg_install package, insert the options into the +CONTENTS
		# XXX: Move to bsd.port.mk?
		if [ "${phase}" = "package" -a $PKGNG -eq 0 ]; then
			options=$(injail make -C ${portdir} pretty-print-config)
			echo "@comment OPTIONS:${options}" >> ${JAILMNT}/var/db/pkg/${name}/+CONTENTS
		fi

		printf "=======================<phase: %-9s>==========================\n" ${phase}
		injail env ${PKGENV} ${PORT_FLAGS} make -C ${portdir} ${phase} || return 1
		echo "==================================================================="

		if [ "${phase}" = "checksum" ]; then
			jail -r ${JAILNAME}
			jrun 0
		fi
		if [ -n "${PORTTESTING}" -a  "${phase}" = "deinstall" ]; then
			msg "Checking for extra files and directories"
			PREFIX=`injail make -C ${portdir} -VPREFIX`
			zset status "fscheck:${port}"
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
				zfs diff -FH ${JAILFS}@prebuild ${JAILFS} | \
					while read mod type path; do
					local ppath
					ppath=`echo "$path" | sed -e "s,^${JAILMNT},," -e "s,^${PREFIX}/,," -e "s,^share/${portname},%%DATADIR%%," -e "s,^etc,%%ETCDIR%%,"`
					case "$ppath" in
					/var/db/pkg/*) continue;;
					/var/run/*) continue;;
					/wrkdirs/*) continue;;
					/tmp/*) continue;;
					share/nls/POSIX) continue;;
					share/nls/en_US.US-ASCII) continue;;
					/var/log/*) continue;;
					/etc/spwd.db) continue;;
					/etc/pwd.db) continue;;
					/etc/group) continue;;
					/etc/passwd) continue;;
					/etc/master.passwd) continue;;
					/etc/shells) continue;;
					esac
					case $mod$type in
					+*) echo "${ppath}" >> ${add};;
					-*) echo "${ppath}" >> ${del};;
					M/) continue;;
					M*) echo "${ppath}" >> ${mod};;
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
	jail -r ${JAILNAME}
	jrun 0
	zset status "next:"
	zfs destroy ${JAILFS}@prebuild || :
	return 0
}

build_pkg() {
	[ $# -ne 1 ] && eargs port
	local port=$1
	local portdir="/usr/ports/${port}"
	local build_failed=0
	local name cnt

	# If this port is IGNORED, skip it
	# This is checked here instead of when building the queue
	# as the list may start big but become very small, so here
	# is a less-common check
	local ignore="$(injail make -C ${portdir} -VIGNORE)"

	msg "Cleaning up wrkdir"
	rm -rf ${JAILMNT}/wrkdirs/*

	msg "Building ${port}"
	PKGNAME=$(cache_get_pkgname ${port})
	log_start $(log_path)/${PKGNAME}.log
	buildlog_start ${portdir}

	if [ -n "${ignore}" ]; then
		msg "Ignoring ${port}: ${ignore}"
		echo "${port}" >> "${MASTERMNT:-${JAILMNT}}/ignored"
	else
		zset status "depends:${port}"
		printf "=======================<phase: %-9s>==========================\n" "depends"
		if ! injail make -C ${portdir} pkg-depends fetch-depends extract-depends \
			patch-depends build-depends lib-depends; then
			build_failed=1
		else
			echo "==================================================================="
			# Only build if the depends built fine
			injail make -C ${portdir} clean
			if ! build_port ${portdir}; then
				build_failed=1
			fi
			injail make -C ${portdir} clean
		fi

		if [ ${build_failed} -eq 0 ]; then
			echo "${port}" >> "${MASTERMNT:-${JAILMNT}}/built"
		else
			echo "${port}" >> "${MASTERMNT:-${JAILMNT}}/failed"
		fi
	fi
	# Cleaning queue (pool is cleaned here)
	lockf -k ${MASTERMNT:-${JAILMNT}}/.lock sh ${SCRIPTPREFIX}/clean.sh "${MASTERMNT:-${JAILMNT}}" "${PKGNAME}"

	zset status "done:${port}"
	buildlog_stop ${portdir}
	log_stop $(log_path)/${PKGNAME}.log
}

list_deps() {
	[ $# -ne 1 ] && eargs directory
	local list="PKG_DEPENDS BUILD_DEPENDS EXTRACT_DEPENDS LIB_DEPENDS PATCH_DEPENDS FETCH_DEPENDS RUN_DEPENDS"
	local dir=$1
	local makeargs=""
	for key in $list; do
		makeargs="${makeargs} -V${key}"
	done
	[ -d "${PORTSDIR}/${dir}" ] && dir="/usr/ports/${dir}"

	local pdeps pn
	injail make -C ${dir} $makeargs | tr '\n' ' ' | \
		sed -e "s,[[:graph:]]*/usr/ports/,,g" -e "s,:[[:graph:]]*,,g" | sort -u
}

delete_old_pkgs() {
	local o v v2 compiled_options current_options
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
		if [ ! -d "${JAILMNT}/usr/ports/${o}" ]; then
			msg "${o} does not exist anymore. Deleting stale ${pkg##*/}"
			rm -f ${pkg}
			continue
		fi
		v2=$(cache_get_pkgname ${o})
		v2=${v2##*-}
		if [ "$v" != "$v2" ]; then
			msg "Deleting old version: ${pkg##*/}"
			rm -f ${pkg}
			continue
		fi

		# Check if the compiled options match the current options from make.conf and /var/db/options
		if [ -n "${CHECK_CHANGED_OPTIONS}" -a "${CHECK_CHANGED_OPTIONS}" != "no" ]; then
			current_options=$(injail make -C /usr/ports/${o} pretty-print-config | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')

			if [ $PKGNG -eq 1 ]; then
				compiled_options=$(pkg query -F ${pkg} '%Ov %Ok' | awk '$1 == "on" {print $2}' | sort | tr '\n' ' ')
			else
				compiled_options=$(pkg_info -qf ${pkg} | awk -F: '$1 == "@comment OPTIONS" {print $2}' | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
			fi
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

next_in_queue() {
	local p
	p=$(lockf -k -t 60 ${JAILMNT}/.lock find ${JAILMNT}/pool -type d -depth 1 -empty -print || : | head -n 1)
	[ -n "$p" ] || return 0
	touch ${p}/.building
	cache_get_origin ${p##*/}
}

cache_get_pkgname() {
	[ $# -ne 1 ] && eargs origin
	local origin=$1
	local pkgname

	pkgname=$(awk -v o=${origin} '$1 == o { print $2 }' ${MASTERMNT:-${JAILMNT}}/cache)

	# Add to cache if not found.
	if [ -z "${pkgname}" ]; then
		pkgname=$(injail make -C /usr/ports/${origin} -VPKGNAME)
		echo "${origin} ${pkgname}" >> ${MASTERMNT:-${JAILMNT}}/cache
	fi
	echo ${pkgname}
}

cache_get_origin() {
	[ $# -ne 1 ] && eargs pkgname
	local pkgname=$1

	awk -v p=${pkgname} '$2 == p { print $1 }' ${MASTERMNT:-${JAILMNT}}/cache
}

compute_deps() {
	[ $# -ne 1 ] && eargs port
	local port=$1
	local name m
	local pn=$(cache_get_pkgname ${port})
	local pkg_pooldir="${JAILMNT}/pool/${pn}"
	[ -d "${pkg_pooldir}" ] && return

	mkdir "${pkg_pooldir}"
	for m in `list_deps ${port}`; do
		compute_deps "${m}"
		name=$(cache_get_pkgname ${m})
		touch "${pkg_pooldir}/${name}"
	done
}

prepare_ports() {
	msg "Calculating ports order and dependencies"
	mkdir -p "${JAILMNT}/pool"
	touch "${JAILMNT}/cache"
	zset status "computingdeps:"
	if [ -z "${LISTPORTS}" ]; then
		if [ -n "${LISTPKGS}" ]; then
			for port in `grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}`; do
				compute_deps "${port}"
			done
		fi
	else
		for port in ${LISTPORTS}; do
			compute_deps "${port}"
		done
	fi
	zset status "sanity:"

	if [ $SKIPSANITY -eq 0 ]; then
		msg "Sanity checking the repository"
		delete_old_pkgs

		while :; do
			sanity_check_pkgs && break
		done
	fi

	msg "Deleting stale symlinks"
	find -L ${PKGDIR} -type l -exec rm -vf {} +

	zset status "cleaning:"
	msg "Cleaning the build queue"
	export LOCALBASE=${MYBASE:-/usr/local}
	find ${JAILMNT}/pool -type d -depth 1 | while read p; do
		pn=${p##*/}
		if [ -f "${PKGDIR}/All/${pn}.${EXT}" ]; then
			rm -rf ${p}
			find ${JAILMNT}/pool -name "${pn}" -type f -delete
		fi
	done

	local nbq=0
	nbq=$(find ${JAILMNT}/pool -type d -depth 1 | wc -l)
	zset stats_queued "${nbq}"
	zset stats_built "0"
	zset stats_failed "0"
	zset stats_ignored "0"
	:> ${JAILMNT}/built
	:> ${JAILMNT}/failed
	:> ${JAILMNT}/ignored
}

prepare_jail() {
	export PACKAGE_BUILDING=yes
	PORTSDIR=`port_get_base ${PTNAME}`/ports
	POUDRIERED=${SCRIPTPREFIX}/../../etc/poudriere.d
	[ -z "${JAILMNT}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

	mount -t nullfs ${PORTSDIR} ${JAILMNT}/usr/ports || err 1 "Failed to mount the ports directory "

	if [ -n "${CCACHE_DIR}" -a -d "${CCACHE_DIR}" ]; then
		# Mount user supplied CCACHE_DIR into /var/cache/ccache
		msg "Mounting ccache from ${CCACHE_DIR}"
		mkdir -p ${JAILMNT}${CCACHE_DIR} || err 1 "Failed to create ccache directory "
		mount -t nullfs ${CCACHE_DIR} ${JAILMNT}${CCACHE_DIR} || err 1 "Failed to mount the ccache directory "
		export CCACHE_DIR
	fi

	mkdir -p ${PORTSDIR}/packages
	mkdir -p ${PKGDIR}/All

	[ ! -d ${DISTFILES_CACHE} ] && err 1 "DISTFILES_CACHE directory	does not exists. (c.f. poudriere.conf)"
	mount -t nullfs ${PKGDIR} ${JAILMNT}/usr/ports/packages || err 1 "Failed to mount the packages directory "
	if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
		mkdir -p ${JAILMNT}/usr/ports/distfiles
		mount -t nullfs ${DISTFILES_CACHE} ${JAILMNT}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
	fi

	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILMNT}/wrkdirs
	[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILMNT}/wrkdirs

	[ -f ${POUDRIERED}/make.conf ] && cat ${POUDRIERED}/make.conf >> ${JAILMNT}/etc/make.conf
	[ -f ${POUDRIERED}/${ORIGNAME:-${JAILNAME}}-make.conf ] && cat ${POUDRIERED}/${ORIGNAME:-${JAILNAME}}-make.conf >> ${JAILMNT}/etc/make.conf

	if [ -d ${POUDRIERED}/${ORIGNAME:-${JAILNAME}}-options ]; then
		mount -t nullfs ${POUDRIERED}/${ORIGNAME:-${JAILNAME}}-options ${JAILMNT}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	elif [ -d ${POUDRIERED}/options ]; then
		mount -t nullfs ${POUDRIERED}/options ${JAILMNT}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	fi

	msg "Populating LOCALBASE"
	mkdir -p ${JAILMNT}/${MYBASE:-/usr/local}
	injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${MYBASE:-/usr/local} >/dev/null

	WITH_PKGNG=$(injail make -f /usr/ports/Mk/bsd.port.mk -V WITH_PKGNG)
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

[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"

trap sig_handler SIGINT SIGTERM SIGKILL EXIT

# Test if spool exists
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
ZVERSION=$(zpool list -H -oversion ${ZPOOL})
# Pool version has now
if [ "${ZVERSION}" = "-" ]; then
	ZVERSION=29
fi

POUDRIERE_DATA=`get_data_dir`
: ${CRONDIR="${POUDRIERE_DATA}/cron"}
: ${SVN_HOST="svn.FreeBSD.org"}
: ${GIT_URL="git://github.com/freebsd/freebsd-ports.git"}
: ${FREEBSD_HOST="ftp://${FTP_HOST:-ftp.FreeBSD.org}"}

case ${PARALLEL_JOBS} in
''|*[!0-9]*)
	PARALLEL_JOBS=$(sysctl -n hw.ncpu)
	;;
*) ;;
esac
