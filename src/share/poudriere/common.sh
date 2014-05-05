#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2010-2011 Julien Laffaye <jlaffaye@FreeBSD.org>
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
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
. $(dirname ${0})/include/common.sh.${BSDPLATFORM}
BLACKLIST=""

# Return true if ran from bulk/testport, ie not daemon/status/jail
was_a_bulk_run() {
	[ "${0##*/}" = "bulk.sh" -o "${0##*/}" = "testport.sh" ]
}
# Return true if in a bulk or other jail run that needs to shutdown the jail
was_a_jail_run() {
	was_a_bulk_run ||  [ "${0##*/}" = "pkgclean.sh" ]
}
# Return true if output via msg() should show elapsed time
should_show_elapsed() {
	[ "${NO_ELAPSED_IN_MSG:-0}" -eq 1 ] && return 1
	case "${0##*/}" in
		daemon.sh) ;;
		help.sh) ;;
		queue.sh) ;;
		status.sh) ;;
		version.sh) ;;
		*) return 0 ;;
	esac
	return 1
}

# Based on Shell Scripting Recipes - Chris F.A. Johnson (c) 2005
# Replace a pattern without needing a subshell/exec
_gsub() {
	[ $# -ne 3 ] && eargs _gsub string pattern replacement
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
	msg_error "$2"
	exit $1
}

_my_path() {
	setvar "$1" "${MASTERMNT}${MY_JOBID+/../${MY_JOBID}}"
}

_my_name() {
	setvar "$1" "${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}}"
}
 
_log_path() {
	setvar "$1" "${POUDRIERE_DATA}/logs/${POUDRIERE_BUILD_TYPE}/${MASTERNAME}/${BUILDNAME}"
}

injail() {
	local name

	_my_name name
	jexec -U ${JUSER:-root} ${name}${JNETNAME:+-${JNETNAME}} \
	    ${MAX_MEMORY_JEXEC} "$@"
}

jstart() {
	local name network

	network="${localipargs}"

	[ "${RESTRICT_NETWORKING}" = "yes" ] || network="${ipargs}"

	_my_name name
	jail -c persist name=${name} \
		path=${MASTERMNT}${MY_JOBID+/../${MY_JOBID}} \
		host.hostname=${BUILDER_HOSTNAME-${name}} \
		${network} \
		allow.socket_af allow.raw_sockets allow.chflags allow.sysvipc
	jail -c persist name=${name}-n \
		path=${MASTERMNT}${MY_JOBID+/../${MY_JOBID}} \
		host.hostname=${BUILDER_HOSTNAME-${name}} \
		${ipargs} \
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
	local name

	_my_name name
	jail -r ${name} 2>/dev/null || :
	jail -r ${name}-n 2>/dev/null || :
}

eargs() {
	local fname="$1"
	shift
	case $# in
	0) err 1 "${fname}: No arguments expected" ;;
	1) err 1 "${fname}: 1 argument expected: $1" ;;
	*) err 1 "${fname}: $# arguments expected: $*" ;;
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

stripcolors() {
	cat -uv | sed -lE "s/\^\[\[([0-9]{1,2}(;[0-9]{1,2})?)?[mK]//g"
}

log_start() {
	local log
	local latest_log

	_log_path log

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
		local stripcolors_pipe add_ts_pipe
		[ "${USE_COLORS}" = "yes" ] && stripcolors_pipe="stripcolors |"
		[ "${TIMESTAMP_LOGS}" = "yes" ] && add_ts_pipe="timestamp \"(${DURATION_FORMAT}) \" |"
		eval ${add_ts_pipe} ${stripcolors_pipe} tee ${logfile}
	} < ${logfile}.pipe >&3 &
	tpid=$!
	exec > ${logfile}.pipe 2>&1

	# Remove fifo pipe file right away to avoid orphaning it.
	# The pipe will continue to work as long as we keep
	# the FD open to it.
	rm -f ${logfile}.pipe
}

buildlog_start() {
	local portdir=$1
	local mnt
	local var

	_my_path mnt

	echo "build started at $(date)"
	echo "port directory: ${portdir}"
	echo "building for: $(injail uname -a)"
	echo "maintained by: $(injail make -C ${portdir} maintainer)"
	echo "Makefile ident: $(ident ${mnt}/${portdir}/Makefile|sed -n '2,2p')"
	echo "Poudriere version: ${POUDRIERE_VERSION}"
	echo "Host OSVERSION: ${HOST_OSVERSION}"
	echo "Jail OSVERSION: ${JAIL_OSVERSION}"
	echo
	if [ ${JAIL_OSVERSION} -gt ${HOST_OSVERSION} ]; then
		echo
		echo
		echo
		echo "!!! Jail is newer than host. (Jail: ${JAIL_OSVERSION}, Host: ${HOST_OSVERSION}) !!!"
		echo "!!! This is not supported. !!!"
		echo "!!! Host kernel must be same or newer than jail. !!!"
		echo "!!! Expect build failures. !!!"
		echo
		echo
		echo
	fi
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
	echo "--PLIST_SUB--"
	echo "$(injail env ${PORT_FLAGS} make -C ${portdir} -V PLIST_SUB | tr ' ' '\n' | grep -v '^$')"
	echo "--End PLIST_SUB--"
	echo ""
	echo "--SUB_LIST--"
	echo "$(injail env ${PORT_FLAGS} make -C ${portdir} -V SUB_LIST | tr ' ' '\n' | grep -v '^$')"
	echo "--End SUB_LIST--"
	echo ""
	echo "---Begin make.conf---"
	cat ${mnt}/etc/make.conf
	echo "---End make.conf---"
}

buildlog_stop() {
	[ $# -eq 2 ] || eargs buildlog_stop portdir build_failed
	local portdir=$1
	local build_failed="$2"
	local log
	local buildtime

	_log_path log
	buildtime=$( \
		stat -f '%N %B' ${log}/logs/${PKGNAME}.log  | awk -v now=$(date +%s) \
		-f ${AWKPREFIX}/siginfo_buildtime.awk |
		awk -F'!' '{print $2}' \
	)

	echo "build of ${portdir} ended at $(date)"
	echo "build time: ${buildtime}"
	[ ${build_failed} -gt 0 ] && echo "!!! build failure encountered !!!"

	return 0
}

log_stop() {
	if [ -n "${tpid}" ]; then
		exec 1>&3 3>&- 2>&4 4>&-
		kill $tpid
		_wait $tpid 2>/dev/null || :
		unset tpid
	fi
}

read_file() {
	[ $# -eq 2 ] || eargs read_file var_return file
	local var_return="$1"
	local file="$2"
	local _data line
	local ret -

	set +e
	_data=
	_read_file_lines_read=0

	if [ ${READ_FILE_USE_CAT:-0} -eq 1 ]; then
		if [ -f "${file}" ]; then
			_data="$(cat "${file}")"
			_read_file_lines_read=$(cat "${file}"|wc -l)
			_read_file_lines_read=${_read_file_lines_read##* }
		else
			ret=1
		fi
	else
		while :; do
			read -r line
			ret=$?
			case ${ret} in
				# Success, process data and keep reading.
				0) ;;
				# EOF
				1)
					ret=0
					break
					;;
				# Some error or interruption/signal. Reread.
				*) continue ;;
			esac
			[ ${_read_file_lines_read} -gt 0 ] && _data="${_data}
"
			_data="${_data}${line}"
			_read_file_lines_read=$((${_read_file_lines_read} + 1))
		done < "${file}" || ret=$?
	fi

	setvar "${var_return}" "${_data}"

	return ${ret}
}

# Read a file until 0 status is found. Partial reads not accepted.
read_line() {
	[ $# -eq 2 ] || eargs read_line var_return file
	local var_return="$1"
	local file="$2"
	local max_reads reads ret line

	ret=0
	line=

	if [ -f "${file}" ]; then
		max_reads=100
		reads=0

		# Read until a full line is returned.
		until [ ${reads} -eq ${max_reads} ] || \
		    read -t 1 -r line < "${file}"; do
			sleep 0.1
			reads=$((${reads} + 1))
		done
		[ ${reads} -eq ${max_reads} ] && ret=1
	else
		ret=1
	fi

	setvar "${var_return}" "${line}"

	return ${ret}
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

_attr_get() {
	[ $# -eq 4 ] || eargs _attr_get var_return type name property
	local var_return="$1"
	local type="$2"
	local name="$3"
	local property="$4"

	read_file "${var_return}" \
	    "${POUDRIERED}/${type}/${name}/${property}" && return 0
	setvar "${var_return}" ""
	return 1
}

attr_get() {
	local attr_get_data

	_attr_get attr_get_data "$@" || :
	[ -n "${attr_get_data}" ] && echo "${attr_get_data}"
}

jget() { attr_get jails "$@" ; }
_jget() {
	[ $# -eq 3 ] || eargs _jget var_return ptname property
	local var_return="$1"

	shift
	_attr_get "${var_return}" jails "$@"
}
pget() { attr_get ports "$@" ; }
_pget() {
	[ $# -eq 3 ] || eargs _pget var_return ptname property
	local var_return="$1"

	shift
	_attr_get "${var_return}" ports "$@"
}

#build getter/setter
_bget() {
	local var_return id property mnt log file READ_FILE_USE_CAT

	var_return="$1"
	_log_path log
	shift
	if [ $# -eq 2 ]; then
		id="$1"
		shift
	fi
	file=".poudriere.${1}${id:+.${id}}"

	# Use cat(1) to read long list files.
	[ -z "${1##ports.*}" ] && READ_FILE_USE_CAT=1

	read_file "${var_return}" "${log}/${file}" && return 0
	setvar "${var_return}" ""
	return 1
}

bget() {
	local bget_data

	_bget bget_data "$@" || :
	[ -n "${bget_data}" ] && echo "${bget_data}"
}

bset() {
	was_a_bulk_run || return 0
	local id property mnt log
	_log_path log
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	property="$1"
	file=.poudriere.${property}${id:+.${id}}
	shift
	[ "${property}" = "status" ] && \
	    echo "$@" >> ${log}/${file}.journal% || :
	echo "$@" > ${log}/${file} || :
}

bset_job_status() {
	[ $# -eq 2 ] || eargs bset_job_status status origin
	local status="$1"
	local origin="$2"

	bset ${MY_JOBID} status "${status}:${origin}:${PKGNAME}:${TIME_START_JOB:-${TIME_START}}:$(date +%s)"
}

badd() {
	local id property mnt log
	_log_path log
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	file=.poudriere.${1}${id:+.${id}}
	shift
	echo "$@" >> ${log}/${file} || :
}

update_stats() {
	local type unused
	local -

	set +e

	lock_acquire update_stats

	for type in built failed ignored; do
		_bget unused "ports.${type}"
		bset "stats_${type}" ${_read_file_lines_read}
	done

	# Skipped may have duplicates in it
	bset stats_skipped $(bget ports.skipped | awk '{print $1}' | \
		sort -u | wc -l)

	lock_release update_stats
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
	fi

	parallel_shutdown

	[ ${STATUS} -eq 1 ] && cleanup

	if was_a_bulk_run; then
		stop_html_json
	fi

	[ -n ${CLEANUP_HOOK} ] && ${CLEANUP_HOOK}
}

show_log_info() {
	local log

	_log_path log
	msg "Logs: ${log}"
	[ -z "${URL_BASE}" ] ||
		msg "WWW: ${URL_BASE}/${POUDRIERE_BUILD_TYPE}/${MASTERNAME}/${BUILDNAME}"
}

siginfo_handler() {
	[ "${POUDRIERE_BUILD_TYPE}" != "bulk" ] && return 0

	trappedinfo=1
	local status nbb nbf nbs nbi nbq ndone nbtobuild
	local log
	local queue_width=2
	local now
	local j elapsed job_id_color
	local pkgname origin phase buildtime started
	local format_origin_phase format_phase

	update_stats

	_bget nbq stats_queued 2>/dev/null || nbq=0
	[ -n "${nbq}" ] || return 0

	_bget status status 2>/dev/null || status=unknown
	[ "${status}" = "index:" -o "${status#stopped:}" = "crashed:" ] && \
	    return 0

	_bget nbf stats_failed 2>/dev/null || nbf=0
	_bget nbi stats_ignored 2>/dev/null || nbi=0
	_bget nbs stats_skipped 2>/dev/null || nbs=0
	_bget nbb stats_built 2>/dev/null || nbb=0
	ndone=$((nbb + nbf + nbi + nbs))
	nbtobuild=$((nbq - ndone))

	if [ ${nbq} -gt 9999 ]; then
		queue_width=5
	elif [ ${nbq} -gt 999 ]; then
		queue_width=4
	elif [ ${nbq} -gt 99 ]; then
		queue_width=3
	fi

	_log_path log
	now=$(date +%s)
	calculate_elapsed ${now} ${log}
	elapsed=${_elapsed_time}
	buildtime=$(date -j -u -r ${elapsed} "+${DURATION_FORMAT}")

	printf "[${MASTERNAME}] [${status}] Queued: %-${queue_width}d Built: %-${queue_width}d Failed: %-${queue_width}d  Skipped: %-${queue_width}d  Ignored: %-${queue_width}d  Tobuild: %-${queue_width}d  Time: %s  \n" \
	    ${nbq} ${nbb} ${nbf} ${nbs} ${nbi} ${nbtobuild} "${buildtime}"

	# Skip if stopping or starting jobs or stopped.
	if [ -n "${JOBS}" -a "${status#starting_jobs:}" = "${status}" \
	    -a "${status}" != "stopping_jobs:" -a -n "${MASTERMNT}" ] && \
	    ! status_is_stopped "${status}"; then
		for j in ${JOBS}; do
			# Ignore error here as the zfs dataset may not be cloned yet.
			_bget status ${j} status 2>/dev/null || :
			# Skip builders not started yet
			[ -z "${status}" ] && continue
			# Hide idle workers
			[ "${status}" = "idle:" ] && continue
			phase="${status%%:*}"
			status="${status#*:}"
			origin="${status%%:*}"
			status="${status#*:}"
			pkgname="${status%%:*}"
			status="${status#*:}"
			started="${status%%:*}"

			colorize_job_id job_id_color "${j}"

			# Must put colors in format
			format_origin_phase="\t[${job_id_color}%s${COLOR_RESET}]: ${COLOR_PORT}%-32s ${COLOR_PHASE}%-15s${COLOR_RESET} (%s)\n"
			format_phase="\t[${job_id_color}%s${COLOR_RESET}]: ${COLOR_PHASE}%15s${COLOR_RESET}\n"

			if [ -n "${pkgname}" ]; then
				elapsed=$((${now} - ${started}))
				buildtime=$(date -j -u -r ${elapsed} "+${DURATION_FORMAT}")
				printf "${format_origin_phase}" "${j}" \
				    "${origin}" "${phase}" ${buildtime}
			else
				printf "${format_phase}" "${j}" "${phase}"
			fi
		done
	fi

	show_log_info
}

jail_exists() {
	[ $# -ne 1 ] && eargs jail_exists jailname
	local jname=$1
	[ -d ${POUDRIERED}/jails/${jname} ] && return 0
	return 1
}

jail_runs() {
	[ $# -ne 1 ] && eargs jail_runs jname
	local jname=$1
	jls -j $jname >/dev/null 2>&1 && return 0
	return 1
}

porttree_list() {
	local name method mntpoint
	[ -d ${POUDRIERED}/ports ] || return 0
	for p in $(find ${POUDRIERED}/ports -type d -maxdepth 1 -mindepth 1 -print); do
		name=${p##*/}
		_pget mnt ${name} mnt 2>/dev/null || :
		_pget method ${name} method 2>/dev/null || :
		echo "${name} ${method:--} ${mnt}"
	done
}

porttree_exists() {
	[ $# -ne 1 ] && eargs porttree_exists portstree_name
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
		    awk '$1 == "data" { print $2; exit; }')
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
	[ $# -ne 2 ] && eargs fetch_file destination source
	fetch -p -o $1 $2 || fetch -p -o $1 $2 || err 1 "Failed to fetch from $2"
}

unmarkfs() {
	[ $# -ne 2 ] && eargs unmarkfs name mnt
	local name=$1
	local mnt=$(realpath $2)

	if [ -n "$(zfs_getfs ${mnt})" ]; then
		zfs destroy -f ${fs}@${name} 2>/dev/null || :
	else
		rm -f ${mnt}/poudriere/mtree.${name} 2>/dev/null || :
	fi
}

markfs() {
	[ $# -lt 2 ] && eargs markfs name mnt path
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
		prepkg)
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
./var/tmp/*
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
./var/tmp/*
./wrkdirs/*
EOF
		;;
	esac
	mtree -X ${mnt}/poudriere/mtree.${name}exclude \
		-cn -k uid,gid,mode,size \
		-p ${mnt}${path} > ${mnt}/poudriere/mtree.${name}
	echo " done"
}

rm() {
	local arg

	for arg in "$@"; do
		[ "${arg}" = "/" ] && err 1 "Tried to rm /"
		[ "${arg%/}" = "/bin" ] && err 1 "Tried to rm /*"
	done

	/bin/rm "$@"
}

do_jail_mounts() {
	[ $# -ne 2 ] && eargs do_jail_mounts mnt arch
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

# Interactive test mode
enter_interactive() {
	local stopmsg

	if [ ${ALL} -ne 0 ]; then
		msg "(-a) Not entering interactive mode."
		return 0
	fi

	print_phase_header "Interactive"
	bset status "interactive:"

	msg "Installing packages"
	echo "PACKAGES=/packages" >> ${MASTERMNT}/etc/make.conf
	echo "127.0.0.1 ${MASTERNAME}" >> ${MASTERMNT}/etc/hosts

	# Skip for testport as it has already installed pkg in the ref jail.
	if [ ${PKGNG} -eq 1 -a "${0##*/}" != "testport.sh" ]; then
		# Install pkg-static so full pkg package can install
		ensure_pkg_installed
		# Install the selected PKGNG package
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    PKG_ADD="/poudriere/pkg-static add" \
		    make -C \
		    /usr/ports/$(injail make -f /usr/ports/Mk/bsd.port.mk \
		    -V PKGNG_ORIGIN) install-package
	fi

	# Enable all selected ports and their run-depends
	for port in $(listed_ports); do
		# Install run-depends since this is an interactive test
		msg "Installing run-depends for ${COLOR_PORT}${port}"
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    make -C /usr/ports/${port} run-depends ||
		    msg_warn "Failed to install ${COLOR_PORT}${port} run-depends"
		msg "Installing ${COLOR_PORT}${port}"
		# Only use PKGENV during install as testport will store
		# the package in a different place than dependencies
		injail env USE_PACKAGE_DEPENDS_ONLY=1 ${PKGENV} \
		    make -C /usr/ports/${port} install-package ||
		    msg_warn "Failed to install ${COLOR_PORT}${port}"
	done

	# Create a pkgng repo configuration, and disable FreeBSD
	if [ ${PKGNG} -eq 1 ]; then
		msg "Installing local Pkg repository to ${LOCALBASE}/etc/pkg/repos"
		mkdir -p ${MASTERMNT}${LOCALBASE}/etc/pkg/repos
		cat > ${MASTERMNT}${LOCALBASE}/etc/pkg/repos/local.conf << EOF
FreeBSD: {
	enabled: no
}

local: {
	url: "file:///packages",
	enabled: yes
}
EOF
	fi

	if [ ${INTERACTIVE_MODE} -eq 1 ]; then
		msg "Entering interactive test mode. Type 'exit' when done."
		JNETNAME="n" injail env -i TERM=${SAVED_TERM} \
		    /usr/bin/login -fp root || :
	elif [ ${INTERACTIVE_MODE} -eq 2 ]; then
		# XXX: Not tested/supported with bulk yet.
		msg "Leaving jail ${MASTERNAME}-n running, mounted at ${MASTERMNT} for interactive run testing"
		msg "To enter jail: jexec ${MASTERNAME}-n env -i TERM=\$TERM /usr/bin/login -fp root"
		stopmsg="-j ${JAILNAME}"
		[ -n "${SETNAME}" ] && stopmsg="${stopmsg} -z ${SETNAME}"
		[ -n "${PTNAME#default}" ] && stopmsg="${stopmsg} -p ${PTNAME}"
		msg "To stop jail: poudriere jail -k ${stopmsg}"
		CLEANED_UP=1
		return 0
	fi
	print_phase_footer
}

use_options() {
	[ $# -ne 2 ] && eargs use_options mnt optionsdir
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
	local mnt

	_my_path mnt
	${NULLMOUNT} "$@" ${PACKAGES} \
		${mnt}/packages ||
		err 1 "Failed to mount the packages directory "
}

do_portbuild_mounts() {
	[ $# -lt 3 ] && eargs do_portbuild_mounts mnt jname ptname setname
	local mnt=$1
	local jname=$2
	local ptname=$3
	local setname=$4
	local portsdir
	local optionsdir

	_pget portsdir ${ptname} mnt

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

	[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] || return 0

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
	local pkgdir_old pkgdir_new stats_failed

	[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] || return 0
	if [ "${COMMIT_PACKAGES_ON_FAILURE}" = "no" ] &&
	    _bget stats_failed stats_failed && [ ${stats_failed} -gt 0 ]; then
		msg_warn "Not committing packages to repository as failures were encountered"
		return 0
	fi

	msg "Committing packages to repository"
	bset status "committing:"

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
	rename ${PACKAGES_ROOT}/.latest_new ${PACKAGES}

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

write_usock() {
	[ $# -eq 1 ] || eargs write_usock socket
	local socket="$1"
	nc -U "${socket}"
}

# If running as non-root, redirect this command to queue and exit
maybe_run_queued() {
	[ $(/usr/bin/id -u) -eq 0 ] && return 0
	local this_command

	# If poudriered not running then the command cannot be
	# satisfied.
	/usr/sbin/service poudriered onestatus >/dev/null 2>&1 || \
	    err 1 "This command requires root or poudriered running"

	this_command="${0##*/}"
	this_command="${this_command%.sh}"

	write_usock ${QUEUE_SOCKET} <<- EOF
	command: "${this_command}", arguments: "$@"
	EOF
	exit
}

jail_start() {
	[ $# -lt 2 ] && eargs jail_start name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local portsdir
	local arch
	local mnt
	local needfs="${NULLFSREF} procfs"
	local needkld="sem"
	local tomnt=${POUDRIERE_DATA}/build/${MASTERNAME}/ref

	_pget portsdir ${ptname} mnt
	_jget arch ${name} arch
	_jget mnt ${name} mnt

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
	for kld in ${needkld}; do
		if ! kldstat -q -m ${kld} ; then
			if [ $JAILED -eq 0 ]; then
				kldload ${kld} || err 1 "Required kernel module '${kld}' not found"
			else
				err 1 "Please load the ${kld} module on the host using \"kldload ${kld}\""
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

	JAIL_OSVERSION=$(awk '/\#define __FreeBSD_version/ { print $3 }' "${mnt}/usr/include/sys/param.h")

	if [ ${JAIL_OSVERSION} -gt ${HOST_OSVERSION} ]; then
		msg_warn "!!! Jail is newer than host. (Jail: ${JAIL_OSVERSION}, Host: ${HOST_OSVERSION}) !!!"
		msg_warn "This is not supported."
		msg_warn "Host kernel must be same or newer than jail."
		msg_warn "Expect build failures."
		sleep 5
	fi

	msg "Mounting system devices for ${MASTERNAME}"
	do_jail_mounts ${tomnt} ${arch}

	PACKAGES=${POUDRIERE_DATA}/packages/${MASTERNAME}

	[ -d "${portsdir}/ports" ] && portsdir="${portsdir}/ports"
	msg "Mounting ports/packages/distfiles"

	mkdir -p ${PACKAGES}/All ${PACKAGES}/Latest
	was_a_bulk_run && stash_packages

	do_portbuild_mounts ${tomnt} ${name} ${ptname} ${setname}

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
	jstart
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
	[ $# -lt 2 ] && eargs load_blacklist name ptname setname
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
			msg_warn "Blacklisting (from ${POUDRIERED}/${bfile}): ${COLOR_PORT}${port}"
			BLACKLIST="${BLACKLIST} ${port}"
		done
	done
}

setup_makeconf() {
	[ $# -lt 3 ] && eargs setup_makeconf dst_makeconf name ptname setname
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

	# We will handle DEVELOPER for testing when appropriate
	sed -i '' '/^DEVELOPER=/d' ${dst_makeconf}
}

jail_stop() {
	[ $# -ne 0 ] && eargs jail_stop
	local last_status

	jstop || :
	# Shutdown all builders
	if [ ${PARALLEL_JOBS} -ne 0 ]; then
		# - here to only check for unset, {start,stop}_builders will set this to blank if already stopped
		for j in ${JOBS-$(jot -w %02d ${PARALLEL_JOBS})}; do
			MY_JOBID=${j} jstop
			destroyfs ${MASTERMNT}/../${j} jail || :
		done
	fi
	msg "Umounting file systems"
	destroyfs ${MASTERMNT} jail || :
	rm -rf ${MASTERMNT}/../
	export STATUS=0

	# Don't override if there is a failure to grab the last status.
	_bget last_status status 2>/dev/null || :
	[ -n "${last_status}" ] && bset status "stopped:${last_status}" \
	    2>/dev/null || :
}

cleanup() {
	local wait_pids

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
				wait_pids="${wait_pids} ${pid}"
			done
			_wait ${wait_pids} || :
		fi

		jail_stop

		rm -rf \
		    ${POUDRIERE_DATA}/packages/${MASTERNAME}/.latest/.new_packages \
		    2>/dev/null || :

	fi

	rmdir "${POUDRIERE_DATA}/.lock-$$-*" 2>/dev/null || :

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
	[ $# -eq 1 ] || eargs sanity_check_pkg pkg
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
	[ $# -lt 1 ] && eargs check_leftovers mnt [stagedir]
	local mnt=$1
	local stagedir="$2"

	{
		if [ -z "${stagedir}" ]; then
			mtree -X ${mnt}/poudriere/mtree.preinstexclude \
			    -f ${mnt}/poudriere/mtree.preinst \
			    -p ${mnt}
		fi
	} | while read l ; do
		local changed read_again

		changed=
		while :; do
			read_again=0

			# Handle leftover read from changed paths
			case ${l} in
			*extra|*missing|extra:*|*changed|*:*)
				if [ -n "${changed}" ]; then
					echo "${changed}"
					changed=
				fi
				;;
			esac
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
			*changed)
				changed="M ${mnt}/${l% *}"
				read_again=1
				;;
			extra:*)
				if [ -d ${mnt}/${l#* } ]; then
					find ${mnt}/${l#* } -exec echo "+ {}" \;
				else
					echo "+ ${mnt}/${l#* }"
				fi
				;;
			*:*)
				changed="M ${mnt}/${l%:*} ${l#*:}"
				read_again=1
				;;
			*)
				changed="${changed} ${l}"
				read_again=1
				;;
			esac
			# Need to read again to find all changes
			[ ${read_again} -eq 1 ] && read l && continue
			[ -n "${changed}" ] && echo "${changed}"
			break
		done
	done
}

check_fs_violation() {
	[ $# -eq 6 ] || eargs check_fs_violation mnt mtree_target port \
	    status_msg err_msg status_value
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
		bset_job_status "${status_value}" "${port}"
		job_msg_verbose "Status for build ${COLOR_PORT}${port}${COLOR_RESET}: ${status_value}"
		ret=1
	fi
	rm -f ${tmpfile}

	return $ret
}

gather_distfiles() {
	[ $# -eq 3 ] || eargs gather_distfiles portdir from to
	local portdir="$1"
	local from=$(realpath $2)
	local to=$(realpath $3)
	local sub dists d tosubd specials special
	sub=$(injail make -C ${portdir} -VDIST_SUBDIR)
	dists=$(injail make -C ${portdir} -V_DISTFILES -V_PATCHFILES)
	specials=$(injail make -C ${portdir} -V_DEPEND_SPECIALS)
	job_msg_verbose "Status for build ${COLOR_PORT}${portdir##/usr/ports/}${COLOR_RESET}: distfiles ${from} -> ${to}"
	for d in ${dists}; do
		[ -f ${from}/${sub}/${d} ] || continue
		tosubd=${to}/${sub}/${d}
		mkdir -p ${tosubd%/*} || return 1
		cpdup ${from}/${sub}/${d} ${to}/${sub}/${d} || return 1
	done

	for special in ${specials}; do
		gather_distfiles ${special} ${from} ${to}
	done

	return 0
}

# Build+test port and return 1 on first failure
# Return 2 on test failure if PORTTESTING_FATAL=no
_real_build_port() {
	[ $# -ne 1 ] && eargs _real_build_port portdir
	local portdir=$1
	local port=${portdir##/usr/ports/}
	local mnt
	local log
	local listfilecmd network
	local hangstatus
	local pkgenv phaseenv
	local no_stage=$(injail make -C ${portdir} -VNO_STAGE)
	local targets install_order
	local stagedir
	local jailuser
	local testfailure=0
	local max_execution_time

	_my_path mnt
	_log_path log
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
		# XXX: run-depends can come out of here with some bsd.port.mk
		# changes. Easier once pkg_install is EOL.
		install_order="run-depends stage package"
		# Don't need to install if only making packages and not
		# testing.
		[ -n "${PORTTESTING}" ] && \
		    install_order="${install_order} install-mtree install"
		stagedir=$(injail make -C ${portdir} -VSTAGEDIR)
	fi
	targets="check-sanity pkg-depends fetch-depends fetch checksum \
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
		phaseenv=
		[ -z "${no_stage}" ] && JUSER=${jailuser}
		bset_job_status "${phase}" "${port}"
		job_msg_verbose "Status for build ${COLOR_PORT}${port}${COLOR_RESET}: ${COLOR_PHASE}${phase}"
		case ${phase} in
		check-sanity) [ -n "${PORTTESTING}" ] && phaseenv="DEVELOPER=1" ;;
		fetch)
			mkdir -p ${mnt}/portdistfiles
			echo "DISTDIR=/portdistfiles" >> ${mnt}/etc/make.conf
			gather_distfiles ${portdir} ${DISTFILES_CACHE} ${mnt}/portdistfiles || return 1
			JNETNAME="n"
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

		if [ "${phase#*-}" = "depends" ]; then
			# No need for nohang or PORT_FLAGS for *-depends
			injail env USE_PACKAGE_DEPENDS_ONLY=1 ${phaseenv} \
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
				${MASTERMNT}/poudriere/var/run/${MY_JOBID:-00}_nohang.pid \
				injail env ${pkgenv} ${phaseenv} ${PORT_FLAGS} \
				make -C ${portdir} ${phase}
			hangstatus=$? # This is done as it may return 1 or 2 or 3
			if [ $hangstatus -ne 0 ]; then
				# 1 = cmd failed, not a timeout
				# 2 = log timed out
				# 3 = cmd timeout
				if [ $hangstatus -eq 2 ]; then
					msg "Killing runaway build after ${NOHANG_TIME} seconds with no output"
					bset_job_status "${phase}/runaway" "${port}"
					job_msg_verbose "Status for build ${COLOR_PORT}${port}${COLOR_RESET}: ${COLOR_PHASE}runaway"
				elif [ $hangstatus -eq 3 ]; then
					msg "Killing timed out build after ${max_execution_time} seconds"
					bset_job_status "${phase}/timeout" "${port}"
					job_msg_verbose "Status for build ${COLOR_PORT}${port}${COLOR_RESET}: ${COLOR_PHASE}timeout"
				fi
				return 1
			fi
		fi

		if [ "${phase}" = "checksum" ]; then
			JNETNAME=""
		fi
		print_phase_footer

		if [ "${phase}" = "checksum" ]; then
			gather_distfiles ${portdir} ${mnt}/portdistfiles ${DISTFILES_CACHE} || return 1
		fi

		if [ "${phase}" = "stage" -a -n "${PORTTESTING}" ]; then
			local die=0

			bset_job_status "stage-qa" "${port}"
			if ! injail env DEVELOPER=1 ${PORT_FLAGS} \
			    make -C ${portdir} stage-qa; then
				msg "Error: stage-qa failures detected"
				[ "${PORTTESTING_FATAL}" != "no" ] &&
					return 1
				die=1
			fi

			bset_job_status "check-plist" "${port}"
			if ! injail env DEVELOPER=1 ${PORT_FLAGS} \
			    make -C ${portdir} check-plist; then
				msg "Error: check-plist failures detected"
				[ "${PORTTESTING_FATAL}" != "no" ] &&
					return 1
				die=1
			fi

			if [ ${die} -eq 1 ]; then
				testfailure=2
				die=0
			fi
		fi

		if [ "${phase}" = "deinstall" ]; then
			local add=$(mktemp ${mnt}/tmp/add.XXXXXX)
			local add1=$(mktemp ${mnt}/tmp/add1.XXXXXX)
			local del=$(mktemp ${mnt}/tmp/del.XXXXXX)
			local del1=$(mktemp ${mnt}/tmp/del1.XXXXXX)
			local mod=$(mktemp ${mnt}/tmp/mod.XXXXXX)
			local mod1=$(mktemp ${mnt}/tmp/mod1.XXXXXX)
			local die=0
			PREFIX=$(injail env ${PORT_FLAGS} make -C ${portdir} -VPREFIX)

			msg "Checking for extra files and directories"
			bset_job_status "leftovers" "${port}"

			if [ -f "${mnt}/usr/ports/Mk/Scripts/check_leftovers.sh" ]; then
				check_leftovers ${mnt} | sed -e "s|${mnt}||" |
				    injail env PORTSDIR=/usr/ports \
				    ${PORT_FLAGS} /bin/sh \
				    /usr/ports/Mk/Scripts/check_leftovers.sh \
				    ${port} | while read modtype data; do
					case "${modtype}" in
						+) echo "${data}" >> ${add} ;;
						-) echo "${data}" >> ${del} ;;
						M) echo "${data}" >> ${mod} ;;
					esac
				done
			else
				# LEGACY - Support for older ports tree.
				local users user homedirs plistsub_sed
				plistsub_sed=$(injail env ${PORT_FLAGS} make -C ${portdir} -V'PLIST_SUB:C/"//g:NLIB32*:NPERL_*:NPREFIX*:N*="":N*="@comment*:C/(.*)=(.*)/-es!\2!%%\1%%!g/')

				users=$(injail make -C ${portdir} -VUSERS)
				homedirs=""
				for user in ${users}; do
					user=$(grep ^${user}: ${mnt}/usr/ports/UIDs | cut -f 9 -d : | sed -e "s|/usr/local|${PREFIX}| ; s|^|${mnt}|")
					homedirs="${homedirs} ${user}"
				done

				check_leftovers ${mnt} | \
					while read modtype path extra; do
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
							*\ ${path}/*\ *) continue;;
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
						*) echo "${ppath#@dirrm } ${extra}" >> ${mod} ;;
						esac
						;;
					esac
				done
			fi

			sort ${add} > ${add1}
			sort ${del} > ${del1}
			sort ${mod} > ${mod1}
			comm -12 ${add1} ${del1} >> ${mod1}
			comm -23 ${add1} ${del1} > ${add}
			comm -13 ${add1} ${del1} > ${del}
			if [ -s "${add}" ]; then
				msg "Error: Files or directories left over:"
				die=1
				grep -v "^@dirrm" ${add}
				grep "^@dirrm" ${add} | sort -r
			fi
			if [ -s "${del}" ]; then
				msg "Error: Files or directories removed:"
				die=1
				cat ${del}
			fi
			if [ -s "${mod}" ]; then
				msg "Error: Files or directories modified:"
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

	bset_job_status "build_port_done" "${port}"
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
	[ $# -ne 4 ] && eargs save_wrkdir mnt port portdir phase
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

	job_msg "Saved ${COLOR_PORT}${port}${COLOR_RESET} wrkdir to: ${tarname}"
}

start_builder() {
	local id=$1
	local arch=$2
	local mnt

	export MY_JOBID=${id}
	_my_path mnt

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
	jstart
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
$(find ${MASTERMNT}/poudriere/building ${MASTERMNT}/poudriere/pool ${MASTERMNT}/poudriere/deps ${MASTERMNT}/poudriere/cleaning)"
}

queue_empty() {
	local pool_dir lock dirs
	local ret=0

	# Lock on balance_pool to avoid race here while it is moving between
	# /unbalanced and a balanced slot
	lock=${MASTERMNT}/poudriere/.lock-balance_pool
	mkdir ${lock} 2>/dev/null || return 1

	dirs="${MASTERMNT}/poudriere/deps ${MASTERMNT}/poudriere/pool/unbalanced ${POOL_BUCKET_DIRS}"

	for pool_dir in ${dirs}; do
		if ! dirempty ${pool_dir}; then
			ret=1
			break
		fi
	done

	rmdir ${lock}
	return ${ret}
}

mark_done() {
	[ $# -eq 1 ] || eargs mark_done pkgname
	local pkgname="$1"
	local origin
	local cache_dir

	if [ "${TRACK_BUILDTIMES}" != "no" ]; then
		cache_get_origin origin "${pkgname}"
		get_cache_dir cache_dir

		echo -n "${origin} $(date +%s) " >> ${cache_dir}/buildtimes
		stat -f "%m" ${MASTERMNT}/poudriere/building/${pkgname} >> \
			${cache_dir}/buildtimes
	fi
	rmdir ${MASTERMNT}/poudriere/building/${pkgname}
}


build_queue() {
	local j name pkgname builders_active queue_empty status

	mkfifo ${MASTERMNT}/poudriere/builders.pipe
	exec 6<> ${MASTERMNT}/poudriere/builders.pipe
	rm -f ${MASTERMNT}/poudriere/builders.pipe
	queue_empty=0

	msg "Hit CTRL+t at any time to see build progress and stats"

	cd "${MASTERMNT}/poudriere/pool"

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
				_bget status ${j} status
				if [ "${status%%:*}" = "done" ]; then
					mark_done ${pkgname}
					bset ${j} status "idle:"
				else
					bset ${j} status "crashed:"
				fi
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

calculate_tobuild() {
	local nbq nbb nbf nbi nbsndone nremaining

	_bget nbq stats_queued 2>/dev/null || nbq=0
	_bget nbb stats_built 2>/dev/null || nbb=0
	_bget nbf stats_failed 2>/dev/null || nbf=0
	_bget nbi stats_ignored 2>/dev/null || nbi=0
	_bget nbs stats_skipped 2>/dev/null || nbs=0

	ndone=$((nbb + nbf + nbi + nbs))
	nremaining=$((nbq - ndone))

	echo ${nremaining}
}

status_is_stopped() {
	[ $# -eq 1 ] || eargs status_is_stopped status
	local status="$1"
	case "${status}" in
		sigterm:|sigint:|crashed:|stop:|stopped:*) return 0 ;;
	esac
	return 1
}

calculate_elapsed() {
	[ $# -eq 2 ] || eargs calculate_elapsed now log
	local now="$1"
	local log="$2"

	[ -f "${log}/.poudriere.status" ] || return 1
	start_end_time=$(stat -f '%B %m' ${log}/.poudriere.status)
	start_time=${start_end_time% *}
	if status_is_stopped "${status}"; then
		end_time=${start_end_time#* }
	else
		end_time=${now}
	fi
	_start_time=${start_time}
	_end_time=${end_time}
	_elapsed_time=$((${end_time} - ${start_time}))
	return 0
}

madvise_protect() {
	[ $# -eq 1 ] || eargs madvise_protect pid
	[ -f /usr/bin/protect ] || return 0
	/usr/bin/protect -p "$1" 2>/dev/null || :
	return 0
}

# Build ports in parallel
# Returns when all are built.
parallel_build() {
	local jname=$1
	local ptname=$2
	local setname=$3
	local real_parallel_jobs=${PARALLEL_JOBS}
	local nremaining=$(calculate_tobuild)

	# Subtract the 1 for the main port to test
	[ "${0##*/}" = "testport.sh" ] && nremaining=$((${nremaining} - 1))

	# If pool is empty, just return
	[ ${nremaining} -eq 0 ] && return 0

	# Minimize PARALLEL_JOBS to queue size
	[ ${PARALLEL_JOBS} -gt ${nremaining} ] && PARALLEL_JOBS=${nremaining##* }

	msg "Building ${nremaining} packages using ${PARALLEL_JOBS} builders"
	JOBS="$(jot -w %02d ${PARALLEL_JOBS})"

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

	bset status "updating_stats:"
	update_stats

	bset status "idle:"

	# Close the builder socket
	exec 5>&-

	# Restore PARALLEL_JOBS
	PARALLEL_JOBS=${real_parallel_jobs}

	return 0
}

clean_pool() {
	[ $# -ne 2 ] && eargs clean_pool pkgname clean_rdepends
	local pkgname=$1
	local clean_rdepends=$2
	local port skipped_origin

	[ -n "${MY_JOBID}" ] && bset ${MY_JOBID} status "clean_pool:"

	[ ${clean_rdepends} -eq 1 ] && cache_get_origin port "${pkgname}"

	# Cleaning queue (pool is cleaned here)
	sh ${SCRIPTPREFIX}/clean.sh "${MASTERMNT}" "${pkgname}" ${clean_rdepends} | sort -u | while read skipped_pkgname; do
		cache_get_origin skipped_origin "${skipped_pkgname}"
		badd ports.skipped "${skipped_origin} ${skipped_pkgname} ${pkgname}"
		COLOR_ARROW="${COLOR_SKIP}" \
		    job_msg "${COLOR_SKIP}Skipping build of ${COLOR_PORT}${skipped_origin}${COLOR_SKIP}: Dependent port ${COLOR_PORT}${port}${COLOR_SKIP} failed"
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
	[ $# -ne 1 ] && eargs build_pkg pkgname
	local pkgname="$1"
	local port portdir
	local build_failed=0
	local name
	local mnt
	local failed_status failed_phase cnt
	local clean_rdepends=0
	local log
	local ignore
	local errortype
	local ret=0

	_my_path mnt
	_my_name name
	_log_path log
	trap '' SIGTSTP
	[ -n "${MAX_MEMORY}" ] && ulimit -v ${MAX_MEMORY_BYTES}

	export PKGNAME="${pkgname}" # set ASAP so cleanup() can use it
	cache_get_origin port "${pkgname}"
	portdir="/usr/ports/${port}"

	TIME_START_JOB=$(date +%s)
	# Don't show timestamps in msg() which goes to logs, only job_msg()
	# which goes to master
	NO_ELAPSED_IN_MSG=1
	colorize_job_id COLOR_JOBID "${MY_JOBID}"

	job_msg "Starting build of ${COLOR_PORT}${port}${COLOR_RESET}"
	bset_job_status "starting" "${port}"

	if [ ${TMPFS_LOCALBASE} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		umount -f ${mnt}/${LOCALBASE:-/usr/local} 2>/dev/null || :
		mnt_tmpfs localbase ${mnt}/${LOCALBASE:-/usr/local}
	fi

	# Stop everything first
	jstop
	[ -f ${mnt}/.need_rollback ] && rollbackfs prepkg ${mnt}
	# Make sure we start with no network
	jstart

	:> ${mnt}/.need_rollback

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
		COLOR_ARROW="${COLOR_IGNORE}" job_msg "${COLOR_IGNORE}Finished build of ${COLOR_PORT}${port}${COLOR_IGNORE}: Ignored: ${ignore}"
		clean_rdepends=1
		run_hook pkgbuild ignored "${port}" "${PKGNAME}" "${ignore}"
	else
		injail make -C ${portdir} clean
		build_port ${portdir} || ret=$?
		if [ ${ret} -ne 0 ]; then
			build_failed=1
			# ret=2 is a test failure
			if [ ${ret} -eq 2 ]; then
				failed_phase=$(awk -f ${AWKPREFIX}/processonelog2.awk \
					${log}/logs/${PKGNAME}.log \
					2> /dev/null)
			else
				_bget failed_status ${MY_JOBID} status
				failed_phase=${failed_status%%:*}
			fi

			save_wrkdir ${mnt} "${port}" "${portdir}" "${failed_phase}" || :
		elif [ -f ${mnt}/${portdir}/.keep ]; then
			save_wrkdir ${mnt} "${port}" "${portdir}" "noneed" ||:
		fi

		injail make -C ${portdir} clean

		if [ ${build_failed} -eq 0 ]; then
			badd ports.built "${port} ${PKGNAME}"
			COLOR_ARROW="${COLOR_SUCCESS}" job_msg "${COLOR_SUCCESS}Finished build of ${COLOR_PORT}${port}${COLOR_SUCCESS}: Success"
			run_hook pkgbuild success "${port}" "${PKGNAME}"
			# Cache information for next run
			pkg_cache_data "${PACKAGES}/All/${PKGNAME}.${PKG_EXT}" ${port} || :
		else
			# Symlink the buildlog into errors/
			ln -s ../${PKGNAME}.log ${log}/logs/errors/${PKGNAME}.log
			errortype=$(/bin/sh ${SCRIPTPREFIX}/processonelog.sh \
				${log}/logs/errors/${PKGNAME}.log \
				2> /dev/null)
			badd ports.failed "${port} ${PKGNAME} ${failed_phase} ${errortype}"
			COLOR_ARROW="${COLOR_FAIL}" job_msg "${COLOR_FAIL}Finished build of ${COLOR_PORT}${port}${COLOR_FAIL}: Failed: ${COLOR_PHASE}${failed_phase}"
			run_hook pkgbuild failed "${port}" "${PKGNAME}" "${failed_phase}" \
				"${log}/logs/errors/${PKGNAME}.log"
			# ret=2 is a test failure
			if [ ${ret} -eq 2 ]; then
				clean_rdepends=0
			else
				clean_rdepends=1
			fi
		fi
	fi

	clean_pool ${PKGNAME} ${clean_rdepends}

	stop_build ${portdir} ${build_failed}

	bset ${MY_JOBID} status "done:"

	echo ${MY_JOBID} >&6
}

stop_build() {
	[ $# -eq 2 ] || eargs stop_build portdir build_failed
	local portdir="$1"
	local build_failed="$2"
	local mnt

	_my_path mnt
	umount -f ${mnt}/new_packages 2>/dev/null || :
	rm -rf "${PACKAGES}/.new_packages/${PKGNAME}"

	# 2 = HEADER+ps itself
	if [ $(injail ps aux | wc -l) -ne 2 ]; then
		msg_warn "Leftover processes:"
		injail ps auxwwd | grep -v 'ps auxwwd'
	fi
	# Always kill to avoid missing anything
	injail kill -9 -1 2>/dev/null || :

	buildlog_stop ${portdir} ${build_failed}
	log_stop
}

# Crazy redirection is to add the portname into stderr.
# Idea from http://superuser.com/a/453609/34747
mangle_stderr() {
	local msg_start="$1"
	local extra="$2"
	local msg_end="$3"
	local - # Make `set +x` local

	shift 3

	set +x

	{
		{
			{
				{
					"$@"
				} 2>&3
			} 3>&1 1>&2 | \
				awk \
				    -v msg_start="${msg_start}" \
				    -v msg_end="${msg_end}" \
				    -v extra="${extra}" \
				    '{print msg_start, extra ":", $0, msg_end}' 1>&3
		} 3>&2 2>&1
	}
}

list_deps() {
	[ $# -ne 1 ] && eargs list_deps directory
	local dir="/usr/ports/$1"
	local makeargs="-VPKG_DEPENDS -VBUILD_DEPENDS -VEXTRACT_DEPENDS -VLIB_DEPENDS -VPATCH_DEPENDS -VFETCH_DEPENDS -VRUN_DEPENDS"

	mangle_stderr "${COLOR_WARN}WARNING" \
		"(${COLOR_PORT}$1${COLOR_RESET})${COLOR_WARN}" \
		"${COLOR_RESET}" \
		injail make -C ${dir} $makeargs | \
		sed -e "s,[[:graph:]]*/usr/ports/,,g" \
		-e "s,:[[:graph:]]*,,g" -e '/^$/d' | tr ' ' '\n' | \
		sort -u || err 1 "Makefile broken: $1"
}

deps_file() {
	[ $# -ne 2 ] && eargs deps_file var_return pkg
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
	[ $# -lt 2 ] && eargs pkg_get_origin var_return pkg
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
		read_line _origin "${originfile}"
	fi

	check_moved new_origin ${_origin} && _origin=${new_origin}

	setvar "${var_return}" "${_origin}"
}

pkg_get_dep_origin() {
	[ $# -ne 2 ] && eargs pkg_get_dep_origin var_return pkg
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
			compiled_dep_origins="${compiled_dep_origins} ${line}"
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
	[ $# -ne 2 ] && eargs pkg_get_options var_return pkg
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
	local mnt

	_my_path mnt
	[ ${PKGNG} -eq 1 ] || return 0
	[ -x ${mnt}/poudriere/pkg-static ] && return 0
	[ -e ${MASTERMNT}/packages/Latest/pkg.txz ] || return 1 #pkg missing
	injail tar xf /packages/Latest/pkg.txz -C / \
		-s ",/.*/,poudriere/,g" "*/pkg-static"
	return 0
}

pkg_cache_data() {
	[ $# -ne 2 ] && eargs pkg_cache_data pkg origin
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
	[ $# -lt 2 ] && eargs get_pkg_cache_dir var_return pkg
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
	[ $# -ne 1 ] && eargs clear_pkg_cache pkg
	local pkg="$1"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	rm -fr "${pkg_cache_dir}"
}

delete_pkg() {
	[ $# -ne 1 ] && eargs delete_pkg pkg
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
	[ $# -eq 1 ] || eargs delete_old_pkg pkgname
	local pkg="$1"
	local mnt pkgname cached_pkgname
	local o v v2 compiled_options current_options current_deps compiled_deps

	pkg_get_origin o "${pkg}"
	port_is_needed "${o}" || return 0

	_my_path mnt

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
		msg "Deleting ${pkg##*/}: new version: ${v2}"
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
			msg "Deleting ${pkg##*/}: changed options"
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
	[ $# -ne 1 ] && eargs lock_acquire lockname
	local lockname=$1

	until mkdir ${POUDRIERE_DATA}/.lock-$$-${MASTERNAME}-${lockname} \
	    2>/dev/null; do
		sleep 0.1
	done
}

lock_release() {
	[ $# -ne 1 ] && eargs lock_release lockname
	local lockname=$1

	rmdir ${POUDRIERE_DATA}/.lock-$$-${MASTERNAME}-${lockname} 2>/dev/null
}

cache_get_pkgname() {
	[ $# -ne 2 ] && eargs cache_get_pkgname var_return origin
	local var_return="$1"
	local origin=${2%/}
	local _pkgname="" existing_origin
	local cache_origin_pkgname=${MASTERMNT}/poudriere/var/cache/origin-pkgname/${origin%%/*}_${origin##*/}
	local cache_pkgname_origin

	[ -f ${cache_origin_pkgname} ] && read_line _pkgname "${cache_origin_pkgname}"

	# Add to cache if not found.
	if [ -z "${_pkgname}" ]; then
		[ -d "${MASTERMNT}/usr/ports/${origin}" ] ||
			err 1 "Invalid port origin '${COLOR_PORT}${origin}${COLOR_RESET}' not found."
		_pkgname=$(injail make -C /usr/ports/${origin} -VPKGNAME ||
			err 1 "Error getting PKGNAME for ${COLOR_PORT}${origin}${COLOR_RESET}")
		[ -n "${_pkgname}" ] || err 1 "Missing PKGNAME for ${COLOR_PORT}${origin}${COLOR_RESET}"
		# Make sure this origin did not already exist
		cache_get_origin existing_origin "${_pkgname}" 2>/dev/null || :
		# It may already exist due to race conditions, it is not harmful. Just ignore.
		if [ "${existing_origin}" != "${origin}" ]; then
			[ -n "${existing_origin}" ] &&
				err 1 "Duplicated origin for ${_pkgname}: ${COLOR_PORT}${origin}${COLOR_RESET} AND ${COLOR_PORT}${existing_origin}${COLOR_RESET}. Rerun with -vv to see which ports are depending on these."
			echo "${_pkgname}" > ${cache_origin_pkgname}
			cache_pkgname_origin="${MASTERMNT}/poudriere/var/cache/pkgname-origin/${_pkgname}"
			echo "${origin}" > "${cache_pkgname_origin}"
		fi
	fi

	setvar "${var_return}" "${_pkgname}"
}

cache_get_origin() {
	[ $# -ne 2 ] && eargs cache_get_origin var_return pkgname
	local var_return="$1"
	local pkgname="$2"
	local cache_pkgname_origin="${MASTERMNT}/poudriere/var/cache/pkgname-origin/${pkgname}"
	local _origin

	read_line _origin "${cache_pkgname_origin%/}"

	setvar "${var_return}" "${_origin}"
}

compute_deps() {
	local port pkgname dep_pkgname

	msg "Calculating ports order and dependencies"
	bset status "computingdeps:"

	:> "${MASTERMNT}/poudriere/port_deps.unsorted"
	:> "${MASTERMNT}/poudriere/pkg_deps.unsorted"

	parallel_start
	for port in $(listed_ports show_moved); do
		if [ -d "${MASTERMNT}/usr/ports/${port}" ]; then
			parallel_run compute_deps_port ${port}
		else
			if [ ${ALL} -eq 1 ]; then
				msg_warn "Invalid port origin listed in category Makefiles: ${COLOR_PORT}${port}"
			else
				err 1 "Invalid port origin listed for build: ${COLOR_PORT}${port}"
			fi
		fi
	done
	parallel_stop

	sort -u "${MASTERMNT}/poudriere/pkg_deps.unsorted" > \
	    "${MASTERMNT}/poudriere/pkg_deps"

	bset status "computingrdeps:"

	# cd into rdeps to allow xargs mkdir to have more args.
	cd "${MASTERMNT}/poudriere/rdeps"
	awk '{print $2}' "${MASTERMNT}/poudriere/pkg_deps" |
	    sort -u | xargs mkdir

	# xargs|touch was no quicker here.
	while read dep_pkgname pkgname; do
		:> "${MASTERMNT}/poudriere/rdeps/${pkgname}/${dep_pkgname}"
	done < "${MASTERMNT}/poudriere/pkg_deps"

	sort -u "${MASTERMNT}/poudriere/port_deps.unsorted" > \
		"${MASTERMNT}/poudriere/port_deps"

	rm -f "${MASTERMNT}/poudriere/port_deps.unsorted" \
	    "${MASTERMNT}/poudriere/pkg_deps.unsorted"

	return 0
}

# Take optional pkgname to speedup lookup
compute_deps_port() {
	[ $# -lt 1 ] && eargs compute_deps_port port
	[ $# -gt 2 ] && eargs compute_deps_port port pkgnme
	local port=$1
	local pkgname="$2"
	local dep_pkgname dep_port
	local pkg_pooldir

	[ -z "${pkgname}" ] && cache_get_pkgname pkgname "${port}"
	pkg_pooldir="${MASTERMNT}/poudriere/deps/${pkgname}"

	mkdir "${pkg_pooldir}" 2>/dev/null || return 0

	msg_verbose "Computing deps for ${COLOR_PORT}${port}"

	for dep_port in `list_deps ${port}`; do
		msg_debug "${port} depends on ${COLOR_PORT}${dep_port}"
		[ "${port}" != "${dep_port}" ] ||
			err 1 "${port} incorrectly depends on itself. Please contact maintainer of the port to fix this."
		# Detect bad cat/origin/ dependency which pkgng will not register properly
		[ "${dep_port}" = "${dep_port%/}" ] ||
			err 1 "${COLOR_PORT}${port}${COLOR_RESET} depends on bad origin '${COLOR_PORT}${dep_port}${COLOR_RESET}'; Please contact maintainer of the port to fix this."
		cache_get_pkgname dep_pkgname "${dep_port}"

		# Only do this if it's not already done, and not ALL, as everything will
		# be touched anyway
		[ ${ALL} -eq 0 ] && ! [ -d "${MASTERMNT}/poudriere/deps/${dep_pkgname}" ] &&
			compute_deps_port "${dep_port}" "${dep_pkgname}"

		:> "${pkg_pooldir}/${dep_pkgname}"
		echo "${pkgname} ${dep_pkgname}" >> \
		    "${MASTERMNT}/poudriere/pkg_deps.unsorted"
		echo "${port} ${dep_port}" >> \
			${MASTERMNT}/poudriere/port_deps.unsorted
	done
}

listed_ports() {
	local tell_moved="${1}"

	if [ ${ALL} -eq 1 ]; then
		_pget PORTSDIR ${PTNAME} mnt
		[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
		for cat in $(awk '$1 == "SUBDIR" { print $3}' ${PORTSDIR}/Makefile); do
			awk -v cat=${cat} '$1 == "SUBDIR" { print cat"/"$3}' ${PORTSDIR}/${cat}/Makefile
		done
		return 0
	fi

	{
		# -f specified
		if [ -z "${LISTPORTS}" ]; then
			[ -n "${LISTPKGS}" ] &&
			    grep -h -v -E \
			    '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS} |
			    sed 's,/*$,,'
		else
			# Ports specified on cmdline
			echo ${LISTPORTS} | tr ' ' '\n' | sed 's,/*$,,'
		fi
	} | while read origin; do
		if check_moved new_origin ${origin}; then
			[ -n "${tell_moved}" ] && msg \
			    "MOVED: ${origin} renamed to ${new_origin}" >&2
			origin=${new_origin}
		fi
		echo "${origin}"
	done
}

# Port was requested to be built
port_is_listed() {
	[ $# -eq 1 ] || eargs port_is_listed origin
	local origin="$1"

	if [ ${ALL} -eq 1 -o ${PORTTESTING_RECURSIVE} -eq 1 ]; then
		return 0
	fi

	listed_ports | grep -q "^${origin}\$" && return 0

	return 1
}

# Port was requested to be built, or is needed by a port requested to be built
port_is_needed() {
	[ $# -eq 1 ] || eargs port_is_needed origin
	local origin="$1"

	[ ${ALL} -eq 1 ] && return 0

	awk -vorigin="${origin}" '
	    $1 == origin || $2 == origin { found=1; exit 0 }
	    END { if (found != 1) exit 1 }' "${MASTERMNT}/poudriere/port_deps"
}

get_porttesting() {
	[ $# -eq 1 ] || eargs get_porttesting pkgname
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

find_all_pool_references() {
	[ $# -ne 1 ] && eargs find_all_pool_references pkgname
	local pkgname="$1"
	local rpn dep_pkgname

	# Cleanup rdeps/*/${pkgname}
	for rpn in ${MASTERMNT}/poudriere/deps/${pkgname}/*; do
		case "${rpn}" in
			"${MASTERMNT}/poudriere/deps/${pkgname}/*")
				break ;;
		esac
		dep_pkgname=${rpn##*/}
		echo "${MASTERMNT}/poudriere/rdeps/${dep_pkgname}/${pkgname}"
	done
	echo "${MASTERMNT}/poudriere/deps/${pkgname}"
	# Cleanup deps/*/${pkgname}
	for rpn in ${MASTERMNT}/poudriere/rdeps/${pkgname}/*; do
		case "${rpn}" in
			"${MASTERMNT}/poudriere/rdeps/${pkgname}/*")
				break ;;
		esac
		dep_pkgname=${rpn##*/}
		echo "${MASTERMNT}/poudriere/deps/${dep_pkgname}/${pkgname}"
	done
	echo "${MASTERMNT}/poudriere/rdeps/${pkgname}"
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
	[ $# -lt 2 ] && eargs check_moved var_return origin
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
	local log
	local n pn nbq resuming_build
	local cache_dir

	_log_path log
	mkdir -p "${MASTERMNT}/poudriere"
	[ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ] && mnt_tmpfs data "${MASTERMNT}/poudriere"
	rm -rf "${MASTERMNT}/poudriere/var/cache/origin-pkgname" \
		"${MASTERMNT}/poudriere/var/cache/pkgname-origin" 2>/dev/null || :
	mkdir -p "${MASTERMNT}/poudriere/building" \
		"${MASTERMNT}/poudriere/pool" \
		"${MASTERMNT}/poudriere/pool/unbalanced" \
		"${MASTERMNT}/poudriere/deps" \
		"${MASTERMNT}/poudriere/rdeps" \
		"${MASTERMNT}/poudriere/cleaning/deps" \
		"${MASTERMNT}/poudriere/cleaning/rdeps" \
		"${MASTERMNT}/poudriere/var/run" \
		"${MASTERMNT}/poudriere/var/cache" \
		"${MASTERMNT}/poudriere/var/cache/origin-pkgname" \
		"${MASTERMNT}/poudriere/var/cache/pkgname-origin"

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

		show_log_info
		start_html_json
	fi

	load_moved

	compute_deps

	bset status "sanity:"

	if [ -f ${PACKAGES}/.jailversion ]; then
		if [ "$(cat ${PACKAGES}/.jailversion)" != \
		    "$(jget ${JAILNAME} version)" ]; then
			JAIL_NEEDS_CLEAN=1
		fi
	fi

	if was_a_bulk_run; then
		[ ${JAIL_NEEDS_CLEAN} -eq 1 ] &&
		    msg_n "Cleaning all packages due to newer version of the jail..."

		[ ${CLEAN} -eq 1 ] &&
		    msg_n "(-c): Cleaning all packages..."

		if [ ${JAIL_NEEDS_CLEAN} -eq 1 ] || [ ${CLEAN} -eq 1 ]; then
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

			if [ ${SKIP_RECURSIVE_REBUILD} -eq 0 ]; then
				msg_verbose "Checking packages for missing dependencies"
				while :; do
					sanity_check_pkgs && break
				done
			else
				msg "(-S) Skipping recursive rebuild"
			fi

			delete_stale_symlinks_and_empty_dirs
		fi
	else
		msg "(-s) Skipping incremental rebuild and repository sanity checks"
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
		# Add 1 for the main port to test
		[ "${0##*/}" = "testport.sh" ] && nbq=$((${nbq} + 1))
		bset stats_queued ${nbq##* }
	fi

	# Create a pool of ready-to-build from the deps pool
	find "${MASTERMNT}/poudriere/deps" -type d -empty -depth 1 | \
		xargs -J % mv % "${MASTERMNT}/poudriere/pool/unbalanced"
	load_priorities
	balance_pool

	[ -n "${ALLOW_MAKE_JOBS}" ] || echo "DISABLE_MAKE_JOBS=poudriere" \
	    >> ${MASTERMNT}/etc/make.conf

	jget ${JAILNAME} version > ${PACKAGES}/.jailversion

	return 0
}

load_priorities() {
	local priority pkgname pkg_boost boosted origin
	local - # Keep set -f local

	POOL_BUCKET_DIRS=""
	if [ ${POOL_BUCKETS} -gt 0 ]; then
		tsort -D "${MASTERMNT}/poudriere/pkg_deps" > \
		    "${MASTERMNT}/poudriere/pkg_deps.depth"

		# Create buckets to satisfy the dependency chains, in reverse
		# order. Not counting here as there may be boosted priorities
		# at 99 or other high values.
		POOL_BUCKET_DIRS=$(awk '{print $1}' \
		    "${MASTERMNT}/poudriere/pkg_deps.depth"|sort -run)

		# If there are no buckets then everything to build will fall
		# into 0 as they depend on nothing and nothing depends on them.
		# I.e., pkg-devel in -ac or testport on something with no deps
		# needed.
		[ -z "${POOL_BUCKET_DIRS}" ] && POOL_BUCKET_DIRS="0"
	else
		POOL_BUCKET_DIRS="unbalanced"
	fi

	set -f # for PRIORITY_BOOST
	boosted=0
	while read priority pkgname; do
		# Does this pkg have an override?
		for pkg_boost in ${PRIORITY_BOOST}; do
			case ${pkgname%-*} in
				${pkg_boost})
					cache_get_origin origin "${pkgname}"
					msg "Boosting priority: ${origin}"
					priority=99
					boosted=1
					break
					;;
			esac
		done
		hash_set "priority" "${pkgname}" ${priority}
	done < "${MASTERMNT}/poudriere/pkg_deps.depth"

	# Add 99 into the pool if needed.
	[ ${boosted} -eq 1 ] && POOL_BUCKET_DIRS="99 ${POOL_BUCKET_DIRS}"

	# Create buckets after loading priorities in case of boosts.
	( cd ${MASTERMNT}/poudriere/pool && mkdir ${POOL_BUCKET_DIRS} )

	return 0
}

balance_pool() {
	# Don't bother if disabled
	[ ${POOL_BUCKETS} -gt 0 ] || return 0

	local pkgname pkg_dir dep_count lock

	# Avoid running this in parallel, no need
	lock=${MASTERMNT}/poudriere/.lock-balance_pool
	mkdir ${lock} 2>/dev/null || return 0

	if dirempty ${MASTERMNT}/poudriere/pool/unbalanced; then
		rmdir ${lock}
		return 0
	fi

	if [ -n "${MY_JOBID}" ]; then
		bset ${MY_JOBID} status "balancing_pool:"
	else
		bset status "balancing_pool:"
	fi

	# For everything ready-to-build...
	for pkg_dir in ${MASTERMNT}/poudriere/pool/unbalanced/*; do
		pkgname=${pkg_dir##*/}
		hash_get "priority" "${pkgname}" dep_count || dep_count=0
		mv ${pkg_dir} ${MASTERMNT}/poudriere/pool/${dep_count}/
	done

	rmdir ${lock}
}

append_make() {
	[ $# -ne 2 ] && eargs append_make src_makeconf dst_makeconf
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
	# For pkg_install remove packages that have lost one of their dependency
	if [ ${PKGNG} -eq 0 ]; then
		msg_verbose "Checking packages for missing dependencies"
		while :; do
			sanity_check_pkgs && break
		done

		delete_stale_symlinks_and_empty_dirs
	fi
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
		elif [ "${PKG_REPO_FROM_HOST:-no}" = "yes" ]; then
			# Sometimes building repo from host is needed if
			# using SSH with DNSSEC as older hosts don't support
			# it.
			${MASTERMNT}/poudriere/pkg-static repo \
			    -o ${MASTERMNT}/tmp/packages ${MASTERMNT}/packages \
			    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
		else
			JNETNAME="n" injail /poudriere/pkg-static repo \
			    -o /tmp/packages /packages \
			    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
		fi
		cp ${MASTERMNT}/tmp/packages/* ${PACKAGES}/
	else
		msg "Preparing INDEX"
		bset status "index:"
		OSMAJ=`injail uname -r | awk -F. '{ print $1 }'`
		INDEXF=${PACKAGES}/INDEX-${OSMAJ}
		rm -f ${INDEXF}.1 2>/dev/null || :
		injail env INDEX_JOBS=${PARALLEL_JOBS} INDEXDIR=/ make -C /usr/ports index
		awk -F\| -v pkgdir=${PACKAGES} \
			'{ if (system( "[ -f ${PACKAGES}/All/"$1".tbz ] " )  == 0) { print $0 } }' \
			${MASTERMNT}/INDEX-${OSMAJ} > ${INDEXF}

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
PATH="${LIBEXECPREFIX}:${PATH}:/sbin:/usr/sbin"

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
# Use a function as it is shared logic with read_file()
enable_siginfo_handler() {
	was_a_bulk_run && trap siginfo_handler SIGINFO
	return 0
}
enable_siginfo_handler

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

HOST_OSVERSION="$(sysctl -n kern.osreldate)"
if [ -z "${NO_ZFS}" -a -z "${ZFS_DEADLOCK_IGNORED}" ]; then
	[ ${HOST_OSVERSION} -gt 900000 -a \
	    ${HOST_OSVERSION} -le 901502 ] && err 1 \
	    "FreeBSD 9.1 ZFS is not safe. It is known to deadlock and cause system hang. Either upgrade the host or set ZFS_DEADLOCK_IGNORED=yes in poudriere.conf"
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
	ipargs="ip6=inherit"
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

NCPU=$(sysctl -n hw.ncpu)

case ${PARALLEL_JOBS} in
''|*[!0-9]*)
	PARALLEL_JOBS=${NCPU}
	;;
esac

case ${POOL_BUCKETS} in
''|*[!0-9]*)
	# 1 will auto determine proper size, 0 disables.
	POOL_BUCKETS=1
	;;
esac

if [ "${PRESERVE_TIMESTAMP:-no}" = "yes" ]; then
	SVN_PRESERVE_TIMESTAMP="--config-option config:miscellany:use-commit-times=yes"
fi

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
: ${JAIL_NEEDS_CLEAN:=0}
: ${VERBOSE:=0}
: ${PORTTESTING_FATAL:=yes}
: ${PORTTESTING_RECURSIVE:=0}
: ${RESTRICT_NETWORKING:=yes}
# - must be last
: ${HASH_VAR_NAME_SUB_GLOB:="[/.+,-]"}

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
: ${USE_COLORS:=yes}

: ${BUILDNAME_FORMAT:="%Y-%m-%d_%Hh%Mm%Ss"}
: ${BUILDNAME:=$(date +${BUILDNAME_FORMAT})}
: ${DURATION_FORMAT:="%H:%M:%S"}

if [ -n "${MAX_MEMORY}" ]; then
	MAX_MEMORY_BYTES="$((${MAX_MEMORY} * 1024 * 1024 * 1024))"
	MAX_MEMORY_JEXEC="/usr/bin/limits -v ${MAX_MEMORY_BYTES}"
fi

TIME_START=$(date +%s)

[ -d ${WATCHDIR} ] || mkdir -p ${WATCHDIR}

. $(dirname ${0})/include/display.sh
. $(dirname ${0})/include/html.sh
. $(dirname ${0})/include/messages.sh
. $(dirname ${0})/include/parallel.sh
. $(dirname ${0})/include/hash.sh
. $(dirname ${0})/include/fs.sh
