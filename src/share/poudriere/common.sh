#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2010-2011 Julien Laffaye <jlaffaye@FreeBSD.org>
# Copyright (c) 2012-2013 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

BSDPLATFORM=`uname -s | tr '[:upper:]' '[:lower:]'`
. $(dirname ${0})/common.sh.${BSDPLATFORM}
BLACKLIST=""

# Return true if ran from bulk/testport, ie not daemon/status/jail
was_a_bulk_run() {
	[ "${0##*/}" = "bulk.sh" -o "${0##*/}" = "testport.sh" ]
}
# Return true if in a bulk or other jail run that needs to shutdown the jail
was_a_jail_run() {
	was_a_bulk_run ||  [ "${0##*/}" = "pkgclean.sh" ]
}

_wait() {
	# Workaround 'wait' builtin possibly returning early due to signals
	# by using 'pwait' to wait(2) and then 'wait' to collect return code
	local ret=0 pid

	pwait "$@" 2>/dev/null || :
	for pid in "$@"; do
		wait ${pid} || ret=$?
	done

	return ${ret}
}

kill_and_wait() {
	[ $# -eq 2 ] || eargs time pids
	local time="$1"
	local pids="$2"
	local ret=0
	local pid
	local found_pid
	local retry

	[ -z "${pids}" ] && return 0

	# Give children $time seconds to exit and then force kill
	retry=${time}
	kill ${pids} 2>/dev/null || :

	while [ ${retry} -gt 0 ]; do
		found_pid=0
		for pid in ${pids}; do
			if ! kill -0 ${pid} 2>/dev/null; then
				sleep 1
				found_pid=1
				break
			fi
		done
		retry=$((retry - 1))
		[ ${found_pid} -eq 0 ] && retry=0
	done

	# Kill all children instead of waiting on them
	[ ${found_pid} -eq 1 ] && kill -9 ${pids} 2>/dev/null || :

	_wait ${pids} || ret=$?

	return ${ret}
}

# Based on Shell Scripting Recipes - Chris F.A. Johnson (c) 2005
# Replace a pattern without needing a subshell/exec
_gsub() {
	[ $# -ne 3 ] && eargs string pattern replacement
	local string="$1"
	local pattern="$2"
	local replacement="$3"
	local result_l= result_r="${string}"

	while :; do
		case ${result_r} in
			*${pattern}*)
				result_l=${result_l}${result_r%%${pattern}*}${replacement}
				result_r=${result_r#*${pattern}}
				;;
			*)
				break
				;;
		esac
	done

	_gsub="${result_l}${result_r}"
}


gsub() {
	_gsub "$@"
	echo "${_gsub}"
}

not_for_os() {
	local os=$1
	shift
	[ "${os}" = "${BSDPLATFORM}" ] && err 1 "This is not supported on ${BSDPLATFORM}: $@"
}

err() {
	export CRASHED=1
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	# Try to set status so other processes know this crashed
	# Don't set it from children failures though, only master
	[ -z "${PARALLEL_CHILD}" ] && was_a_bulk_run &&
		bset status "${EXIT_STATUS:-crashed:}" 2>/dev/null || :
	local err_msg="Error: $2"
	msg "${err_msg}" >&2
	[ -n "${MY_JOBID}" ] && job_msg "${err_msg}"
	exit $1
}

msg_n() { echo -n "${DRY_MODE}====>> $1"; }
msg() { msg_n "$@"; echo; }
msg_verbose() {
	[ ${VERBOSE} -gt 0 ] || return 0
	msg "$1"
}

msg_debug() {
	[ ${VERBOSE} -gt 1 ] || return 0
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

my_path() {
	echo ${MASTERMNT}${MY_JOBID+/../${MY_JOBID}}
}

my_name() {
	echo ${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}}
}

log_path() {
	echo "${POUDRIERE_DATA}/logs/${POUDRIERE_BUILD_TYPE}/${MASTERNAME}/${BUILDNAME}"
}

injail() {
	jexec -U ${JUSER:-root} ${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}} "$@"
}

jstart() {
	local enable_networking="$1"
	local network="${localipargs}"

	[ "${RESTRICT_NETWORKING}" = "yes" ] || enable_networking=1
	[ ${enable_networking} -eq 1 ] && network="${ipargs}"

	jail -c persist name=${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}} \
		path=${MASTERMNT}${MY_JOBID+/../${MY_JOBID}} \
		host.hostname=${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}} \
		${network} \
		allow.socket_af allow.raw_sockets allow.chflags allow.sysvipc
	if ! injail id ${PORTBUILD_USER} >/dev/null 2>&1 ; then
		msg_n "Creating user/group ${PORTBUILD_USER}"
		injail pw groupadd ${PORTBUILD_USER} -g 65532 || \
		err 1 "Unable to create group ${PORTBUILD_USER}"
		injail pw useradd ${PORTBUILD_USER} -u 65532 -d /nonexistent -c "Package builder" || \
		err 1 "Unable to create user ${PORTBUILD_USER}"
		echo " done"
	fi
}

jstop() {
	# SIGKILL everything as jail -r does not seem to wait
	# for processes to actually exit. So there is a race condition
	# on umount after this where files may still be opened.
	injail kill -9 -1 2>/dev/null || :
	jail -r ${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}} 2>/dev/null || :
}

eargs() {
	case $# in
	0) err 1 "No arguments expected" ;;
	1) err 1 "1 argument expected: $1" ;;
	*) err 1 "$# arguments expected: $*" ;;
	esac
}

run_hook() {
	local hookfile=${HOOKDIR}/${1}.sh
	shift

	[ -f ${hookfile} ] &&
		URL_BASE="${URL_BASE}" \
		POUDRIERE_BUILD_TYPE=${POUDRIERE_BUILD_TYPE} \
		POUDRIERED="${POUDRIERED}" \
		POUDRIERE_DATA="${POUDRIERE_DATA}" \
		MASTERNAME="${MASTERNAME}" \
		BUILDNAME="${BUILDNAME}" \
		JAILNAME="${JAILNAME}" \
		PTNAME="${PTNAME}" \
		SETNAME="${SETNAME}" \
		PACKAGES="${PACKAGES}" \
		PACKAGES_ROOT="${PACKAGES_ROOT}" \
		/bin/sh ${hookfile} "$@"
	return 0
}

log_start() {
	local log=$(log_path)
	local latest_log

	logfile="${log}/logs/${PKGNAME}.log"
	latest_log=${POUDRIERE_DATA}/logs/${POUDRIERE_BUILD_TYPE}/latest-per-pkg/${PKGNAME%-*}/${PKGNAME##*-}

	# Make sure directory exists
	mkdir -p ${log}/logs ${latest_log}

	:> ${logfile}

	# Link to BUILD_TYPE/latest-per-pkg/PORTNAME/PKGVERSION/MASTERNAME.log
	ln -f ${logfile} ${latest_log}/${MASTERNAME}.log

	# Link to JAIL/latest-per-pkg/PKGNAME.log
	ln -f ${logfile} ${log}/../latest-per-pkg/${PKGNAME}.log

	# Tee all of the output to the logfile through a pipe
	exec 3>&1 4>&2
	[ ! -e ${logfile}.pipe ] && mkfifo ${logfile}.pipe
	{
		if [ "${TIMESTAMP_LOGS}" = "yes" ]; then
			tee ${logfile} | while read line; do
				echo "$(date "+%Y%m%d%H%M.%S") ${line}";
			done
		else
			tee ${logfile}
		fi
	} < ${logfile}.pipe >&3 &
	export tpid=$!
	exec > ${logfile}.pipe 2>&1

	# Remove fifo pipe file right away to avoid orphaning it.
	# The pipe will continue to work as long as we keep
	# the FD open to it.
	rm -f ${logfile}.pipe
}

buildlog_start() {
	local portdir=$1
	local mnt=$(my_path)
	local var

	echo "build started at $(date)"
	echo "port directory: ${portdir}"
	echo "building for: $(injail uname -a)"
	echo "maintained by: $(injail make -C ${portdir} maintainer)"
	echo "Makefile ident: $(ident ${mnt}/${portdir}/Makefile|sed -n '2,2p')"
	echo "Poudriere version: ${POUDRIERE_VERSION}"
	echo ""
	echo "---Begin Environment---"
	injail env ${PKGENV} ${PORT_FLAGS}
	echo "---End Environment---"
	echo ""
	echo "---Begin OPTIONS List---"
	injail make -C ${portdir} showconfig
	echo "---End OPTIONS List---"
	echo ""
	for var in CONFIGURE_ARGS CONFIGURE_ENV MAKE_ENV; do
		echo "--${var}--"
		echo "$(injail env ${PORT_FLAGS} make -C ${portdir} -V ${var})"
		echo "--End ${var}--"
		echo ""
	done
	echo "--SUB_LIST--"
	echo "$(injail env ${PORT_FLAGS} make -C ${portdir} -V SUB_LIST | tr ' ' '\n' | grep -v '^$')"
	echo "--End SUB_LIST--"
	echo ""
	echo "---Begin make.conf---"
	cat ${mnt}/etc/make.conf
	echo "---End make.conf---"
}

buildlog_stop() {
	local portdir=$1
	local log=$(log_path)
	local buildtime

	buildtime=$( \
		stat -f '%N %B' ${log}/logs/${PKGNAME}.log  | awk -v now=$(date +%s) \
		-f ${AWKPREFIX}/siginfo_buildtime.awk |
		awk -F'!' '{print $2}' \
	)

	echo "build of ${portdir} ended at $(date)"
	echo "build time: ${buildtime}"
}

log_stop() {
	if [ -n "${tpid}" ]; then
		exec 1>&3 3>&- 2>&4 4>&-
		kill $tpid
		_wait $tpid 2>/dev/null || :
		unset tpid
	fi
}

attr_set() {
	local type=$1
	local name=$2
	local property=$3
	shift 3
	mkdir -p ${POUDRIERED}/${type}/${name}
	echo "$@" > ${POUDRIERED}/${type}/${name}/${property} || :
}

jset() { attr_set jails "$@" ; }
pset() { attr_set ports "$@" ; }

attr_get() {
	local type=$1
	local name=$2
	local property=$3
	cat ${POUDRIERED}/${type}/${name}/${property} || :
}

jget() { attr_get jails "$@" ; }
pget() { attr_get ports "$@" ; }

#build getter/setter
bget() {
	local id property mnt
	local log=$(log_path)
	if [ $# -eq 2 ]; then
		id=$1
		shift
	fi
	file=.poudriere.${1}${id:+.${id}}

	cat ${log}/${file} || :
}

bset() {
	was_a_bulk_run || return 0
	local id property mnt
	local log=$(log_path)
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	file=.poudriere.${1}${id:+.${id}}
	shift
	echo "$@" > ${log}/${file} || :
}

badd() {
	local id property mnt
	local log=$(log_path)
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	file=.poudriere.${1}${id:+.${id}}
	shift
	echo "$@" >> ${log}/${file} || :
}

update_stats() {
	local type
	for type in built failed ignored; do
		bset stats_${type} $(bget ports.${type} | wc -l)
	done
	# Skipped may have duplicates in it
	bset stats_skipped $(bget ports.skipped | awk '{print $1}' | \
		sort -u | wc -l)
}

sigint_handler() {
	EXIT_STATUS="sigint:"
	sig_handler
}

sigterm_handler() {
	EXIT_STATUS="sigterm:"
	sig_handler
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

	if was_a_bulk_run; then
		log_stop
		stop_html_json
	fi

	parallel_shutdown

	[ ${STATUS} -eq 1 ] && cleanup

	[ -n ${CLEANUP_HOOK} ] && ${CLEANUP_HOOK}
}

show_log_info() {
	local log=$(log_path)
	msg "Logs: ${log}"
	[ -z "${URL_BASE}" ] ||
		msg "WWW: ${URL_BASE}/${POUDRIERE_BUILD_TYPE}/${MASTERNAME}/${BUILDNAME}"
}

siginfo_handler() {
	[ "${POUDRIERE_BUILD_TYPE}" != "bulk" ] && return 0

	trappedinfo=1
	local status=$(bget status 2> /dev/null || echo unknown)
	local nbb=$(bget stats_built 2>/dev/null || echo 0)
	local nbf=$(bget stats_failed 2>/dev/null || echo 0)
	local nbi=$(bget stats_ignored 2>/dev/null || echo 0)
	local nbs=$(bget stats_skipped 2>/dev/null || echo 0)
	local nbq=$(bget stats_queued 2>/dev/null || echo 0)
	local ndone=$((nbb + nbf + nbi + nbs))
	local queue_width=2
	local now
	local j
	local pkgname origin phase buildtime
	local format_origin_phase format_phase

	[ -n "${nbq}" ] || return 0
	[ "${status}" = "index:" -o "${status}" = "crashed:" ] && return 0

	if [ ${nbq} -gt 9999 ]; then
		queue_width=5
	elif [ ${nbq} -gt 999 ]; then
		queue_width=4
	elif [ ${nbq} -gt 99 ]; then
		queue_width=3
	fi

	printf "[${MASTERNAME}] [${status}] [%0${queue_width}d/%0${queue_width}d] Built: %-${queue_width}d Failed: %-${queue_width}d  Ignored: %-${queue_width}d  Skipped: %-${queue_width}d  \n" \
	  ${ndone} ${nbq} ${nbb} ${nbf} ${nbi} ${nbs}

	# Skip if stopping or starting jobs
	if [ -n "${JOBS}" -a "${status#starting_jobs:}" = "${status}" -a "${status}" != "stopping_jobs:" ]; then
		now=$(date +%s)
		format_origin_phase="\t[%s]: %-32s %-15s (%s)\n"
		format_phase="\t[%s]: %15s\n"

		# Collect build stats into a string with minimal execs
		pkgname_buildtimes=$(find ${MASTERMNT}/poudriere/building -depth 1 \
			-exec stat -f "%N %m" {} + 2>/dev/null | \
			awk -v now=${now} -f ${AWKPREFIX}/siginfo_buildtime.awk)

		for j in ${JOBS}; do
			# Ignore error here as the zfs dataset may not be cloned yet.
			status=$(bget ${j} status 2>/dev/null || :)
			# Skip builders not started yet
			[ -z "${status}" ] && continue
			# Hide idle workers
			[ "${status}" = "idle:" ] && continue
			origin=${status#*:}
			phase="${status%:*}"
			if [ -n "${origin}" -a "${origin}" != "${status}" ]; then
				cache_get_pkgname pkgname "${origin}"
				# Find the buildtime for this pkgname
				for pkgname_buildtime in $pkgname_buildtimes; do
					[ "${pkgname_buildtime%!*}" = "${pkgname}" ] || continue
					buildtime="${pkgname_buildtime#*!}"
					break
				done
				printf "${format_origin_phase}" ${j} ${origin} ${phase} \
					${buildtime}
			else
				printf "${format_phase}" ${j} ${phase}
			fi
		done
	fi

	show_log_info
}

jail_exists() {
	[ $# -ne 1 ] && eargs jailname
	local jname=$1
	[ -d ${POUDRIERED}/jails/${jname} ] && return 0
	return 1
}

jail_runs() {
	[ $# -ne 1 ] && eargs jname
	local jname=$1
	jls -j $jname >/dev/null 2>&1 && return 0
	return 1
}

porttree_list() {
	local name method mntpoint
	[ -d ${POUDRIERED}/ports ] || return 0
	for p in $(find ${POUDRIERED}/ports -type d -maxdepth 1 -mindepth 1 -print); do
		name=${p##*/}
		mnt=$(pget ${name} mnt)
		method=$(pget ${name} method)
		echo "${name} ${method:--} ${mnt}"
	done
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

get_data_dir() {
	local data
	if [ -n "${POUDRIERE_DATA}" ]; then
		echo ${POUDRIERE_DATA}
		return
	fi

	if [ -z "${NO_ZFS}" ]; then
		data=$(zfs list -rt filesystem -H -o ${NS}:type,mountpoint ${ZPOOL}${ZROOTFS} 2>/dev/null |
		    awk '$1 == "data" { print $2 }' | head -n 1)
		if [ -n "${data}" ]; then
			echo $data
			return
		fi
		zfs create -p -o ${NS}:type=data \
			-o mountpoint=${BASEFS}/data \
			${ZPOOL}${ZROOTFS}/data
	else
		mkdir -p "${BASEFS}/data"
	fi
	echo "${BASEFS}/data"
}

fetch_file() {
	[ $# -ne 2 ] && eargs destination source
	fetch -p -o $1 $2 || fetch -p -o $1 $2 || err 1 "Failed to fetch from $2"
}

createfs() {
	[ $# -ne 3 ] && eargs name mnt fs
	local name mnt fs
	name=$1
	mnt=$(echo $2 | sed -e "s,//,/,g")
	fs=$3

	[ -z "${NO_ZFS}" ] || fs=none

	if [ -n "${fs}" -a "${fs}" != "none" ]; then
		msg_n "Creating ${name} fs..."
		zfs create -p \
			-o mountpoint=${mnt} ${fs} || err 1 " fail"
		echo " done"
	else
		mkdir -p ${mnt}
	fi
}

rollbackfs() {
	[ $# -ne 2 ] && eargs name mnt
	local name=$1
	local mnt=$2
	local fs=$(zfs_getfs ${mnt})
	local mtree_mnt

	if [ -n "${fs}" ]; then
		zfs rollback -r ${fs}@${name}  || err 1 "Unable to rollback ${fs}"
		return
	fi

	if [ "${name}" = "prepkg" ]; then
		mtree_mnt="${MASTERMNT}"
	else
		mtree_mnt="${mnt}"
	fi

	cpdup -i0 -x ${MASTERMNT} ${mnt}
}

umountfs() {
	[ $# -lt 1 ] && eargs mnt childonly
	local mnt=$1
	local childonly=$2
	local pattern

	[ -n "${childonly}" ] && pattern="/"

	[ -d "${mnt}" ] || return 0
	mnt=$(realpath ${mnt})
	mount | sort -r -k 2 | while read dev on pt opts; do
		case ${pt} in
		${mnt}${pattern}*)
			umount -f ${pt} || :
			[ "${dev#/dev/md*}" != "${dev}" ] && mdconfig -d -u ${dev#/dev/md*}
		;;
		esac
	done

	return 0
}

zfs_getfs() {
	[ $# -ne 1 ] && eargs mnt
	local mnt=$(realpath $1)
	mount -t zfs | awk -v n="${mnt}" ' $3 == n { print $1 }'
}

unmarkfs() {
	[ $# -ne 2 ] && eargs name mnt
	local name=$1
	local mnt=$(realpath $2)

	if [ -n "$(zfs_getfs ${mnt})" ]; then
		zfs destroy -f ${fs}@${name} 2>/dev/null || :
	else
		rm -f ${mnt}/poudriere/mtree.${name} 2>/dev/null || :
	fi
}

markfs() {
	[ $# -lt 2 ] && eargs name mnt path
	local name=$1
	local mnt=$(realpath $2)
	local path="$3"
	local fs="$(zfs_getfs ${mnt})"
	local dozfs=0
	local domtree=0

	msg_n "Recording filesystem state for ${name}..."

	case "${name}" in
	clean) [ -n "${fs}" ] && dozfs=1 ;;
	prepkg)
		[ -n "${fs}" ] && dozfs=1
		# Only create prepkg mtree in ref
		# Everything else may need to snapshot
		if [ "${mnt##*/}" = "ref" ]; then
			domtree=1
		else
			domtree=0
		fi
		;;
	prebuild|prestage) domtree=1 ;;
	preinst) domtree=1 ;;
	poststage) domtree=1 ;;
	esac

	if [ $dozfs -eq 1 ]; then
		# remove old snapshot if exists
		zfs destroy -r ${fs}@${name} 2>/dev/null || :
		#create new snapshot
		zfs snapshot ${fs}@${name}
	fi

	if [ $domtree -eq 0 ]; then
		echo " done"
		return 0
	fi
	mkdir -p ${mnt}/poudriere/

	case "${name}" in
		prepkg|poststage)
			cat > ${mnt}/poudriere/mtree.${name}exclude << EOF
.${HOME}/.ccache/*
./compat/linux/proc
./dev/*
./distfiles/*
./new_packages/*
./packages/*
./portdistfiles/*
./poudriere/*
./proc
./usr/ports/*
./usr/src
./var/db/ports/*
./wrkdirs/*
EOF
			;;
		prebuild|prestage)
			cat > ${mnt}/poudriere/mtree.${name}exclude << EOF
.${HOME}/.ccache/*
./compat/linux/proc
./dev/*
./distfiles/*
./new_packages/*
./packages/*
./portdistfiles/*
./poudriere/*
./proc
./tmp/*
./usr/ports/*
./usr/src
./var/db/ports/*
./wrkdirs/*
EOF
			;;
		preinst)
			cat >  ${mnt}/poudriere/mtree.${name}exclude << EOF
.${HOME}/*
.${HOME}/.ccache/*
./compat/linux/proc
./dev/*
./distfiles/*
./etc/group
./etc/make.conf
./etc/make.conf.bak
./etc/master.passwd
./etc/passwd
./etc/pwd.db
./etc/shells
./etc/spwd.db
./new_packages/*
./packages/*
./portdistfiles/*
./poudriere/*
./proc
./tmp/*
./usr/ports/*
./usr/src
./var/db/pkg/*
./var/db/ports/*
./var/log/*
./var/mail/*
./var/run/*
./wrkdirs/*
EOF
		;;
	esac
	mtree -X ${mnt}/poudriere/mtree.${name}exclude \
		-cn -k uid,gid,mode,size \
		-p ${mnt}${path} > ${mnt}/poudriere/mtree.${name}
	echo " done"
}

mnt_tmpfs() {
	[ $# -lt 2 ] && eargs type dst
	local type="$1"
	local dst="$2"
	local limit size

	case ${type} in
		data)
			# Limit data to 1GiB
			limit=1
			;;

		*)
			limit=${TMPFS_LIMIT}
			;;
	esac

	[ -n "${limit}" ] && size="-o size=${limit}G"

	mount -t tmpfs ${size} tmpfs "${dst}"
}

clonefs() {
	[ $# -lt 2 ] && eargs from to snap
	local from=$1
	local to=$2
	local snap=$3
	local name zfs_to
	local fs=$(zfs_getfs ${from})

	destroyfs ${to} jail
	mkdir -p ${to}
	to=$(realpath ${to})
	[ ${TMPFS_ALL} -eq 1 ] && unset fs
	if [ -n "${fs}" ]; then
		name=${to##*/}

		if [ "${name}" = "ref" ]; then
			zfs_to=${fs%/*}/${MASTERNAME}-${name}
		else
			zfs_to=${fs}/${name}
		fi

		zfs clone -o mountpoint=${to} \
			-o sync=disabled \
			-o atime=off \
			-o compression=off \
			${fs}@${snap} \
			${zfs_to}
	else
		[ ${TMPFS_ALL} -eq 1 ] && mnt_tmpfs all ${to}
		# Mount /usr/src into target, no need for anything to write to it
		mkdir -p ${to}/usr/src
		${NULLMOUNT} -o ro ${from}/usr/src ${to}/usr/src
		cpdup -x ${from} ${to}
	fi
}

rm() {
	local arg

	for arg in "$@"; do
		[ "${arg}" = "/" ] && err 1 "Tried to rm /"
		[ "${arg%/}" = "/bin" ] && err 1 "Tried to rm /*"
	done

	/bin/rm "$@"
}

destroyfs() {
	[ $# -ne 2 ] && eargs name type
	local mnt fs type
	mnt=$1
	type=$2
	[ -d ${mnt} ] || return 0
	mnt=$(realpath ${mnt})
	fs=$(zfs_getfs ${mnt})
	umountfs ${mnt} 1
	if [ ${TMPFS_ALL} -eq 1 ]; then
		umount -f ${mnt} 2>/dev/null || :
	elif [ -n "${fs}" -a "${fs}" != "none" ]; then
		zfs destroy -rf ${fs}
		rmdir ${mnt}
	else
		chflags -R noschg ${mnt}
		rm -rf ${mnt}
	fi
}

do_jail_mounts() {
	[ $# -ne 2 ] && eargs mnt arch
	local mnt=$1
	local arch=$2
	local devfspath="null zero random urandom stdin stdout stderr fd fd/* bpf* pts pts/*"

	# clone will inherit from the ref jail
	if [ ${mnt##*/} = "ref" ]; then
		mkdir -p ${mnt}/proc
		mkdir -p ${mnt}/dev
		mkdir -p ${mnt}/compat/linux/proc
		mkdir -p ${mnt}/usr/ports
		mkdir -p ${mnt}/wrkdirs
		mkdir -p ${mnt}/${LOCALBASE:-/usr/local}
		mkdir -p ${mnt}/distfiles
		mkdir -p ${mnt}/packages
		mkdir -p ${mnt}/new_packages
		mkdir -p ${mnt}${HOME}/.ccache
		mkdir -p ${mnt}/var/db/ports
	fi

	# ref jail only needs devfs
	mount -t devfs devfs ${mnt}/dev
	if [ ${JAILED} -eq 0 ]; then
		devfs -m ${mnt}/dev rule apply hide
		for p in ${devfspath} ; do
			devfs -m ${mnt}/dev/ rule apply path "${p}" unhide
		done
	fi
	if [ "${mnt##*/}" != "ref" ]; then
		[ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ] && mount -t fdescfs fdesc ${mnt}/dev/fd
		mount -t procfs proc ${mnt}/proc
		if [ -z "${NOLINUX}" ]; then
			[ "${arch}" = "i386" -o "${arch}" = "amd64" ] &&
				mount -t linprocfs linprocfs ${mnt}/compat/linux/proc
		fi
	fi

	return 0
}

use_options() {
	[ $# -ne 2 ] && eargs mnt optionsdir
	local mnt=$1
	local optionsdir=$2

	if [ "${optionsdir}" = "-" ]; then
		optionsdir="${POUDRIERED}/options"
	else
		optionsdir="${POUDRIERED}/${optionsdir}-options"
	fi
	[ -d "${optionsdir}" ] || return 1
	optionsdir=$(realpath ${optionsdir} 2>/dev/null)
	[ "${mnt##*/}" = "ref" ] &&
		msg "Mounting /var/db/ports from: ${optionsdir}"
	${NULLMOUNT} -o ro ${optionsdir} ${mnt}/var/db/ports ||
		err 1 "Failed to mount OPTIONS directory"

	return 0
}

mount_packages() {
	local mnt=$(my_path)
	${NULLMOUNT} "$@" ${PACKAGES} \
		${mnt}/packages ||
		err 1 "Failed to mount the packages directory "
}

do_portbuild_mounts() {
	[ $# -lt 3 ] && eargs mnt jname ptname setname
	local mnt=$1
	local jname=$2
	local ptname=$3
	local setname=$4
	local portsdir=$(pget ${ptname} mnt)
	local optionsdir

	[ -d ${portsdir}/ports ] && portsdir=${portsdir}/ports

	[ -d "${CCACHE_DIR:-/nonexistent}" ] &&
		${NULLMOUNT} ${CCACHE_DIR} ${mnt}${HOME}/.ccache
	[ -n "${MFSSIZE}" ] && mdmfs -t -S -o async -s ${MFSSIZE} md ${mnt}/wrkdirs
	[ ${TMPFS_WRKDIR} -eq 1 ] && mnt_tmpfs wrkdir ${mnt}/wrkdirs
	# Only show mounting messages once, not for every builder
	if [ ${mnt##*/} = "ref" ]; then
		[ -d "${CCACHE_DIR}" ] &&
			msg "Mounting ccache from: ${CCACHE_DIR}"
		msg "Mounting packages from: ${PACKAGES_ROOT}"
	fi

	${NULLMOUNT} -o ro ${portsdir} ${mnt}/usr/ports ||
		err 1 "Failed to mount the ports directory "
	mount_packages -o ro
	${NULLMOUNT} ${DISTFILES_CACHE} ${mnt}/distfiles ||
		err 1 "Failed to mount the distfiles cache directory"

	optionsdir="${MASTERNAME}"
	[ -n "${setname}" ] && optionsdir="${optionsdir} ${jname}-${setname}"
	optionsdir="${optionsdir} ${jname}-${ptname} ${setname} ${ptname} ${jname} -"

	for opt in ${optionsdir}; do
		use_options ${mnt} ${opt} && break || continue
	done

	return 0
}

# Convert the repository to the new format of links
# so that an atomic update can be done at the end
# of the build.
# This is done at the package repo level instead of the parent
# dir in DATA/packages because someone may have created a separate
# ZFS dataset / NFS mount for each dataset. Avoid cross-device linking.
convert_repository() {
	local pkgdir

	msg "Converting package repository to new format"

	pkgdir=.real_$(date +%s)
	mkdir ${PACKAGES}/${pkgdir}

	# Move all top-level dirs into .real
	find ${PACKAGES}/ -mindepth 1 -maxdepth 1 -type d ! -name ${pkgdir} |
	    xargs -J % mv % ${PACKAGES}/${pkgdir}
	# Symlink them over through .latest
	find ${PACKAGES}/${pkgdir} -mindepth 1 -maxdepth 1 -type d \
	    ! -name ${pkgdir} | while read directory; do
		dirname=${directory##*/}
		ln -s .latest/${dirname} ${PACKAGES}/${dirname}
	done

	# Now move+symlink any files in the top-level
	find ${PACKAGES}/ -mindepth 1 -maxdepth 1 -type f |
	    xargs -J % mv % ${PACKAGES}/${pkgdir}
	find ${PACKAGES}/${pkgdir} -mindepth 1 -maxdepth 1 -type f |
	    while read file; do
		fname=${file##*/}
		ln -s .latest/${fname} ${PACKAGES}/${fname}
	done

	# Setup current symlink which is how the build will atomically finish
	ln -s ${pkgdir} ${PACKAGES}/.latest
}

stash_packages() {

	PACKAGES_ROOT=${PACKAGES}

	[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] && return 0

	[ -L ${PACKAGES}/.latest ] || convert_repository

	if [ -d ${PACKAGES}/.building ]; then
		# If the .building directory is still around, use it. The
		# previous build may have failed, but all of the successful
		# packages are still worth keeping for this build.
		msg "Using packages from previously failed build"
	else
		msg "Stashing existing package repository"

		# Use a linked shadow directory in the package root, not
		# in the parent directory as the user may have created
		# a separate ZFS dataset or NFS mount for each package
		# set; Must stay on the same device for linking.

		mkdir -p ${PACKAGES}/.building
		# hardlink copy all top-level directories
		find ${PACKAGES}/.latest/ -mindepth 1 -maxdepth 1 -type d \
		    ! -name .building | xargs -J % cp -al % ${PACKAGES}/.building

		# Copy all top-level files to avoid appending
		# to real copy in pkg-repo, etc.
		find ${PACKAGES}/.latest/ -mindepth 1 -maxdepth 1 -type f |
		    xargs -J % cp -a % ${PACKAGES}/.building
	fi

	# From this point forward, only work in the shadow
	# package dir
	PACKAGES=${PACKAGES}/.building
}

commit_packages() {
	local pkgdir_old pkgdir_new

	[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] || return 0
	if [ "${COMMIT_PACKAGES_ON_FAILURE}" = "no" ] &&
	    [ $(bget stats_failed) -gt 0 ]; then
		msg "Not committing packages to repository as failures were encountered"
		return 0
	fi

	msg "Committing packages to repository"

	# Find any new top-level files not symlinked yet. This is
	# mostly incase pkg adds a new top-level repo or the ports framework
	# starts creating a new directory
	find ${PACKAGES}/ -mindepth 1 -maxdepth 1 ! -name '.*' |
	    while read path; do
		name=${path##*/}
		[ ! -L "${PACKAGES_ROOT}/${name}" ] || continue
		ln -s .latest/${name} ${PACKAGES_ROOT}/${name}
	done

	pkgdir_old=$(realpath ${PACKAGES_ROOT}/.latest)

	# Rename shadow dir to a production name
	pkgdir_new=.real_$(date +%s)
	mv ${PACKAGES_ROOT}/.building ${PACKAGES_ROOT}/${pkgdir_new}

	# XXX: Copy in packages that failed to build

	# Switch latest symlink to new build
	PACKAGES=${PACKAGES_ROOT}/.latest
	ln -s ${pkgdir_new} ${PACKAGES_ROOT}/.latest_new
	mv -fh ${PACKAGES_ROOT}/.latest_new ${PACKAGES}

	# Look for broken top-level links and remove them, if they reference
	# the old directory
	find -L ${PACKAGES_ROOT}/ -mindepth 1 -maxdepth 1 ! -name '.*' -type l |
	    while read path; do
		link=$(readlink ${path})
		# Skip if link does not reference inside latest
		[ "${link##.latest}" != "${link}" ] || continue
		rm -f ${path}
	done


	msg "Removing old packages"

	if [ "${KEEP_OLD_PACKAGES}" = "yes" ]; then
		keep_cnt=$((${KEEP_OLD_PACKAGES_COUNT} + 1))
		find ${PACKAGES_ROOT}/ -type d -mindepth 1 -maxdepth 1 \
		    -name '.real_*' | sort -Vr |
		    sed -n "${keep_cnt},\$p" |
		    xargs rm -rf 2>/dev/null || :
	else
		# Remove old and shadow dir
		rm -rf ${pkgdir_old} 2>/dev/null || :
	fi
}

jail_start() {
	[ $# -lt 2 ] && eargs name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local portsdir=$(pget ${ptname} mnt)
	local arch=$(jget ${name} arch)
	local mnt=$(jget ${name} mnt)
	local needfs="${NULLFSREF} procfs"

	local tomnt=${POUDRIERE_DATA}/build/${MASTERNAME}/ref

	[ -d ${DISTFILES_CACHE:-/nonexistent} ] || err 1 "DISTFILES_CACHE directory does not exist. (c.f. poudriere.conf)"

	if [ -z "${NOLINUX}" ]; then
		if [ "${arch}" = "i386" -o "${arch}" = "amd64" ]; then
			needfs="${needfs} linprocfs linsysfs"
			sysctl -n compat.linux.osrelease >/dev/null 2>&1 || kldload linux
		fi
	fi
	[ -n "${USE_TMPFS}" ] && needfs="${needfs} tmpfs"
	[ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ] && needfs="${needfs} fdescfs"
	for fs in ${needfs}; do
		if ! lsvfs $fs >/dev/null 2>&1; then
			if [ $JAILED -eq 0 ]; then
				kldload $fs || err 1 "Required kernel module '${fs}' not found"
			else
				err 1 "please load the $fs module on host using \"kldload $fs\""
			fi
		fi
	done
	jail_exists ${name} || err 1 "No such jail: ${name}"
	jail_runs ${MASTERNAME} && err 1 "jail already running: ${MASTERNAME}"

	# Block the build dir from being traversed by non-root to avoid
	# system blowup due to all of the extra mounts
	mkdir -p ${MASTERMNT%/ref}
	chmod 0755 ${POUDRIERE_DATA}/build
	chmod 0711 ${MASTERMNT%/ref}

	export HOME=/root
	export USER=root
	[ -z "${NO_FORCE_PACKAGE}" ] && export FORCE_PACKAGE=yes
	[ -z "${NO_PACKAGE_BUILDING}" ] && export PACKAGE_BUILDING=yes

	[ ${SET_STATUS_ON_START-1} -eq 1 ] && export STATUS=1
	msg_n "Creating the reference jail..."
	clonefs ${mnt} ${tomnt} clean
	echo "src" >> ${tomnt}/usr/.cpignore
	echo "poudriere" >> ${tomnt}/.cpignore
	echo " done"

	msg "Mounting system devices for ${MASTERNAME}"
	do_jail_mounts ${tomnt} ${arch}

	PACKAGES=${POUDRIERE_DATA}/packages/${MASTERNAME}

	[ -d "${portsdir}/ports" ] && portsdir="${portsdir}/ports"
	msg "Mounting ports/packages/distfiles"

	mkdir -p ${PACKAGES}/All ${PACKAGES}/Latest
	was_a_bulk_run && stash_packages

	do_portbuild_mounts ${tomnt} ${name} ${ptname} ${setname}

	was_a_bulk_run && show_log_info

	if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
		echo "WITH_CCACHE_BUILD=yes" >> ${tomnt}/etc/make.conf
		echo "CCACHE_DIR=${HOME}/.ccache" >> ${tomnt}/etc/make.conf
	fi
	echo "PORTSDIR=/usr/ports" >> ${tomnt}/etc/make.conf
	echo "PACKAGES=/packages" >> ${tomnt}/etc/make.conf
	echo "DISTDIR=/distfiles" >> ${tomnt}/etc/make.conf

	setup_makeconf ${tomnt}/etc/make.conf ${name} ${ptname} ${setname}
	load_blacklist ${name} ${ptname} ${setname}

	test -n "${RESOLV_CONF}" && cp -v "${RESOLV_CONF}" "${tomnt}/etc/"
	msg "Starting jail ${MASTERNAME}"
	jstart 0
	# Only set STATUS=1 if not turned off
	# jail -s should not do this or jail will stop on EXIT
	WITH_PKGNG=$(injail make -f /usr/ports/Mk/bsd.port.mk -V WITH_PKGNG)
	if [ -n "${WITH_PKGNG}" ]; then
		export PKGNG=1
		export PKG_EXT="txz"
		export PKG_BIN="${LOCALBASE:-/usr/local}/sbin/pkg-static"
		export PKG_ADD="${PKG_BIN} add"
		export PKG_DELETE="${PKG_BIN} delete -y -f"
		export PKG_VERSION="/poudriere/pkg-static version"
	else
		export PKGNG=0
		export PKG_ADD=pkg_add
		export PKG_DELETE=pkg_delete
		export PKG_VERSION=pkg_version
		export PKG_EXT="tbz"
	fi

	# 8.3 did not have distrib-dirs ran on it, so various
	# /usr and /var dirs are missing. Namely /var/games
	if [ "$(injail uname -r | cut -d - -f 1 )" = "8.3" ]; then
		injail mtree -eu -f /etc/mtree/BSD.var.dist -p /var >/dev/null 2>&1 || :
		injail mtree -eu -f /etc/mtree/BSD.usr.dist -p /usr >/dev/null 2>&1 || :
	fi
}

load_blacklist() {
	[ $# -lt 2 ] && eargs name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local bl b bfile

	bl="- ${setname} ${ptname} ${name} ${name}-${ptname}"
	[ -n "${setname}" ] && bl="${bl} ${bl}-${setname} \
		${name}-${ptname}-${setname}"
	for b in ${bl} ; do
		if [ "${b}" = "-" ]; then
			unset b
		fi
		bfile=${b:+${b}-}blacklist
		[ -f ${POUDRIERED}/${bfile} ] || continue
		for port in `grep -h -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${POUDRIERED}/${bfile}`; do
			case " ${BLACKLIST} " in
			*\ ${port}\ *) continue;;
			esac
			msg "Blacklisting (from ${POUDRIERED}/${bfile}): ${port}"
			BLACKLIST="${BLACKLIST} ${port}"
		done
	done
}

setup_makeconf() {
	[ $# -lt 3 ] && eargs dst_makeconf name ptname setname
	local dst_makeconf=$1
	local name=$2
	local ptname=$3
	local setname=$4
	local makeconf opt

	makeconf="- ${setname} ${ptname} ${name} ${name}-${ptname}"
	[ -n "${setname}" ] && makeconf="${makeconf} ${name}-${setname} \
		    ${name}-${ptname}-${setname}"
	for opt in ${makeconf}; do
		append_make ${opt} ${dst_makeconf}
	done
}

jail_stop() {
	[ $# -ne 0 ] && eargs
	if ! jail_runs ${MASTERNAME}; then
		[ -n "${CLEANING_UP}" ] && return 0
		err 1 "No such jail running: ${MASTERNAME}"
	fi
	local fs=$(zfs_getfs ${MASTERMNT})

	# err() will set status to 'crashed', don't override.
	[ -n "${CRASHED}" ] || bset status "stop:" 2>/dev/null || :

	jstop
	# Shutdown all builders
	if [ ${PARALLEL_JOBS} -ne 0 ]; then
		# - here to only check for unset, {start,stop}_builders will set this to blank if already stopped
		for j in ${JOBS-$(jot -w %02d ${PARALLEL_JOBS})}; do
			MY_JOBID=${j} jstop
			destroyfs ${MASTERMNT}/../${j} jail || :
		done
	fi
	msg "Umounting file systems"
	destroyfs ${MASTERMNT} jail
	rm -rf ${MASTERMNT}/../
	export STATUS=0
}

cleanup() {
	[ -n "${CLEANED_UP}" ] && return 0
	# Prevent recursive cleanup on error
	if [ -n "${CLEANING_UP}" ]; then
		echo "Failure cleaning up. Giving up." >&2
		return
	fi
	export CLEANING_UP=1
	msg "Cleaning up"

	# Only bother with this if using jails as this may be being ran
	# from queue.sh or daemon.sh, etc.
	if [ -n "${MASTERMNT}" -a -n "${MASTERNAME}" ] && was_a_jail_run; then
		# If this is a builder, don't cleanup, the master will handle that.
		if [ -n "${MY_JOBID}" ]; then
			[ -n "${PKGNAME}" ] && clean_pool ${PKGNAME} 1 || :
			return 0
		fi

		if [ -d ${MASTERMNT}/poudriere/var/run ]; then
			for pid in ${MASTERMNT}/poudriere/var/run/*.pid; do
				# Ensure there is a pidfile to read or break
				[ "${pid}" = "${MASTERMNT}/poudriere/var/run/*.pid" ] && break
				pkill -15 -F ${pid} >/dev/null 2>&1 || :
			done
		fi
		wait

		jail_stop

		rm -rf \
		    ${POUDRIERE_DATA}/packages/${MASTERNAME}/.latest/.new_packages \
		    2>/dev/null || :

	fi

	export CLEANED_UP=1
}

# return 0 if the package dir exists and has packages, 0 otherwise
package_dir_exists_and_has_packages() {
	[ ! -d ${PACKAGES}/All ] && return 1
	dirempty ${PACKAGES}/All && return 1
	# Check for non-empty directory with no packages in it
	for pkg in ${PACKAGES}/All/*.${PKG_EXT}; do
		[ "${pkg}" = \
		    "${PACKAGES}/All/*.${PKG_EXT}" ] \
		    && return 1
		# Stop on first match
		break
	done
	return 0
}

sanity_check_pkg() {
	[ $# -eq 1 ] || eargs pkg
	local pkg="$1"
	local depfile origin

	pkg_get_origin origin "${pkg}"
	port_is_needed "${origin}" || return 0
	deps_file depfile "${pkg}"
	while read dep; do
		if [ ! -e "${PACKAGES}/All/${dep}.${PKG_EXT}" ]; then
			msg_debug "${pkg} needs missing ${PACKAGES}/All/${dep}.${PKG_EXT}"
			msg "Deleting ${pkg##*/}: missing dependency: ${dep}"
			delete_pkg "${pkg}"
			return 65	# Package deleted, need another pass
		fi
	done < "${depfile}"

	return 0
}

sanity_check_pkgs() {
	local ret=0

	package_dir_exists_and_has_packages || return 0

	parallel_start
	for pkg in ${PACKAGES}/All/*.${PKG_EXT}; do
		parallel_run sanity_check_pkg "${pkg}" || ret=$?
	done
	parallel_stop || ret=$?
	[ ${ret} -eq 0 ] && return 0	# Nothing deleted
	[ ${ret} -eq 65 ] && return 1	# Packages deleted
	err 1 "Failure during sanity check"
}

check_leftovers() {
	[ $# -lt 1 ] && eargs mnt [stagedir]
	local mnt=$1
	local stagedir="$2"

	{
		if [ -z "${stagedir}" ]; then
			mtree -X ${mnt}/poudriere/mtree.preinstexclude \
			    -f ${mnt}/poudriere/mtree.preinst \
			    -p ${mnt}
		else
			markfs poststage ${mnt} ${stagedir}
			injail mtree -f /poudriere/mtree.poststage \
			    -e -L -p /
		fi
	} | while read l ; do
		case ${l} in
		*extra)
			if [ -d ${mnt}/${l% *} ]; then
				find ${mnt}/${l% *} -exec echo "+ {}" \;
			else
				echo "+ ${mnt}/${l% *}"
			fi
			;;
		*missing)
			l=${l#./}
			echo "- ${mnt}/${l% *}"
			;;
		*changed) echo "M ${mnt}/${l% *}" ;;
		extra:*)
			if [ -d ${mnt}/${l#* } ]; then
				find ${mnt}/${l#* } -exec echo "+ {}" \;
			else
				echo "+ ${mnt}/${l#* }"
			fi
			;;
		*:*) echo "M ${mnt}/${l%:*}" ;;
		esac
	done
}

check_fs_violation() {
	[ $# -eq 6 ] || eargs mnt mtree_target port status_msg err_msg \
	    status_value
	local mnt="$1"
	local mtree_target="$2"
	local port="$3"
	local status_msg="$4"
	local err_msg="$5"
	local status_value="$6"
	local tmpfile=${mnt}/tmp/check_fs_violation
	local ret=0

	msg_n "${status_msg}..."
	mtree -X ${mnt}/poudriere/mtree.${mtree_target}exclude \
		-f ${mnt}/poudriere/mtree.${mtree_target} \
		-p ${mnt} > ${tmpfile}
	echo " done"

	if [ -s ${tmpfile} ]; then
		msg "Error: ${err_msg}"
		cat ${tmpfile}
		bset ${MY_JOBID} status "${status_value}:${port}"
		job_msg_verbose "Status for build ${port}: ${status_value}"
		ret=1
	fi
	rm -f ${tmpfile}

	return $ret
}

nohang() {
	[ $# -gt 4 ] || eargs cmd_timeout log_timeout logfile cmd
	local cmd_timeout
	local log_timeout
	local logfile
	local childpid
	local now starttime
	local fifo
	local n
	local read_timeout
	local ret=0

	cmd_timeout="$1"
	log_timeout="$2"
	logfile="$3"
	shift 3

	read_timeout=$((log_timeout / 10))

	fifo=$(mktemp -ut nohang)
	mkfifo ${fifo}
	exec 7<> ${fifo}
	rm -f ${fifo}

	starttime=$(date +%s)

	# Run the actual command in a child subshell
	(
		local ret=0
		"$@" || ret=1
		# Notify the pipe the command is done
		echo done >&7 2>/dev/null || :
		exit $ret
	) &
	childpid=$!

	# Now wait on the cmd with a timeout on the log's mtime
	while :; do
		if ! kill -CHLD $childpid 2>/dev/null; then
			_wait $childpid || ret=1
			break
		fi

		lastupdated=$(stat -f "%m" ${logfile})
		now=$(date +%s)

		# No need to actually kill anything as stop_build()
		# will be called and kill -9 -1 the jail later
		if [ $((now - lastupdated)) -gt $log_timeout ]; then
			ret=2
			break
		elif [ $((now - starttime)) -gt $cmd_timeout ]; then
			ret=3
			break
		fi

		# Wait until it is done, but check on it every so often
		# This is done instead of a 'sleep' as it should recognize
		# the command has completed right away instead of waiting
		# on the 'sleep' to finish
		unset n; until trappedinfo=; read -t $read_timeout n <&7 ||
			[ -z "$trappedinfo" ]; do :; done
		if [ "${n}" = "done" ]; then
			_wait $childpid || ret=1
			break
		fi
		# Not done, was a timeout, check the log time
	done

	exec 7<&-
	exec 7>&-

	return $ret
}

gather_distfiles() {
	[ $# -eq 2 ] || eargs portdir distfiles
	local portdir="$1"
	local distfiles="$2"
	local sub dists d special
	sub=$(injail make -C ${portdir} -VDIST_SUBDIR)
	dists=$(injail make -C ${portdir} -V_DISTFILES -V_PATCHFILES)
	specials=$(injail make -C ${portdir} -V_DEPEND_SPECIALS)
	job_msg_verbose "Status for build ${portdir##/usr/ports/}: distfiles"
	for d in ${dists}; do
		[ -f ${DISTFILES_CACHE}/${sub}/${d} ] || continue
		echo ${DISTFILES_CACHE}/${sub}/${d}
	done | pax -rw -p p -s ",${DISTFILES_CACHE},,g" ${mnt}/portdistfiles ||
		return 1

	for special in ${specials}; do
		gather_distfiles ${special} ${distfiles}
	done

	return 0
}

# Build+test port and return 1 on first failure
# Return 2 on test failure if PORTTESTING_FATAL=no
_real_build_port() {
	[ $# -ne 1 ] && eargs portdir
	local portdir=$1
	local port=${portdir##/usr/ports/}
	local mnt=$(my_path)
	local log=$(log_path)
	local listfilecmd network
	local hangstatus
	local pkgenv
	local no_stage=$(injail make -C ${portdir} -VNO_STAGE)
	local targets install_order
	local stagedir plistsub_sed
	local jailuser
	local testfailure=0
	local max_execution_time

	# Must install run-depends as 'actual-package-depends' and autodeps
	# only consider installed packages as dependencies
	if [ -n "${no_stage}" ]; then
		install_order="run-depends install-mtree install package"
	else
		jailuser=root
		if [ "${BUILD_AS_NON_ROOT}" = "yes" ] &&
		    [ -z "$(injail make -C ${portdir} -VNEED_ROOT)" ]; then
			jailuser=${PORTBUILD_USER}
			chown -R ${jailuser} ${mnt}/wrkdirs
		fi
		install_order="run-depends stage package install-mtree install"
		stagedir=$(injail make -C ${portdir} -VSTAGEDIR)
	fi
	targets="check-config pkg-depends fetch-depends fetch checksum \
		  extract-depends extract patch-depends patch build-depends \
		  lib-depends configure build ${install_order} \
		  ${PORTTESTING:+deinstall}"

	# If not testing, then avoid rechecking deps in build/install;
	# When testing, check depends twice to ensure they depend on
	# proper files, otherwise they'll hit 'package already installed'
	# errors.
	[ -z "${PORTTESTING}" ] && PORT_FLAGS="${PORT_FLAGS} NO_DEPENDS=yes"

	for phase in ${targets}; do
		max_execution_time=${MAX_EXECUTION_TIME}
		[ -z "${no_stage}" ] && JUSER=${jailuser}
		bset ${MY_JOBID} status "${phase}:${port}"
		job_msg_verbose "Status for build ${port}: ${phase}"
		case ${phase} in
		fetch)
			jstop
			jstart 1
			JUSER=root
			;;
		extract)
			max_execution_time=3600
			chown -R ${JUSER} ${mnt}/wrkdirs
			;;
		configure) [ -n "${PORTTESTING}" ] && markfs prebuild ${mnt} ;;
		run-depends)
			JUSER=root
			if [ -n "${PORTTESTING}" ]; then
				check_fs_violation ${mnt} prebuild "${port}" \
				    "Checking for filesystem violations" \
				    "Filesystem touched during build:" \
				    "build_fs_violation" ||
				if [ "${PORTTESTING_FATAL}" != "no" ]; then
					return 1
				else
					testfailure=2
				fi
			fi
			;;
		checksum|*-depends|install-mtree) JUSER=root ;;
		stage) [ -n "${PORTTESTING}" ] && markfs prestage ${mnt} ;;
		install)
			max_execution_time=3600
			JUSER=root
			[ -n "${PORTTESTING}" ] && markfs preinst ${mnt}
			;;
		package)
			max_execution_time=3600
			if [ -n "${PORTTESTING}" ] &&
			    [ -z "${no_stage}" ]; then
				check_fs_violation ${mnt} prestage "${port}" \
				    "Checking for staging violations" \
				    "Filesystem touched during stage (files must install to \${STAGEDIR}):" \
				    "stage_fs_violation" || if [ "${PORTTESTING_FATAL}" != "no" ]; then
					return 1
				else
					testfailure=2
				fi
			fi
			;;
		deinstall)
			max_execution_time=3600
			JUSER=root
			# Skip for all linux ports, they are not safe
			if [ "${PKGNAME%%*linux*}" != "" ]; then
				msg "Checking shared library dependencies"
				listfilecmd="grep -v '^@' /var/db/pkg/${PKGNAME}/+CONTENTS"
				[ ${PKGNG} -eq 1 ] && listfilecmd="pkg query '%Fp' ${PKGNAME}"
				injail ${listfilecmd} | injail xargs ldd 2>&1 |
					awk '/=>/ { print $3 }' | sort -u
			fi
			;;
		esac

		print_phase_header ${phase}

		if [ "${phase}" = "package" ]; then
			echo "PACKAGES=/new_packages" >> ${mnt}/etc/make.conf
			# Create sandboxed staging dir for new package for this build
			rm -rf "${PACKAGES}/.new_packages/${PKGNAME}"
			mkdir -p "${PACKAGES}/.new_packages/${PKGNAME}"
			${NULLMOUNT} \
				"${PACKAGES}/.new_packages/${PKGNAME}" \
				${mnt}/new_packages
			chown -R ${JUSER} ${mnt}/new_packages
		fi

		if [ "${phase}" = "deinstall" ]; then
			plistsub_sed=$(injail env ${PORT_FLAGS} make -C ${portdir} -V'PLIST_SUB:C/"//g:NLIB32*:NPERL_*:NPREFIX*:N*="":N*="@comment*:C/(.*)=(.*)/-es!\2!%%\1%%!g/')
			PREFIX=$(injail env ${PORT_FLAGS} make -C ${portdir} -VPREFIX)
			if [ -z "${no_stage}" ]; then
				msg "Checking for orphaned files and directories in stage directory (missing from plist)"
				bset ${MY_JOBID} status "stage_orphans:${port}"
				local orphans=$(mktemp ${mnt}/tmp/orphans.XXXXXX)
				local die=0

				check_leftovers ${mnt} ${stagedir} | \
				    while read modtype path; do
					local ppath

					# If this is a directory, use @dirrm in output
					if [ -d "${path}" ]; then
						ppath="@dirrm "`echo $path | sed \
							-e "s,^${mnt},," \
							-e "s,^${PREFIX}/,," \
							${plistsub_sed} \
						`
					else
						ppath=`echo "$path" | sed \
							-e "s,^${mnt},," \
							-e "s,^${PREFIX}/,," \
							${plistsub_sed} \
						`
					fi

					[ "${modtype}" = "M" ] && continue

					# Ignore PREFIX as orphan, which
					# happens via stage-dir if
					# NO_MTREE is set
					[ "${path#${mnt}}" != "${PREFIX}" ] &&
					  [ "${path#${mnt}}" != "/usr" ] &&
					  [ "${path#${mnt}}" != "/." ] &&
					    echo "${ppath}" >> ${orphans}
				done

				if [ -s "${orphans}" ]; then
					msg "Files or directories orphaned:"
					die=1
					grep -v "^@dirrm" ${orphans}
					grep "^@dirrm" ${orphans} | sort -r
				fi
				[ ${die} -eq 1 -a "${0##*/}" = "testport.sh" -a \
				    "${PREFIX}" != "${LOCALBASE}" ] && msg \
				    "This test was done with PREFIX!=LOCALBASE which \
may show failures if the port does not respect PREFIX. \
Try testport with -n to use PREFIX=LOCALBASE"
				rm -f ${orphans}
				[ $die -eq 0 ] || if [ "${PORTTESTING_FATAL}" != "no" ]; then
					return 1
				else
					testfailure=2
					die=0
				fi

				msg "Checking for absolute symlinks into staging directory"
				bset ${MY_JOBID} status "stage_symlinks:${port}"
				if [ ${PKGNG} -eq 1 ]; then
					injail ${PKG_BIN} query %Fp ${PKGNAME}
				else
					injail pkg_info -qL ${PKGNAME}
				fi | tr '\n' '\0' | injail xargs -0 -J % \
				    find % -type l -print0 |
				    injail xargs -0 stat -l |
				    grep "${portdir}/work/stage" && die=1
				if [ ${die} -eq 1 ]; then
					msg "Port is installing absolute symlinks into stagedir"
					return 1
				fi
			fi
		fi

		if [ "${phase#*-}" = "depends" ]; then
			# No need for nohang or PORT_FLAGS for *-depends
			injail env USE_PACKAGE_DEPENDS_ONLY=1 \
			    make -C ${portdir} ${phase} || return 1
		else
			# Only set PKGENV during 'package' to prevent
			# testport-built packages from going into the main repo
			# Also enable during stage/install since it now
			# uses a pkg for pkg_tools
			if [ "${phase}" = "package" ] || [ -z "${no_stage}" \
			    -a "${phase}" = "install" -a $PKGNG -eq 0 ]; then
				pkgenv="${PKGENV}"
			else
				pkgenv=
			fi

			nohang ${max_execution_time} ${NOHANG_TIME} \
				${log}/logs/${PKGNAME}.log \
				injail env ${pkgenv} ${PORT_FLAGS} \
				make -C ${portdir} ${phase}
			hangstatus=$? # This is done as it may return 1 or 2 or 3
			if [ $hangstatus -ne 0 ]; then
				# 1 = cmd failed, not a timeout
				# 2 = log timed out
				# 3 = cmd timeout
				if [ $hangstatus -eq 2 ]; then
					msg "Killing runaway build after ${NOHANG_TIME} seconds with no output"
					bset ${MY_JOBID} status "${phase}/runaway:${port}"
					job_msg_verbose "Status for build ${port}: runaway"
				elif [ $hangstatus -eq 3 ]; then
					msg "Killing timed out build after ${MAX_EXECUTION_TIME} seconds"
					bset ${MY_JOBID} status "${phase}/timeout:${port}"
					job_msg_verbose "Status for build ${port}: timeout"
				fi
				return 1
			fi
		fi

		if [ "${phase}" = "checksum" ]; then
			jstop
			jstart 0
		fi
		print_phase_footer

		if [ "${phase}" = "checksum" ]; then
			mkdir -p ${mnt}/portdistfiles
			echo "DISTDIR=/portdistfiles" >> ${mnt}/etc/make.conf
			gather_distfiles ${portdir} ${mnt}/portdistfiles || return 1
		fi

		if [ "${phase}" = "deinstall" ]; then
			msg "Checking for extra files and directories"
			bset ${MY_JOBID} status "leftovers:${port}"
			local add=$(mktemp ${mnt}/tmp/add.XXXXXX)
			local add1=$(mktemp ${mnt}/tmp/add1.XXXXXX)
			local del=$(mktemp ${mnt}/tmp/del.XXXXXX)
			local del1=$(mktemp ${mnt}/tmp/del1.XXXXXX)
			local mod=$(mktemp ${mnt}/tmp/mod.XXXXXX)
			local mod1=$(mktemp ${mnt}/tmp/mod1.XXXXXX)
			local die=0
			local users user homedirs

			users=$(injail make -C ${portdir} -VUSERS)
			homedirs=""
			for user in ${users}; do
				user=$(grep ^${user}: ${mnt}/usr/ports/UIDs | cut -f 9 -d : | sed -e "s|/usr/local|${PREFIX}| ; s|^|${mnt}|")
				homedirs="${homedirs} ${user}"
			done

			check_leftovers ${mnt} | \
				while read modtype path; do
				local ppath ignore_path=0

				# If this is a directory, use @dirrm in output
				if [ -d "${path}" ]; then
					ppath="@dirrm "`echo $path | sed \
						-e "s,^${mnt},," \
						-e "s,^${PREFIX}/,," \
						${plistsub_sed} \
					`
				else
					ppath=`echo "$path" | sed \
						-e "s,^${mnt},," \
						-e "s,^${PREFIX}/,," \
						${plistsub_sed} \
					`
				fi
				case $modtype in
				+)
					if [ -d "${path}" ]; then
						# home directory of users created
						case " ${homedirs} " in
						*\ ${path}\ *) continue;;
						esac
					fi
					case "${ppath}" in
					# gconftool-2 --makefile-uninstall-rule is unpredictable
					etc/gconf/gconf.xml.defaults/%gconf-tree*.xml) ;;
					# fc-cache - skip for now
					/var/db/fontconfig/*) ;;
					*) echo "${ppath}" >> ${add} ;;
					esac
					;;
				-)
					# Skip if it is PREFIX and non-LOCALBASE. See misc/kdehier4
					# or mail/qmail for examples
					[ "${path#${mnt}}" = "${PREFIX}" -a \
						"${LOCALBASE}" != "${PREFIX}" ] && ignore_path=1

					# fc-cache - skip for now
					case "${ppath}" in
					/var/db/fontconfig/*) ignore_path=1 ;;
					esac

					if [ $ignore_path -eq 0 ]; then
						echo "${ppath}" >> ${del}
					fi
					;;
				M)
					[ -d "${path}" ] && continue
					case "${ppath}" in
					# gconftool-2 --makefile-uninstall-rule is unpredictable
					etc/gconf/gconf.xml.defaults/%gconf-tree*.xml) ;;
					# This is a cache file for gio modules could be modified for any gio modules
					lib/gio/modules/giomodule.cache) ;;
					# removal of info files leaves entry uneasy to cleanup in info/dir
					# accept a modification of this file
					info/dir) ;;
					*/info/dir) ;;
					# The is pear database cache
					%%PEARDIR%%/.depdb|%%PEARDIR%%/.filemap) ;;
					#ls-R files from texmf are often regenerated
					*/ls-R);;
					# Octave packages database, blank lines can be inserted between pre-install and post-deinstall
					share/octave/octave_packages) ;;
					# xmlcatmgr is constantly updating catalog.ports ignore modification to that file
					share/xml/catalog.ports);;
					# fc-cache - skip for now
					/var/db/fontconfig/*) ;;
					*) echo "${ppath}" >> ${mod} ;;
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
			[ ${die} -eq 1 -a "${0##*/}" = "testport.sh" -a \
			    "${PREFIX}" != "${LOCALBASE}" ] && msg \
			    "This test was done with PREFIX!=LOCALBASE which \
may show failures if the port does not respect PREFIX. \
Try testport with -n to use PREFIX=LOCALBASE"
			rm -f ${add} ${add1} ${del} ${del1} ${mod} ${mod1}
			[ $die -eq 0 ] || if [ "${PORTTESTING_FATAL}" != "no" ]; then
				return 1
			else
				testfailure=2
			fi
		fi
	done

	if [ -d "${PACKAGES}/.new_packages/${PKGNAME}" ]; then
		# everything was fine we can copy package the package to the package
		# directory
		find ${PACKAGES}/.new_packages/${PKGNAME} \
			-mindepth 1 \( -type f -or -type l \) | while read pkg_path; do
			pkg_file=${pkg_path#${PACKAGES}/.new_packages/${PKGNAME}}
			pkg_base=${pkg_file%/*}
			mkdir -p ${PACKAGES}/${pkg_base}
			mv ${pkg_path} ${PACKAGES}/${pkg_base}
		done
	fi

	bset ${MY_JOBID} status "idle:"
	return ${testfailure}
}

# Wrapper to ensure JUSER is reset and any other cleanup needed
build_port() {
	local ret
	_real_build_port "$@" || ret=$?
	JUSER=root
	return ${ret}
}

# Save wrkdir and return path to file
save_wrkdir() {
	[ $# -ne 4 ] && eargs mnt port portdir phase
	local mnt=$1
	local port="$2"
	local portdir="$3"
	local phase="$4"
	local tardir=${POUDRIERE_DATA}/wrkdirs/${MASTERNAME}/${PTNAME}
	local tarname=${tardir}/${PKGNAME}.${WRKDIR_ARCHIVE_FORMAT}
	local mnted_portdir=${mnt}/wrkdirs/${portdir}

	[ "${SAVE_WRKDIR}" != "no" ] || return 0
	# Only save if not in fetch/checksum phase
	[ "${failed_phase}" != "fetch" -a "${failed_phase}" != "checksum" -a \
		"${failed_phase}" != "extract" ] || return 0

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
	local id=$1
	local arch=$2
	local mnt

	export MY_JOBID=${id}
	mnt=$(my_path)

	# Jail might be lingering from previous build. Already recursively
	# destroyed all the builder datasets, so just try stopping the jail
	# and ignore any errors
	jstop
	destroyfs ${mnt} jail
	mkdir -p "${mnt}"
	clonefs ${MASTERMNT} ${mnt} prepkg
	# Create the /poudriere so that on zfs rollback does not nukes it
	mkdir -p ${mnt}/poudriere
	markfs prepkg ${mnt} >/dev/null
	do_jail_mounts ${mnt} ${arch}
	do_portbuild_mounts ${mnt} ${jname} ${ptname} ${setname}
	jstart 0
	bset ${id} status "idle:"
}

start_builders() {
	local arch=$(injail uname -p)

	bset builders "${JOBS}"
	bset status "starting_builders:"
	parallel_start
	for j in ${JOBS}; do
		parallel_run start_builder ${j} ${arch}
	done
	parallel_stop
}

stop_builders() {
	local mnt

	# wait for the last running processes
	cat ${MASTERMNT}/poudriere/var/run/*.pid 2>/dev/null | xargs pwait 2>/dev/null

	msg "Stopping ${PARALLEL_JOBS} builders"

	for j in ${JOBS}; do
		MY_JOBID=${j} jstop
		destroyfs ${MASTERMNT}/../${j} jail
	done

	# No builders running, unset JOBS
	JOBS=""
}

deadlock_detected() {
	local always_fail=${1:-1}
	local crashed_packages dependency_cycles

	# If there are still packages marked as "building" they have crashed
	# and it's likely some poudriere or system bug
	crashed_packages=$( \
		find ${MASTERMNT}/poudriere/building -type d -mindepth 1 -maxdepth 1 | \
		sed -e "s,${MASTERMNT}/poudriere/building/,," | tr '\n' ' ' \
	)
	[ -z "${crashed_packages}" ] ||	\
		err 1 "Crashed package builds detected: ${crashed_packages}"

	# Check if there's a cycle in the need-to-build queue
	dependency_cycles=$(\
		find ${MASTERMNT}/poudriere/deps -mindepth 2 | \
		sed -e "s,${MASTERMNT}/poudriere/deps/,," -e 's:/: :' | \
		# Only cycle errors are wanted
		tsort 2>&1 >/dev/null | \
		sed -e 's/tsort: //' | \
		awk -f ${AWKPREFIX}/dependency_loop.awk \
	)

	if [ -n "${dependency_cycles}" ]; then
		err 1 "Dependency loop detected:
${dependency_cycles}"
	fi

	[ ${always_fail} -eq 1 ] || return 0

	# No cycle, there's some unknown poudriere bug
	err 1 "Unknown stuck queue bug detected. Please submit the entire build output to poudriere developers.
$(find ${MASTERMNT}/poudriere/building ${MASTERMNT}/poudriere/pool ${MASTERMNT}/poudriere/deps)"
}

queue_empty() {
	local pool_dir lock dirs

	# Lock on balance_pool to avoid race here while it is moving between
	# /unbalanced and a balanced slot
	lock=${MASTERMNT}/poudriere/.lock-balance_pool
	mkdir ${lock} 2>/dev/null || return 1

	dirs="${MASTERMNT}/poudriere/deps ${MASTERMNT}/poudriere/pool/unbalanced ${POOL_BUCKET_DIRS}"

	for pool_dir in ${dirs}; do
		if ! dirempty ${pool_dir}; then
			rmdir ${lock}
			return 1
		fi
	done

	rmdir ${lock}
	return 0
}

mark_done() {
	[ $# -eq 1 ] || eargs pkgname
	local pkgname="$1"
	local origin
	local cache_dir

	cache_get_origin origin "${pkgname}"
	get_cache_dir cache_dir

	if [ "${TRACK_BUILDTIMES}" != "no" ]; then
		echo -n "${origin} $(date +%s) " >> ${cache_dir}/buildtimes
		stat -f "%m" ${MASTERMNT}/poudriere/building/${pkgname} >> \
			${cache_dir}/buildtimes
	fi
	rmdir ${MASTERMNT}/poudriere/building/${pkgname}
}


build_queue() {
	local j name pkgname builders_active queue_empty

	mkfifo ${MASTERMNT}/poudriere/builders.pipe
	exec 6<> ${MASTERMNT}/poudriere/builders.pipe
	rm -f ${MASTERMNT}/poudriere/builders.pipe
	queue_empty=0

	msg "Hit CTRL+t at any time to see build progress and stats"

	while :; do
		builders_active=0
		for j in ${JOBS}; do
			name="${MASTERNAME}-job-${j}"
			if [ -f  "${MASTERMNT}/poudriere/var/run/${j}.pid" ]; then
				if pgrep -qF "${MASTERMNT}/poudriere/var/run/${j}.pid" 2>/dev/null; then
					builders_active=1
					continue
				fi
				read pkgname < ${MASTERMNT}/poudriere/var/run/${j}.pkgname
				rm -f ${MASTERMNT}/poudriere/var/run/${j}.pid \
					${MASTERMNT}/poudriere/var/run/${j}.pkgname
				bset ${j} status "idle:"
				mark_done ${pkgname}
			fi

			[ ${queue_empty} -eq 0 ] || continue

			next_in_queue pkgname
			if [ -z "${pkgname}" ]; then
				# Check if the ready-to-build pool and need-to-build pools
				# are empty
				queue_empty && queue_empty=1

				# Pool is waiting on dep, wait until a build
				# is done before checking the queue again
			else
				MY_JOBID="${j}" PORTTESTING=$(get_porttesting "${pkgname}") \
					build_pkg "${pkgname}" > /dev/null &
				echo "$!" > ${MASTERMNT}/poudriere/var/run/${j}.pid
				echo "${pkgname}" > ${MASTERMNT}/poudriere/var/run/${j}.pkgname

				# A new job is spawned, try to read the queue
				# just to keep things moving
				builders_active=1
			fi
		done

		update_stats

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

		unset jobid; until trappedinfo=; read -t 30 jobid <&6 ||
			[ -z "$trappedinfo" ]; do :; done
	done
	exec 6<&-
	exec 6>&-
}

start_html_json() {
	json_main &
	JSON_PID=$!
}

json_main() {
	while :; do
		build_json
		sleep 2
	done
}

build_json() {
	local log=$(log_path)
	awk \
		-f ${AWKPREFIX}/json.awk ${log}/.poudriere.* | \
		awk 'ORS=""; {print}' | \
		sed  -e 's/,\([]}]\)/\1/g' \
		> ${log}/.data.json.tmp
	mv -f ${log}/.data.json.tmp ${log}/.data.json

	# Build mini json for stats
	awk -v mini=yes \
		-f ${AWKPREFIX}/json.awk ${log}/.poudriere.* | \
		awk 'ORS=""; {print}' | \
		sed  -e 's/,\([]}]\)/\1/g' \
		> ${log}/.data.mini.json.tmp
	mv -f ${log}/.data.mini.json.tmp ${log}/.data.mini.json
}

stop_html_json() {
	local log=$(log_path)
	if [ -n "${JSON_PID}" ]; then
		kill ${JSON_PID} 2>/dev/null || :
		_wait ${JSON_PID} 2>/dev/null || :
		unset JSON_PID
	fi
	build_json 2>/dev/null || :
	rm -f ${log}/.data.json.tmp ${log}/.data.mini.json 2>/dev/null || :
}

calculate_tobuild() {
	local nbq=$(bget stats_queued)
	local nbb=$(bget stats_built)
	local nbf=$(bget stats_failed)
	local nbi=$(bget stats_ignored)
	local nbs=$(bget stats_skipped)
	local ndone=$((nbb + nbf + nbi + nbs))
	local nremaining=$((nbq - ndone))

	echo ${nremaining}
}

# Build ports in parallel
# Returns when all are built.
parallel_build() {
	local jname=$1
	local ptname=$2
	local setname=$3
	local real_parallel_jobs=${PARALLEL_JOBS}
	local nremaining=$(calculate_tobuild)

	# If pool is empty, just return
	[ ${nremaining} -eq 0 ] && return 0

	# Minimize PARALLEL_JOBS to queue size
	[ ${PARALLEL_JOBS} -gt ${nremaining} ] && PARALLEL_JOBS=${nremaining##* }

	msg "Building ${nremaining} packages using ${PARALLEL_JOBS} builders"
	JOBS="$(jot -w %02d ${PARALLEL_JOBS})"

	start_html_json

	bset status "starting_jobs:"
	msg "Starting/Cloning builders"
	start_builders

	# Duplicate stdout to socket 5 so the child process can send
	# status information back on it since we redirect its
	# stdout to /dev/null
	exec 5<&1

	bset status "parallel_build:"

	build_queue

	bset status "stopping_jobs:"
	stop_builders
	bset status "idle:"

	# Close the builder socket
	exec 5>&-

	stop_html_json

	# Restore PARALLEL_JOBS
	PARALLEL_JOBS=${real_parallel_jobs}

	return 0
}

clean_pool() {
	[ $# -ne 2 ] && eargs pkgname clean_rdepends
	local pkgname=$1
	local clean_rdepends=$2
	local port skipped_origin

	[ ${clean_rdepends} -eq 1 ] && cache_get_origin port "${pkgname}"

	# Cleaning queue (pool is cleaned here)
	sh ${SCRIPTPREFIX}/clean.sh "${MASTERMNT}" "${pkgname}" ${clean_rdepends} | sort -u | while read skipped_pkgname; do
		cache_get_origin skipped_origin "${skipped_pkgname}"
		badd ports.skipped "${skipped_origin} ${skipped_pkgname} ${pkgname}"
		job_msg "Skipping build of ${skipped_origin}: Dependent port ${port} failed"
		run_hook pkgbuild skipped "${skipped_origin}" "${skipped_pkgname}" "${port}"
	done

	balance_pool
}

print_phase_header() {
	printf "=======================<phase: %-15s>============================\n" "$1"
}

print_phase_footer() {
	echo "==========================================================================="
}

build_pkg() {
	# If this first check fails, the pool will not be cleaned up,
	# since PKGNAME is not yet set.
	[ $# -ne 1 ] && eargs pkgname
	local pkgname="$1"
	local port portdir
	local build_failed=0
	local name=${MASTERNAME}-job-${MY_JOBID}
	local mnt=$(my_path)
	local failed_status failed_phase cnt
	local clean_rdepends=0
	local log=$(log_path)
	local ignore
	local errortype
	local ret=0

	trap '' SIGTSTP
	[ -n "${MAX_MEMORY}" ] && ulimit -m $((${MAX_MEMORY} * 1024 * 1024))

	export PKGNAME="${pkgname}" # set ASAP so cleanup() can use it
	cache_get_origin port "${pkgname}"
	portdir="/usr/ports/${port}"

	job_msg "Starting build of ${port}"
	bset ${MY_JOBID} status "starting:${port}"

	if [ ${TMPFS_LOCALBASE} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		umount -f ${mnt}/${LOCALBASE:-/usr/local} 2>/dev/null || :
		mnt_tmpfs localbase ${mnt}/${LOCALBASE:-/usr/local}
	fi

	# Stop everything first
	jstop
	[ -f ${mnt}/.need_rollback ] && rollbackfs prepkg ${mnt}
	# Make sure we start with no network
	jstart 0

	touch ${mnt}/.need_rollback

	case " ${BLACKLIST} " in
	*\ ${port}\ *) ignore="Blacklisted" ;;
	esac
	# If this port is IGNORED, skip it
	# This is checked here instead of when building the queue
	# as the list may start big but become very small, so here
	# is a less-common check
	: ${ignore:=$(injail make -C ${portdir} -VIGNORE)}

	msg "Cleaning up wrkdir"
	rm -rf ${mnt}/wrkdirs/*

	log_start
	msg "Building ${port}"
	buildlog_start ${portdir}

	# Ensure /dev/null exists (kern/139014)
	[ ${JAILED} -eq 0 ] && devfs -m ${mnt}/dev rule apply path null unhide

	if [ -n "${ignore}" ]; then
		msg "Ignoring ${port}: ${ignore}"
		badd ports.ignored "${port} ${PKGNAME} ${ignore}"
		job_msg "Finished build of ${port}: Ignored: ${ignore}"
		clean_rdepends=1
		run_hook pkgbuild ignored "${port}" "${PKGNAME}" "${ignore}"
	else
		injail make -C ${portdir} clean
		build_port ${portdir} || ret=$?
		if [ ${ret} -ne 0 ]; then
			build_failed=1
			if [ ${ret} -eq 2 ]; then
				failed_phase=$(${SCRIPTPREFIX}/processonelog2.sh \
					${log}/logs/${PKGNAME}.log \
					2> /dev/null)
			else
				failed_status=$(bget ${MY_JOBID} status)
				failed_phase=${failed_status%:*}
			fi

			save_wrkdir ${mnt} "${port}" "${portdir}" "${failed_phase}" || :
		elif [ -f ${mnt}/${portdir}/.keep ]; then
			save_wrkdir ${mnt} "${port}" "${portdir}" "noneed" ||:
		fi

		injail make -C ${portdir} clean

		if [ ${build_failed} -eq 0 ]; then
			badd ports.built "${port} ${PKGNAME}"
			job_msg "Finished build of ${port}: Success"
			run_hook pkgbuild success "${port}" "${PKGNAME}"
			# Cache information for next run
			pkg_cache_data "${PACKAGES}/All/${PKGNAME}.${PKG_EXT}" ${port} || :
		else
			# Symlink the buildlog into errors/
			ln -s ../${PKGNAME}.log ${log}/logs/errors/${PKGNAME}.log
			errortype=$(${SCRIPTPREFIX}/processonelog.sh \
				${log}/logs/errors/${PKGNAME}.log \
				2> /dev/null)
			badd ports.failed "${port} ${PKGNAME} ${failed_phase} ${errortype}"
			job_msg "Finished build of ${port}: Failed: ${failed_phase}"
			run_hook pkgbuild failed "${port}" "${PKGNAME}" "${failed_phase}" \
				"${log}/logs/errors/${PKGNAME}.log"
			if [ ${ret} -eq 2 ]; then
				clean_rdepends=0
			else
				clean_rdepends=1
			fi
		fi
	fi

	clean_pool ${PKGNAME} ${clean_rdepends}

	bset ${MY_JOBID} status "done:${port}"

	stop_build ${portdir}

	echo ${MY_JOBID} >&6
}

stop_build() {
	[ $# -eq 1 ] || eargs portdir
	local portdir="$1"
	local mnt=$(my_path)

	umount -f ${mnt}/new_packages 2>/dev/null || :
	rm -rf "${PACKAGES}/.new_packages/${PKGNAME}"

	# 2 = HEADER+ps itself
	if [ $(injail ps aux | wc -l) -ne 2 ]; then
		msg "Leftover processes:"
		injail ps auxwwd | grep -v 'ps auxwwd'
	fi
	# Always kill to avoid missing anything
	injail kill -9 -1 2>/dev/null || :

	buildlog_stop ${portdir}
	log_stop
}

# Crazy redirection is to add the portname into stderr.
# Idea from http://superuser.com/a/453609/34747
mangle_stderr() {
	local msg_type="$1"
	local extra="$2"
	local - # Make `set +x` local

	shift 2

	set +x

	{
		{
			{
				{
					"$@"
				} 2>&3
			} 3>&1 1>&2 | \
				awk \
					-v msg_type="${msg_type}" -v extra="${extra}" \
					'{print msg_type, extra ":", $0}' 1>&3
		} 3>&2 2>&1
	}
}

list_deps() {
	[ $# -ne 1 ] && eargs directory
	local dir="/usr/ports/$1"
	local makeargs="-VPKG_DEPENDS -VBUILD_DEPENDS -VEXTRACT_DEPENDS -VLIB_DEPENDS -VPATCH_DEPENDS -VFETCH_DEPENDS -VRUN_DEPENDS"

	mangle_stderr "WARNING" "($1)" injail make -C ${dir} $makeargs | \
		tr '\n' ' ' | sed -e "s,[[:graph:]]*/usr/ports/,,g" \
		-e "s,:[[:graph:]]*,,g" | \
		sort -u || err 1 "Makefile broken: $1"
}

deps_file() {
	[ $# -ne 2 ] && eargs var_return pkg
	local var_return="$1"
	local pkg="$2"
	local pkg_cache_dir
	local _depfile

	get_pkg_cache_dir pkg_cache_dir "${pkg}"
	_depfile="${pkg_cache_dir}/deps"

	if [ ! -f "${_depfile}" ]; then
		if [ "${PKG_EXT}" = "tbz" ]; then
			injail tar -qxf "/packages/All/${pkg##*/}" -O +CONTENTS | awk '$1 == "@pkgdep" { print $2 }' > "${_depfile}"
		else
			injail /poudriere/pkg-static info -qdF "/packages/All/${pkg##*/}" > "${_depfile}"
		fi
	fi

	setvar "${var_return}" "${_depfile}"
}

pkg_get_origin() {
	[ $# -lt 2 ] && eargs var_return pkg
	local var_return="$1"
	local pkg="$2"
	local _origin=$3
	local pkg_cache_dir
	local originfile
	local new_origin

	get_pkg_cache_dir pkg_cache_dir "${pkg}"
	originfile="${pkg_cache_dir}/origin"

	if [ ! -f "${originfile}" ]; then
		if [ -z "${_origin}" ]; then
			if [ "${PKG_EXT}" = "tbz" ]; then
				_origin=$(injail tar -qxf "/packages/All/${pkg##*/}" -O +CONTENTS | \
					awk -F: '$1 == "@comment ORIGIN" { print $2 }')
			else
				_origin=$(injail /poudriere/pkg-static query -F \
					"/packages/All/${pkg##*/}" "%o")
			fi
		fi
		echo ${_origin} > "${originfile}"
	else
		read _origin < "${originfile}"
	fi

	check_moved new_origin ${_origin} && _origin=${new_origin}

	setvar "${var_return}" "${_origin}"
}

pkg_get_dep_origin() {
	[ $# -ne 2 ] && eargs var_return pkg
	local var_return="$1"
	local pkg="$2"
	local dep_origin_file
	local pkg_cache_dir
	local compiled_dep_origins
	local origin new_origin _old_dep_origins

	get_pkg_cache_dir pkg_cache_dir "${pkg}"
	dep_origin_file="${pkg_cache_dir}/dep_origin"

	if [ ! -f "${dep_origin_file}" ]; then
		if [ "${PKG_EXT}" = "tbz" ]; then
			compiled_dep_origins=$(injail tar -qxf "/packages/All/${pkg##*/}" -O +CONTENTS | \
				awk -F: '$1 == "@comment DEPORIGIN" {print $2}' | tr '\n' ' ')
		else
			compiled_dep_origins=$(injail /poudriere/pkg-static query -F \
				"/packages/All/${pkg##*/}" '%do' | tr '\n' ' ')
		fi
		echo "${compiled_dep_origins}" > "${dep_origin_file}"
	else
		while read line; do
			compiled_dep_origins="${deps} ${line}"
		done < "${dep_origin_file}"
	fi

	# Check MOVED
	_old_dep_origins="${compiled_dep_origins}"
	compiled_dep_origins=
	for origin in ${_old_dep_origins}; do
		if check_moved new_origin "${origin}"; then
			compiled_dep_origins="${compiled_dep_origins} ${new_origin}"
		else
			compiled_dep_origins="${compiled_dep_origins} ${origin}"
		fi
	done

	setvar "${var_return}" "${compiled_dep_origins}"
}

pkg_get_options() {
	[ $# -ne 2 ] && eargs var_return pkg
	local var_return="$1"
	local pkg="$2"
	local optionsfile
	local pkg_cache_dir
	local _compiled_options

	get_pkg_cache_dir pkg_cache_dir "${pkg}"
	optionsfile="${pkg_cache_dir}/options"

	if [ ! -f "${optionsfile}" ]; then
		if [ "${PKG_EXT}" = "tbz" ]; then
			_compiled_options=$(injail tar -qxf "/packages/All/${pkg##*/}" -O +CONTENTS | \
				awk -F: '$1 == "@comment OPTIONS" {print $2}' | tr ' ' '\n' | \
				sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
		else
			_compiled_options=$(injail /poudriere/pkg-static query -F \
				"/packages/All/${pkg##*/}" '%Ov%Ok' | sed '/^off/d;s/^on//' | sort | tr '\n' ' ')
		fi
		echo "${_compiled_options}" > "${optionsfile}"
		setvar "${var_return}" "${_compiled_options}"
		return 0
	fi

	# Special care here to match whitespace of 'pretty-print-config'
	while read line; do
		_compiled_options="${_compiled_options}${_compiled_options:+ }${line}"
	done < "${optionsfile}"

	# Space on end to match 'pretty-print-config' in delete_old_pkg
	[ -n "${_compiled_options}" ] &&
	    _compiled_options="${_compiled_options} "
	setvar "${var_return}" "${_compiled_options}"
}

ensure_pkg_installed() {
	local mnt=$(my_path)

	[ ${PKGNG} -eq 1 ] || return 0
	[ -x ${mnt}/poudriere/pkg-static ] && return 0
	[ -e ${MASTERMNT}/packages/Latest/pkg.txz ] || return 1 #pkg missing
	injail tar xf /packages/Latest/pkg.txz -C / \
		-s ",/.*/,poudriere/,g" "*/pkg-static"
	return 0
}

pkg_cache_data() {
	[ $# -ne 2 ] && eargs pkg origin
	local - # Make `set +e` local
	# Ignore errors in here
	set +e

	local pkg="$1"
	local origin=$2
	local pkg_cache_dir
	local originfile

	get_pkg_cache_dir pkg_cache_dir "${pkg}"
	originfile="${pkg_cache_dir}/origin"

	ensure_pkg_installed
	pkg_get_options _ignored "${pkg}" > /dev/null
	pkg_get_origin _ignored "${pkg}" ${origin} > /dev/null
	pkg_get_dep_origin _ignored "${pkg}" > /dev/null
	deps_file _ignored "${pkg}" > /dev/null
}

get_cache_dir() {
	local var_return="$1"
	setvar "${var_return}" ${POUDRIERE_DATA}/cache/${MASTERNAME}
}

# Return the cache dir for the given pkg
# @param var_return The variable to set the result in
# @param string pkg $PKGDIR/All/PKGNAME.PKG_EXT
get_pkg_cache_dir() {
	[ $# -lt 2 ] && eargs var_return pkg
	local var_return="$1"
	local pkg="$2"
	local use_mtime="${3:-1}"
	local pkg_file="${pkg##*/}"
	local pkg_dir
	local cache_dir
	local pkg_mtime

	get_cache_dir cache_dir

	[ ${use_mtime} -eq 1 ] && pkg_mtime=$(stat -f %m "${pkg}")

	pkg_dir="${cache_dir}/${pkg_file}/${pkg_mtime}"

	[ -d "${pkg_dir}" ] || mkdir -p "${pkg_dir}"

	setvar "${var_return}" "${pkg_dir}"
}

clear_pkg_cache() {
	[ $# -ne 1 ] && eargs pkg
	local pkg="$1"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	rm -fr "${pkg_cache_dir}"
}

delete_pkg() {
	[ $# -ne 1 ] && eargs pkg
	local pkg="$1"

	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	rm -f "${pkg}"
	clear_pkg_cache "${pkg}"
}

# Deleted cached information for stale packages (manually removed)
delete_stale_pkg_cache() {
	local pkgname
	local cache_dir

	get_cache_dir cache_dir

	msg_verbose "Checking for stale cache files"

	[ ! -d ${cache_dir} ] && return 0
	dirempty ${cache_dir} && return 0
	for pkg in ${cache_dir}/*.${PKG_EXT}; do
		pkg_file="${pkg##*/}"
		# If this package no longer exists in the PKGDIR, delete the cache.
		[ ! -e "${PACKAGES}/All/${pkg_file}" ] &&
			clear_pkg_cache "${pkg}"
	done

	return 0
}

delete_old_pkg() {
	[ $# -eq 1 ] || eargs pkgname
	local pkg="$1"
	local mnt pkgname cached_pkgname
	local o v v2 compiled_options current_options current_deps compiled_deps

	pkg_get_origin o "${pkg}"
	port_is_needed "${o}" || return 0

	mnt=$(my_path)

	if [ ! -d "${mnt}/usr/ports/${o}" ]; then
		msg "${o} does not exist anymore. Deleting stale ${pkg##*/}"
		delete_pkg "${pkg}"
		return 0
	fi

	v="${pkg##*-}"
	v=${v%.*}
	cache_get_pkgname cached_pkgname "${o}"
	v2=${cached_pkgname##*-}
	if [ "$v" != "$v2" ]; then
		msg "Deleting old version: ${pkg##*/}"
		delete_pkg "${pkg}"
		return 0
	fi

	# Detect ports that have new dependencies that the existing packages
	# do not have and delete them.
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		current_deps=""
		liblist=""
		# FIXME: Move into Infrastructure/scripts and 
		# 'make actual-run-depends-list' after enough testing,
		# which will avoida all of the injail hacks

		for td in LIB RUN; do
			raw_deps=$(injail make -C /usr/ports/${o} -V${td}_DEPENDS)
			for d in ${raw_deps}; do
				key=${d%:*}
				dpath=${d#*:/usr/ports/}
				case ${td} in
				LIB)
					[ -n "${liblist}" ] || liblist=$(injail ldconfig -r | awk '$1 ~ /:-l/ { gsub(/.*-l/, "", $1); printf("%s ",$1) } END { printf("\n") }')
					case ${key} in
					lib*)
						unset found
						for dir in /lib /usr/lib ; do
							if injail test -f "${dir}/${key}"; then
								found=yes
								break;
							fi
						done
						[ -n "${found}" ] || current_deps="${current_deps} ${dpath}"
						;;
					*.*)
						case " ${liblist} " in
							*\ ${key}\ *) ;;
							*) current_deps="${current_deps} ${dpath}" ;;
						esac
						;;
					*)
						unset found
						for dir in /lib /usr/lib ; do
							if injail test -f "${dir}/lib${key}.so"; then
								found=yes
								break;
							fi
						done
						[ -n "${found}" ] || current_deps="${current_deps} ${dpath}"
						;;
					esac
					;;
				RUN)
					case $key in
					/*) [ -e ${mnt}/${key} ] || current_deps="${current_deps} ${dpath}" ;;
					*) [ -n "$(injail which ${key})" ] || current_deps="${current_deps} ${dpath}" ;;
					esac
					;;
				esac
			done
		done
		pkg_get_dep_origin compiled_deps "${pkg}"

		for d in ${current_deps}; do
			case " $compiled_deps " in
			*\ $d\ *) ;;
			*)
				msg "Deleting ${pkg##*/}: new dependency: ${d}"
				delete_pkg "${pkg}"
				return 0
				;;
			esac
		done
	fi

	# Check if the compiled options match the current options from make.conf and /var/db/ports
	if [ "${CHECK_CHANGED_OPTIONS}" != "no" ]; then
		current_options=$(injail make -C /usr/ports/${o} pretty-print-config | \
			tr ' ' '\n' | sed -n 's/^\+\(.*\)/\1/p' | sort | tr '\n' ' ')
		pkg_get_options compiled_options "${pkg}"

		if [ "${compiled_options}" != "${current_options}" ]; then
			msg "Options changed, deleting: ${pkg##*/}"
			if [ "${CHECK_CHANGED_OPTIONS}" = "verbose" ]; then
				msg "Pkg: ${compiled_options}"
				msg "New: ${current_options}"
			fi
			delete_pkg "${pkg}"
			return 0
		fi
	fi

	pkgname="${pkg##*/}"
	# XXX: Check if the pkgname has changed and rename in the repo
	if [ "${pkgname%-*}" != "${cached_pkgname%-*}" ]; then
		msg "Deleting ${pkg##*/}: package name changed to '${cached_pkgname%-*}'"
		delete_pkg "${pkg}"
		return 0
	fi
}

delete_old_pkgs() {

	msg_verbose "Checking packages for incremental rebuild needed"

	package_dir_exists_and_has_packages || return 0

	parallel_start
	for pkg in ${PACKAGES}/All/*.${PKG_EXT}; do
		parallel_run delete_old_pkg "${pkg}"
	done
	parallel_stop
}

## Pick the next package from the "ready to build" queue in pool/
## Then move the package to the "building" dir in building/
## This is only ran from 1 process
next_in_queue() {
	local var_return="$1"
	local p _pkgname

	[ ! -d ${MASTERMNT}/poudriere/pool ] && err 1 "Build pool is missing"
	p=$(find ${POOL_BUCKET_DIRS} -type d -depth 1 -empty -print -quit || :)
	if [ -n "$p" ]; then
		_pkgname=${p##*/}
		mv ${p} ${MASTERMNT}/poudriere/building/${_pkgname}
		# Update timestamp for buildtime accounting
		touch ${MASTERMNT}/poudriere/building/${_pkgname}
	fi

	setvar "${var_return}" "${_pkgname}"
}

lock_acquire() {
	[ $# -ne 1 ] && eargs lockname
	local lockname=$1

	while :; do
		mkdir ${POUDRIERE_DATA}/.lock-${MASTERNAME}-${lockname} 2>/dev/null &&
			break
		sleep 0.1
	done
}

lock_release() {
	[ $# -ne 1 ] && eargs lockname
	local lockname=$1

	rmdir ${POUDRIERE_DATA}/.lock-${MASTERNAME}-${lockname} 2>/dev/null
}

cache_get_pkgname() {
	[ $# -ne 2 ] && eargs var_return origin
	local var_return="$1"
	local origin=${2%/}
	local _pkgname="" existing_origin
	local cache_origin_pkgname=${MASTERMNT}/poudriere/var/cache/origin-pkgname/${origin%%/*}_${origin##*/}
	local cache_pkgname_origin

	[ -f ${cache_origin_pkgname} ] && read _pkgname < ${cache_origin_pkgname}

	# Add to cache if not found.
	if [ -z "${_pkgname}" ]; then
		[ -d "${MASTERMNT}/usr/ports/${origin}" ] ||
			err 1 "Invalid port origin '${origin}' not found."
		_pkgname=$(injail make -C /usr/ports/${origin} -VPKGNAME ||
			err 1 "Error getting PKGNAME for ${origin}")
		[ -n "${_pkgname}" ] || err 1 "Missing PKGNAME for ${origin}"
		# Make sure this origin did not already exist
		cache_get_origin existing_origin "${_pkgname}" 2>/dev/null || :
		# It may already exist due to race conditions, it is not harmful. Just ignore.
		if [ "${existing_origin}" != "${origin}" ]; then
			[ -n "${existing_origin}" ] &&
				err 1 "Duplicated origin for ${_pkgname}: ${origin} AND ${existing_origin}. Rerun with -vv to see which ports are depending on these."
			echo "${_pkgname}" > ${cache_origin_pkgname}
			cache_pkgname_origin="${MASTERMNT}/poudriere/var/cache/pkgname-origin/${_pkgname}"
			echo "${origin}" > "${cache_pkgname_origin}"
		fi
	fi

	setvar "${var_return}" "${_pkgname}"
}

cache_get_origin() {
	[ $# -ne 2 ] && eargs var_return pkgname
	local var_return="$1"
	local pkgname="$2"
	local cache_pkgname_origin="${MASTERMNT}/poudriere/var/cache/pkgname-origin/${pkgname}"
	local _origin

	read _origin < "${cache_pkgname_origin%/}"

	setvar "${var_return}" "${_origin}"
}

# Take optional pkgname to speedup lookup
compute_deps() {
	[ $# -lt 1 ] && eargs port
	[ $# -gt 2 ] && eargs port pkgnme
	local port=$1
	local pkgname="$2"
	local dep_pkgname dep_port
	local pkg_pooldir

	[ -z "${pkgname}" ] && cache_get_pkgname pkgname "${port}"
	pkg_pooldir="${MASTERMNT}/poudriere/deps/${pkgname}"

	mkdir "${pkg_pooldir}" 2>/dev/null || return 0

	msg_verbose "Computing deps for ${port}"

	for dep_port in `list_deps ${port}`; do
		msg_debug "${port} depends on ${dep_port}"
		[ "${port}" != "${dep_port}" ] ||
			err 1 "${port} incorrectly depends on itself. Please contact maintainer of the port to fix this."
		# Detect bad cat/origin/ dependency which pkgng will not register properly
		[ "${dep_port}" = "${dep_port%/}" ] ||
			err 1 "${port} depends on bad origin '${dep_port}'; Please contact maintainer of the port to fix this."
		cache_get_pkgname dep_pkgname "${dep_port}"

		# Only do this if it's not already done, and not ALL, as everything will
		# be touched anyway
		[ ${ALL} -eq 0 ] && ! [ -d "${MASTERMNT}/poudriere/deps/${dep_pkgname}" ] &&
			compute_deps "${dep_port}" "${dep_pkgname}"

		:> "${pkg_pooldir}/${dep_pkgname}"
		mkdir -p "${MASTERMNT}/poudriere/rdeps/${dep_pkgname}"
		ln -sf "${pkg_pooldir}/${dep_pkgname}" \
			"${MASTERMNT}/poudriere/rdeps/${dep_pkgname}/${pkgname}"
		echo "${port} ${dep_port}" >> \
			${MASTERMNT}/poudriere/port_deps.unsorted
	done
}

listed_ports() {
	if [ ${ALL} -eq 1 ]; then
		PORTSDIR=$(pget ${PTNAME} mnt)
		[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
		for cat in $(awk '$1 == "SUBDIR" { print $3}' ${PORTSDIR}/Makefile); do
			awk -v cat=${cat} '$1 == "SUBDIR" { print cat"/"$3}' ${PORTSDIR}/${cat}/Makefile
		done
		return 0
	fi
	if [ -z "${LISTPORTS}" ]; then
		[ -n "${LISTPKGS}" ] &&
			grep -h -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}
	else
		echo ${LISTPORTS} | tr ' ' '\n'
	fi
}

# Port was requested to be built
port_is_listed() {
	[ $# -eq 1 ] || eargs origin
	local origin="$1"

	if [ ${ALL} -eq 1 -o ${PORTTESTING_RECURSIVE} -eq 1 ]; then
		return 0
	fi

	listed_ports | grep -q "^${origin}\$" && return 0

	return 1
}

# Port was requested to be built, or is needed by a port requested to be built
port_is_needed() {
	[ $# -eq 1 ] || eargs origin
	local origin="$1"

	[ ${ALL} -eq 1 ] && return 0

	awk -vorigin="${origin}" '
	    $1 == origin || $2 == origin { found=1; exit 0 }
	    END { if (found != 1) exit 1 }' "${MASTERMNT}/poudriere/port_deps"
}

get_porttesting() {
	[ $# -eq 1 ] || eargs pkgname
	local pkgname="$1"
	local porttesting
	local origin

	if [ -n "${PORTTESTING}" ]; then
		cache_get_origin origin "${pkgname}"
		if port_is_listed "${origin}"; then
			porttesting=1
		fi
	fi

	echo $porttesting
}

parallel_exec() {
	local cmd="$1"
	local ret=0
	local - # Make `set +e` local
	local errexit=0
	shift 1

	# Disable -e so that the actual execution failing does not
	# return early and prevent notifying the FIFO that the
	# exec is done
	case $- in *e*) errexit=1;; esac
	set +e
	(
		# Do still cause the actual command to return
		# non-zero if it has any failures, if caller
		# was set -e as well. Using 'if cmd' or 'cmd || '
		# here would disable set -e in the cmd execution
		[ $errexit -eq 1 ] && set -e
		${cmd} "$@"
	)
	ret=$?
	echo >&6 || :
	exit ${ret}
	# set -e will be restored by 'local -'
}

parallel_start() {
	local fifo

	if [ -n "${MASTERMNT}" ]; then
		fifo=${MASTERMNT}/poudriere/parallel.pipe
	else
		fifo=$(mktemp -ut parallel)
	fi
	mkfifo ${fifo}
	exec 6<> ${fifo}
	rm -f ${fifo}
	export NBPARALLEL=0
	export PARALLEL_PIDS=""
	_SHOULD_REAP=0
}

# For all running children, look for dead ones, collect their status, error out
# if any have non-zero return, and then remove them from the PARALLEL_PIDS
# list.
_reap_children() {
	local pid
	local ret=0

	for pid in ${PARALLEL_PIDS}; do
		# Check if this pid is still alive
		if ! kill -0 ${pid} 2>/dev/null; then
			# This will error out if the return status is non-zero
			_wait ${pid} || ret=$?
			# Remove pid from PARALLEL_PIDS and strip away all
			# spaces
			PARALLEL_PIDS_L=${PARALLEL_PIDS%% ${pid} *}
			PARALLEL_PIDS_L=${PARALLEL_PIDS_L% }
			PARALLEL_PIDS_L=${PARALLEL_PIDS_L# }
			PARALLEL_PIDS_R=${PARALLEL_PIDS##* ${pid} }
			PARALLEL_PIDS_R=${PARALLEL_PIDS_R% }
			PARALLEL_PIDS_R=${PARALLEL_PIDS_R# }
			PARALLEL_PIDS=" ${PARALLEL_PIDS_L} ${PARALLEL_PIDS_R} "
		fi
	done

	return ${ret}
}

# Wait on all remaining running processes and clean them up. Error out if
# any have non-zero return status.
parallel_stop() {
	local ret=0
	local do_wait="${1:-1}"

	if [ ${do_wait} -eq 1 ]; then
		_wait ${PARALLEL_PIDS} || ret=$?
	fi

	exec 6<&-
	exec 6>&-
	unset PARALLEL_PIDS
	unset NBPARALLEL

	return ${ret}
}

parallel_shutdown() {
	kill_and_wait 30 "${PARALLEL_PIDS}" 2>/dev/null || :
	# Reap the pids
	parallel_stop 0 2>/dev/null || :
}

parallel_run() {
	local cmd="$1"
	shift 1

	# Occasionally reap dead children. Don't do this too often or it
	# becomes a bottleneck. Do it too infrequently and there is a risk
	# of PID reuse/collision
	_SHOULD_REAP=$((_SHOULD_REAP + 1))
	if [ ${_SHOULD_REAP} -eq 16 ]; then
		_SHOULD_REAP=0
		_reap_children || return $?
	fi

	# Only read once all slots are taken up; burst jobs until maxed out.
	# NBPARALLEL is never decreased and only inreased until maxed.
	if [ ${NBPARALLEL} -eq ${PARALLEL_JOBS} ]; then
		unset a; until trappedinfo=; read a <&6 || [ -z "$trappedinfo" ]; do :; done
	fi

	[ ${NBPARALLEL} -lt ${PARALLEL_JOBS} ] && NBPARALLEL=$((NBPARALLEL + 1))
	PARALLEL_CHILD=1 parallel_exec $cmd "$@" &
	PARALLEL_PIDS="${PARALLEL_PIDS} $! "
}

find_all_pool_references() {
	[ $# -ne 1 ] && eargs pkgname
	local pkgname="$1"
	local rpn

	# Cleanup rdeps/*/${pkgname}
	for rpn in $(ls "${MASTERMNT}/poudriere/deps/${pkgname}"); do
		echo "${MASTERMNT}/poudriere/rdeps/${rpn}/${pkgname}"
	done
	echo "${MASTERMNT}/poudriere/deps/${pkgname}"
	# Cleanup deps/*/${pkgname}
	if [ -d "${MASTERMNT}/poudriere/rdeps/${pkgname}" ]; then
		for rpn in $(ls "${MASTERMNT}/poudriere/rdeps/${pkgname}"); do
			echo "${MASTERMNT}/poudriere/deps/${rpn}/${pkgname}"
		done
		echo "${MASTERMNT}/poudriere/rdeps/${pkgname}"
	fi
}

delete_stale_symlinks_and_empty_dirs() {
	msg "Deleting stale symlinks"
	find -L ${PACKAGES} -type l \
		-exec rm -f {} +

	msg "Deleting empty directories"
	find ${PACKAGES} -type d -mindepth 1 \
		-empty -delete
}

load_moved() {
	msg "Loading MOVED"
	bset status "loading_moved:"
	mkdir ${MASTERMNT}/poudriere/MOVED
	grep -v '^#' ${MASTERMNT}/usr/ports/MOVED | awk \
	    -F\| '
		$2 != "" {
			sub("/", "_", $1);
			print $1,$2;
		}' | while read old_origin new_origin; do
			echo ${new_origin} > \
			    ${MASTERMNT}/poudriere/MOVED/${old_origin}
		done
}

check_moved() {
	[ $# -lt 2 ] && eargs var_return origin
	local var_return="$1"
	local origin="$2"
	local _new_origin

	_gsub ${origin} "/" "_"
	[ -f "${MASTERMNT}/poudriere/MOVED/${_gsub}" ] &&
	    read _new_origin < "${MASTERMNT}/poudriere/MOVED/${_gsub}"

	setvar "${var_return}" "${_new_origin}"

	# Return 0 if blank
	[ -n "${_new_origin}" ]
}


prepare_ports() {
	local pkg
	local log=$(log_path)
	local n port pn nbq resuming_build
	local cache_dir

	mkdir -p "${MASTERMNT}/poudriere"
	[ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ] && mnt_tmpfs data "${MASTERMNT}/poudriere"
	rm -rf "${MASTERMNT}/poudriere/var/cache/origin-pkgname" \
		"${MASTERMNT}/poudriere/var/cache/pkgname-origin" 2>/dev/null || :
	mkdir -p "${MASTERMNT}/poudriere/building" \
		"${MASTERMNT}/poudriere/pool" \
		"${MASTERMNT}/poudriere/deps" \
		"${MASTERMNT}/poudriere/rdeps" \
		"${MASTERMNT}/poudriere/var/run" \
		"${MASTERMNT}/poudriere/var/cache" \
		"${MASTERMNT}/poudriere/var/cache/origin-pkgname" \
		"${MASTERMNT}/poudriere/var/cache/pkgname-origin"

	POOL_BUCKET_DIRS=""
	if [ ${POOL_BUCKETS} -gt 0 ]; then
		# Add pool/N dirs in reverse order from highest to lowest
		for n in $(jot ${POOL_BUCKETS} 0 | sort -nr); do
			POOL_BUCKET_DIRS="${POOL_BUCKET_DIRS} ${MASTERMNT}/poudriere/pool/${n}"
		done
	fi
	mkdir -p ${POOL_BUCKET_DIRS} ${MASTERMNT}/poudriere/pool/unbalanced

	if was_a_bulk_run; then
		get_cache_dir cache_dir
		mkdir -p ${log}/../../latest-per-pkg ${log}/../latest-per-pkg
		mkdir -p ${log}/logs ${log}/logs/errors ${log}/assets
		mkdir -p ${cache_dir}
		ln -sfh ${BUILDNAME} ${log%/*}/latest
		cp ${HTMLPREFIX}/index.html ${log}
		cp -R ${HTMLPREFIX}/assets/ ${log}/assets/

		# Record the SVN URL@REV in the build
		[ -d ${MASTERMNT}/usr/ports/.svn ] && bset svn_url $(
			${SVN_CMD} info ${MASTERMNT}/usr/ports | awk '
				/^URL: / {URL=substr($0, 6)}
				/Revision: / {REVISION=substr($0, 11)}
				END { print URL "@" REVISION }
			')

		bset mastername "${MASTERNAME}"
		bset jailname "${JAILNAME}"
		bset setname "${SETNAME}"
		bset ptname "${PTNAME}"
		bset buildname "${BUILDNAME}"
	fi

	load_moved

	msg "Calculating ports order and dependencies"
	bset status "computingdeps:"

	:> "${MASTERMNT}/poudriere/port_deps.unsorted"
	parallel_start
	for port in $(listed_ports); do
		[ -d "${MASTERMNT}/usr/ports/${port}" ] ||
			err 1 "Invalid port origin listed for build: ${port}"
		parallel_run compute_deps ${port}
	done
	parallel_stop

	sort -u "${MASTERMNT}/poudriere/port_deps.unsorted" > \
		"${MASTERMNT}/poudriere/port_deps"
	rm -f "${MASTERMNT}/poudriere/port_deps.unsorted"

	bset status "sanity:"

	if was_a_bulk_run; then
		if [ ${CLEAN} -eq 1 ]; then
			msg_n "(-c): Cleaning all packages..."
			rm -rf ${PACKAGES}/*
			rm -rf ${POUDRIERE_DATA}/cache/${MASTERNAME}
			echo " done"
		fi

		if [ ${CLEAN_LISTED} -eq 1 ]; then
			msg "(-C) Cleaning specified ports to build"
			listed_ports | while read port; do
				cache_get_pkgname pkgname "${port}"
				pkg="${PACKAGES}/All/${pkgname}.${PKG_EXT}"
				if [ -f "${pkg}" ]; then
					msg "(-C) Deleting existing package: ${pkg##*/}"
					delete_pkg "${pkg}"
				fi
			done
		fi

		# If the build dir already exists, it is being resumed and any
		# packages already built/failed/skipped/ignored should not
		# be rebuilt
		if [ -e ${log}/.poudriere.ports.built ]; then
			resuming_build=1
			awk '{print $2}' \
				${log}/.poudriere.ports.built \
				${log}/.poudriere.ports.failed \
				${log}/.poudriere.ports.ignored \
				${log}/.poudriere.ports.skipped | \
			while read pn; do
				find_all_pool_references "${pn}"
			done | xargs rm -rf
		else
			# New build
			resuming_build=0
			bset stats_queued 0
			bset stats_built 0
			bset stats_failed 0
			bset stats_ignored 0
			bset stats_skipped 0
			:> ${log}/.data.json
			:> ${log}/.data.mini.json
			:> ${log}/.poudriere.ports.built
			:> ${log}/.poudriere.ports.failed
			:> ${log}/.poudriere.ports.ignored
			:> ${log}/.poudriere.ports.skipped
		fi
	fi

	if ! ensure_pkg_installed && [ ${SKIPSANITY} -eq 0 ]; then
		msg "pkg package missing, skipping sanity"
		SKIPSANITY=1
	fi

	if [ $SKIPSANITY -eq 0 ]; then
		msg "Sanity checking the repository"

		for n in repo.txz digests.txz packagesite.txz; do
			pkg="${PACKAGES}/All/${n}"
			if [ -f "${pkg}" ]; then
				msg "Removing invalid pkg repo file: ${pkg}"
				rm -f "${pkg}"
			fi

		done

		delete_stale_pkg_cache

		# Skip incremental build for pkgclean
		if was_a_bulk_run; then
			delete_old_pkgs

			msg_verbose "Checking packages for missing dependencies"
			while :; do
				sanity_check_pkgs && break
			done

			delete_stale_symlinks_and_empty_dirs
		fi
	fi

	bset status "cleaning:"
	msg "Cleaning the build queue"
	export LOCALBASE=${LOCALBASE:-/usr/local}
	for pn in $(ls ${MASTERMNT}/poudriere/deps/); do
		if [ -f "${MASTERMNT}/packages/All/${pn}.${PKG_EXT}" ]; then
			find_all_pool_references "${pn}"
		fi
	done | xargs rm -rf

	# Call the deadlock code as non-fatal which will check for cycles
	deadlock_detected 0

	if was_a_bulk_run && [ $resuming_build -eq 0 ]; then
		nbq=0
		nbq=$(find ${MASTERMNT}/poudriere/deps -type d -depth 1 | wc -l)
		bset stats_queued ${nbq##* }
	fi

	# Create a pool of ready-to-build from the deps pool
	find "${MASTERMNT}/poudriere/deps" -type d -empty -depth 1 | \
		xargs -J % mv % "${MASTERMNT}/poudriere/pool/unbalanced"
	balance_pool

	[ -n "${ALLOW_MAKE_JOBS}" ] || echo "DISABLE_MAKE_JOBS=poudriere" \
	    >> ${MASTERMNT}/etc/make.conf

	return 0
}

balance_pool() {
	# Don't bother if disabled
	[ ${POOL_BUCKETS} -gt 0 ] || return 0

	local pkgname pkg_dir dep_count rdep lock

	! dirempty ${MASTERMNT}/poudriere/pool/unbalanced || return 0
	# Avoid running this in parallel, no need
	lock=${MASTERMNT}/poudriere/.lock-balance_pool
	mkdir ${lock} 2>/dev/null || return 0

	if [ -n "${MY_JOBID}" ]; then
		bset ${MY_JOBID} status "balancing_pool:"
	else
		bset status "balancing_pool:"
	fi
	# For everything ready-to-build...
	for pkg_dir in ${MASTERMNT}/poudriere/pool/unbalanced/*; do
		pkgname=${pkg_dir##*/}
		dep_count=0
		# Determine its priority, based on how much depends on it
		for rdep in ${MASTERMNT}/poudriere/rdeps/${pkgname}/*; do
			# Empty
			[ ${rdep} = "${MASTERMNT}/poudriere/rdeps/${pkgname}/*" ] && break
			dep_count=$(($dep_count + 1))
			[ $dep_count -eq $((${POOL_BUCKETS} - 1)) ] && break
		done
		mv ${pkg_dir} ${MASTERMNT}/poudriere/pool/${dep_count##* }/ 2>/dev/null || :
	done

	rmdir ${lock}
}

append_make() {
	[ $# -ne 2 ] && eargs src_makeconf dst_makeconf
	local src_makeconf=$1
	local dst_makeconf=$2

	if [ "${src_makeconf}" = "-" ]; then
		src_makeconf="${POUDRIERED}/make.conf"
	else
		src_makeconf="${POUDRIERED}/${src_makeconf}-make.conf"
	fi

	[ -f "${src_makeconf}" ] || return 0
	src_makeconf="$(realpath ${src_makeconf} 2>/dev/null)"
	msg "Appending to make.conf: ${src_makeconf}"
	echo "#### ${src_makeconf} ####" >> ${dst_makeconf}
	cat "${src_makeconf}" >> ${dst_makeconf}
}

read_packages_from_params()
{
	if [ $# -eq 0 ]; then
		[ -n "${LISTPKGS}" -o ${ALL} -eq 1 ] ||
		    err 1 "No packages specified"
		if [ ${ALL} -eq 0 ]; then
			for listpkg_name in ${LISTPKGS}; do
				[ -f "${listpkg_name}" ] ||
				    err 1 "No such list of packages: ${listpkg_name}"
			done
		fi
	else
		[ ${ALL} -eq 0 ] ||
		    err 1 "command line arguments and -a cannot be used at the same time"
		[ -z "${LISTPKGS}" ] ||
		    err 1 "command line arguments and list of ports cannot be used at the same time"
		LISTPORTS="$@"
	fi
}

clean_restricted() {
	msg "Cleaning restricted packages"
	bset status "clean_restricted:"
	# Remount rw
	# mount_nullfs does not support mount -u
	umount -f ${MASTERMNT}/packages
	mount_packages
	injail make -C /usr/ports -j ${PARALLEL_JOBS} clean-restricted >/dev/null
	# Remount ro
	umount -f ${MASTERMNT}/packages
	mount_packages -o ro
}

build_repo() {
	local origin

	if [ $PKGNG -eq 1 ]; then
		msg "Creating pkgng repository"
		bset status "pkgrepo:"
		ensure_pkg_installed
		mkdir -p ${MASTERMNT}/tmp/packages
		if [ -f "${PKG_REPO_SIGNING_KEY:-/nonexistent}" ]; then
			install -m 0400 ${PKG_REPO_SIGNING_KEY} \
				${MASTERMNT}/tmp/repo.key
			injail /poudriere/pkg-static repo -o /tmp/packages \
				/packages /tmp/repo.key
			rm -f ${MASTERMNT}/tmp/repo.key
		else
			# XXX SIGNING command should most of the time need network access
			jstop
			jstart 1
			injail /poudriere/pkg-static repo -o /tmp/packages \
			    /packages \
			    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
		fi
		cp ${MASTERMNT}/tmp/packages/* ${PACKAGES}/
	else
		msg "Preparing INDEX"
		bset status "index:"
		OSMAJ=`injail uname -r | awk -F. '{ print $1 }'`
		INDEXF=${PACKAGES}/INDEX-${OSMAJ}
		INDEXF_JAIL=$(mktemp -u /tmp/index.XXXXXX)
		rm -f ${INDEXF}.1 2>/dev/null || :
		for pkg_file in ${PACKAGES}/All/*.tbz; do
			# Check for non-empty directory with no packages in it
			[ "${pkg}" = "${PACKAGES}/All/*.tbz" ] && break
			pkg_get_origin origin "${pkg_file}"
			msg_verbose "Extracting description for ${origin} ..."
			[ -d ${MASTERMNT}/usr/ports/${origin} ] &&
				injail make -C /usr/ports/${origin} describe >> ${INDEXF}.1
		done

		msg_n "Generating INDEX..."
		# Move temp INDEX file into the jail. make_index will jail_attach()
		# to the specified jail
		mv ${INDEXF}.1 ${MASTERMNT}${INDEXF_JAIL}.1
		make_index -j ${MASTERNAME} ${INDEXF_JAIL}.1 ${INDEXF_JAIL}
		mv ${MASTERMNT}${INDEXF_JAIL} ${INDEXF}
		echo " done"

		[ -f ${INDEXF}.bz2 ] && rm ${INDEXF}.bz2
		msg_n "Compressing INDEX-${OSMAJ}..."
		bzip2 -9 ${INDEXF}
		echo " done"
	fi
}


RESOLV_CONF=""
STATUS=0 # out of jail #

[ -z "${POUDRIERE_ETC}" ] &&
    POUDRIERE_ETC=$(realpath ${SCRIPTPREFIX}/../../etc)
[ -f ${POUDRIERE_ETC}/poudriere.conf ] ||
	err 1 "Unable to find ${POUDRIERE_ETC}/poudriere.conf"

. ${POUDRIERE_ETC}/poudriere.conf
POUDRIERED=${POUDRIERE_ETC}/poudriere.d
LIBEXECPREFIX=$(realpath ${SCRIPTPREFIX}/../../libexec/poudriere)
AWKPREFIX=${SCRIPTPREFIX}/awk
HTMLPREFIX=${SCRIPTPREFIX}/html
HOOKDIR=${POUDRIERED}/hooks
PATH="${LIBEXECPREFIX}:${PATH}"

# If the zfs module is not loaded it means we can't have zfs
[ -z "${NO_ZFS}" ] && lsvfs zfs >/dev/null 2>&1 || NO_ZFS=yes
# Short circuit to prevent running zpool(1) and loading zfs.ko
[ -z "${NO_ZFS}" ] && [ -z "$(zpool list -H -o name 2>/dev/null)" ] && NO_ZFS=yes

[ -z "${NO_ZFS}" -a -z ${ZPOOL} ] && err 1 "ZPOOL variable is not set"
[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"

trap sigint_handler SIGINT
trap sigterm_handler SIGTERM
trap sig_handler SIGKILL
trap exit_handler EXIT
trap siginfo_handler SIGINFO

# Test if zpool exists
if [ -z "${NO_ZFS}" ]; then
	zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
fi

: ${SVN_HOST="svn0.us-west.freebsd.org"}
: ${GIT_URL="git://github.com/freebsd/freebsd-ports.git"}
: ${FREEBSD_HOST="http://ftp.FreeBSD.org"}
if [ -z "${NO_ZFS}" ]; then
	: ${ZROOTFS="/poudriere"}
	case ${ZROOTFS} in
	[!/]*) err 1 "ZROOTFS shoud start with a /" ;;
	esac
fi

[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

for val in ${USE_TMPFS}; do
	case ${val} in
	wrkdir|yes) TMPFS_WRKDIR=1 ;;
	data) TMPFS_DATA=1 ;;
	all) TMPFS_ALL=1 ;;
	localbase) TMPFS_LOCALBASE=1 ;;
	*) err 1 "Unknown value for USE_TMPFS can be a combination of wrkdir,data,all,yes,localbase" ;;
	esac
done

case ${TMPFS_WRKDIR}${TMPFS_DATA}${TMPFS_LOCALBASE}${TMPFS_ALL} in
1**1|*1*1|**11)
	TMPFS_WRKDIR=0
	TMPFS_DATA=0
	TMPFS_LOCALBASE=0
	;;
esac

POUDRIERE_DATA=`get_data_dir`
: ${WRKDIR_ARCHIVE_FORMAT="tbz"}
case "${WRKDIR_ARCHIVE_FORMAT}" in
	tar|tgz|tbz|txz);;
	*) err 1 "invalid format for WRKDIR_ARCHIVE_FORMAT: ${WRKDIR_ARCHIVE_FORMAT}" ;;
esac

#Converting portstree if any
if [ ! -d ${POUDRIERED}/ports ]; then
	mkdir -p ${POUDRIERED}/ports
	[ -z "${NO_ZFS}" ] && zfs list -t filesystem -H \
		-o ${NS}:type,${NS}:name,${NS}:method,mountpoint,name | \
		grep "^ports" | \
		while read t name method mnt fs; do
			msg "Converting the ${name} ports tree"
			pset ${name} method ${method}
			pset ${name} mnt ${mnt}
			pset ${name} fs ${fs}
			# Delete the old properties
			zfs inherit -r ${NS}:type ${fs}
			zfs inherit -r ${NS}:name ${fs}
			zfs inherit -r ${NS}:method ${fs}
		done
	if [ -f ${POUDRIERED}/portstrees ]; then
		while read name method mnt; do
			[ -z "${name###*}" ] && continue # Skip comments
			msg "Converting the ${name} ports tree"
			mkdir ${POUDRIERED}/ports/${name}
			echo ${method} > ${POUDRIERED}/ports/${name}/method
			echo ${mnt} > ${POUDRIERED}/ports/${name}/mnt
		done < ${POUDRIERED}/portstrees
		rm -f ${POUDRIERED}/portstrees
	fi
fi

#Converting jails if any
if [ ! -d ${POUDRIERED}/jails ]; then
	mkdir -p ${POUDRIERED}/jails
	[ -z "${NO_ZFS}" ] && zfs list -t filesystem -H \
		-o ${NS}:type,${NS}:name,${NS}:version,${NS}:arch,${NS}:method,mountpoint,name | \
		grep "^rootfs" | \
		while read t name version arch method mnt fs; do
			msg "Converting the ${name} jail"
			jset ${name} version ${version}
			jset ${name} arch ${arch}
			jset ${name} method ${method}
			jset ${name} mnt ${mnt}
			jset ${name} fs ${fs}
			# Delete the old properties
			zfs inherit -r ${NS}:type ${fs}
			zfs inherit -r ${NS}:name ${fs}
			zfs inherit -r ${NS}:method ${fs}
			zfs inherit -r ${NS}:version ${fs}
			zfs inherit -r ${NS}:arch ${fs}
			zfs inherit -r ${NS}:stats_built ${fs}
			zfs inherit -r ${NS}:stats_failed ${fs}
			zfs inherit -r ${NS}:stats_skipped ${fs}
			zfs inherit -r ${NS}:stats_ignored ${fs}
			zfs inherit -r ${NS}:stats_queued ${fs}
			zfs inherit -r ${NS}:status ${fs}
		done
fi

: ${LOIP6:=::1}
: ${LOIP4:=127.0.0.1}
case $IPS in
01)
	localipargs="ip6.addr=${LOIP6}"
	ipargs="ip6.addr=inherit"
	;;
10)
	localipargs="ip4.addr=${LOIP4}"
	ipargs="ip4=inherit"
	;;
11)
	localipargs="ip4.addr=${LOIP4} ip6.addr=${LOIP6}"
	ipargs="ip4=inherit ip6=inherit"
	;;
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

: ${WATCHDIR:=${POUDRIERE_DATA}/queue}
: ${PIDFILE:=${POUDRIERE_DATA}/daemon.pid}
: ${QUEUE_SOCKET:=/var/run/poudriered.sock}
: ${PORTBUILD_USER:=nobody}
: ${BUILD_AS_NON_ROOT:=no}
: ${SVN_CMD:=$(which svn 2>/dev/null || which svnlite 2>/dev/null)}
# 24 hours for 1 command
: ${MAX_EXECUTION_TIME:=86400}
# 120 minutes with no log update
: ${NOHANG_TIME:=7200}
: ${PATCHED_FS_KERNEL:=no}
: ${ALL:=0}
: ${CLEAN:=0}
: ${CLEAN_LISTED:=0}
: ${VERBOSE:=0}
: ${PORTTESTING_FATAL:=yes}
: ${PORTTESTING_RECURSIVE:=0}
: ${RESTRICT_NETWORKING:=yes}

# Be sure to update poudriere.conf to document the default when changing these
: ${MAX_EXECUTION_TIME:=86400}         # 24 hours for 1 command
: ${NOHANG_TIME:=7200}                 # 120 minutes with no log update
: ${TIMESTAMP_LOGS:=no}
: ${ATOMIC_PACKAGE_REPOSITORY:=yes}
: ${KEEP_OLD_PACKAGES:=no}
: ${KEEP_OLD_PACKAGES_COUNT:=5}
: ${COMMIT_PACKAGES_ON_FAILURE:=yes}
: ${SAVE_WRKDIR:=no}
: ${TRACK_BUILDTIMES:=no}
: ${CHECK_CHANGED_DEPS:=yes}
: ${CHECK_CHANGED_OPTIONS:=verbose}
: ${NO_RESTRICTED:=no}

: ${BUILDNAME:=$(date +%Y-%m-%d_%Hh%Mm%Ss)}

[ -d ${WATCHDIR} ] || mkdir -p ${WATCHDIR}
