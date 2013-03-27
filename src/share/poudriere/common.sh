#!/bin/sh

# zfs namespace
NS="poudriere"
IPS="$(sysctl -n kern.features.inet 2>/dev/null || echo 0)$(sysctl -n kern.features.inet6 2>/dev/null || echo 0)"

dir_empty() {
	find $1 -maxdepth 0 -empty
}

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	local err_msg="Error: $2"
	msg "${err_msg}" >&2
	[ -n "${MY_JOBID}" ] && job_msg "${err_msg}"
	exit $1
}

msg_n() { echo -n "====>> $1"; }
msg() { echo "====>> $1"; }
msg_verbose() {
	[ ${VERBOSE:-0} -gt 0 ] || return 0
	msg "$1"
}

msg_debug() {
	[ ${VERBOSE:-0} -gt 1 ] || return 0

	msg "DEBUG: $1" >&2
}

job_msg() {
	if [ -n "${MY_JOBID}" ]; then
		msg "[${MY_JOBID}] $1" >&5
	else
		msg "$1"
	fi
}

job_msg_verbose() {
	[ -n "${MY_JOBID}" ] || return 0
	msg_verbose "[${MY_JOBID}] $1" >&5
}

eargs() {
	case $# in
	0) err 1 "No arguments expected" ;;
	1) err 1 "1 argument expected: $1" ;;
	*) err 1 "$# arguments expected: $*" ;;
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
	echo "${LOGS}/${POUDRIERE_BUILD_TYPE}/${JAILNAME%-job-*}/${PTNAME}${SETNAME}"
}

buildlog_start() {
	local portdir=$1

	echo "build started at $(date)"
	echo "port directory: ${portdir}"
	echo "building for: $(injail uname -rm)"
	echo "maintained by: $(injail make -C ${portdir} maintainer)"
	echo "Makefile ident: $(injail ident ${portdir}/Makefile|sed -n '2,2p')"
	echo "Poudriere version: ${POUDRIERE_VERSION}"

	echo "---Begin Environment---"
	injail env ${PKGENV} ${PORT_FLAGS}
	echo "---End Environment---"
	echo ""
	echo "---Begin make.conf---"
	cat ${JAILMNT}/etc/make.conf
	echo "---End make.conf---"
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
	if [ -n "${tpid}" ]; then
		exec 1>&3 3>&- 2>&4 4>&-
		wait $tpid
		unset tpid
	fi
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
	trap - SIGTERM SIGKILL
	# Ignore SIGINT while cleaning up
	trap '' SIGINT
	err 1 "Signal caught, cleaning up and exiting"
}

exit_handler() {
	# Avoid recursively cleaning up here
	trap - EXIT SIGTERM SIGKILL
	# Ignore SIGINT while cleaning up
	trap '' SIGINT

	log_stop

	# Kill all children - this does NOT recurse, so orphans can still
	# occur. This is just to avoid requiring pid files for parallel_run
	for pid in $(jobs -p); do
		kill ${pid} 2>/dev/null || :
	done

	[ ${STATUS} -eq 1 ] && cleanup

	[ -n ${CLEANUP_HOOK} ] && ${CLEANUP_HOOK}
}

siginfo_handler() {
	if [ "${POUDRIERE_BUILD_TYPE}" != "bulk" ]; then
		return 0;
	fi
	trappedinfo=1
	local status=$(zget status)
	local nbb=$(zget stats_built)
	local nbf=$(zget stats_failed)
	local nbi=$(zget stats_ignored)
	local nbs=$(zget stats_skipped)
	local nbq=$(zget stats_queued)
	local ndone=$((nbb + nbf + nbi + nbs))
	local queue_width=2
	local j

	[ "${status}" = "index:" ] && return 0

	if [ ${nbq} -gt 9999 ]; then
		queue_width=5
	elif [ ${nbq} -gt 999 ]; then
		queue_width=4
	elif [ ${nbq} -gt 99 ]; then
		queue_width=3
	fi

	printf "[${JAILNAME}] [${status}] [%0${queue_width}d/%0${queue_width}d] Built: %-${queue_width}d Failed: %-${queue_width}d  Ignored: %-${queue_width}d  Skipped: %-${queue_width}d  \n" \
	  ${ndone} ${nbq} ${nbb} ${nbf} ${nbi} ${nbs}

	# Skip if stopping or starting jobs
	if [ -n "${JOBS}" -a "${status#starting_jobs:}" = "${status}" -a "${status}" != "stopping_jobs:" ]; then
		for j in ${JOBS}; do
			# Ignore error here as the zfs dataset may not be cloned yet.
			status=$(JAILFS=${JAILFS}/build/${j} zget status 2>/dev/null || :)
			# Skip builders not started yet
			[ -z "${status}" ] && continue
			# Hide idle workers
			[ "${status}" = "idle:" ] && continue
			echo -e "\t[${j}]: ${status}"
		done
	fi
}

jail_exists() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name ${ZPOOL}${ZROOTFS} | \
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
	zfs list -rt filesystem -s name -H -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}${ZROOTFS} | \
		awk -v n=$1 '$1 == "rootfs" && $2 == n  { print $3 }' | head -n 1
}

jail_get_version() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -rt filesystem -s name -H -o ${NS}:type,${NS}:name,${NS}:version ${ZPOOL}${ZROOTFS} | \
		awk -v n=$1 '$1 == "rootfs" && $2 == n { print $3 }' | head -n 1
}

jail_get_fs() {
	[ $# -ne 1 ] && eargs jailname
	zfs list -rt filesystem -s name -H -o ${NS}:type,${NS}:name,name ${ZPOOL}${ZROOTFS} | \
		awk -v n=$1 '$1 == "rootfs" && $2 == n { print $3 }' | head -n 1
}

porttree_list() {
	local name method mntpoint n format
	# Combine local ZFS and manual list
	zfs list -t filesystem -H -o ${NS}:type,${NS}:name,${NS}:method,mountpoint | \
		awk '$1 == "ports" { print $2 " " $3 " " $4 }'
	if [ -f "${POUDRIERED}/portstrees" ]; then
		# Validate proper format
		format="Format expected: NAME METHOD PATH"
		n=0
		while read name method mntpoint; do
			n=$((n + 1))
			[ -z "${name###*}" ] && continue # Skip comments
			[ -n "${name%%/*}" ] || \
				err 1 "$(realpath ${POUDRIERED}/portstrees):${n}: Invalid name '${name}'. ${format}"
			[ -n "${method}" -a -n "${method%%/*}" ] || \
				err 1 "$(realpath ${POUDRIERED}/portstrees):${n}: Missing method for '${name}'. ${format}"
			[ -n "${mntpoint}" ] || \
				err 1 "$(realpath ${POUDRIERED}/portstrees):${n}: Missing path for '${name}'. ${format}"
			[ -z "${mntpoint%%/*}" ] || \
				err 1 "$(realpath ${POUDRIERED}/portstrees):${n}: Invalid path '${mntpoint}' for '${name}'. ${format}"
			echo "${name} ${method} ${mntpoint}"
		done < ${POUDRIERED}/portstrees
	fi
	# Outputs: name method mountpoint
}

porttree_get_method() {
	[ $# -ne 1 ] && eargs portstree_name
	porttree_list | awk -v portstree_name=$1 '$1 == portstree_name {print $2}'
}

porttree_exists() {
	[ $# -ne 1 ] && eargs portstree_name
	porttree_list |
		awk -v portstree_name=$1 '
		BEGIN { ret = 1 }
		$1 == portstree_name {ret = 0; }
		END { exit ret }
		' && return 0
	return 1
}

porttree_get_base() {
	[ $# -ne 1 ] && eargs portstree_name
	porttree_list | awk -v portstree_name=$1 '$1 == portstree_name { print $3 }'
}

porttree_get_fs() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -t filesystem -H -o ${NS}:type,${NS}:name,name | \
		awk -v n=$1 '$1 == "ports" && $2 == n { print $3 }'
}

get_data_dir() {
	local data
	if [ -n "${POUDRIERE_DATA}" ]; then
		echo ${POUDRIERE_DATA}
		return
	fi
	data=$(zfs list -rt filesystem -H -o ${NS}:type,mountpoint ${ZPOOL}${ZROOTFS} | awk '$1 == "data" { print $2 }' | head -n 1)
	if [ -n "${data}" ]; then
		echo $data
		return
	fi
	zfs create -p -o ${NS}:type=data \
		-o mountpoint=${BASEFS}/data \
		${ZPOOL}${ZROOTFS}/data
	echo "${BASEFS}/data"
}

fetch_file() {
	[ $# -ne 2 ] && eargs destination source
	fetch -p -o $1 $2 || fetch -p -o $1 $2 || err 1 "Failed to fetch from $2"
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

do_jail_mounts() {
	[ $# -ne 1 ] && eargs should_mkdir
	local should_mkdir=$1
	local arch=$(zget arch)

	# Only do this when starting the master jail, clones will already have the dirs
	if [ ${should_mkdir} -eq 1 ]; then
		mkdir -p ${JAILMNT}/proc
	fi

	mount -t devfs devfs ${JAILMNT}/dev
	mount -t fdescfs fdesc ${JAILMNT}/dev/fd
	mount -t procfs proc ${JAILMNT}/proc

	if [ -z "${NOLINUX}" ]; then
		if [ "${arch}" = "i386" -o "${arch}" = "amd64" ]; then
			if [ ${should_mkdir} -eq 1 ]; then
				mkdir -p ${JAILMNT}/compat/linux/proc
				mkdir -p ${JAILMNT}/compat/linux/sys
			fi
			mount -t linprocfs linprocfs ${JAILMNT}/compat/linux/proc
#			mount -t linsysfs linsysfs ${JAILMNT}/compat/linux/sys
		fi
	fi
}

use_options() {
	[ $# -ne 2 ] && eargs optionsdir verbose
	local optionsdir="$(realpath "$1")"
	local verbose="$2"

	[ ${verbose} -eq 1 ] && msg "Mounting /var/db/ports from: ${optionsdir}"
	mount -t nullfs ${optionsdir} ${JAILMNT}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
}

mount_packages() {
	mount -t nullfs "$@" ${PKGDIR} ${JAILMNT}/usr/ports/packages \
		|| err 1 "Failed to mount the packages directory "
}

do_portbuild_mounts() {
	[ $# -ne 1 ] && eargs should_mkdir
	local should_mkdir=$1

	# Only do this when starting the master jail, clones will already have the dirs
	if [ ${should_mkdir} -eq 1 ]; then
		mkdir -p ${JAILMNT}/new_packages
		mkdir -p ${PORTSDIR}/packages
		mkdir -p ${PKGDIR}/All
		mkdir -p ${PORTSDIR}/distfiles
		if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
			mkdir -p ${JAILMNT}${CCACHE_DIR} || err 1 "Failed to create ccache directory "
			msg "Mounting ccache from: ${CCACHE_DIR}"
			export CCACHE_DIR
			export WITH_CCACHE_BUILD=yes
		fi
		# Check for invalid options-JAILNAME created by bad options.sh
		[ -d ${POUDRIERED}/options-${JAILNAME%-job-*} ] && err 1 "Please move your options-${JAILNAME%-job-*} to ${JAILNAME%-job-*}-options"

		msg "Mounting packages from: ${PKGDIR}"
	fi

	mount -t nullfs -o ro ${PORTSDIR} ${JAILMNT}/usr/ports || err 1 "Failed to mount the ports directory "
	mount_packages -o ro

	mount -t nullfs ${DISTFILES_CACHE} ${JAILMNT}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILMNT}/wrkdirs
	[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILMNT}/wrkdirs

	# Order is JAILNAME-SETNAME, then SETNAME, then JAILNAME, then default.
	if [ -n "${SETNAME}" -a -d ${POUDRIERED}/${JAILNAME%-job-*}${SETNAME}-options ]; then
		use_options ${POUDRIERED}/${JAILNAME%-job-*}${SETNAME}-options ${should_mkdir}
	elif [ -d ${POUDRIERED}/${SETNAME#-}-options ]; then
		use_options ${POUDRIERED}/${SETNAME#-}-options ${should_mkdir}
	elif [ -d ${POUDRIERED}/${JAILNAME%-job-*}-options ]; then
		use_options ${POUDRIERED}/${JAILNAME%-job-*}-options ${should_mkdir}
	elif [ -d ${POUDRIERED}/options ]; then
		use_options ${POUDRIERED}/options ${should_mkdir}
	fi

	if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
		# Mount user supplied CCACHE_DIR into /var/cache/ccache
		mount -t nullfs ${CCACHE_DIR} ${JAILMNT}${CCACHE_DIR} || err 1 "Failed to mount the ccache directory "
	fi
}

jail_start() {
	[ $# -ne 0 ] && eargs
	local arch=$(zget arch)
	local NEEDFS="nullfs procfs"
	if [ -z "${NOLINUX}" ]; then
		if [ "${arch}" = "i386" -o "${arch}" = "amd64" ]; then
			NEEDFS="${NEEDFS} linprocfs linsysfs"
			sysctl -n compat.linux.osrelease >/dev/null 2>&1 || kldload linux
		fi
	fi
	[ -n "${USE_TMPFS}" ] && NEEDFS="${NEEDFS} tmpfs"
	for fs in ${NEEDFS}; do
		lsvfs $fs >/dev/null 2>&1 || kldload $fs
	done
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs && err 1 "jail already running: ${JAILNAME}"
	zset status "start:"
	zfs destroy -r ${JAILFS}/build 2>/dev/null || :
	zfs rollback -R ${JAILFS}@clean

	msg "Mounting system devices for ${JAILNAME}"
	do_jail_mounts 1

	test -n "${RESOLV_CONF}" && cp -v "${RESOLV_CONF}" "${JAILMNT}/etc/"
	msg "Starting jail ${JAILNAME}"
	jrun 0
	# Only set STATUS=1 if not turned off
	# jail -s should not do this or jail will stop on EXIT
	[ ${SET_STATUS_ON_START-1} -eq 1 ] && export STATUS=1
}

jail_stop() {
	[ $# -ne 0 ] && eargs
	local mnt
	jail_runs || err 1 "No such jail running: ${JAILNAME%-job-*}"
	zset status "stop:"

	jail -r ${JAILNAME%-job-*} >/dev/null
	# Shutdown all builders
	if [ ${PARALLEL_JOBS} -ne 0 ]; then
		# - here to only check for unset, {start,stop}_builders will set this to blank if already stopped
		for j in ${JOBS-$(jot -w %02d ${PARALLEL_JOBS})}; do
			jail -r ${JAILNAME%-job-*}-job-${j} >/dev/null 2>&1 || :
		done
	fi
	msg "Umounting file systems"
	mnt=`realpath ${MASTERMNT:-${JAILMNT}}`
	mount | awk -v mnt="${mnt}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r | xargs umount -f || :

	if [ -n "${MFSSIZE}" ]; then
		# umount the ${JAILMNT}/build/$jobno/wrkdirs
		mount | grep "/dev/md.*${mnt}/build" | while read mntpt; do
			local dev=`echo $mntpt | awk '{print $1}'`
			if [ -n "$dev" ]; then
				umount $dev
				mdconfig -d -u $dev
			fi
		done
		# umount the $JAILMNT/wrkdirs
		local dev=`mount | grep "/dev/md.*${mnt}" | awk '{print $1}'`
		if [ -n "$dev" ]; then
			umount $dev
			mdconfig -d -u $dev
		fi
	fi
	zfs rollback -R ${JAILFS%/build/*}@clean
	zset status "idle:"
	export STATUS=0
}

porttree_create_fs() {
	[ $# -ne 3 ] && eargs name mountpoint fs
	local name=$1
	local mnt=$( echo $2 | sed -e 's,//,/,g')
	local fs=$3
	if [ $fs != "none" ]; then
		msg_n "Creating ${name} fs..."
		zfs create -p \
			-o atime=off \
			-o compression=off \
			-o mountpoint=${mnt} \
			-o ${NS}:type=ports \
			-o ${NS}:name=${name} \
			${fs} || err 1 " Fail" && echo " done"
	else
		mkdir -p ${mnt}
		echo "${name} __METHOD__ ${mnt}" >> ${POUDRIERED}/portstrees
	fi
}

cleanup() {
	[ -n "${CLEANED_UP}" ] && return 0
	msg "Cleaning up"
	# If this is a builder, don't cleanup, the master will handle that.
	if [ -n "${MY_JOBID}" ]; then
		[ -n "${PKGNAME}" ] && clean_pool ${PKGNAME} 1 || :
		return 0

	fi
	# Prevent recursive cleanup on error
	if [ -n "${CLEANING_UP}" ]; then
		echo "Failure cleaning up. Giving up." >&2
		return
	fi
	export CLEANING_UP=1
	[ -z "${JAILNAME%-job-*}" ] && err 2 "Fail: Missing JAILNAME"

	if [ -d ${MASTERMNT:-${JAILMNT}}/poudriere/var/run ]; then
		for pid in ${MASTERMNT:-${JAILMNT}}/poudriere/var/run/*.pid; do
			# Ensure there is a pidfile to read or break
			[ "${pid}" = "${MASTERMNT:-${JAILMNT}}/poudriere/var/run/*.pid" ] && break
			pkill -15 -F ${pid} >/dev/null 2>&1 || :
		done
	fi
	wait

	zfs destroy -r ${JAILFS%/build/*}/build 2>/dev/null || :
	zfs destroy -r ${JAILFS%/build/*}@prepkg 2>/dev/null || :
	jail_stop
	export CLEANED_UP=1
}

injail() {
	jexec -U root ${JAILNAME} $@
}

sanity_check_pkgs() {
	local ret=0
	local depfile
	[ ! -d ${PKGDIR}/All ] && return $ret
	[ -n "$(dir_empty ${PKGDIR}/All)" ] && return $ret
	for pkg in ${PKGDIR}/All/*.${PKG_EXT}; do
		# Check for non-empty directory with no packages in it
		[ "${pkg}" = "${PKGDIR}/All/*.${PKG_EXT}" ] && break
		depfile=$(deps_file ${pkg})
		while read dep; do
			if [ ! -e "${PKGDIR}/All/${dep}.${PKG_EXT}" ]; then
				ret=1
				msg_debug "${pkg} needs missing ${PKGDIR}/All/${dep}.${PKG_EXT}"
				msg "Deleting ${pkg}: missing dependencies"
				delete_pkg ${pkg}
				break
			fi
		done < "${depfile}"
	done

	return $ret
}

mark_preinst() {

	cat > ${JAILMNT}/tmp/mtree.preexclude <<EOF
./var/db/pkg/*
./var/run/*
./wrkdirs/*
./new_packages/*
./tmp/*
./${LOCALBASE:-/usr/local}/share/nls/POSIX
./${LOCALBASE:-/usr/local}/share/nls/en_US.US-ASCII
./var/db/*
./var/log/*
./${HOME}/*
./etc/spwd.db
./etc/pwd.db
./etc/group
./etc/make.conf
./etc/make.conf.bak
./etc/passwd
./etc/master.passwd
./etc/shells
./compat/linux/proc
./proc
./var/mail/*
EOF
	mtree -X ${JAILMNT}/tmp/mtree.preexclude \
		-xcn -k uid,gid,mode,size \
		-p ${JAILMNT} >> ${JAILMNT}/tmp/mtree.preinst
}

check_leftovers() {
	mtree -X ${JAILMNT}/tmp/mtree.preexclude -x -f ${JAILMNT}/tmp/mtree.preinst \
		-p ${JAILMNT} | while read l ; do
		case ${l} in
		*extra)
			if [ -d ${JAILMNT}/${l% *} ]; then
				find ${JAILMNT}/${l% *} -exec echo "+ {}" \;
			else
				echo "+ ${JAILMNT}/${l% *}"
			fi
			;;
		*missing)
			l=${l#./}
			echo "- ${JAILMNT}/${l% *}"
			;;
		*changed) echo "M ${JAILMNT}/${l% *}" ;;
		esac
	done
}

# Build+test port and return on first failure
build_port() {
	[ $# -ne 1 ] && eargs portdir
	local portdir=$1
	local port=${portdir##/usr/ports/}
	local targets="check-config fetch checksum extract patch configure build run-depends install-mtree install package ${PORTTESTING:+deinstall}"
	local sub dists

	for phase in ${targets}; do
		zset status "${phase}:${port}"
		job_msg_verbose "Status for build ${port}: ${phase}"
		if [ "${phase}" = "fetch" ]; then
			jail -r ${JAILNAME} >/dev/null
			jrun 1
		fi
		case ${phase} in
		install) [ -n "${PORTTESTING}" ] && mark_preinst ;;
		deinstall)
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
			;;
		esac

		print_phase_header ${phase}
		[ "${phase}" = "package" ] && echo "PACKAGES=/new_packages" >> ${JAILMNT}/etc/make.conf
		injail env ${PKGENV} ${PORT_FLAGS} make -C ${portdir} ${phase} || return 1
		print_phase_footer

		if [ "${phase}" = "checksum" ]; then
			sub=$(injail make -C ${portdir} -VDIST_SUBDIR)
			dists=$(injail make -C ${portdir} -V_DISTFILES -V_PATCHFILES)
			mkdir -p ${JAILMNT}/portdistfiles
			echo "DISTDIR=/portdistfiles" >> ${JAILMNT}/etc/make.conf
			for d in ${dists}; do
				[ -f ${DISTFILES_CACHE}/${sub}/${d} ] || continue
				echo ${DISTFILES_CACHE}/${sub}/${d}
			done | pax -rw -p p -s ",${DISTFILES_CACHE},,g" ${JAILMNT}/portdistfiles
		fi

		if [ "${phase}" = "checksum" ]; then
			jail -r ${JAILNAME} >/dev/null
			jrun 0
		fi
		if [ "${phase}" = "deinstall" ]; then
			msg "Checking for extra files and directories"
			PREFIX=`injail env ${PORT_FLAGS} make -C ${portdir} -VPREFIX`
			zset status "leftovers:${port}"
			local portname datadir etcdir docsdir examplesdir wwwdir site_perl
			local add=$(mktemp ${JAILMNT}/tmp/add.XXXXXX)
			local add1=$(mktemp ${JAILMNT}/tmp/add1.XXXXXX)
			local del=$(mktemp ${JAILMNT}/tmp/del.XXXXXX)
			local del1=$(mktemp ${JAILMNT}/tmp/del1.XXXXXX)
			local mod=$(mktemp ${JAILMNT}/tmp/mod.XXXXXX)
			local mod1=$(mktemp ${JAILMNT}/tmp/mod1.XXXXXX)
			local die=0

			sedargs=$(injail env ${PORT_FLAGS} make -C ${portdir} -V'PLIST_SUB:NLIB32*:NPERL_*:NPREFIX*:N*="":N*="@comment*:C/(.*)=(.*)/-es!\2!%%\1%%!g/')

			check_leftovers | \
				while read modtype path; do
				local ppath

				# If this is a directory, use @dirrm in output
				if [ -d "${path}" ]; then
					ppath="@dirrm "`echo $path | sed \
						-e "s,^${JAILMNT},," \
						-e "s,^${PREFIX}/,," \
						${sedargs} \
					`
				else
					ppath=`echo "$path" | sed \
						-e "s,^${JAILMNT},," \
						-e "s,^${PREFIX}/,," \
						${sedargs} \
					`
				fi
				case $modtype in
				+) echo "${ppath}" >> ${add};;
				-) echo "${ppath}" >> ${del};;
				M)
					[ -d "${path}" ] && continue
					echo "${ppath}" >> ${mod}
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
				die=1
				grep -v "^@dirrm" ${add}
				grep "^@dirrm" ${add} | sort -r
			fi
			if [ -s "${del}" ]; then
				msg "Files or directories removed:"
				die=1
				cat ${del}
			fi
			if [ -s "${mod}" ]; then
				msg "Files or directories modified:"
				die=1
				cat ${mod1}
			fi
			rm -f ${add} ${add1} ${del} ${del1} ${mod} ${mod1}
			[ $die -eq 0 ] || return 1
		fi
	done
	jail -r ${JAILNAME} >/dev/null
	jrun 0

	# everything was fine we can copy package the package to the package
	# directory
	pax -rw -p p -s ",${JAILMNT}/new_packages,,g" ${JAILMNT}/new_packages ${POUDRIERE_DATA}/packages/${JAILNAME%-job-*}-${PTNAME}${SETNAME}

	zset status "idle:"
	return 0
}

# Save wrkdir and return path to file
save_wrkdir() {
	[ $# -ne 3 ] && eargs port portdir phase
	local port="$1"
	local portdir="$2"
	local phase="$3"
	local tardir=${POUDRIERE_DATA}/wrkdirs/${JAILNAME%-job-*}/${PTNAME}
	local tarname=${tardir}/${PKGNAME}.${WRKDIR_ARCHIVE_FORMAT}
	local mnted_portdir=${JAILMNT}/wrkdirs/${portdir}

	[ -n "${SAVE_WRKDIR}" ] || return 0
	# Only save if not in fetch/checksum phase
	[ "${failed_phase}" != "fetch" -a "${failed_phase}" != "checksum" -a "${failed_phase}" != "extract" ] || return 0

	mkdir -p ${tardir}

	# Tar up the WRKDIR, and ignore errors
	case ${WRKDIR_ARCHIVE_FORMAT} in
	tar) COMPRESSKEY="" ;;
	tgz) COMPRESSKEY="z" ;;
	tbz) COMPRESSKEY="j" ;;
	txz) COMPRESSKEY="J" ;;
	esac
	rm -f ${tarname}
	tar -s ",${mnted_portdir},," -c${COMPRESSKEY}f ${tarname} ${mnted_portdir}/work > /dev/null 2>&1

	job_msg "Saved ${port} wrkdir to: ${tarname}"
}

start_builder() {
	local j="$1"
	local mnt fs name

	mnt="${JAILMNT}/build/${j}"
	fs="${JAILFS}/build/${j}"
	name="${JAILNAME}-job-${j}"
	zset status "starting_jobs:${j}"
	mkdir -p "${mnt}"
	zfs clone -o mountpoint=${mnt} \
		-o sync=disabled \
		-o atime=off \
		-o compression=off \
		-o ${NS}:name=${name} \
		-o ${NS}:type=rootfs \
		-o ${NS}:arch=${arch} \
		-o ${NS}:version=${version} \
		${JAILFS}@prepkg ${fs}
	zfs snapshot ${fs}@prepkg
	# Jail might be lingering from previous build. Already recursively
	# destroyed all the builder datasets, so just try stopping the jail
	# and ignore any errors
	jail -r ${name} >/dev/null 2>&1 || :
	MASTERMNT=${JAILMNT} JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} do_jail_mounts 0
	MASTERMNT=${JAILMNT} JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} do_portbuild_mounts 0
	MASTERMNT=${JAILMNT} JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} jrun 0
	JAILFS=${fs} zset status "idle:"

}
start_builders() {
	local arch=$(zget arch)
	local version=$(zget version)
	local j

	zfs create -o canmount=off ${JAILFS}/build

	parallel_start
	for j in ${JOBS}; do
		parallel_run start_builder ${j}
	done
	parallel_stop
}

stop_builders() {
	local j mnt

	# wait for the last running processes
	cat ${JAILMNT}/poudriere/var/run/*.pid 2>/dev/null | xargs pwait 2>/dev/null

	msg "Stopping ${PARALLEL_JOBS} builders"

	for j in ${JOBS}; do
		jail -r ${JAILNAME}-job-${j} >/dev/null 2>&1 || :
	done

	mnt=`realpath ${JAILMNT}`
	mount | awk -v mnt="${mnt}/build/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r | xargs umount -f 2>/dev/null || :

	zfs destroy -r ${JAILFS}/build 2>/dev/null || :

	# No builders running, unset JOBS
	JOBS=""
}

build_stats_list() {
	[ $# -ne 3 ] && eargs html_path type display_name
	local html_path="$1"
	local type=$2
	local display_name="$3"
	local port cnt pkgname extra port_category port_name
	local status_head="" status_col=""
	local reason_head="" reason_col=""

	if [ "${type}" != "skipped" ]; then
		status_head="<th>status</th>"
	fi

	# ignored has a reason
	if [ "${type}" = "ignored" -o "${type}" = "skipped" ]; then
		reason_head="<th>reason</th>"
	elif [ "${type}" = "failed" ]; then
		reason_head="<th>phase</th>"
	fi

cat >> ${html_path} << EOF
    <div id="${type}">
      <h2>${display_name} ports </h2>
      <table>
        <tr>
          <th>Port</th>
          <th>Origin</th>
	  ${status_head}
	  ${reason_head}
        </tr>
EOF
	cnt=0
	while read port extra; do
		pkgname=$(cache_get_pkgname ${port})
		port_category=${port%/*}
		port_name=${port#*/}

		if [ -n "${status_head}" ]; then
			status_col="<td><a href=\"${pkgname}.log\">logfile</a></td>"
		fi

		if [ "${type}" = "ignored" ]; then
			reason_col="<td>${extra}</td>"
		elif [ "${type}" = "skipped" ]; then
			reason_col="<td>depends failed: <a href="#tr_pkg_${extra}">${extra}</a></td>"
		elif [ "${type}" = "failed" ]; then
			reason_col="<td>${extra}</td>"
		fi

		cat >> ${html_path} << EOF
        <tr>
          <td id="tr_pkg_${pkgname}">${pkgname}</td>
          <td><a href="http://portsmon.freebsd.org/portoverview.py?category=${port_category}&amp;portname=${port_name}">${port}</a></td>
	  ${status_col}
	  ${reason_col}
        </tr>
EOF
		cnt=$(( cnt + 1 ))
	done <  ${JAILMNT}/poudriere/ports.${type}

	if [ "${type}" = "skipped" ]; then
		# Skipped lists the skipped origin for every dependency that wanted it
		zset stats_skipped $(
			awk '{print $1}' ${JAILMNT}/poudriere/ports.skipped |
			sort -u |
			wc -l)
	else
		zset stats_${type} $cnt
	fi

cat >> ${html_path} << EOF
      </table>
    </div>
EOF
}

build_stats() {
	local should_refresh=${1:-1}
	local port logdir pkgname html_path refresh_meta=""

	if [ "${POUDRIERE_BUILD_TYPE}" = "testport" ]; then
		# Discard test stats page for now
		html_path="/dev/null"
	else
		logdir=`log_path`
		[ -d "${logdir}" ] || mkdir -p "${logdir}"
		html_path="${logdir}/index.html.tmp"
	fi
	
	[ ${should_refresh} -eq 1 ] && \
		refresh_meta='<meta http-equiv="refresh" content="10">'

	cat > ${html_path} << EOF
<html>
  <head>
    ${refresh_meta}
    <meta http-equiv="pragma" content="NO-CACHE">
    <title>Poudriere bulk results</title>
    <style type="text/css">
      table {
        display: block;
        border: 2px;
        border-collapse:collapse;
        border: 2px solid black;
        margin-top: 5px;
      }
      th, td { border: 1px solid black; }
      #built td { background-color: #00CC00; }
      #failed td { background-color: #E00000 ; }
      #skipped td { background-color: #CC6633; }
      #ignored td { background-color: #FF9900; }
      :target { color: #FF0000; }
    </style>
    <script type="text/javascript">
      function toggle_display(id) {
        var e = document.getElementById(id);
        if (e.style.display != 'none')
          e.style.display = 'none';
        else
          e.style.display = 'block';
      }
    </script>
  </head>
  <body>
    <h1>Poudriere bulk results</h1>
    Page will auto refresh every 10 seconds.
    <ul>
      <li>Jail: ${JAILNAME}</li>
      <li>Ports tree: ${PTNAME}</li>
      <li>Set Name: ${SETNAME:-none}</li>
EOF
	local nbb=$(zget stats_built)
	local nbf=$(zget stats_failed)
	local nbi=$(zget stats_ignored)
	local nbs=$(zget stats_skipped)
	local nbq=$(zget stats_queued)
	local nbdone=$((nbb + nbf + nbi + nbs))
	cat >> ${html_path} << EOF
      <li>Queue: ${nbdone} / ${nbq}</li>
      <li>Nb ports built: ${nbb}</li>
      <li>Nb ports failed: ${nbf}</li>
      <li>Nb ports ignored: ${nbi}</li>
      <li>Nb ports skipped: ${nbs}</li>
    </ul>
    <hr />
    <button onclick="toggle_display('built');">Show/Hide success</button>
    <button onclick="toggle_display('failed');">Show/Hide failure</button>
    <button onclick="toggle_display('ignored');">Show/Hide ignored</button>
    <button onclick="toggle_display('skipped');">Show/Hide skipped</button>
    <hr />
EOF

	build_stats_list "${html_path}" "built" "Successful"
	build_stats_list "${html_path}" "failed" "Failed"
	build_stats_list "${html_path}" "ignored" "Ignored"
	build_stats_list "${html_path}" "skipped" "Skipped"

	cat >> ${html_path} << EOF
  </body>
</html>
EOF


	[ "${html_path}" = "/dev/null" ] || mv ${html_path} ${html_path%.tmp}
}

deadlock_detected() {
	local always_fail=${1:-1}
	local crashed_packages dependency_cycles

	# If there are still packages marked as "building" they have crashed
	# and it's likely some poudriere or system bug
	crashed_packages=$( \
		find ${JAILMNT}/poudriere/building -type d -mindepth 1 -maxdepth 1 | \
		sed -e "s:${JAILMNT}/poudriere/building/::" | tr '\n' ' ' \
	)
	[ -z "${crashed_packages}" ] ||	\
		err 1 "Crashed package builds detected: ${crashed_packages}"

	# Check if there's a cycle in the need-to-build queue
	dependency_cycles=$(\
		find ${JAILMNT}/poudriere/deps -mindepth 2 | \
		sed -e "s:${JAILMNT}/poudriere/deps/::" -e 's:/: :' | \
		# Only cycle errors are wanted
		tsort 2>&1 >/dev/null | \
		sed -e 's/tsort: //' | \
		awk '
		BEGIN {
			i = 0
		}
		{
			if ($0 == "cycle in data") {
				i = i + 1
				next
			}
			if (a[i])
				a[i] = a[i] " " $1
			else
				a[i] = $1
		}
		END {
			for (n in a)
				print "These packages depend on each other: " a[n]
		}' \
	)

	if [ -n "${dependency_cycles}" ]; then
		err 1 "Dependency loop detected:
${dependency_cycles}"
	fi

	[ ${always_fail} -eq 1 ] || return 0

	# No cycle, there's some unknown poudriere bug
	err 1 "Unknown stuck queue bug detected. Give this information to poudriere developers:
$(find ${JAILMNT}/poudriere/building ${JAILMNT}/poudriere/pool ${JAILMNT}/poudriere/deps)"
}

queue_empty() {
	local pool_dir
	[ -n "$(dir_empty ${JAILMNT}/poudriere/deps)" ] || return 1

	for pool_dir in ${POOL_BUCKET_DIRS}; do
		[ -n "$(dir_empty ${pool_dir})" ] || return 1
	done

	return 0
}

build_queue() {

	local j cnt mnt fs name pkgname read_queue builders_active should_build_stats
	local queue_empty

	should_build_stats=1 # Always build stats on first pass
	mkfifo ${MASTERMNT:-${JAILMNT}}/poudriere/builders.pipe
	exec 6<> ${MASTERMNT:-${JAILMNT}}/poudriere/builders.pipe
	rm -f ${MASTERMNT:-${JAILMNT}}/poudriere/builders.pipe
	queue_empty=0
	while :; do
		builders_active=0
		for j in ${JOBS}; do
			mnt="${JAILMNT}/build/${j}"
			fs="${JAILFS}/build/${j}"
			name="${JAILNAME}-job-${j}"
			if [ -f  "${JAILMNT}/poudriere/var/run/${j}.pid" ]; then
				if pgrep -F "${JAILMNT}/poudriere/var/run/${j}.pid" >/dev/null 2>&1; then
					builders_active=1
					continue
				fi
				should_build_stats=1
				rm -f "${JAILMNT}/poudriere/var/run/${j}.pid"
				JAILFS="${fs}" zset status "idle:"
			fi

			[ ${queue_empty} -eq 0 ] || continue

			pkgname=$(next_in_queue)
			if [ -z "${pkgname}" ]; then
				# Check if the ready-to-build pool and need-to-build pools
				# are empty
				queue_empty && queue_empty=1

				# Pool is waiting on dep, wait until a build
				# is done before checking the queue again
			else
				MASTERMNT=${JAILMNT} JAILNAME="${name}" JAILMNT="${mnt}" JAILFS="${fs}" \
					MY_JOBID="${j}" \
					build_pkg "${pkgname}" >/dev/null 2>&1 &
				echo "$!" > ${JAILMNT}/poudriere/var/run/${j}.pid

				# A new job is spawned, try to read the queue
				# just to keep things moving
				builders_active=1
			fi
		done

		if [ ${queue_empty} -eq 1 ]; then
			if [ ${builders_active} -eq 1 ]; then
				# The queue is empty, but builds are still going.
				# Wait on them.
				continue
			else
				# All work is done
				break
			fi
		fi

		[ ${builders_active} -eq 1 ] || deadlock_detected

		unset jobid; until trappedinfo=; read -t 30 jobid <&6 || [ -z "$trappedinfo" ]; do :; done

		if [ ${should_build_stats} -eq 1 ]; then
			build_stats
			should_build_stats=0
		fi
	done
	exec 6<&-
	exec 6>&-
}

# Build ports in parallel
# Returns when all are built.
parallel_build() {
	[ -z "${JAILMNT}" ] && err 2 "Fail: Missing JAILMNT"
	local nbq=$(zget stats_queued)
	local real_parallel_jobs=${PARALLEL_JOBS}

	# If pool is empty, just return
	test ${nbq} -eq 0 && return 0

	# Minimize PARALLEL_JOBS to queue size
	if [ ${PARALLEL_JOBS} -gt ${nbq} ]; then
		PARALLEL_JOBS=${nbq##* }
	fi

	msg "Hit ctrl+t at any time to see build progress and stats"
	msg "Building ${nbq} packages using ${PARALLEL_JOBS} builders"
	JOBS="$(jot -w %02d ${PARALLEL_JOBS})"

	zset status "starting_jobs:"
	start_builders

	# Duplicate stdout to socket 5 so the child process can send
	# status information back on it since we redirect its
	# stdout to /dev/null
	exec 5<&1

	zset status "parallel_build:"
	build_queue
	build_stats 0

	zset status "stopping_jobs:"
	stop_builders
	zset status "idle:"

	# Close the builder socket
	exec 5>&-

	# Restore PARALLEL_JOBS
	PARALLEL_JOBS=${real_parallel_jobs}

	return $(($(zget stats_failed) + $(zget stats_skipped)))
}

clean_pool() {
	[ $# -ne 2 ] && eargs pkgname clean_rdepends
	local pkgname=$1
	local clean_rdepends=$2
	local port skipped_origin

	[ ${clean_rdepends} -eq 1 ] && port=$(cache_get_origin "${pkgname}")

	# Cleaning queue (pool is cleaned here)
	sh ${SCRIPTPREFIX}/clean.sh "${MASTERMNT:-${JAILMNT}}" "${pkgname}" ${clean_rdepends} | sort -u | while read skipped_pkgname; do
		skipped_origin=$(cache_get_origin "${skipped_pkgname}")
		echo "${skipped_origin} ${pkgname}" >> ${MASTERMNT:-${JAILMNT}}/poudriere/ports.skipped
		job_msg "Skipping build of ${skipped_origin}: Dependent port ${port} failed"
	done

	rmdir ${MASTERMNT:-${JAILMNT}}/poudriere/building/${pkgname}
	balance_pool
}

print_phase_header() {
	printf "=======================<phase: %-13s>==========================\n" "$1"
}

print_phase_footer() {
	echo "======================================================================="
}

build_pkg() {
	# If this first check fails, the pool will not be cleaned up,
	# since PKGNAME is not yet set.
	[ $# -ne 1 ] && eargs pkgname
	local pkgname="$1"
	local port portdir
	local build_failed=0
	local name cnt
	local failed_status failed_phase
	local clean_rdepends=0
	local ignore

	PKGNAME="${pkgname}" # set ASAP so cleanup() can use it
	port=$(cache_get_origin ${pkgname})
	portdir="/usr/ports/${port}"

	job_msg "Starting build of ${port}"
	zset status "starting:${port}"
	zfs rollback -r ${JAILFS}@prepkg || err 1 "Unable to rollback ${JAILFS}"

	if [ -n "${TMPFS_LOCALBASE}" ]; then
		umount -f ${JAILMNT}/${LOCALBASE:-/usr/local} 2>/dev/null || :
		mount -t tmpfs tmpfs ${JAILMNT}/${LOCALBASE:-/usr/local}
	fi
	# If this port is IGNORED, skip it
	# This is checked here instead of when building the queue
	# as the list may start big but become very small, so here
	# is a less-common check
	ignore="$(injail make -C ${portdir} -VIGNORE)"

	msg "Cleaning up wrkdir"
	rm -rf ${JAILMNT}/wrkdirs/*

	msg "Building ${port}"
	log_start $(log_path)/${PKGNAME}.log
	buildlog_start ${portdir}

	if [ -n "${ignore}" ]; then
		msg "Ignoring ${port}: ${ignore}"
		echo "${port} ${ignore}" >> "${MASTERMNT:-${JAILMNT}}/poudriere/ports.ignored"
		job_msg "Finished build of ${port}: Ignored: ${ignore}"
		clean_rdepends=1
	else
		zset status "depends:${port}"
		job_msg_verbose "Status for build ${port}: depends"
		print_phase_header "depends"
		if ! injail make -C ${portdir} pkg-depends fetch-depends extract-depends \
			patch-depends build-depends lib-depends; then
			build_failed=1
			failed_phase="depends"
		else
			print_phase_footer
			# Only build if the depends built fine
			injail make -C ${portdir} clean
			if ! build_port ${portdir}; then
				build_failed=1
				failed_status=$(zget status)
				failed_phase=${failed_status%:*}

				save_wrkdir "${port}" "${portdir}" "${failed_phase}" || :
			elif [ -f ${mnt}/${portdir}/.keep ]; then
				save_wrkdir ${mnt} "${port}" "${portdir}" "noneed" ||:
			fi

			injail make -C ${portdir} clean
		fi

		if [ ${build_failed} -eq 0 ]; then
			echo "${port}" >> "${MASTERMNT:-${JAILMNT}}/poudriere/ports.built"

			job_msg "Finished build of ${port}: Success"
			# Cache information for next run
			pkg_cache_data "${PKGDIR}/All/${PKGNAME}.${PKG_EXT}" ${port} || :
		else
			echo "${port} ${failed_phase}" >> "${MASTERMNT:-${JAILMNT}}/poudriere/ports.failed"
			job_msg "Finished build of ${port}: Failed: ${failed_phase}"
			clean_rdepends=1
		fi
	fi

	clean_pool ${PKGNAME} ${clean_rdepends}

	zset status "done:${port}"
	buildlog_stop ${portdir}
	log_stop $(log_path)/${PKGNAME}.log
	echo ${MY_JOBID} >&6
}

list_deps() {
	[ $# -ne 1 ] && eargs directory
	local dir=$1
	local makeargs="-VPKG_DEPENDS -VBUILD_DEPENDS -VEXTRACT_DEPENDS -VLIB_DEPENDS -VPATCH_DEPENDS -VFETCH_DEPENDS -VRUN_DEPENDS"
	[ -d "${PORTSDIR}/${dir}" ] && dir="/usr/ports/${dir}"

	injail make -C ${dir} $makeargs | tr '\n' ' ' | \
		sed -e "s,[[:graph:]]*/usr/ports/,,g" -e "s,:[[:graph:]]*,,g" | sort -u
}

deps_file() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1
	local depfile=$(pkg_cache_dir ${pkg})/deps

	if [ ! -f "${depfile}" ]; then
		if [ "${PKG_EXT}" = "tbz" ]; then
			injail pkg_info -qr "/usr/ports/packages/All/${pkg##*/}" | awk '{ print $2 }' > "${depfile}"
		else
			pkg info -qdF "${pkg}" > "${depfile}"
		fi
	fi

	echo ${depfile}
}

pkg_get_origin() {
	[ $# -lt 1 ] && eargs pkg
	local pkg=$1
	local originfile=$(pkg_cache_dir ${pkg})/origin
	local origin=$2

	if [ ! -f "${originfile}" ]; then
		if [ -z "${origin}" ]; then
			if [ "${PKG_EXT}" = "tbz" ]; then
				origin=$(injail pkg_info -qo "/usr/ports/packages/All/${pkg##*/}")
			else
				origin=$(pkg query -F "${pkg}" "%o")
			fi
		fi
		echo ${origin} > "${originfile}"
	else
		read origin < "${originfile}"
	fi
	echo ${origin}
}

pkg_get_options() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1
	local optionsfile=$(pkg_cache_dir ${pkg})/options
	local compiled_options

	if [ ! -f "${optionsfile}" ]; then
		if [ "${PKG_EXT}" = "tbz" ]; then
			compiled_options=$(injail pkg_info -qf "/usr/ports/packages/All/${pkg##*/}" | awk -F: '$1 == "@comment OPTIONS" {print $2}' | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
		else
			compiled_options=$(pkg query -F "${pkg}" '%Ov %Ok' | awk '$1 == "on" {print $2}' | sort | tr '\n' ' ')
		fi
		echo "${compiled_options}" > "${optionsfile}"
		echo "${compiled_options}"
		return
	fi
	# optionsfile is multi-line, no point for read< trick here
	cat "${optionsfile}"
}

pkg_cache_data() {
	[ $# -ne 2 ] && eargs pkg origin
	# Ignore errors in here
	set +e
	local pkg=$1
	local origin=$2
	local cachedir=$(pkg_cache_dir ${pkg})
	local originfile=${cachedir}/origin

	mkdir -p $(pkg_cache_dir ${pkg})
	pkg_get_options ${pkg} > /dev/null
	pkg_get_origin ${pkg} ${origin} > /dev/null
	deps_file ${pkg} > /dev/null
	set -e
}

pkg_to_pkgname() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1
	local pkg_file=${pkg##*/}
	local pkgname=${pkg_file%.*}
	echo ${pkgname}
}

cache_dir() {
	echo ${POUDRIERE_DATA}/cache/${JAILNAME%-job-*}/${PTNAME}${SETNAME}
}

# Return the cache dir for the given pkg
# @param string pkg $PKGDIR/All/PKGNAME.PKG_EXT
pkg_cache_dir() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1
	local pkg_file=${pkg##*/}

	echo $(cache_dir)/${pkg_file}
}

clear_pkg_cache() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1

	rm -fr $(pkg_cache_dir ${pkg})
}

delete_pkg() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1

	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	rm -f "${pkg}"
	clear_pkg_cache ${pkg}
}

# Deleted cached information for stale packages (manually removed)
delete_stale_pkg_cache() {
	local pkgname
	local cachedir=$(cache_dir)
	[ ! -d ${cachedir} ] && return 0
	[ -n "$(dir_empty ${cachedir})" ] && return 0
	for pkg in ${cachedir}/*.${PKG_EXT}; do
		pkg_file=${pkg##*/}
		# If this package no longer exists in the PKGDIR, delete the cache.
		if [ ! -e "${PKGDIR}/All/${pkg_file}" ]; then
			clear_pkg_cache ${pkg}
		fi
	done
}

delete_old_pkg() {
	local pkg="$1"
	local o v v2 compiled_options current_options
	if [ "${pkg##*/}" = "repo.txz" ]; then
		msg "Removing invalid pkg repo file: ${pkg}"
		rm -f ${pkg}
		return 0
	fi

	mkdir -p $(pkg_cache_dir ${pkg})

	o=$(pkg_get_origin ${pkg})
	v=${pkg##*-}
	v=${v%.*}
	if [ ! -d "${JAILMNT}/usr/ports/${o}" ]; then
		msg "${o} does not exist anymore. Deleting stale ${pkg##*/}"
		delete_pkg ${pkg}
		return 0
	fi
	v2=$(cache_get_pkgname ${o})
	v2=${v2##*-}
	if [ "$v" != "$v2" ]; then
		msg "Deleting old version: ${pkg##*/}"
		delete_pkg ${pkg}
		return 0
	fi

	# Check if the compiled options match the current options from make.conf and /var/db/options
	if [ "${CHECK_CHANGED_OPTIONS:-no}" != "no" ]; then
		current_options=$(injail make -C /usr/ports/${o} pretty-print-config | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
		compiled_options=$(pkg_get_options ${pkg})

		if [ "${compiled_options}" != "${current_options}" ]; then
			msg "Options changed, deleting: ${pkg##*/}"
			if [ "${CHECK_CHANGED_OPTIONS}" = "verbose" ]; then
				msg "Pkg: ${compiled_options}"
				msg "New: ${current_options}"
			fi
			delete_pkg ${pkg}
			return 0
		fi
	fi
}

delete_old_pkgs() {
	[ ! -d ${PKGDIR}/All ] && return 0
	[ -n "$(dir_empty ${PKGDIR}/All)" ] && return 0
	parallel_start
	for pkg in ${PKGDIR}/All/*.${PKG_EXT}; do
		# Check for non-empty directory with no packages in it
		[ "${pkg}" = "${PKGDIR}/All/*.${PKG_EXT}" ] && break
		parallel_run delete_old_pkg "${pkg}"
	done
	parallel_stop
}

## Pick the next package from the "ready to build" queue in pool/
## Then move the package to the "building" dir in building/
## This is only ran from 1 process
next_in_queue() {
	local p pkgname

	[ ! -d ${JAILMNT}/poudriere/pool ] && err 1 "Build pool is missing"
	p=$(find ${POOL_BUCKET_DIRS} -type d -depth 1 -empty -print -quit || :)
	[ -n "$p" ] || return 0
	pkgname=${p##*/}
	mv ${p} ${JAILMNT}/poudriere/building/${pkgname}
	echo ${pkgname}
}

lock_acquire() {
	[ $# -ne 1 ] && eargs lockname
	local lockname=$1

	while :; do
		if mkdir ${POUDRIERE_DATA}/.lock-${JAILNAME}-${lockname} 2>/dev/null; then
			break
		fi
		sleep 0.1
	done
}

lock_release() {
	[ $# -ne 1 ] && eargs lockname
	local lockname=$1

	rmdir ${POUDRIERE_DATA}/.lock-${JAILNAME}-${lockname} 2>/dev/null
}

cache_get_pkgname() {
	[ $# -ne 1 ] && eargs origin
	local origin=${1%/}
	local pkgname="" existing_origin
	local cache_origin_pkgname=${MASTERMNT:-${JAILMNT}}/poudriere/var/cache/origin-pkgname/${origin%%/*}_${origin##*/}
	local cache_pkgname_origin

	[ -f ${cache_origin_pkgname} ] && read pkgname < ${cache_origin_pkgname}

	# Add to cache if not found.
	if [ -z "${pkgname}" ]; then
		[ -d "${PORTSDIR}/${origin}" ] || err 1 "Invalid port origin '${origin}' not found."
		pkgname=$(injail make -C /usr/ports/${origin} -VPKGNAME)
		# Make sure this origin did not already exist
		existing_origin=$(cache_get_origin "${pkgname}" 2>/dev/null || :)
		# It may already exist due to race conditions, it is not harmful. Just ignore.
		if [ "${existing_origin}" != "${origin}" ]; then
			[ -n "${existing_origin}" ] && \
				err 1 "Duplicated origin for ${pkgname}: ${origin} AND ${existing_origin}. Rerun with -vv to see which ports are depending on these."
			echo "${pkgname}" > ${cache_origin_pkgname}
			cache_pkgname_origin="${MASTERMNT:-${JAILMNT}}/poudriere/var/cache/pkgname-origin/${pkgname}"
			echo "${origin}" > "${cache_pkgname_origin}"
		fi
	fi

	echo ${pkgname}
}

cache_get_origin() {
	[ $# -ne 1 ] && eargs pkgname
	local pkgname=$1
	local cache_pkgname_origin="${MASTERMNT:-${JAILMNT}}/poudriere/var/cache/pkgname-origin/${pkgname}"

	cat "${cache_pkgname_origin%/}"
}

# Take optional pkgname to speedup lookup
compute_deps() {
	[ $# -lt 1 ] && eargs port
	[ $# -gt 2 ] && eargs port pkgnme
	local port=$1
	local pkgname="${2:-$(cache_get_pkgname ${port})}"
	local dep_pkgname dep_port
	local pkg_pooldir="${JAILMNT}/poudriere/deps/${pkgname}"
	mkdir "${pkg_pooldir}" 2>/dev/null || return 0

	msg_verbose "Computing deps for ${port}"

	for dep_port in `list_deps ${port}`; do
		msg_debug "${port} depends on ${dep_port}"
		[ "${port}" != "${dep_port}" ] || err 1 "${port} incorrectly depends on itself. Please contact maintainer of the port to fix this."
		# Detect bad cat/origin/ dependency which pkgng will not register properly
		[ "${dep_port}" = "${dep_port%/}" ] || err 1 "${port} depends on bad origin '${dep_port}'; Please contact maintainer of the port to fix this."
		dep_pkgname=$(cache_get_pkgname ${dep_port})

		# Only do this if it's not already done, and not ALL, as everything will
		# be touched anyway
		[ ${ALL:-0} -eq 0 ] && ! [ -d "${JAILMNT}/poudriere/deps/${dep_pkgname}" ] && \
			compute_deps "${dep_port}" "${dep_pkgname}"

		touch "${pkg_pooldir}/${dep_pkgname}"
		mkdir -p "${JAILMNT}/poudriere/rdeps/${dep_pkgname}"
		ln -sf "${pkg_pooldir}/${dep_pkgname}" \
			"${JAILMNT}/poudriere/rdeps/${dep_pkgname}/${pkgname}"
	done
}

listed_ports() {
	if [ ${ALL:-0} -eq 1 ]; then
		PORTSDIR=`porttree_get_base ${PTNAME}`
		[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
		for cat in $(awk '$1 == "SUBDIR" { print $3}' ${PORTSDIR}/Makefile); do
			awk -v cat=${cat}  '$1 == "SUBDIR" { print cat"/"$3}' ${PORTSDIR}/${cat}/Makefile
		done
		return
	fi
	if [ -z "${LISTPORTS}" ]; then
		if [ -n "${LISTPKGS}" ]; then
			grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}
		fi
	else
		echo ${LISTPORTS} | tr ' ' '\n'
	fi
}

parallel_exec() {
	local cmd="$1"
	shift 1
	${cmd} "$@"
	echo >&6
}

parallel_start() {
	local fifo

	if [ -n "${MASTERMNT:-${JAILMNT}}" ]; then
		fifo=${MASTERMNT:-${JAILMNT}}/poudriere/parallel.pipe
	else
		fifo=$(mktemp -ut parallel)
	fi
	mkfifo ${fifo}
	exec 6<> ${fifo}
	rm -f ${fifo}
	export NBPARALLEL=0
	export PARALLEL_PIDS=""
}

parallel_stop() {
	for pid in ${PARALLEL_PIDS}; do
		# This will read the return code of each child
		# and properly error out if the children errored
		wait ${pid}
	done

	exec 6<&-
	exec 6>&-
	unset PARALLEL_PIDS
}

parallel_run() {
	local cmd="$1"
	shift 1

	if [ ${NBPARALLEL} -eq ${PARALLEL_JOBS} ]; then
		unset a; until trappedinfo=; read a <&6 || [ -z "$trappedinfo" ]; do :; done
	fi
	[ ${NBPARALLEL} -lt ${PARALLEL_JOBS} ] && NBPARALLEL=$((NBPARALLEL + 1))

	parallel_exec $cmd "$@" &
	PARALLEL_PIDS="${PARALLEL_PIDS} $!"
}

# Get all data that make this build env unique,
# so if the same build is done again,
# we can use the some of the same cached data
cache_get_key() {
	if [ -z "${CACHE_KEY}" ]; then
		CACHE_KEY=$({
			injail env
			injail cat /etc/make.conf
			injail find /var/db/ports -exec sha256 {} +
			echo ${JAILNAME}-${SETNAME}-${PTNAME}
			if [ -f ${JAILMNT}/usr/ports/.poudriere.stamp ]; then
				cat ${JAILMNT}/usr/ports/.poudriere.stamp
			else
				# This is not a poudriere-managed ports tree.
				# Just toss in getpid() to invalidate the cache
				# as there is no quick way to hash the tree without
				# taking possibly minutes+
				echo $$
			fi
		} | sha256)
	fi
	echo ${CACHE_KEY}
}

prepare_ports() {
	local pkg n

	msg "Calculating ports order and dependencies"
	mkdir -p "${JAILMNT}/poudriere"
	[ -n "${TMPFS_DATA}" ] && mount -t tmpfs tmpfs "${JAILMNT}/poudriere"
	rm -rf "${JAILMNT}/poudriere/var/cache/origin-pkgname" \
	       "${JAILMNT}/poudriere/var/cache/pkgname-origin" 2>/dev/null || :
	mkdir -p "${JAILMNT}/poudriere/building" \
		"${JAILMNT}/poudriere/pool" \
		"${JAILMNT}/poudriere/deps" \
		"${JAILMNT}/poudriere/rdeps" \
		"${JAILMNT}/poudriere/var/run" \
		"${JAILMNT}/poudriere/var/cache" \
		"${JAILMNT}/poudriere/var/cache/origin-pkgname" \
		"${JAILMNT}/poudriere/var/cache/pkgname-origin"

	POOL_BUCKET_DIRS=""
	if [ ${POOL_BUCKETS} -gt 0 ]; then
		# Add pool/N dirs in reverse order from highest to lowest
		for n in $(jot ${POOL_BUCKETS} 0 | sort -nr); do
			POOL_BUCKET_DIRS="${POOL_BUCKET_DIRS} ${JAILMNT}/poudriere/pool/${n}"
		done
	fi
	# Add unbalanced at the end
	POOL_BUCKET_DIRS="${POOL_BUCKET_DIRS} ${JAILMNT}/poudriere/pool/unbalanced"

	mkdir -p ${POOL_BUCKET_DIRS}

	zset stats_queued 0
	zset stats_built 0
	zset stats_failed 0
	zset stats_ignored 0
	zset stats_skipped 0
	:> ${JAILMNT}/poudriere/ports.built
	:> ${JAILMNT}/poudriere/ports.failed
	:> ${JAILMNT}/poudriere/ports.ignored
	:> ${JAILMNT}/poudriere/ports.skipped
	build_stats

	zset status "computingdeps:"
	parallel_start
	for port in $(listed_ports); do
		[ -d "${PORTSDIR}/${port}" ] || err 1 "Invalid port origin: ${port}"
		parallel_run compute_deps ${port}
	done
	parallel_stop

	zset status "sanity:"

	if [ ${CLEAN_LISTED:-0} -eq 1 ]; then
		listed_ports | while read port; do
			pkg="${PKGDIR}/All/$(cache_get_pkgname  ${port}).${PKG_EXT}"
			if [ -f "${pkg}" ]; then
				msg "Deleting existing package: ${pkg##*/}"
				delete_pkg ${pkg}
			fi
		done
	fi

	if [ $SKIPSANITY -eq 0 ]; then
		msg "Sanity checking the repository"
		delete_stale_pkg_cache
		delete_old_pkgs

		while :; do
			sanity_check_pkgs && break
		done
	fi

	msg "Deleting stale symlinks"
	find -L ${PKGDIR} -type l -exec rm -vf {} +

	zset status "cleaning:"
	msg "Cleaning the build queue"
	export LOCALBASE=${LOCALBASE:-/usr/local}
	for pn in $(ls ${JAILMNT}/poudriere/deps/); do
		if [ -f "${PKGDIR}/All/${pn}.${PKG_EXT}" ]; then
			# Cleanup rdeps/*/${pn}
			for rpn in $(ls "${JAILMNT}/poudriere/deps/${pn}"); do
				echo "${JAILMNT}/poudriere/rdeps/${rpn}/${pn}"
			done
			echo "${JAILMNT}/poudriere/deps/${pn}"
			# Cleanup deps/*/${pn}
			if [ -d "${JAILMNT}/poudriere/rdeps/${pn}" ]; then
				for rpn in $(ls "${JAILMNT}/poudriere/rdeps/${pn}"); do
					echo "${JAILMNT}/poudriere/deps/${rpn}/${pn}"
				done
				echo "${JAILMNT}/poudriere/rdeps/${pn}"
			fi
		fi
	done | xargs rm -rf

	# Call the deadlock code as non-fatal which will check for cycles
	deadlock_detected 0

	local nbq=0
	nbq=$(find ${JAILMNT}/poudriere/deps -type d -depth 1 | wc -l)
	zset stats_queued "${nbq##* }"

	# Create a pool of ready-to-build from the deps pool
	find "${JAILMNT}/poudriere/deps" -type d -empty|xargs -J % mv % "${JAILMNT}/poudriere/pool/unbalanced"
	balance_pool
}

balance_pool() {
	local pkgname pkg_dir dep_count rdep lock
	local mnt=${MASTERMNT:-${JAILMNT}}

	# Don't bother if disabled
	[ ${POOL_BUCKETS} -gt 0 ] || return 0

	[ -z "$(dir_empty ${mnt}/poudriere/pool/unbalanced)" ] || return 0
	# Avoid running this in parallel, no need
	lock=${mnt}/poudriere/.lock-balance_pool
	mkdir ${lock} 2>/dev/null || return 0

	zset status "balancing_pool:"

	# For everything ready-to-build...
	for pkg_dir in ${mnt}/poudriere/pool/unbalanced/*; do
		pkgname=${pkg_dir##*/}
		dep_count=0
		# Determine its priority, based on how much depends on it
		for rdep in ${mnt}/poudriere/rdeps/${pkgname}/*; do
			# Empty
			[ ${rdep} = "${mnt}/poudriere/rdeps/${pkgname}/*" ] && break
			dep_count=$(($dep_count + 1))
			[ $dep_count -eq $((${POOL_BUCKETS} - 1)) ] && break
		done
		mv ${pkg_dir} ${mnt}/poudriere/pool/${dep_count##* }/ 2>/dev/null || :
	done

	rmdir ${lock}
}

append_make() {
	[ $# -ne 1 ] && eargs makeconf
	local makeconf="$(realpath "$1")"

	msg "Appending to /etc/make.conf: ${makeconf}"
	echo "#### ${makeconf} ####" >> ${JAILMNT}/etc/make.conf
	cat "${makeconf}" >> ${JAILMNT}/etc/make.conf
}

prepare_jail() {
	if [ -z "${NO_PACKAGE_BUILDING}" ]; then
		export PACKAGE_BUILDING=yes
	fi
	export FORCE_PACKAGE=yes
	export USER=root
	export HOME=/root
	PORTSDIR=`porttree_get_base ${PTNAME}`
	[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
	[ -z "${JAILMNT}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"
	[ -d ${DISTFILES_CACHE:-/nonexistent} ] || err 1 "DISTFILES_CACHE directory does not exists. (c.f. poudriere.conf)"
	[ "$(realpath ${DISTFILES_CACHE})" != \
		"$(realpath -q ${PORTSDIR}/distfiles)" ] || err 1 \
		"DISTFILES_CACHE cannot be in the portsdir as the portsdir will be mounted read-only"

	msg "Mounting ports from: ${PORTSDIR}"
	do_portbuild_mounts 1

	[ -f ${POUDRIERED}/make.conf ] && append_make ${POUDRIERED}/make.conf
	[ -f ${POUDRIERED}/${SETNAME#-}-make.conf ] && append_make ${POUDRIERED}/${SETNAME#-}-make.conf
	[ -f ${POUDRIERED}/${PTNAME}-make.conf ] && append_make ${POUDRIERED}/${PTNAME}-make.conf
	[ -f ${POUDRIERED}/${JAILNAME}-make.conf ] && append_make ${POUDRIERED}/${JAILNAME}-make.conf
	[ -f ${POUDRIERED}/${JAILNAME}-${PTNAME}-make.conf ] && append_make ${POUDRIERED}/${JAILNAME}-${PTNAME}-make.conf
	[ -n "${SETNAME}" -a -f ${POUDRIERED}/${JAILNAME}${SETNAME}-make.conf ] && append_make ${POUDRIERED}/${JAILNAME}${SETNAME}-make.conf
	if [ -z "${NO_PACKAGE_BUILDING}" ]; then
		echo "PACKAGE_BUILDING=yes" >> ${JAILMNT}/etc/make.conf
	fi

	mkdir -p ${JAILMNT}/${LOCALBASE:-/usr/local}
	WITH_PKGNG=$(injail make -f /usr/ports/Mk/bsd.port.mk -V WITH_PKGNG)
	if [ -n "${WITH_PKGNG}" ]; then
		export PKGNG=1
		export PKG_EXT="txz"
		export PKG_ADD="${LOCALBASE:-/usr/local}/sbin/pkg add"
		export PKG_DELETE="${LOCALBASE:-/usr/local}/sbin/pkg delete -y -f"
	else
		export PKGNG=0
		export PKG_ADD=pkg_add
		export PKG_DELETE=pkg_delete
		export PKG_EXT="tbz"
	fi

	export LOGS=${POUDRIERE_DATA}/logs
}

RESOLV_CONF=""
STATUS=0 # out of jail #

test -f ${SCRIPTPREFIX}/../../etc/poudriere.conf || err 1 "Unable to find ${SCRIPTPREFIX}/../../etc/poudriere.conf"
. ${SCRIPTPREFIX}/../../etc/poudriere.conf
POUDRIERED=${SCRIPTPREFIX}/../../etc/poudriere.d

[ -z ${ZPOOL} ] && err 1 "ZPOOL variable is not set"
[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"

trap sig_handler SIGINT SIGTERM SIGKILL
trap exit_handler EXIT
trap siginfo_handler SIGINFO

# Test if zpool exists
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"

: ${SVN_HOST="svn.FreeBSD.org"}
: ${GIT_URL="git://github.com/freebsd/freebsd-ports.git"}
: ${FREEBSD_HOST="${FTP_HOST:-ftp.FreeBSD.org}"}
: ${ZROOTFS="/poudriere"}

case ${ZROOTFS} in
	[!/]*)
		err 1 "ZROOTFS shoud start with a /"
		;;
esac

: ${CRONDIR="${POUDRIERE_DATA}/cron"}
POUDRIERE_DATA=`get_data_dir`
: ${WRKDIR_ARCHIVE_FORMAT="tbz"}
case "${WRKDIR_ARCHIVE_FORMAT}" in
	tar|tgz|tbz|txz);;
	*) err 1 "invalid format for WRKDIR_ARCHIVE_FORMAT: ${WRKDIR_ARCHIVE_FORMAT}" ;;
esac

case ${PARALLEL_JOBS} in
''|*[!0-9]*)
	PARALLEL_JOBS=$(sysctl -n hw.ncpu)
	;;
esac

case ${POOL_BUCKETS} in
''|*[!0-9]*)
	POOL_BUCKETS=10
	;;
esac
