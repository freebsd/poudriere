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
	echo "${LOGS}/${POUDRIERE_BUILD_TYPE}/${JAILNAME%-job-*}/${PTNAME}"
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

port_exists() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,name ${ZPOOL}${ZROOTFS} | \
		awk -v n=$1 'BEGIN { ret = 1 } $1 == "ports" && $2 == n { ret = 0; } END { exit ret }' && return 0
	return 1
}

port_get_base() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,mountpoint ${ZPOOL}${ZROOTFS} | \
		awk -v n=$1 '$1 == "ports" && $2 == n { print $3 }'
}

port_get_fs() {
	[ $# -ne 1 ] && eargs portstree_name
	zfs list -rt filesystem -H -o ${NS}:type,${NS}:name,name ${ZPOOL}${ZROOTFS} | \
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

do_jail_mounts() {
	[ $# -ne 1 ] && eargs should_mkdir
	local should_mkdir=$1
	local arch=$(zget arch)

	# Only do this when starting the master jail, clones will already have the dirs
	if [ ${should_mkdir} -eq 1 ]; then
		mkdir -p ${JAILMNT}/proc
	fi

	mount -t devfs devfs ${JAILMNT}/dev
	mount -t procfs proc ${JAILMNT}/proc

	if [ -z "${NOLINUX}" ]; then
		if [ "${arch}" = "i386" -o "${arch}" = "amd64" ]; then
			if [ ${should_mkdir} -eq 1 ]; then
				mkdir -p ${JAILMNT}/compat/linux/proc
				mkdir -p ${JAILMNT}/compat/linux/sys
			fi
			mount -t linprocfs linprocfs ${JAILMNT}/compat/linux/proc
			mount -t linsysfs linsysfs ${JAILMNT}/compat/linux/sys
		fi
	fi
}

do_portbuild_mounts() {
	[ $# -ne 1 ] && eargs should_mkdir
	local should_mkdir=$1

	# Only do this when starting the master jail, clones will already have the dirs
	if [ ${should_mkdir} -eq 1 ]; then
		mkdir -p ${PORTSDIR}/packages
		mkdir -p ${PKGDIR}/All
		if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
			mkdir -p ${JAILMNT}/usr/ports/distfiles
		fi
		if [ -n "${CCACHE_DIR}" -a -d "${CCACHE_DIR}" ]; then
			mkdir -p ${JAILMNT}${CCACHE_DIR} || err 1 "Failed to create ccache directory "
			msg "Mounting ccache from ${CCACHE_DIR}"
			export CCACHE_DIR
			export WITH_CCACHE_BUILD=yes
		fi
	fi

	mount -t nullfs ${PORTSDIR} ${JAILMNT}/usr/ports || err 1 "Failed to mount the ports directory "
	mount -t nullfs ${PKGDIR} ${JAILMNT}/usr/ports/packages || err 1 "Failed to mount the packages directory "

	if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
		mount -t nullfs ${DISTFILES_CACHE} ${JAILMNT}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
	fi
	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILMNT}/wrkdirs
	[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILMNT}/wrkdirs

	if [ -d ${POUDRIERED}/${JAILNAME%-job-*}-options ]; then
		mount -t nullfs ${POUDRIERED}/${JAILNAME%-job-*}-options ${JAILMNT}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	elif [ -d ${POUDRIERED}/options ]; then
		mount -t nullfs ${POUDRIERED}/options ${JAILMNT}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	fi

	if [ -n "${CCACHE_DIR}" -a -d "${CCACHE_DIR}" ]; then
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
	jail_runs || err 1 "No such jail running: ${JAILNAME%-job-*}"
	zset status "stop:"

	jail -r ${JAILNAME%-job-*}
	# Shutdown all builders
	if [ ${PARALLEL_JOBS} -ne 0 ]; then
		# - here to only check for unset, {start,stop}_builders will set this to blank if already stopped
		for j in ${JOBS-$(jot -w %02d ${PARALLEL_JOBS})}; do
			jail -r ${JAILNAME%-job-*}-job-${j} >/dev/null 2>&1 || :
		done
	fi
	msg "Umounting file systems"
	mount | awk -v mnt="${MASTERMNT:-${JAILMNT}}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r | xargs umount -f || :

	if [ -n "${MFSSIZE}" ]; then
		# umount the ${JAILMNT}/build/$jobno/wrkdirs
		mount | grep "/dev/md.*${MASTERMNT:-${JAILMNT}}/build" | while read mnt; do
			local dev=`echo $mnt | awk '{print $1}'`
			if [ -n "$dev" ]; then
				umount $dev
				mdconfig -d -u $dev
			fi
		done
		# umount the $JAILMNT/wrkdirs
		local dev=`mount | grep "/dev/md.*${MASTERMNT:-${JAILMNT}}" | awk '{print $1}'`
		if [ -n "$dev" ]; then
			umount $dev
			mdconfig -d -u $dev
		fi
	fi
	zfs rollback -R ${JAILFS%/build/*}@clean
	zset status "idle:"
	export STATUS=0
}

port_create_zfs() {
	[ $# -ne 3 ] && eargs name mountpoint fs
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
	[ -z "${JAILNAME%-job-*}" ] && err 2 "Fail: Missing JAILNAME"
	log_stop
	for pid in ${MASTERMNT:-${JAILMNT}}/*.pid; do
		# Ensure there is a pidfile to read or break
		[ "${pid}" = "${MASTERMNT:-${JAILMNT}}/*.pid" ] && break
		pkill -15 -F ${pid} >/dev/null 2>&1 || :
	done
	wait
	zfs destroy -r ${JAILFS%/build/*}/build 2>/dev/null || :
	zfs destroy -r ${JAILFS%/build/*}@prepkg 2>/dev/null || :
	zfs destroy -r ${JAILFS%/build/*}@prebuild 2>/dev/null || :
	jail_stop
}

injail() {
	jexec -U root ${JAILNAME} $@
}

sanity_check_pkgs() {
	local ret=0
	local depfile
	[ ! -d ${PKGDIR}/All ] && return $ret
	[ -z "$(ls -A ${PKGDIR}/All)" ] && return $ret
	for pkg in ${PKGDIR}/All/*.${PKG_EXT}; do
		# Check for non-empty directory with no packages in it
		[ "${pkg}" = "${PKGDIR}/All/*.${PKG_EXT}" ] && break
		depfile=$(deps_file ${pkg})
		while read dep; do
			if [ ! -e "${PKGDIR}/All/${dep}.${PKG_EXT}" ]; then
				ret=1
				msg "Deleting ${pkg}: missing dependencies"
				delete_pkg ${pkg}
				break
			fi
		done < "${depfile}"
	done

	return $ret
}

build_port() {
	[ $# -ne 1 ] && eargs portdir
	local portdir=$1
	local port=${portdir##/usr/ports/}
	local targets="fetch checksum extract patch configure build install package"

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
					ppath=`echo "$path" | sed -e "s,^${JAILMNT},," -e "s,^${PREFIX}/,," -e "s,^share/${portname},%%DATADIR%%," -e "s,^etc/${portname},%%ETCDIR%%,"`
					case "$ppath" in
					/var/db/pkg/*) continue;;
					/var/run/*) continue;;
					/wrkdirs/*) continue;;
					/tmp/*) continue;;
					share/nls/POSIX) continue;;
					share/nls/en_US.US-ASCII) continue;;
					/var/log/*) continue;;
					/var/mail/*) continue;;
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
	zfs destroy -r ${JAILFS}@prebuild || :
	return 0
}

save_wrkdir() {
	[ $# -ne 1 ] && eargs port

	local portdir="/usr/ports/${port}"
	local tardir=${POUDRIERE_DATA}/wrkdirs/${JAILNAME%-job-*}/${PTNAME}
	local tarname=${tardir}/${PKGNAME}.tbz
	local mnted_portdir=${JAILMNT}/wrkdirs/${portdir}

	mkdir -p ${tardir}

	# Tar up the WRKDIR, and ignore errors
	rm -f ${tarname}
	tar -s ",${mnted_portdir},," -cjf ${tarname} ${mnted_portdir}/work > /dev/null 2>&1
	msg "[${MY_JOBID}] Saved ${port} wrkdir to: ${tarname}" >&5
}

start_builders() {
	local arch=$(zget arch)
	local version=$(zget version)
	local j mnt fs name

	zfs create -o canmount=off ${JAILFS}/build

	for j in ${JOBS}; do
		mnt="${JAILMNT}/build/${j}"
		fs="${JAILFS}/build/${j}"
		name="${JAILNAME}-job-${j}"
		mkdir -p "${mnt}"
		zfs clone -o mountpoint=${mnt} \
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
	done
}

stop_builders() {
	local j mnt

	# wait for the last running processes
	cat ${JAILMNT}/*.pid 2>/dev/null | xargs pwait 2>/dev/null

	msg "Stopping ${PARALLEL_JOBS} builders"

	for j in ${JOBS}; do
		jail -r ${JAILNAME}-job-${j} >/dev/null 2>&1 || :
	done

	mount | awk -v mnt="${JAILMNT}/build/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r | xargs umount -f 2>/dev/null || :

	zfs destroy -r ${JAILFS}/build 2>/dev/null || :

	# No builders running, unset JOBS
	JOBS=""
}


build_stats() {
	local port logdir pkgname
	logdir=`log_path`

cat > ${logdir}/index.html << EOF
<html>
  <head>
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
      td.success { background-color: #00CC00; }
      td.failed { background-color: #E00000 ; }
      td.ignored { background-color: #FF9900; }
    </style>
    <script type="text/javascript">
      function toggle_display(id) {
        var e = document.getElementById(id);
        if(e.style.display == 'block')
          e.style.display = 'none';
        else
          e.style.display = 'block';
      }
    </script>
  </head>
  <body>
    <h1>Poudriere bulk results</h1>
    <ul>
      <li>Jail: ${JAILNAME}</li>
      <li>Ports tree: ${PTNAME}</li>
EOF
				cnt=$(zget stats_queued)
cat >> ${logdir}/index.html << EOF
      <li>Nb ports queued: ${cnt}</li>
    </ul>
    <hr />
    <button onclick="toggle_display('success');">Show/Hide success</button>
    <button onclick="toggle_display('failed');">Show/Hide failure</button>
    <button onclick="toggle_display('ignored');">Show/Hide ignored</button>
    <hr />
    <div id="failed">
      <h2>Failed ports </h2>
      <table>
        <tr>
          <th>Port</th>
          <th>Origin</th>
          <th>status</th>
        </tr>
EOF
				cnt=0
				while read port; do
	pkgname=$(cache_get_pkgname ${port})
cat >> ${logdir}/index.html << EOF
        <tr>
          <td>${pkgname}</td>
          <td>${port}</td>
          <td><a href="${pkgname}.log">logfile</a></td>
        </tr>
EOF
				cnt=$(( cnt + 1 ))
				done <  ${JAILMNT}/failed
				zset stats_failed $cnt
cat >> ${logdir}/index.html << EOF
      </table>
    </div>
    <div id="ignored">
      <h2>Ignored ports </h2>
      <table>
        <tr>
          <th>Port</th>
          <th>Origin</th>
          <th>status</th>
        </tr>
EOF
				cnt=0
				while read port; do
	pkgname=$(cache_get_pkgname ${port})
cat >> ${logdir}/index.html << EOF
        <tr>
          <td>${pkgname}</td>
          <td>${port}</td>
          <td><a href="${pkgname}.log">logfile</a></td>
        </tr>
EOF
				cnt=$(( cnt + 1 ))
				done < ${JAILMNT}/ignored
				zset stats_ignored $cnt
cat >> ${logdir}/index.html << EOF
      </table>
    </div>
    <div id="success">
      <h2>Successful ports </h2>
      <table>
        <tr>
          <th>Port</th>
          <th>Origin</th>
          <th>status</th>
        </tr>
EOF
				cnt=0
				while read port; do
	pkgname=$(cache_get_pkgname ${port})
cat >> ${logdir}/index.html << EOF
        <tr>
          <td>${pkgname}</td>
          <td>${port}</td>
          <td><a href="${pkgname}.log">logfile</a></td>
        </tr>
EOF
				cnt=$(( cnt + 1 ))
				done < ${JAILMNT}/built
				zset stats_built $cnt
cat >> ${logdir}/index.html << EOF
      </table>
    </div>
  </body>
</html>
EOF
}

build_queue() {

	local activity j cnt mnt fs name port

	while :; do
		activity=0
		for j in ${JOBS}; do
			mnt="${JAILMNT}/build/${j}"
			fs="${JAILFS}/build/${j}"
			name="${JAILNAME}-job-${j}"
			if [ -f  "${JAILMNT}/${j}.pid" ]; then
				if pgrep -qF "${JAILMNT}/${j}.pid" >/dev/null 2>&1; then
					continue
				fi
				build_stats
				rm -f "${JAILMNT}/${j}.pid"
			fi
			port=$(next_in_queue)
			if [ -z "${port}" ]; then
				# pool empty ?
				[ $(stat -f '%z' ${JAILMNT}/pool) -eq 2 ] && return
				break
			fi
			msg "[${j}] Starting build of ${port}" >&5
			JAILFS=${fs} zset status "starting:${port}"
			activity=1
			zfs rollback -r ${fs}@prepkg
			MASTERMNT=${JAILMNT} JAILNAME="${name}" JAILMNT="${mnt}" JAILFS="${fs}" \
				MY_JOBID="${j}" \
				build_pkg ${port} >/dev/null 2>&1 &
			echo "$!" > ${JAILMNT}/${j}.pid
		done
		# Sleep briefly if still waiting on builds, to save CPU
		[ $activity -eq 0 ] && sleep 0.1
	done
}

# Build ports in parallel
# Returns when all are built.
parallel_build() {
	[ -z "${JAILMNT}" ] && err 2 "Fail: Missing JAILMNT"
	local nbq=$(zget stats_queued)

	# If pool is empty, just return
	test ${nbq} -eq 0 && return 0

	msg "Starting using ${PARALLEL_JOBS} builders"
	JOBS="$(jot -w %02d ${PARALLEL_JOBS})"

	start_builders

	# Duplicate stdout to socket 5 so the child process can send
	# status information back on it since we redirect its
	# stdout to /dev/null
	exec 5<&1

	build_queue

	stop_builders

	# Close the builder socket
	exec 5>&-
}


build_pkg() {
	[ $# -ne 1 ] && eargs port
	local port=$1
	local portdir="/usr/ports/${port}"
	local build_failed=0
	local name cnt
	local failed_status failed_phase

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
		msg "[${MY_JOBID}] Finished build of ${port}: Ignored: ${ignore}" >&5
	else
		zset status "depends:${port}"
		printf "=======================<phase: %-9s>==========================\n" "depends"
		if ! injail make -C ${portdir} pkg-depends fetch-depends extract-depends \
			patch-depends build-depends lib-depends; then
			build_failed=1
			failed_phase="depends"
		else
			echo "==================================================================="
			# Only build if the depends built fine
			injail make -C ${portdir} clean
			if ! build_port ${portdir}; then
				build_failed=1
				failed_status=$(zget status)
				failed_phase=${failed_status%:*}

				if [ "${SAVE_WRKDIR}" -eq 1 ]; then
					# Only save if not in fetch/checksum phase
					if ! [ "${failed_phase}" = "fetch" -o "${failed_phase}" = "checksum" ]; then
						save_wrkdir ${portdir} || :
					fi
				fi
			fi

			injail make -C ${portdir} clean
		fi

		if [ ${build_failed} -eq 0 ]; then
			echo "${port}" >> "${MASTERMNT:-${JAILMNT}}/built"

			msg "[${MY_JOBID}] Finished build of ${port}: Success" >&5
			# Cache information for next run
			pkg_cache_data "${PKGDIR}/All/${PKGNAME}.${PKG_EXT}" ${port} || :
		else
			echo "${port}" >> "${MASTERMNT:-${JAILMNT}}/failed"
			failed_status=$(zget status)
			msg "[${MY_JOBID}] Finished build of ${port}: Failed: ${failed_status%:*}" >&5
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

deps_file() {
	[ $# -ne 1 ] && eargs pkg
	local pkg=$1
	local depfile=$(pkg_cache_dir ${pkg})/deps

	if [ ! -f "${depfile}" ]; then
		if [ "${PKG_EXT}" = "tbz" ]; then
			pkg_info -qr "${pkg}" | awk '{ print $2 }' > "${depfile}"
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
				origin=$(pkg_info -qo "${pkg}")
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
			compiled_options=$(pkg_info -qf "${pkg}" | awk -F: '$1 == "@comment OPTIONS" {print $2}' | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
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
	echo ${POUDRIERE_DATA}/cache/${JAILNAME%-job-*}/${PTNAME}
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
	[ -z "$(ls -A ${cachedir})" ] && return 0
	for pkg in ${cachedir}/*.${PKG_EXT}; do
		pkg_file=${pkg##*/}
		# If this package no longer exists in the PKGDIR, delete the cache.
		if [ ! -e "${PKGDIR}/All/${pkg_file}" ]; then
			clear_pkg_cache ${pkg}
		fi
	done
}

delete_old_pkgs() {
	local o v v2 compiled_options current_options
	[ ! -d ${PKGDIR}/All ] && return 0
	[ -z "$(ls -A ${PKGDIR}/All)" ] && return 0
	for pkg in ${PKGDIR}/All/*.${PKG_EXT}; do
		# Check for non-empty directory with no packages in it
		[ "${pkg}" = "${PKGDIR}/All/*.${PKG_EXT}" ] && break
		if [ "${pkg##*/}" = "repo.txz" ]; then
			msg "Removing invalid pkg repo file: ${pkg}"
			rm -f ${pkg}
			continue
		fi

		mkdir -p $(pkg_cache_dir ${pkg})

		o=$(pkg_get_origin ${pkg})
		v=${pkg##*-}
		v=${v%.*}
		if [ ! -d "${JAILMNT}/usr/ports/${o}" ]; then
			msg "${o} does not exist anymore. Deleting stale ${pkg##*/}"
			delete_pkg ${pkg}
			continue
		fi
		v2=$(cache_get_pkgname ${o})
		v2=${v2##*-}
		if [ "$v" != "$v2" ]; then
			msg "Deleting old version: ${pkg##*/}"
			delete_pkg ${pkg}
			continue
		fi

		# Check if the compiled options match the current options from make.conf and /var/db/options
		if [ -n "${CHECK_CHANGED_OPTIONS}" -a "${CHECK_CHANGED_OPTIONS}" != "no" ]; then
			current_options=$(injail make -C /usr/ports/${o} pretty-print-config | tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
			compiled_options=$(pkg_get_options ${pkg})

			if [ "${compiled_options}" != "${current_options}" ]; then
				msg "Options changed, deleting: ${pkg##*/}"
				if [ "${CHECK_CHANGED_OPTIONS}" = "verbose" ]; then
					msg "Pkg: ${compiled_options}"
					msg "New: ${current_options}"
				fi
				delete_pkg ${pkg}
				continue
			fi
		fi
	done
}

next_in_queue() {
	local p
	[ ! -d ${JAILMNT}/pool ] && err 1 "Build pool is missing"
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
			grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS} | while read port; do
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
	export LOCALBASE=${MYBASE:-/usr/local}
	find ${JAILMNT}/pool -type d -depth 1 | while read p; do
		pn=${p##*/}
		if [ -f "${PKGDIR}/All/${pn}.${PKG_EXT}" ]; then
			rm -rf ${p}
			find ${JAILMNT}/pool -name "${pn}" -type f -delete
		fi
	done

	local nbq=0
	nbq=$(find ${JAILMNT}/pool -type d -depth 1 | wc -l)
	zset stats_queued "${nbq##* }"
	zset stats_built "0"
	zset stats_failed "0"
	zset stats_ignored "0"
	:> ${JAILMNT}/built
	:> ${JAILMNT}/failed
	:> ${JAILMNT}/ignored

	# Minimize PARALLEL_JOBS to queue size
	if [ ${PARALLEL_JOBS} -gt ${nbq} ]; then
		PARALLEL_JOBS=${nbq##* }
	fi
}

prepare_jail() {
	export PACKAGE_BUILDING=yes
	export FORCE_PACKAGE=yes
	export USER=root
	export HOME=/root
	PORTSDIR=`port_get_base ${PTNAME}`/ports
	POUDRIERED=${SCRIPTPREFIX}/../../etc${ZROOTFS}.d
	[ -z "${JAILMNT}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

	msg "Mounting ports filesystems for ${JAILNAME}"
	do_portbuild_mounts 1

	[ ! -d ${DISTFILES_CACHE} ] && err 1 "DISTFILES_CACHE directory	does not exists. (c.f. poudriere.conf)"

	[ -f ${POUDRIERED}/make.conf ] && cat ${POUDRIERED}/make.conf >> ${JAILMNT}/etc/make.conf
	[ -f ${POUDRIERED}/${JAILNAME}-make.conf ] && cat ${POUDRIERED}/${JAILNAME}-make.conf >> ${JAILMNT}/etc/make.conf

	msg "Populating LOCALBASE"
	mkdir -p ${JAILMNT}/${MYBASE:-/usr/local}
	injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${MYBASE:-/usr/local} >/dev/null

	WITH_PKGNG=$(injail make -f /usr/ports/Mk/bsd.port.mk -V WITH_PKGNG)
	if [ -n "${WITH_PKGNG}" ]; then
		export PKGNG=1
		export PKG_EXT="txz"
		export PKG_ADD="${MYBASE:-/usr/local}/sbin/pkg add"
		export PKG_DELETE="${MYBASE:-/usr/local}/sbin/pkg delete -y -f"
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

test -f ${SCRIPTPREFIX}/../../etc${ZROOTFS}.conf || err 1 "Unable to find ${SCRIPTPREFIX}/../../etc${ZROOTFS}.conf"
. ${SCRIPTPREFIX}/../../etc${ZROOTFS}.conf

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
: ${GIT_URL="git://git.freebsd.org/freebsd-ports.git"}
: ${FREEBSD_HOST="ftp://${FTP_HOST:-ftp.FreeBSD.org}"}
: ${ZROOTFS:="/poudriere}

case ${PARALLEL_JOBS} in
''|*[!0-9]*)
	PARALLEL_JOBS=$(sysctl -n hw.ncpu)
	;;
*) ;;
esac

case ${ZROOTFS} in
	/*)
		;;
	*)
		err 1 "ZROOTFS shoud start with a /"
		;;
esac
