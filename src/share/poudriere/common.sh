#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2010-2011 Julien Laffaye <jlaffaye@FreeBSD.org>
# Copyright (c) 2012-2017 Bryan Drewery <bdrewery@FreeBSD.org>
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
. ${SCRIPTPREFIX}/include/common.sh.${BSDPLATFORM}
BLACKLIST=""
EX_SOFTWARE=70

# Return true if ran from bulk/testport, ie not daemon/status/jail
was_a_bulk_run() {
	[ "${SCRIPTPATH##*/}" = "bulk.sh" ] || was_a_testport_run
}
was_a_testport_run() {
	[ "${SCRIPTPATH##*/}" = "testport.sh" ]
}
# Return true if in a bulk or other jail run that needs to shutdown the jail
was_a_jail_run() {
	was_a_bulk_run ||  [ "${SCRIPTPATH##*/}" = "pkgclean.sh" ]
}
# Return true if output via msg() should show elapsed time
should_show_elapsed() {
	[ -z "${TIME_START}" ] && return 1
	[ "${NO_ELAPSED_IN_MSG:-0}" -eq 1 ] && return 1
	case "${SCRIPTPATH##*/}" in
		daemon.sh) ;;
		help.sh) ;;
		queue.sh) ;;
		status.sh) ;;
		version.sh) ;;
		*) return 0 ;;
	esac
	return 1
}

not_for_os() {
	local os=$1
	shift
	[ "${os}" = "${BSDPLATFORM}" ] && err 1 "This is not supported on ${BSDPLATFORM}: $@"
}

err() {
	if [ -n "${IGNORE_ERR}" ]; then
		return 0
	fi
	trap '' SIGINFO
	export CRASHED=1
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	# Try to set status so other processes know this crashed
	# Don't set it from children failures though, only master
	if [ -z "${PARALLEL_CHILD}" ] && was_a_bulk_run; then
		if [ -n "${MY_JOBID}" ]; then
			bset ${MY_JOBID} status "${EXIT_STATUS:-crashed:}" \
			    2>/dev/null || :
		else
			bset status "${EXIT_STATUS:-crashed:}" 2>/dev/null || :
		fi
	fi
	if [ ${1} -eq 0 ]; then
		msg "$2" || :
	else
		msg_error "$2" || :
	fi
	if [ -n "${ERRORS_ARE_DEP_FATAL}" ]; then
		set_dep_fatal_error
	fi
	# Avoid recursive err()->exit_handler()->err()... Just let
	# exit_handler() cleanup.
	if [ ${ERRORS_ARE_FATAL:-1} -eq 1 ]; then
		exit $1
	else
		return 0
	fi
}

# Message functions that depend on VERBOSE are stubbed out in post_getopts.

_msg_n() {
	local -; set +x
	local now elapsed
	local NL="${1}"
	local arrow DRY_MODE
	shift 1

	if [ "${MSG_NESTED:-0}" -eq 1 ]; then
		unset elapsed arrow DRY_MODE
	elif should_show_elapsed; then
		now=$(clock -monotonic)
		calculate_duration elapsed "$((${now} - ${TIME_START:-0}))"
		elapsed="[${elapsed}] "
		unset arrow
	else
		unset elapsed
		arrow="=>>"
	fi
	if [ -n "${COLOR_ARROW}" ] || [ -z "${1##*\033[*}" ]; then
		printf "${elapsed}${DRY_MODE}${arrow:+${COLOR_ARROW}${arrow}${COLOR_RESET} }${1}${COLOR_RESET}${NL}"
	else
		printf "${elapsed}${DRY_MODE}${arrow:+${arrow} }${1}${NL}"
	fi
}

msg_n() {
	_msg_n '' "$@"
}

msg() {
	_msg_n "\n" "$@"
}

msg_verbose() {
	_msg_n "\n" "$@"
}

msg_error() {
	local -; set +x
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	if [ -n "${MY_JOBID}" ]; then
		# Send colored msg to bulk log...
		COLOR_ARROW="${COLOR_ERROR}" job_msg "${COLOR_ERROR}Error: $1"
		# And non-colored to buld log
		msg "Error: $1" >&2
	elif [ ${OUTPUT_REDIRECTED:-0} -eq 1 ]; then
		# Send to true stderr
		COLOR_ARROW="${COLOR_ERROR}" msg "${COLOR_ERROR}Error: $1" >&4
	else
		COLOR_ARROW="${COLOR_ERROR}" msg "${COLOR_ERROR}Error: $1" >&2
	fi
	return 0
}

msg_dev() {
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_DEV}" \
	    _msg_n "\n" "${COLOR_DEV}Dev: $@" >&2
}

msg_debug() {
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_DEBUG}" \
	    _msg_n "\n" "${COLOR_DEBUG}Debug: $@" >&2
}

msg_warn() {
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_WARN}" \
	    _msg_n "\n" "${COLOR_WARN}Warning: $@" >&2
}

job_msg() {
	local -; set +x
	local now elapsed NO_ELAPSED_IN_MSG output

	if [ -n "${MY_JOBID}" ]; then
		NO_ELAPSED_IN_MSG=0
		now=$(clock -monotonic)
		calculate_duration elapsed "$((${now} - ${TIME_START_JOB:-${TIME_START:-0}}))"
		output="[${COLOR_JOBID}${MY_JOBID}${COLOR_RESET}] [${elapsed}] $1"
	else
		output="$@"
	fi
	if [ ${OUTPUT_REDIRECTED:-0} -eq 1 ]; then
		# Send to true stdout (not any build log)
		_msg_n "\n" "${output}" >&3
	else
		_msg_n "\n" "${output}"
	fi
}

# Stubbed until post_getopts
job_msg_verbose() {
	job_msg "$@"
}

# These are aligned for 'Building msg'
job_msg_dev() {
	COLOR_ARROW="${COLOR_DEV}" \
	    job_msg "${COLOR_DEV}Dev:     $@"
}

job_msg_debug() {
	COLOR_ARROW="${COLOR_DEBUG}" \
	    job_msg "${COLOR_DEBUG}Debug:   $@"
}

job_msg_warn() {
	COLOR_ARROW="${COLOR_WARN}" \
	    job_msg "${COLOR_WARN}Warning: $@"
}

prompt() {
	[ $# -eq 1 ] || eargs prompt message
	local message="$1"
	local answer

	msg_n "${message} [y/N] "
	read answer
	case "${answer}" in
		[Yy][Ee][Ss]|[Yy][Ee]|[Yy])
			return 0
			;;
	esac

	return 1
}

confirm_if_tty() {
	[ $# -eq 1 ] || eargs confirm_if_tty message
	local message="${1}"

	[ -t 0 ] || return 0
	prompt "${message}"
}

# Handle needs after processing arguments.
post_getopts() {
	# Short-circuit verbose functions to save CPU
	if ! [ ${VERBOSE} -gt 2 ]; then
		msg_dev() { }
		job_msg_dev() { }
	fi
	if ! [ ${VERBOSE} -gt 1 ]; then
		msg_debug() { }
		job_msg_debug() { }
	fi
	if ! [ ${VERBOSE} -gt 0 ]; then
		msg_verbose() { }
		job_msg_verbose() { }
	fi
}

_mastermnt() {
	local hashed_name mnt mnttest mnamelen testpath mastername

	mnamelen=$(grep "#define[[:space:]]MNAMELEN" \
	    /usr/include/sys/mount.h 2>/dev/null | awk '{print $3}')
	: ${mnamelen:=88}

	# Avoid : which causes issues with PATH for non-jailed commands
	# like portlint in testport.
	mastername="${MASTERNAME}"
	_gsub "${mastername}" ":" "_"
	mastername="${_gsub}"
	mnt="${POUDRIERE_DATA}/.m/${mastername}/ref"
	if [ -z "${NOLINUX}" ]; then
		testpath="/compat/linux/proc"
	else
		testpath="/var/db/ports"
	fi
	mnttest="${mnt}${testpath}"

	if [ "${FORCE_MOUNT_HASH}" = "yes" ] || \
	    [ ${#mnttest} -ge $((${mnamelen} - 1)) ]; then
		hashed_name=$(sha256 -qs "${MASTERNAME}" | \
		    awk '{print substr($0, 0, 6)}')
		mnt="${POUDRIERE_DATA}/.m/${hashed_name}/ref"
		mnttest="${mnt}${testpath}"
		[ ${#mnttest} -ge $((${mnamelen} - 1)) ] && \
		    err 1 "Mountpath '${mnt}' exceeds system MNAMELEN limit of ${mnamelen}. Unable to mount. Try shortening BASEFS."
		msg_warn "MASTERNAME '${MASTERNAME}' too long for mounting, using hashed version of '${hashed_name}'"
	fi

	setvar "$1" "${mnt}"
	# MASTERMNTROOT
	setvar "${1}ROOT" "${mnt%/ref}"
}

_my_path() {
	if [ -z "${MY_JOBID}" ]; then
		setvar "$1" "${MASTERMNT}"
	elif [ -n "${MASTERMNTROOT}" ]; then
		setvar "$1" "${MASTERMNTROOT}/${MY_JOBID}"
	else
		setvar "$1" "${MASTERMNT}/../${MY_JOBID}"

	fi
}

_my_name() {
	setvar "$1" "${MASTERNAME}${MY_JOBID+-job-${MY_JOBID}}"
}
 
_log_path_top() {
	setvar "$1" "${POUDRIERE_DATA}/logs/${POUDRIERE_BUILD_TYPE}"
}

_log_path_jail() {
	local log_path_top

	_log_path_top log_path_top
	setvar "$1" "${log_path_top}/${MASTERNAME}"
}

_log_path() {
	local log_path_jail

	_log_path_jail log_path_jail
	setvar "$1" "${log_path_jail}/${BUILDNAME}"
}

# Call function with vars set:
# log MASTERNAME BUILDNAME jailname ptname setname
for_each_build() {
	[ -n "${BUILDNAME_GLOB}" ] || \
	    err 1 "for_each_build requires BUILDNAME_GLOB"
	[ -n "${SHOW_FINISHED}" ] || \
	    err 1 "for_each_build requires SHOW_FINISHED"
	[ $# -eq 1 ] || eargs for_each_build action
	local action="$1"
	local MASTERNAME BUILDNAME buildname jailname ptname setname
	local log_top ret

	POUDRIERE_BUILD_TYPE="bulk" _log_path_top log_top
	[ -d "${log_top}" ] || err 1 "Log path ${log_top} does not exist."
	cd ${log_top}

	found_jobs=0
	ret=0
	for mastername in *; do
		# Check empty dir
		case "${mastername}" in
			"*") break ;;
		esac
		[ -L "${mastername}/latest" ] || continue
		MASTERNAME=${mastername}
		[ "${MASTERNAME}" = "latest-per-pkg" ] && continue
		[ ${SHOW_FINISHED} -eq 0 ] && ! jail_runs ${MASTERNAME} && \
		    continue

		# Look for all wanted buildnames (will be 1 or Many(-a)))
		for buildname in ${mastername}/${BUILDNAME_GLOB}; do
			# Check for no match. If not using a glob ensure the
			# file exists otherwise check for the glob coming back
			if [ "${BUILDNAME_GLOB%\**}" != \
			    "${BUILDNAME_GLOB}" ]; then
				case "${buildname}" in
					# Check no results
					"${mastername}/${BUILDNAME_GLOB}")
						break
						;;
					# Skip latest if from a glob, let it be
					# found normally.
					"${mastername}/latest")
						continue
						;;
					"${mastername}/latest-done")
						continue
						;;
					# Don't want latest-per-pkg
					"${mastername}/latest-per-pkg")
						continue
						;;
				esac
			else
				# No match
				[ -e "${buildname}" ] || break
			fi
			buildname="${buildname#${mastername}/}"
			BUILDNAME="${buildname}"
			# Unset so later they can be checked for NULL (don't
			# want to lookup again if value looked up is empty
			unset jailname ptname setname
			# Try matching on any given JAILNAME/PTNAME/SETNAME,
			# and if any don't match skip this MASTERNAME entirely.
			# If the file is missing it's a legacy build, skip it
			# but not the entire mastername if it has a match.
			if [ -n "${JAILNAME}" ]; then
				if _bget jailname jailname 2>/dev/null; then
					[ "${jailname}" = "${JAILNAME}" ] || \
					    continue 2
				else
					case "${MASTERNAME}" in
						${JAILNAME}-*) ;;
						*) continue 2 ;;
					esac
					continue
				fi
			fi
			if [ -n "${PTNAME}" ]; then
				if _bget ptname ptname 2>/dev/null; then
					[ "${ptname}" = "${PTNAME}" ] || \
					    continue 2
				else
					case "${MASTERNAME}" in
						*-${PTNAME}) ;;
						*) continue 2 ;;
					esac
					continue
				fi
			fi
			if [ -n "${SETNAME}" ]; then
				if _bget setname setname 2>/dev/null; then
					[ "${setname}" = "${SETNAME%0}" ] || \
					    continue 2
				else
					case "${MASTERNAME}" in
						*-${SETNAME%0}) ;;
						*) continue 2 ;;
					esac
					continue
				fi
			fi
			# Dereference latest into actual buildname
			[ "${buildname}" = "latest-done" ] && \
			    _bget BUILDNAME buildname 2>/dev/null
			[ "${buildname}" = "latest" ] && \
			    _bget BUILDNAME buildname 2>/dev/null
			# May be blank if build is still starting up
			[ -z "${BUILDNAME}" ] && continue 2

			found_jobs=$((${found_jobs} + 1))

			# Lookup jailname/setname/ptname if needed. Delayed
			# from earlier for performance for -a
			[ -z "${jailname+null}" ] && \
			    _bget jailname jailname 2>/dev/null || :
			[ -z "${setname+null}" ] && \
			    _bget setname setname 2>/dev/null || :
			[ -z "${ptname+null}" ] && \
			    _bget ptname ptname 2>/dev/null || :
			log=${mastername}/${BUILDNAME}

			${action} || ret=$?
			# Skip the rest of this build if return = 100
			[ ${ret} -eq 100 ] && continue 2
			# Halt if the function requests it
			[ ${ret} -eq 101 ] && break 2
		done

	done
	cd ${OLDPWD}
	return ${ret}
}

stat_humanize() {
	xargs -0 stat -f '%i %b' | \
	    sort -u | \
	    awk -vbsize=512 '{total += $2} END {print total*bsize}' | \
	    awk -f ${AWKPREFIX}/humanize.awk
}

do_confirm_delete() {
	[ $# -eq 4 ] || eargs do_confirm_delete badfiles_list \
	    reason_plural_object answer DRY_RUN
	local filelist="$1"
	local reason="$2"
	local answer="$3"
	local DRY_RUN="$4"
	local file_cnt hsize ret

	file_cnt=$(wc -l ${filelist} | awk '{print $1}')
	if [ ${file_cnt} -eq 0 ]; then
		msg "No ${reason} to cleanup"
		return 2
	fi

	msg_n "Calculating size for found files..."
	hsize=$(cat ${filelist} | \
	    tr '\n' '\000' | \
	    xargs -0 -J % find % -print0 | \
	    stat_humanize)
	echo " done"

	msg "These ${reason} will be deleted:"
	cat ${filelist}
	msg "Removing these ${reason} will free: ${hsize}"

	if [ ${DRY_RUN} -eq 1 ];  then
		msg "Dry run: not cleaning anything."
		return 2
	fi

	if [ -z "${answer}" ]; then
		prompt "Proceed?" && answer="yes"
	fi

	ret=0
	if [ "${answer}" = "yes" ]; then
		msg_n "Removing files..."
		cat ${filelist} | tr '\n' '\000' | \
		    xargs -0 -J % \
		    find % -mindepth 0 -maxdepth 0 -exec rm -rf {} +
		echo " done"
		ret=1
	fi
	return ${ret}
}

injail() {
	if [ ${INJAIL_HOST:-0} -eq 1 ]; then
		# For test/
		"$@"
	elif [ "${USE_JEXECD}" = "no" ]; then
		injail_tty "$@"
	else
		local name

		_my_name name
		[ -n "${name}" ] || err 1 "No jail setup"
		rexec -s ${MASTERMNT}/../${name}${JNETNAME:+-${JNETNAME}}.sock \
			-u ${JUSER:-root} "$@"
	fi
}

injail_tty() {
	local name

	_my_name name
	[ -n "${name}" ] || err 1 "No jail setup"
	if [ ${JEXEC_LIMITS:-0} -eq 1 ]; then
		jexec -U ${JUSER:-root} ${name}${JNETNAME:+-${JNETNAME}} \
			${JEXEC_LIMITS+/usr/bin/limits} \
			${MAX_MEMORY_BYTES:+-v ${MAX_MEMORY_BYTES}} \
			${MAX_FILES:+-n ${MAX_FILES}} \
			"$@"
	else
		jexec -U ${JUSER:-root} ${name}${JNETNAME:+-${JNETNAME}} \
			"$@"
	fi
}

jstart() {
	local name network

	network="${localipargs}"

	if [ "${RESTRICT_NETWORKING}" != "yes" ]; then
		network="${ipargs} ${JAIL_NET_PARAMS}"
	fi

	_my_name name
	# Restrict to no networking (if RESTRICT_NETWORKING==yes)
	jail -c persist name=${name} \
		path=${MASTERMNT}${MY_JOBID+/../${MY_JOBID}} \
		host.hostname=${BUILDER_HOSTNAME-${name}} \
		${network} ${JAIL_PARAMS}
	[ "${USE_JEXECD}" = "yes" ] && \
	    jexecd -j ${name} -d ${MASTERMNT}/../ \
	    ${MAX_MEMORY_BYTES+-m ${MAX_MEMORY_BYTES}} \
	    ${MAX_FILES+-n ${MAX_FILES}}
	# Allow networking in -n jail
	jail -c persist name=${name}-n \
		path=${MASTERMNT}${MY_JOBID+/../${MY_JOBID}} \
		host.hostname=${BUILDER_HOSTNAME-${name}} \
		${ipargs} ${JAIL_PARAMS} ${JAIL_NET_PARAMS}
	[ "${USE_JEXECD}" = "yes" ] && \
	    jexecd -j ${name}-n -d ${MASTERMNT}/../ \
	    ${MAX_MEMORY_BYTES+-m ${MAX_MEMORY_BYTES}} \
	    ${MAX_FILES+-n ${MAX_FILES}}
	return 0
}

jail_has_processes() {
	local pscnt

	# 2 = HEADER+ps itself
	pscnt=2
	[ "${USE_JEXECD}" = "yes" ] && pscnt=4
	# Cannot use ps -J here as not all versions support it.
	if [ $(injail ps aux | wc -l) -ne ${pscnt} ]; then
		return 0
	fi
	return 1
}

jkill_wait() {
	injail kill -9 -1 2>/dev/null || return 0
	while jail_has_processes; do
		sleep 1
		injail kill -9 -1 2>/dev/null || return 0
	done
}

# Kill everything in the jail and ensure it is free of any processes
# before returning.
jkill() {
	[ "${USE_JEXECD}" = "yes" ] && return 0
	jkill_wait
	JNETNAME="n" jkill_wait
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
	0) err ${EX_SOFTWARE} "${fname}: No arguments expected" ;;
	1) err ${EX_SOFTWARE} "${fname}: 1 argument expected: $1" ;;
	*) err ${EX_SOFTWARE} "${fname}: $# arguments expected: $*" ;;
	esac
}

run_hook() {
	[ $# -ge 2 ] || eargs run_hook hook event args
	local hook="$1"
	local event="$2"
	local build_url log log_url plugin_dir

	shift 2

	build_url build_url || :
	log_url log_url || :
	_log_path log || :

	run_hook_file "${HOOKDIR}/${hook}.sh" "${hook}" "${event}" \
	    "${build_url}" "${log_url}" "${log}" "$@"

	if [ -d "${HOOKDIR}/plugins" ]; then
		for plugin_dir in ${HOOKDIR}/plugins/*; do
			# Check empty dir
			case "${plugin_dir}" in
			"${HOOKDIR}/plugins/*") break ;;
			esac
			run_hook_file "${plugin_dir}/${hook}.sh" "${hook}" \
			    "${event}" "${build_url}" "${log_url}" "${log}" \
			    "$@"
		done
	fi
}

run_hook_file() {
	[ $# -ge 6 ] || eargs run_hook_file hookfile hook event build_url \
	    log_url log args
	local hookfile="$1"
	local hook="$2"
	local event="$3"
	local build_url="$4"
	local log_url="$5"
	local log="$6"
	[ -f "${hookfile}" ] || return 0

	shift 6

	job_msg_dev "Running ${hookfile} for event '${hook}:${event}' args: ${@:-(null)}"

	(
		set +e
		cd /tmp
		BUILD_URL="${build_url}" \
		    LOG_URL="${log_url}" \
		    LOG="${log}" \
		    POUDRIERE_BUILD_TYPE=${POUDRIERE_BUILD_TYPE} \
		    POUDRIERED="${POUDRIERED}" \
		    POUDRIERE_DATA="${POUDRIERE_DATA}" \
		    MASTERNAME="${MASTERNAME}" \
		    MASTERMNT="${MASTERMNT}" \
		    MY_JOBID="${MY_JOBID}" \
		    BUILDNAME="${BUILDNAME}" \
		    JAILNAME="${JAILNAME}" \
		    PTNAME="${PTNAME}" \
		    SETNAME="${SETNAME}" \
		    PACKAGES="${PACKAGES}" \
		    PACKAGES_ROOT="${PACKAGES_ROOT}" \
		    /bin/sh "${hookfile}" "${event}" "$@"
	) || err 1 "Hook ${hookfile} for '${hook}:${event}' returned non-zero"
	return 0
}

log_start() {
	[ $# -eq 1 ] || eargs log_start need_tee
	local need_tee="$1"
	local log log_top
	local latest_log

	_log_path log
	_log_path_top log_top

	logfile="${log}/logs/${PKGNAME}.log"
	latest_log=${log_top}/latest-per-pkg/${PKGBASE}/${PKGNAME##*-}

	# Make sure directory exists
	mkdir -p ${log}/logs ${latest_log}

	:> ${logfile}

	# Link to BUILD_TYPE/latest-per-pkg/PORTNAME/PKGVERSION/MASTERNAME.log
	ln -f ${logfile} ${latest_log}/${MASTERNAME}.log

	# Link to JAIL/latest-per-pkg/PKGNAME.log
	ln -f ${logfile} ${log}/../latest-per-pkg/${PKGNAME}.log

	# Save stdout/stderr for restoration later for bulk/testport -i
	exec 3>&1 4>&2
	OUTPUT_REDIRECTED=1
	# Pipe output to tee(1) or timestamp if needed.
	if [ ${need_tee} -eq 1 ] || [ "${TIMESTAMP_LOGS}" = "yes" ]; then
		[ ! -e ${logfile}.pipe ] && mkfifo ${logfile}.pipe
		if [ ${need_tee} -eq 1 ]; then
			if [ "${TIMESTAMP_LOGS}" = "yes" ]; then
				timestamp < ${logfile}.pipe | tee ${logfile} &
			else
				tee ${logfile} < ${logfile}.pipe &
			fi
		elif [ "${TIMESTAMP_LOGS}" = "yes" ]; then
			timestamp > ${logfile} < ${logfile}.pipe &
		fi
		tpid=$!
		exec > ${logfile}.pipe 2>&1

		# Remove fifo pipe file right away to avoid orphaning it.
		# The pipe will continue to work as long as we keep
		# the FD open to it.
		unlink ${logfile}.pipe
	else
		# Send output directly to file.
		tpid=
		exec > ${logfile} 2>&1
	fi
}

buildlog_start() {
	local originspec="$1"
	local mnt var portdir
	local make_vars
	local wanted_vars="
	    MAINTAINER
	    CONFIGURE_ARGS
	    CONFIGURE_ENV
	    MAKE_ENV
	    PLIST_SUB
	    SUB_LIST
	    "

	_my_path mnt
	originspec_decode "${originspec}" port '' ''
	portdir="${PORTSDIR}/${port}"

	for var in ${wanted_vars}; do
		local "mk_${var}"
		make_vars="${make_vars:+${make_vars} }${var} mk_${var}"
	done

	port_var_fetch_originspec "${originspec}" \
	    ${PORT_FLAGS} \
	    ${make_vars}

	echo "build started at $(date)"
	echo "port directory: ${portdir}"
	echo "package name: ${PKGNAME}"
	echo "building for: $(injail uname -a)"
	echo "maintained by: ${mk_MAINTAINER}"
	echo "Makefile ident: $(ident -q ${mnt}/${portdir}/Makefile|sed -n '2,2p')"
	echo "Poudriere version: ${POUDRIERE_VERSION}"
	echo "Host OSVERSION: ${HOST_OSVERSION}"
	echo "Jail OSVERSION: ${JAIL_OSVERSION}"
	echo "Job Id: ${MY_JOBID}"
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
	injail /usr/bin/env
	echo "---End Environment---"
	echo ""
	echo "---Begin Poudriere Port Flags/Env---"
	echo "PORT_FLAGS=${PORT_FLAGS}"
	echo "PKGENV=${PKGENV}"
	echo "FLAVOR=${FLAVOR}"
	echo "DEPENDS_ARGS=${DEPENDS_ARGS}"
	echo "MAKE_ARGS=${MAKE_ARGS}"
	echo "---End Poudriere Port Flags/Env---"
	echo ""
	echo "---Begin OPTIONS List---"
	injail /usr/bin/make -C ${portdir} ${MAKE_ARGS} showconfig || :
	echo "---End OPTIONS List---"
	echo ""
	for var in ${wanted_vars}; do
		echo "--${var}--"
		eval "echo \"\${mk_${var}}\""
		echo "--End ${var}--"
		echo ""
	done
	echo "---Begin make.conf---"
	cat ${mnt}/etc/make.conf
	echo "---End make.conf---"
	if [ -f "${mnt}/etc/make.nxb.conf" ]; then
		echo "---Begin make.nxb.conf---"
		cat ${mnt}/etc/make.nxb.conf
		echo "---End make.nxb.conf---"
	fi

	echo "--Resource limits--"
	injail /bin/sh -c "ulimit -a" || :
	echo "--End resource limits--"
}

buildlog_stop() {
	[ $# -eq 3 ] || eargs buildlog_stop pkgname originspec build_failed
	local pkgname="$1"
	local originspec=$2
	local build_failed="$3"
	local log
	local buildtime

	_log_path log
	buildtime=$( \
		stat -f '%N %B' ${log}/logs/${pkgname}.log  | awk -v now=$(clock -epoch) \
		-f ${AWKPREFIX}/siginfo_buildtime.awk |
		awk -F'!' '{print $2}' \
	)

	echo "build of ${originspec} | ${pkgname} ended at $(date)"
	echo "build time: ${buildtime}"
	[ ${build_failed} -gt 0 ] && echo "!!! build failure encountered !!!"

	return 0
}

log_stop() {
	if [ ${OUTPUT_REDIRECTED:-0} -eq 1 ]; then
		exec 1>&3 3>&- 2>&4 4>&-
		OUTPUT_REDIRECTED=0
	fi
	if [ -n "${tpid}" ]; then
		# Give tee a moment to flush buffers
		timed_wait_and_kill 5 $tpid || :
		unset tpid
	fi
}

read_file() {
	[ $# -eq 2 ] || eargs read_file var_return file
	local var_return="$1"
	local file="$2"
	local _data line
	local ret -

	# var_return may be empty if only $_read_file_lines_read is being
	# used.

	set +e
	_data=
	_read_file_lines_read=0

	if [ ${READ_FILE_USE_CAT:-0} -eq 1 ]; then
		if [ -f "${file}" ]; then
			if [ -n "${var_return}" ]; then
				_data="$(cat "${file}")"
			fi
			_read_file_lines_read=$(wc -l < "${file}")
			_read_file_lines_read=${_read_file_lines_read##* }
			ret=0
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
			if [ -n "${var_return}" ]; then
				# Add extra newline
				[ ${_read_file_lines_read} -gt 0 ] && \
				    _data="${_data}
"
				_data="${_data}${line}"
			fi
			_read_file_lines_read=$((${_read_file_lines_read} + 1))
		done < "${file}" || ret=$?
	fi

	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_data}"
	fi

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

	if _attr_get attr_get_data "$@"; then
		[ -n "${attr_get_data}" ] && echo "${attr_get_data}"
		return 0
	fi
	return 1
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
	# It may be empty if only a count was being looked up
	# via $_read_file_lines_read hack.
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" ""
	fi
	return 1
}

bget() {
	local bget_data

	if _bget bget_data "$@"; then
		[ -n "${bget_data}" ] && echo "${bget_data}"
		return 0
	fi
	return 1
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
	echo "$@" > "${log}/${file}"
}

bset_job_status() {
	[ $# -eq 2 ] || eargs bset_job_status status originspec
	local status="$1"
	local originspec="$2"

	bset ${MY_JOBID} status "${status}:${originspec}:${PKGNAME}:${TIME_START_JOB:-${TIME_START}}:$(clock -monotonic)"
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

	if [ -n "${update_stats_done}" ]; then
		return 0
	fi

	set +e

	lock_acquire update_stats || return 1

	for type in built failed ignored; do
		_bget '' "ports.${type}"
		bset "stats_${type}" ${_read_file_lines_read}
	done

	# Skipped may have duplicates in it
	bset stats_skipped $(bget ports.skipped | awk '{print $1}' | \
		sort -u | wc -l)

	lock_release update_stats
}

sigpipe_handler() {
	EXIT_STATUS="sigpipe:"
	SIGNAL="SIGPIPE"
	sig_handler
}

sigint_handler() {
	EXIT_STATUS="sigint:"
	SIGNAL="SIGINT"
	sig_handler
}

sigterm_handler() {
	EXIT_STATUS="sigterm:"
	SIGNAL="SIGTERM"
	sig_handler
}


sig_handler() {
	# Reset SIGTERM handler, just exit if another is received.
	trap - SIGTERM
	# Ignore SIGPIPE for messages
	trap '' SIGPIPE
	# Ignore SIGINT while cleaning up
	trap '' SIGINT
	trap '' SIGINFO
	err 1 "Signal ${SIGNAL} caught, cleaning up and exiting"
}

exit_handler() {
	# Ignore errors while cleaning up
	set +e
	ERRORS_ARE_FATAL=0
	trap '' SIGINFO
	# Avoid recursively cleaning up here
	trap - EXIT SIGTERM
	# Ignore SIGPIPE for messages
	trap '' SIGPIPE
	# Ignore SIGINT while cleaning up
	trap '' SIGINT

	if was_a_bulk_run; then
		log_stop
		# build_queue may have done cd MASTERMNT/.p/pool,
		# but some of the cleanup here assumes we are
		# PWD=MASTERMNT/.p.  Switch back if possible.
		# It will be changed to / in jail_cleanup
		if [ -d "${MASTERMNT}/.p" ]; then
			cd "${MASTERMNT}/.p"
		fi
	fi
	if was_a_jail_run; then
		# Don't use jail for any caching in cleanup
		SHASH_VAR_PATH="${SHASH_VAR_PATH_DEFAULT}"
	fi

	parallel_shutdown

	if was_a_bulk_run; then
		# build_queue socket
		exec 6<&- 6>&- || :
		coprocess_stop pkg_cacher
	fi

	# stdin may be redirected if a signal interrupted the read builtin (or
	# any redirection to stdin).  Close it to avoid possibly referencing a
	# file in the jail like builders.pipe on socket 6.
	exec </dev/null

	[ ${STATUS} -eq 1 ] && jail_cleanup

	if was_a_bulk_run; then
		coprocess_stop html_json
		if [ ${CREATED_JLOCK:-0} -eq 1 ]; then
			update_stats >/dev/null 2>&1 || :
		fi
		if [ ${DRY_RUN} -eq 1 ] && [ -n "${PACKAGES_ROOT}" ]; then
			rm -rf "${PACKAGES_ROOT}/.building" || :
		fi
	fi

	[ -n ${CLEANUP_HOOK} ] && ${CLEANUP_HOOK}

	if [ ${CREATED_JLOCK:-0} -eq 1 ]; then
		_jlock jlock
		rm -rf "${jlock}" 2>/dev/null || :
	fi
	rm -rf "${POUDRIERE_TMPDIR}" >/dev/null 2>&1 || :
}

build_url() {
	if [ -z "${URL_BASE}" ]; then
		setvar "$1" ""
		return 1
	fi
	setvar "$1" "${URL_BASE}/build.html?mastername=${MASTERNAME}&build=${BUILDNAME}"
}

log_url() {
	if [ -z "${URL_BASE}" ]; then
		setvar "$1" ""
		return 1
	fi
	setvar "$1" "${URL_BASE}/data/${MASTERNAME}/${BUILDNAME}/logs"
}

show_log_info() {
	local log build_url

	_log_path log
	msg "Logs: ${log}"
	build_url build_url && \
	    msg "WWW: ${build_url}"
	return 0
}

show_dry_run_summary() {
	[ ${DRY_RUN} -eq 1 ] || return 0
	local log

	_log_path log

	bset status "done:"
	msg "Dry run mode, cleaning up and exiting"
	tobuild=$(calculate_tobuild)
	if [ ${tobuild} -gt 0 ]; then
		[ ${PARALLEL_JOBS} -gt ${tobuild} ] &&
		    PARALLEL_JOBS=${tobuild##* }
		msg "Would build ${tobuild} packages using ${PARALLEL_JOBS} builders"

		msg_n "Ports to build: "
		{
			if was_a_testport_run; then
				echo "${ORIGINSPEC}"
			fi
			cat "${log}/.poudriere.ports.queued"
		} | \
		    while read originspec pkgname _ignored; do
			# Trim away DEPENDS_ARGS for display
			originspec_decode "${originspec}" origin '' flavor
			originspec_encode originspec "${origin}" '' "${flavor}"
			echo "${originspec}"
		done | sort | tr '\n' ' '
		echo
	else
		msg "No packages would be built"
	fi
	show_log_info
	exit 0
}

show_build_summary() {
	local status nbb nbf nbs nbi nbq ndone nbtobuild buildname
	local log now elapsed buildtime queue_width

	update_stats 2>/dev/null || return 0

	_bget nbq stats_queued 2>/dev/null || nbq=0
	_bget status status 2>/dev/null || status=unknown
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
	else
		queue_width=2
	fi

	_log_path log
	_bget buildname buildname 2>/dev/null || :
	now=$(clock -epoch)

	calculate_elapsed_from_log "${now}" "${log}" || return 1
	elapsed=${_elapsed_time}
	calculate_duration buildtime "${elapsed}"

	printf "[${MASTERNAME}] [${buildname}] [${status}] \
Queued: %-${queue_width}d ${COLOR_SUCCESS}Built: %-${queue_width}d \
${COLOR_FAIL}Failed: %-${queue_width}d ${COLOR_SKIP}Skipped: \
%-${queue_width}d ${COLOR_IGNORE}Ignored: %-${queue_width}d${COLOR_RESET} \
Tobuild: %-${queue_width}d  Time: %s\n" \
	    ${nbq} ${nbb} ${nbf} ${nbs} ${nbi} ${nbtobuild} "${buildtime}"
}

siginfo_handler() {
	trappedinfo=1
	in_siginfo_handler=1
	[ "${POUDRIERE_BUILD_TYPE}" != "bulk" ] && return 0
	local status
	local now
	local j elapsed elapsed_phase job_id_color
	local pkgname origin phase buildtime buildtime_phase started
	local started_phase format_origin_phase format_phase
	local -

	set +e

	trap '' SIGINFO

	_bget status status 2>/dev/null || status=unknown
	if [ "${status}" = "index:" -o "${status#stopped:}" = "crashed:" ]; then
		enable_siginfo_handler
		return 0
	fi

	_bget nbq stats_queued 2>/dev/null || nbq=0
	if [ -z "${nbq}" ]; then
		enable_siginfo_handler
		return 0
	fi

	show_build_summary

	now=$(clock -monotonic)

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
			status="${status#*:}"
			started_phase="${status%%:*}"

			colorize_job_id job_id_color "${j}"

			# Must put colors in format
			format_origin_phase="\t[${job_id_color}%s${COLOR_RESET}]: ${COLOR_PORT}%-25s | %-25s ${COLOR_PHASE}%-15s${COLOR_RESET} (%s / %s)\n"
			format_phase="\t[${job_id_color}%s${COLOR_RESET}]: %53s ${COLOR_PHASE}%-15s${COLOR_RESET}\n"
			if [ -n "${pkgname}" ]; then
				elapsed=$((${now} - ${started}))
				calculate_duration buildtime "${elapsed}"
				elapsed_phase=$((${now} - ${started_phase}))
				calculate_duration buildtime_phase \
				    "${elapsed_phase}"
				printf "${format_origin_phase}" "${j}" \
				    "${origin}" "${pkgname}" "${phase}" \
				    "${buildtime_phase}" "${buildtime}"
			else
				printf "${format_phase}" "${j}" '' "${phase}"
			fi
		done
	fi

	show_log_info
	enable_siginfo_handler
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
			echo "${data}"
			return
		fi
		# Manually created dataset may be missing type, set it and
		# don't add more child datasets.
		if zfs get mountpoint ${ZPOOL}${ZROOTFS}/data >/dev/null \
		    2>&1; then
			zfs set ${NS}:type=data ${ZPOOL}${ZROOTFS}/data
			zfs get -H -o value mountpoint ${ZPOOL}${ZROOTFS}/data
			return
		fi
		zfs create -p -o ${NS}:type=data \
			-o atime=off \
			-o mountpoint=${BASEFS}/data \
			${ZPOOL}${ZROOTFS}/data
		zfs create ${ZPOOL}${ZROOTFS}/data/.m
		zfs create -o compression=off ${ZPOOL}${ZROOTFS}/data/cache
		zfs create -o compression=lz4 ${ZPOOL}${ZROOTFS}/data/logs
		zfs create -o compression=off ${ZPOOL}${ZROOTFS}/data/packages
		zfs create -o compression=off ${ZPOOL}${ZROOTFS}/data/wrkdirs
	else
		mkdir -p "${BASEFS}/data"
	fi
	echo "${BASEFS}/data"
}

fetch_file() {
	[ $# -ne 2 ] && eargs fetch_file destination source
	fetch -p -o $1 $2 || fetch -p -o $1 $2 || err 1 "Failed to fetch from $2"
}

# Export handling is different in builtin vs external
if [ "$(type mktemp)" = "mktemp is a shell builtin" ]; then
	MKTEMP_BUILTIN=1
fi
# Wrap mktemp to put most tmpfiles in mnt/.p/tmp rather than system /tmp.
mktemp() {
	local ret

	if [ -z "${TMPDIR}" ]; then
		if [ -n "${MASTERMNT}" -a ${STATUS} -eq 1 ]; then
			local mnt
			_my_path mnt
			TMPDIR="${mnt}/.p/tmp"
			[ -d "${TMPDIR}" ] || unset TMPDIR
		else
			TMPDIR="${POUDRIERE_TMPDIR}"
		fi
	fi
	if [ -n "${MKTEMP_BUILTIN}" ]; then
		# No export needed here since TMPDIR is set above in scope.
		builtin mktemp "$@"
	else
		[ -n "${TMPDIR}" ] && export TMPDIR
		command mktemp "$@"
	fi
}

unlink() {
	command unlink "$@" 2>/dev/null || :
}

common_mtree() {
	[ $# -eq 1 ] || eargs common_mtree mnt
	local mnt="${1}"
	local exclude nullpaths dir

	cat <<-EOF
	./.npkg
	./.p
	./.poudriere-snap-*
	.${HOME}/.ccache
	./compat/linux/proc
	./dev
	./distfiles
	./packages
	./portdistfiles
	./proc
	.${PORTSDIR}
	./usr/src
	./var/db/freebsd-update
	./var/db/etcupdate
	./var/db/ports
	./wrkdirs
	EOF
	nullpaths="$(nullfs_paths "${mnt}")"
	for dir in ${nullpaths}; do
		echo ".${dir}"
	done
	for exclude in ${LOCAL_MTREE_EXCLUDES}; do
		echo ".${exclude#.}"
	done
}

markfs() {
	[ $# -lt 2 ] && eargs markfs name mnt path
	local name=$1
	local mnt="${2}"
	local path="$3"
	local fs="$(zfs_getfs ${mnt})"
	local dozfs=0
	local domtree=0
	local mtreefile
	local snapfile

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
		rollback_file "${mnt}" "${name}" snapfile
		unlink "${snapfile}" >/dev/null 2>&1 || :
		#create new snapshot
		zfs snapshot ${fs}@${name}
		# Mark that we are in this snapshot, which rollbackfs
		# will check for not existing when rolling back later.
		: > "${snapfile}"
	fi

	if [ $domtree -eq 0 ]; then
		echo " done"
		return 0
	fi
	mtreefile="${mnt}/.p/mtree.${name}exclude"
	{
		common_mtree "${mnt}"
		case "${name}" in
			prebuild|prestage)
				cat <<-EOF
				.${HOME}
				./tmp
				./var/crash/*.core
				./var/tmp
				EOF
				;;
			preinst)
				cat <<-EOF
				./etc/group
				./etc/make.conf
				./etc/make.conf.bak
				./etc/master.passwd
				./etc/passwd
				./etc/pwd.db
				./etc/shells
				./etc/spwd.db
				./tmp
				./var/db/pkg
				./var/log
				./var/mail
				./var/run
				./var/tmp
				EOF
			;;
		esac
	} > "${mtreefile}"
	( cd "${mnt}${path}" && mtree -X "${mtreefile}" \
		-cn -k uid,gid,mode,size \
		-p . ) > "${mnt}/.p/mtree.${name}"
	echo " done"
}

rm() {
	local arg

	for arg in "$@"; do
		[ "${arg}" = "/" ] && err 1 "Tried to rm /"
		[ "${arg%/}" = "/bin" ] && err 1 "Tried to rm /*"
	done

	command rm "$@"
}

# Handle relative path change needs
cd() {
	local ret

	ret=0
	command cd "$@" || ret=$?
	# Handle fixing relative paths
	if [ "${OLDPWD}" != "${PWD}" ]; then
		# Only change if it is relative
		if [ -n "${SHASH_VAR_PATH##/*}" ]; then
			_relpath "${OLDPWD}/${SHASH_VAR_PATH}" "${PWD}"
			SHASH_VAR_PATH="${_relpath}"
		fi
	fi
	return ${ret}
}

do_jail_mounts() {
	[ $# -ne 4 ] && eargs do_jail_mounts from mnt arch name
	local from="$1"
	local mnt="$2"
	local arch="$3"
	local name="$4"
	local devfspath="null zero random urandom stdin stdout stderr fd fd/* bpf* pts pts/*"
	local srcpath nullpaths nullpath

	# from==mnt is via jail -u

	# clone will inherit from the ref jail
	if [ ${mnt##*/} = "ref" ]; then
		mkdir -p ${mnt}/proc \
		    ${mnt}/dev \
		    ${mnt}/compat/linux/proc \
		    ${mnt}/usr/src
	fi

	# Mount some paths read-only from the ref-jail if possible.
	nullpaths="$(nullfs_paths "${mnt}")"
	echo ${nullpaths} | tr ' ' '\n' | sed -e "s,^/,${mnt}/," | \
	    xargs mkdir -p
	for nullpath in ${nullpaths}; do
		[ -d "${from}${nullpath}" -a "${from}" != "${mnt}" ] && \
		    ${NULLMOUNT} -o ro "${from}${nullpath}" "${mnt}${nullpath}"
	done

	# Mount /usr/src into target if it exists and not overridden
	_jget srcpath ${name} srcpath 2>/dev/null || srcpath="${from}/usr/src"
	[ -d "${srcpath}" -a "${from}" != "${mnt}" ] && \
	    ${NULLMOUNT} -o ro ${srcpath} ${mnt}/usr/src

	mount -t devfs devfs ${mnt}/dev
	if [ ${JAILED} -eq 0 ]; then
		devfs -m ${mnt}/dev rule apply hide
		for p in ${devfspath} ; do
			devfs -m ${mnt}/dev/ rule apply path "${p}" unhide
		done
	fi

	[ "${USE_FDESCFS}" = "yes" ] && \
	    [ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ] && \
	    mount -t fdescfs fdesc "${mnt}/dev/fd"
	[ "${USE_PROCFS}" = "yes" ] && \
	    mount -t procfs proc "${mnt}/proc"
	[ -z "${NOLINUX}" ] && \
	    [ "${arch}" = "i386" -o "${arch}" = "amd64" ] && \
	    [ -d "${mnt}/compat" ] && \
	    mount -t linprocfs linprocfs "${mnt}/compat/linux/proc"

	run_hook jail mount ${mnt}

	return 0
}

# Interactive test mode
enter_interactive() {
	local stopmsg pkgname port originspec dep_args flavor packages

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
	if ! was_a_testport_run; then
		# Install pkg-static so full pkg package can install
		ensure_pkg_installed force_extract || \
		    err 1 "Unable to extract pkg."
		# Install the selected pkg package
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    /usr/bin/make -C \
		    ${PORTSDIR}/$(injail /usr/bin/make \
		    -f ${PORTSDIR}/Mk/bsd.port.mk -V PKGNG_ORIGIN) \
		    PKG_BIN="${PKG_BIN}" install-package
	fi

	# Enable all selected ports and their run-depends
	if ! was_a_testport_run; then
		packages="$(listed_pkgnames)"
	else
		packages="${PKGNAME}"
	fi
	for pkgname in ${packages}; do
		get_originspec_from_pkgname originspec "${pkgname}"
		originspec_decode "${originspec}" port dep_args flavor
		# Install run-depends since this is an interactive test
		msg "Installing run-depends for ${COLOR_PORT}${port} | ${pkgname}"
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    /usr/bin/make -C ${PORTSDIR}/${port} ${dep_args} \
		    ${flavor:+FLAVOR=${flavor}} run-depends ||
		    msg_warn "Failed to install ${COLOR_PORT}${port} | ${pkgname}${COLOR_RESET} run-depends"
		msg "Installing ${COLOR_PORT}${port} | ${pkgname}"
		# Only use PKGENV during install as testport will store
		# the package in a different place than dependencies
		injail env USE_PACKAGE_DEPENDS_ONLY=1 ${PKGENV} \
		    /usr/bin/make -C ${PORTSDIR}/${port} ${dep_args} \
		    ${flavor:+FLAVOR=${flavor}} install-package ||
		    msg_warn "Failed to install ${COLOR_PORT}${port} | ${pkgname}"
	done

	# Create a pkg repo configuration, and disable FreeBSD
	msg "Installing local Pkg repository to ${LOCALBASE}/etc/pkg/repos"
	mkdir -p ${MASTERMNT}${LOCALBASE}/etc/pkg/repos
	cat > ${MASTERMNT}${LOCALBASE}/etc/pkg/repos/local.conf <<-EOF
	FreeBSD: {
		enabled: no
	}

	local: {
		url: "file:///packages",
		enabled: yes
	}
	EOF

	if [ ${INTERACTIVE_MODE} -eq 1 ]; then
		msg "Entering interactive test mode. Type 'exit' when done."
		JNETNAME="n" injail_tty env -i TERM=${SAVED_TERM} \
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
	[ "${mnt##*/}" = "ref" ] && \
	    msg "Copying /var/db/ports from: ${optionsdir}"
	do_clone "${optionsdir}" "${mnt}/var/db/ports" || \
	    err 1 "Failed to copy OPTIONS directory"

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

	# clone will inherit from the ref jail
	if [ ${mnt##*/} = "ref" ]; then
		mkdir -p "${mnt}${PORTSDIR}" \
		    "${mnt}/wrkdirs" \
		    "${mnt}/${LOCALBASE:-/usr/local}" \
		    "${mnt}/distfiles" \
		    "${mnt}/packages" \
		    "${mnt}/.npkg" \
		    "${mnt}/var/db/ports" \
		    "${mnt}${HOME}/.ccache"
	fi
	[ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ] &&
	    mnt_tmpfs data "${mnt}/.p"

	mkdir -p "${mnt}/.p/tmp"

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

	_pget portsdir ${ptname} mnt
	[ -d ${portsdir}/ports ] && portsdir=${portsdir}/ports
	${NULLMOUNT} -o ro ${portsdir} ${mnt}${PORTSDIR} ||
		err 1 "Failed to mount the ports directory "
	mount_packages -o ro
	${NULLMOUNT} ${DISTFILES_CACHE} ${mnt}/distfiles ||
		err 1 "Failed to mount the distfiles cache directory"

	# Copy in the options for the ref jail, but just ro nullmount it
	# in builders.
	if [ "${mnt##*/}" = "ref" ]; then
		[ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ] && \
		    mnt_tmpfs config "${mnt}/var/db/ports"
		optionsdir="${MASTERNAME}"
		[ -n "${setname}" ] && optionsdir="${optionsdir} ${jname}-${setname}"
		optionsdir="${optionsdir} ${jname}-${ptname}"
		[ -n "${setname}" ] && optionsdir="${optionsdir} ${ptname}-${setname} ${setname}"
		optionsdir="${optionsdir} ${ptname} ${jname} -"

		for opt in ${optionsdir}; do
			use_options ${mnt} ${opt} && break || continue
		done
	else
		${NULLMOUNT} -o ro ${MASTERMNT}/var/db/ports \
		    ${mnt}/var/db/ports || \
		    err 1 "Failed to mount the options directory"
	fi

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

	pkgdir=.real_$(clock -epoch)
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
	local pkgdir_old pkgdir_new stats_failed log

	# Link the latest-done path now that we're done
	_log_path log
	ln -sfh ${BUILDNAME} ${log%/*}/latest-done

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
	find ${PACKAGES}/ -mindepth 1 -maxdepth 1 \
	    \( ! -name '.*' -o -name '.jailversion' -o -name '.buildname' \) |
	    while read path; do
		name=${path##*/}
		[ ! -L "${PACKAGES_ROOT}/${name}" ] || continue
		if [ -e "${PACKAGES_ROOT}/${name}" ]; then
			case "${name}" in
			.buildname|.jailversion|meta.txz|digests.txz|packagesite.txz|All|Latest)
				# Auto fix pkg-owned files
				unlink "${PACKAGES_ROOT}/${name}"
				;;
			*)
				msg_error "${PACKAGES_ROOT}/${name}
shadows repository file in .latest/${name}. Remove the top-level one and
symlink to .latest/${name}"
				continue
				;;
			esac
		fi
		ln -s .latest/${name} ${PACKAGES_ROOT}/${name}
	done

	pkgdir_old=$(realpath ${PACKAGES_ROOT}/.latest 2>/dev/null || :)

	# Rename shadow dir to a production name
	pkgdir_new=.real_$(clock -epoch)
	mv ${PACKAGES_ROOT}/.building ${PACKAGES_ROOT}/${pkgdir_new}

	# XXX: Copy in packages that failed to build

	# Switch latest symlink to new build
	PACKAGES=${PACKAGES_ROOT}/.latest
	ln -s ${pkgdir_new} ${PACKAGES_ROOT}/.latest_new
	rename ${PACKAGES_ROOT}/.latest_new ${PACKAGES}

	# Look for broken top-level links and remove them, if they reference
	# the old directory
	find -L ${PACKAGES_ROOT}/ -mindepth 1 -maxdepth 1 \
	    \( ! -name '.*' -o -name '.jailversion' -o -name '.buildname' \) \
	    -type l |
	    while read path; do
		link=$(readlink ${path})
		# Skip if link does not reference inside latest
		[ "${link##.latest}" != "${link}" ] || continue
		unlink ${path}
	done


	msg "Removing old packages"

	if [ "${KEEP_OLD_PACKAGES}" = "yes" ]; then
		keep_cnt=$((${KEEP_OLD_PACKAGES_COUNT} + 1))
		find ${PACKAGES_ROOT}/ -type d -mindepth 1 -maxdepth 1 \
		    -name '.real_*' | sort -dr |
		    sed -n "${keep_cnt},\$p" |
		    xargs rm -rf 2>/dev/null || :
	else
		# Remove old and shadow dir
		[ -n "${pkgdir_old}" ] && rm -rf ${pkgdir_old} 2>/dev/null || :
	fi
}

show_build_results() {
	local failed built ignored skipped nbbuilt nbfailed nbignored nbskipped

	failed=$(bget ports.failed | awk '{print $1 ":" $3 }' | xargs echo)
	failed=$(bget ports.failed | \
	    awk -v color_phase="${COLOR_PHASE}" \
	    -v color_port="${COLOR_PORT}" \
	    '{print $1 ":" color_phase $3 color_port }' | xargs echo)
	built=$(bget ports.built | awk '{print $1}' | xargs echo)
	ignored=$(bget ports.ignored | awk '{print $1}' | xargs echo)
	skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)
	_bget nbbuilt stats_built
	_bget nbfailed stats_failed
	_bget nbignored stats_ignored
	_bget nbskipped stats_skipped

	[ $nbbuilt -gt 0 ] && COLOR_ARROW="${COLOR_SUCCESS}" \
	    msg "${COLOR_SUCCESS}Built ports: ${COLOR_PORT}${built}"
	[ $nbfailed -gt 0 ] && COLOR_ARROW="${COLOR_FAIL}" \
	    msg "${COLOR_FAIL}Failed ports: ${COLOR_PORT}${failed}"
	[ $nbskipped -gt 0 ] && COLOR_ARROW="${COLOR_SKIP}" \
	    msg "${COLOR_SKIP}Skipped ports: ${COLOR_PORT}${skipped}"
	[ $nbignored -gt 0 ] && COLOR_ARROW="${COLOR_IGNORE}" \
	    msg "${COLOR_IGNORE}Ignored ports: ${COLOR_PORT}${ignored}"

	show_build_summary
	show_log_info

	return 0
}

write_usock() {
	[ $# -gt 1 ] || eargs write_usock socket msg
	local socket="$1"
	shift
	nc -U "${socket}" <<- EOF
	$@
	EOF
}

# If running as non-root, redirect this command to queue and exit
maybe_run_queued() {
	[ $(/usr/bin/id -u) -eq 0 ] && return 0
	local this_command

	# If poudriered not running then the command cannot be
	# satisfied.
	/usr/sbin/service poudriered onestatus >/dev/null 2>&1 || \
	    err 1 "This command requires root or poudriered running"

	this_command="${SCRIPTPATH##*/}"
	this_command="${this_command%.sh}"

	write_usock ${QUEUE_SOCKET} command: "${this_command}", arguments: "$@"
	exit
}

get_host_arch() {
	[ $# -eq 1 ] || eargs get_host_arch var_return
	local var_return="$1"
	local _arch

	_arch="$(uname -m).$(uname -p)"
	# If TARGET=TARGET_ARCH trim it away and just use TARGET_ARCH
	[ "${_arch%.*}" = "${_arch#*.}" ] && _arch="${_arch#*.}"
	setvar "${var_return}" "${_arch}"
}

check_emulation() {
	[ $# -eq 2 ] || eargs check_emulation real_arch wanted_arch
	local real_arch="${1}"
	local wanted_arch="${2}"

	if need_emulation "${wanted_arch}"; then
		msg "Cross-building ports for ${wanted_arch} on ${real_arch} requires QEMU"
		[ -x "${BINMISC}" ] || \
		    err 1 "Cannot find ${BINMISC}. Install ${BINMISC} and restart"
		EMULATOR=$(${BINMISC} lookup ${wanted_arch#*.} 2>/dev/null | \
		    awk '/interpreter:/ {print $2}')
		[ -x "${EMULATOR}" ] || \
		    err 1 "You need to install the qemu-user-static package or setup an emulator with binmiscctl(8) for ${wanted_arch#*.}"
		export QEMU_EMULATING=1
	fi
}

need_emulation() {
	[ $# -eq 1 ] || eargs need_emulation wanted_arch
	local wanted_arch="$1"
	local target_arch

	# kern.supported_archs is a list of TARGET_ARCHs.
	target_arch="${wanted_arch#*.}"

	# Check the list of supported archs from the kernel.
	# DragonFly does not have kern.supported_archs, fallback to
	# uname -m (advised by dillon)
	if { sysctl -n kern.supported_archs 2>/dev/null || uname -m; } | \
	    grep -qw "${target_arch}"; then
		return 1
	else
		# Returning 1 means no emulation required.
		return 0
	fi
}

need_cross_build() {
	[ $# -eq 2 ] || eargs need_cross_build real_arch wanted_arch
	local real_arch="$1"
	local wanted_arch="$2"

	# Check TARGET=i386 not TARGET_ARCH due to pc98/i386
	[ "${wanted_arch%.*}" = "i386" -a "${real_arch}" = "amd64" ] || \
	    [ "${wanted_arch#*.}" = "powerpc" -a \
	    "${real_arch#*.}" = "powerpc64" ] || \
	    need_emulation "${wanted_arch}"
}

_jlock() {
	setvar "$1" "${SHARED_LOCK_DIR}/poudriere.${MASTERNAME}.lock"
}

lock_jail() {
	local jlock jlockf jlockpid

	_jlock jlock
	jlockf="${jlock}/pid"
	mkdir -p "${SHARED_LOCK_DIR}" >/dev/null 2>&1 || :
	# Ensure no other processes are trying to start this jail
	if ! mkdir "${jlock}" 2>/dev/null; then
		if [ -d "${jlock}" ]; then
			jlockpid=
			if [ -f "${jlockf}" ]; then
				if locked_mkdir 5 "${jlock}.pid"; then
					read jlockpid < "${jlockf}" || :
					rmdir "${jlock}.pid"
				else
					# Something went wrong, just try again
					lock_jail
					return
				fi
			fi
			if [ -n "${jlockpid}" ]; then
				if ! kill -0 ${jlockpid} >/dev/null 2>&1; then
					# The process is dead;
					# the lock is stale
					rm -rf "${jlock}"
					# Try to get the lock again
					lock_jail
					return
				else
					# The lock is currently held
					err 1 "jail currently starting: ${MASTERNAME}"
				fi
			else
				# This shouldn't happen due to the
				# use of locking on the file, just
				# blow it away and try again.
				rm -rf "${jlock}"
				lock_jail
				return
			fi
		else
			err 1 "Unable to create jail lock ${jlock}"
		fi
	else
		# We're safe to start the jail and to later remove the lock.
		if locked_mkdir 5 "${jlock}.pid"; then
			CREATED_JLOCK=1
			echo "$$" > "${jlock}/pid"
			rmdir "${jlock}.pid"
			return 0
		else
			# Something went wrong, just try again
			lock_jail
			return
		fi
	fi
}

setup_ccache() {
	[ $# -eq 1 ] || eargs setup_ccache tomnt
	local tomnt="$1"

	if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
		cat >> "${tomnt}/etc/make.conf" <<-EOF
		WITH_CCACHE_BUILD=yes
		CCACHE_DIR=${HOME}/.ccache
		EOF
	fi
	# A static host version may have been requested.
	if [ -n "${CCACHE_STATIC_PREFIX}" ] && \
	    [ -x "${CCACHE_STATIC_PREFIX}/bin/ccache" ]; then
		file "${CCACHE_STATIC_PREFIX}/bin/ccache" | \
		    grep -q "statically linked" || \
		    err 1 "CCACHE_STATIC_PREFIX used but ${CCACHE_STATIC_PREFIX}/bin/ccache is not static."
		mkdir -p "${tomnt}${CCACHE_JAIL_PREFIX}/libexec/ccache/world" \
		    "${tomnt}${CCACHE_JAIL_PREFIX}/bin"
		msg "Copying host static ccache from ${CCACHE_STATIC_PREFIX}/bin/ccache"
		cp -f "${CCACHE_STATIC_PREFIX}/bin/ccache" \
		    "${CCACHE_STATIC_PREFIX}/bin/ccache-update-links" \
		    "${tomnt}${CCACHE_JAIL_PREFIX}/bin/"
		cp -f "${CCACHE_STATIC_PREFIX}/libexec/ccache/world/ccache" \
		    "${tomnt}${CCACHE_JAIL_PREFIX}/libexec/ccache/world/ccache"
		# Tell the ports framework that we don't need it to add
		# a BUILD_DEPENDS on everything for ccache.
		# Also set it up to look in our ccacheprefix location for the
		# wrappers.
		cat >> "${tomnt}/etc/make.conf" <<-EOF
		NO_CCACHE_DEPEND=1
		CCACHE_WRAPPER_PATH=	${CCACHE_JAIL_PREFIX}/libexec/ccache
		EOF
		# Link the wrapper update script to /sbin so that
		# any package trying to update the links will find it
		# rather than an actual ccache package in the jail.
		ln -fs "../${CCACHE_JAIL_PREFIX}/bin/ccache-update-links" \
		    "${tomnt}/sbin/ccache-update-links"
		# Fix the wrapper update script to always make the links
		# in the new prefix.
		sed -i '' -e "s,^\(PREFIX\)=.*,\1=\"${CCACHE_JAIL_PREFIX}\"," \
		    "${tomnt}${CCACHE_JAIL_PREFIX}/bin/ccache-update-links"
		# Create base compiler links
		injail "${CCACHE_JAIL_PREFIX}/bin/ccache-update-links"
	fi
}

# Copy in the latest version of the emulator.
qemu_install() {
	[ $# -eq 1 ] || eargs qemu_install mnt
	local mnt="$1"

	msg "Copying latest version of the emulator from: ${EMULATOR}"
	[ -n "${EMULATOR}" ] || err 1 "No EMULATOR set"
	mkdir -p "${mnt}${EMULATOR%/*}"
	cp -f "${EMULATOR}" "${mnt}${EMULATOR}"
}

setup_xdev() {
	[ $# -eq 2 ] || eargs setup_xdev mnt target
	local mnt="$1"
	local target="$2"
	local HLINK_FILES file

	[ -d "${mnt}/nxb-bin" ] || return 0

	msg_n "Setting up native-xtools environment in jail..."
	cat > "${mnt}/etc/make.nxb.conf" <<-EOF
	CC=/nxb-bin/usr/bin/cc
	CPP=/nxb-bin/usr/bin/cpp
	CXX=/nxb-bin/usr/bin/c++
	AS=/nxb-bin/usr/bin/as
	NM=/nxb-bin/usr/bin/nm
	LD=/nxb-bin/usr/bin/ld
	OBJCOPY=/nxb-bin/usr/bin/objcopy
	SIZE=/nxb-bin/usr/bin/size
	STRIPBIN=/nxb-bin/usr/bin/strip
	SED=/nxb-bin/usr/bin/sed
	RANLIB=/nxb-bin/usr/bin/ranlib
	YACC=/nxb-bin/usr/bin/yacc
	MAKE=/nxb-bin/usr/bin/make
	STRINGS=/nxb-bin/usr/bin/strings
	AWK=/nxb-bin/usr/bin/awk
	FLEX=/nxb-bin/usr/bin/flex
	EOF

	# hardlink these files to capture scripts and tools
	# that explicitly call them instead of using paths.
	HLINK_FILES="usr/bin/env usr/bin/gzip usr/bin/id usr/bin/limits \
			usr/bin/make usr/bin/dirname usr/bin/diff \
			usr/bin/makewhatis \
			usr/bin/find usr/bin/gzcat usr/bin/awk \
			usr/bin/touch usr/bin/sed usr/bin/patch \
			usr/bin/install usr/bin/gunzip \
			usr/bin/readelf usr/bin/sort \
			usr/bin/tar usr/bin/xargs usr/sbin/chown bin/cp \
			bin/cat bin/chmod bin/echo bin/expr \
			bin/hostname bin/ln bin/ls bin/mkdir bin/mv \
			bin/realpath bin/rm bin/rmdir bin/sleep \
			sbin/sha256 sbin/sha512 sbin/md5 sbin/sha1"

	# Endian issues on mips/mips64 are not handling exec of 64bit shells
	# from emulated environments correctly.  This works just fine on ARM
	# because of the same issue, so allow it for now.
	[ ${target} = "mips" ] || \
	    HLINK_FILES="${HLINK_FILES} bin/sh bin/csh"

	for file in ${HLINK_FILES}; do
		if [ -f "${mnt}/nxb-bin/${file}" ]; then
			unlink "${mnt}/${file}"
			ln "${mnt}/nxb-bin/${file}" "${mnt}/${file}"
		fi
	done

	echo " done"
}

setup_ports_env() {
	[ $# -eq 2 ] || eargs setup_ports_env mnt __MAKE_CONF
	local mnt="$1"
	local __MAKE_CONF="$2"

	# Suck in ports environment to avoid redundant fork/exec for each
	# child.
	if [ -f "${mnt}${PORTSDIR}/Mk/Scripts/ports_env.sh" ]; then
		local make

		if [ -x "${mnt}/usr/bin/bmake" ]; then
			make=/usr/bin/bmake
		else
			make=/usr/bin/make
		fi
		{
			echo "#### /usr/ports/Mk/Scripts/ports_env.sh ####"
			injail env \
			    SCRIPTSDIR=${PORTSDIR}/Mk/Scripts \
			    PORTSDIR=${PORTSDIR} \
			    MAKE=${make} \
			    /bin/sh ${PORTSDIR}/Mk/Scripts/ports_env.sh | \
			    grep '^export [^;&]*' | \
			    sed -e 's,^export ,,' -e 's,=",=,' -e 's,"$,,'
			echo "#### Misc Poudriere ####"
			# This is not set by ports_env as older Poudriere
			# would not handle it right.
			echo "GID=0"
			echo "UID=0"
		} >> "${__MAKE_CONF}"
	fi
}

jail_start() {
	[ $# -lt 2 ] && eargs jail_start name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local arch host_arch
	local mnt
	local needfs="${NULLFSREF}"
	local needkld kldpair kld kldmodname
	local tomnt
	local portbuild_uid aarchld

	lock_jail

	if [ -n "${MASTERMNT}" ]; then
		tomnt="${MASTERMNT}"
	else
		_mastermnt tomnt
	fi
	_jget arch ${name} arch
	get_host_arch host_arch
	_jget mnt ${name} mnt

	# Protect ourselves from OOM
	madvise_protect $$ || :

	PORTSDIR="/usr/ports"

	JAIL_OSVERSION=$(awk '/\#define __FreeBSD_version/ { print $3 }' "${mnt}/usr/include/sys/param.h")

	[ ${JAIL_OSVERSION} -lt 900000 ] && needkld="${needkld} sem"

	if [ "${DISTFILES_CACHE}" != "no" -a ! -d "${DISTFILES_CACHE}" ]; then
		err 1 "DISTFILES_CACHE directory does not exist. (c.f.  poudriere.conf)"
	fi
	[ ${TMPFS_ALL} -ne 1 ] && [ $(sysctl -n kern.securelevel) -ge 1 ] && \
	    err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags. USE_TMPFS=all can override this."
	[ "${name#*.*}" = "${name}" ] ||
		err 1 "The jail name cannot contain a period (.). See jail(8)"
	[ "${ptname#*.*}" = "${ptname}" ] ||
		err 1 "The ports name cannot contain a period (.). See jail(8)"
	[ "${setname#*.*}" = "${setname}" ] ||
		err 1 "The set name cannot contain a period (.). See jail(8)"
	if [ -n "${HARDLINK_CHECK}" -a ! "${HARDLINK_CHECK}" = "00" ]; then
		case ${BUILD_AS_NON_ROOT} in
			[Yy][Ee][Ss])
				msg_warn "You have BUILD_AS_NON_ROOT set to '${BUILD_AS_NON_ROOT}' (c.f. poudriere.conf),"
				msg_warn "    and 'security.bsd.hardlink_check_uid' or 'security.bsd.hardlink_check_gid' are not set to '0'."
				err 1 "Poudriere will not be able to stage some ports. Exiting."
				;;
			*)
				;;
		esac
	fi
	if [ -z "${NOLINUX}" ]; then
		if [ "${arch}" = "i386" -o "${arch}" = "amd64" ]; then
			needfs="${needfs} linprocfs"
			needkld="${needkld} linuxelf:linux"
			if [ "${arch}" = "amd64" ] && \
			    [ ${HOST_OSVERSION} -ge 1002507 ]; then
				needkld="${needkld} linux64elf:linux64"
			fi
		fi
	fi

	if [ ${JAILED} -eq 1 ]; then
		# Verify we have some of the needed configuration enabled
		# or advise how to fix it.
		local nested_perm

		[ $(sysctl -n security.jail.enforce_statfs) -eq 1 ] || \
		    nested_perm="${nested_perm:+${nested_perm} }enforce_statfs=1"
		[ $(sysctl -n security.jail.mount_allowed) -eq 1 ] || \
		    nested_perm="${nested_perm:+${nested_perm} }allow.mount"
		[ $(sysctl -n security.jail.mount_devfs_allowed) -eq 1 ] || \
		    nested_perm="${nested_perm:+${nested_perm} }allow.mount.devfs"
		[ $(sysctl -n security.jail.mount_nullfs_allowed) -eq 1 ] || \
		    nested_perm="${nested_perm:+${nested_perm} }allow.mount.nullfs"
		[ "${USE_TMPFS}" != "no" ] && \
		    [ $(sysctl -n security.jail.mount_tmpfs_allowed) -eq 0 ] && \
		    nested_perm="${nested_perm:+${nested_perm} }allow.mount.tmpfs (with USE_TMPFS=${USE_TMPFS})"
		[ -n "${nested_perm}" ] && \
		    err 1 "Nested jail requires these missing params: ${nested_perm}"
	fi
	[ "${USE_TMPFS}" != "no" ] && needfs="${needfs} tmpfs"
	[ "${USE_PROCFS}" = "yes" ] && needfs="${needfs} procfs"
	[ "${USE_FDESCFS}" = "yes" ] && \
	    [ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ] && \
	    needfs="${needfs} fdescfs"
	for fs in ${needfs}; do
		if ! lsvfs $fs >/dev/null 2>&1; then
			if [ $JAILED -eq 0 ]; then
				kldload $fs || err 1 "Required kernel module '${fs}' not found"
			else
				err 1 "please load the $fs module on host using \"kldload $fs\""
			fi
		fi
	done
	for kldpair in ${needkld}; do
		kldmodname="${kldpair%:*}"
		kld="${kldpair#*:}"
		if ! kldstat -q -m "${kldmodname}" ; then
			if [ $JAILED -eq 0 ]; then
				kldload "${kld}" || \
				    err 1 "Required kernel module '${kld}' not found"
			else
				err 1 "Please load the ${kld} module on the host using \"kldload ${kld}\""
			fi
		fi
	done
	jail_exists ${name} || err 1 "No such jail: ${name}"
	jail_runs ${MASTERNAME} && err 1 "jail already running: ${MASTERNAME}"
	check_emulation "${host_arch}" "${arch}"

	# Block the build dir from being traversed by non-root to avoid
	# system blowup due to all of the extra mounts
	mkdir -p ${MASTERMNT%/ref}
	chmod 0755 ${POUDRIERE_DATA}/.m
	chmod 0711 ${MASTERMNT%/ref}
	# Mount tmpfs at the root to avoid crossing tmpfs-zfs-tmpfs boundary
	# for cloning.
	if [ ${TMPFS_ALL} -eq 1 ]; then
		mnt_tmpfs all "${MASTERMNTROOT}"
	fi

	export HOME=/root
	export USER=root

	# Only set STATUS=1 if not turned off
	# jail -s should not do this or jail will stop on EXIT
	[ ${SET_STATUS_ON_START-1} -eq 1 ] && export STATUS=1
	msg_n "Creating the reference jail..."
	if [ ${USE_CACHED} = "yes" ]; then
		export CACHESOCK=${MASTERMNT%/ref}/cache.sock
		export CACHEPID=${MASTERMNT%/ref}/cache.pid
		cached -s /${MASTERNAME} -p ${CACHEPID} -n ${MASTERNAME}
	fi
	clonefs ${mnt} ${tomnt} clean
	echo " done"

	if [ ${JAIL_OSVERSION} -gt ${HOST_OSVERSION} ]; then
		msg_warn "!!! Jail is newer than host. (Jail: ${JAIL_OSVERSION}, Host: ${HOST_OSVERSION}) !!!"
		msg_warn "This is not supported."
		msg_warn "Host kernel must be same or newer than jail."
		msg_warn "Expect build failures."
		sleep 1
	fi

	msg "Mounting system devices for ${MASTERNAME}"
	do_jail_mounts "${mnt}" "${tomnt}" ${arch} ${name}

	# May already be set for pkgclean
	: ${PACKAGES:=${POUDRIERE_DATA}/packages/${MASTERNAME}}

	msg "Mounting ports/packages/distfiles"

	mkdir -p ${PACKAGES}/
	was_a_bulk_run && stash_packages

	do_portbuild_mounts ${tomnt} ${name} ${ptname} ${setname}

	# Handle special QEMU needs.
	if [ ${QEMU_EMULATING} -eq 1 ]; then
		setup_xdev "${tomnt}" "${arch%.*}"

		# QEMU is really slow. Extend the time significantly.
		msg "Raising MAX_EXECUTION_TIME and NOHANG_TIME for QEMU from QEMU_ values"
		MAX_EXECUTION_TIME=${QEMU_MAX_EXECUTION_TIME}
		NOHANG_TIME=${QEMU_NOHANG_TIME}
		# Setup native-xtools overrides.
		cat >> "${tomnt}/etc/make.conf" <<-EOF
		.sinclude "/etc/make.nxb.conf"
		EOF
		qemu_install "${tomnt}"
	fi
	# Handle special ARM64 needs
	if [ "${arch#*.}" = "aarch64" ] && ! [ -f "${tomnt}/usr/bin/ld" ]; then
		for aarchld in /usr/local/aarch64-*freebsd*/bin/ld; do
			case "${aarchld}" in
			"/usr/local/aarch64-*freebsd*/bin/ld")
				# empty dir
				err 1 "Arm64 requires aarch64-binutils to be installed."
				;;
			esac
			msg "Copying aarch64-binutils ld from "${aarchld}""
			cp -f "${aarchld}" \
			    "${tomnt}/usr/bin/ld"
			if [ -d "${tomnt}/nxb-bin/usr/bin" ]; then
				# Create a symlink to satisfy the LD in
				# make.nxb.conf and because running
				# /nxb-bin/usr/bin/cc defaults to looking for
				# /nxb-bin/usr/bin/ld.
				ln -f "${tomnt}/usr/bin/ld" \
				    "${tomnt}/nxb-bin/usr/bin/ld"
			fi
		done
	fi

	cat >> "${tomnt}/etc/make.conf" <<-EOF
	USE_PACKAGE_DEPENDS=yes
	BATCH=yes
	WRKDIRPREFIX=/wrkdirs
	PORTSDIR=${PORTSDIR}
	PACKAGES=/packages
	DISTDIR=/distfiles
	EOF
	[ -z "${NO_FORCE_PACKAGE}" ] && \
	    echo "FORCE_PACKAGE=yes" >> "${tomnt}/etc/make.conf"
	if [ -z "${NO_PACKAGE_BUILDING}" ]; then
		echo "PACKAGE_BUILDING=yes" >> "${tomnt}/etc/make.conf"
		export PACKAGE_BUILDING=yes
		echo "PACKAGE_BUILDING_FLAVORS=yes" >> "${tomnt}/etc/make.conf"
	fi

	setup_makeconf ${tomnt}/etc/make.conf ${name} ${ptname} ${setname}
	load_blacklist ${name} ${ptname} ${setname}

	[ -n "${RESOLV_CONF}" ] && cp -v "${RESOLV_CONF}" "${tomnt}/etc/"
	msg "Starting jail ${MASTERNAME}"
	jstart
	if [ ${CREATED_JLOCK:-0} -eq 1 ]; then
		_jlock jlock
		rm -rf "${jlock}" 2>/dev/null || :
	fi
	injail id >/dev/null 2>&1 || \
	    err 1 "Unable to execute id(1) in jail. Emulation or ABI wrong."
	portbuild_uid=$(injail id -u ${PORTBUILD_USER} 2>/dev/null || :)
	if [ -z "${portbuild_uid}" ]; then
		msg_n "Creating user/group ${PORTBUILD_USER}"
		injail pw groupadd ${PORTBUILD_USER} -g ${PORTBUILD_UID} || \
		err 1 "Unable to create group ${PORTBUILD_USER}"
		injail pw useradd ${PORTBUILD_USER} -u ${PORTBUILD_UID} -d /nonexistent -c "Package builder" || \
		err 1 "Unable to create user ${PORTBUILD_USER}"
		echo " done"
	else
		PORTBUILD_UID=${portbuild_uid}
		PORTBUILD_GID=$(injail id -g ${PORTBUILD_USER})
	fi
	injail service ldconfig start >/dev/null || \
	    err 1 "Failed to set ldconfig paths."

	setup_ccache "${tomnt}"

	# We want this hook to run before any make -V executions in case
	# a hook modifies ports or the jail somehow relevant.
	run_hook jail start

	setup_ports_env "${tomnt}" "${tomnt}/etc/make.conf"

	PKG_EXT="txz"
	PKG_BIN="/.p/pkg-static"
	PKG_ADD="${PKG_BIN} add"
	PKG_DELETE="${PKG_BIN} delete -y -f"
	PKG_VERSION="${PKG_BIN} version"

	[ -n "${PKG_REPO_SIGNING_KEY}" ] &&
		! [ -f "${PKG_REPO_SIGNING_KEY}" ] &&
		err 1 "PKG_REPO_SIGNING_KEY defined but the file is missing."

	# Fetch library list for later comparisons
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		CHANGED_DEPS_LIBLIST=$(injail \
		    ldconfig -r | \
		    awk '$1 ~ /:-l/ { gsub(/.*-l/, "", $1); printf("%s ",$1) } END { printf("\n") }')
	fi

	return 0
}

load_blacklist() {
	[ $# -lt 2 ] && eargs load_blacklist name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local bl b bfile

	bl="- ${setname} ${ptname} ${name}"
	[ -n "${setname}" ] && bl="${bl} ${ptname}-${setname}"
	bl="${bl} ${name}-${ptname}"
	[ -n "${setname}" ] && bl="${bl} ${name}-${setname} \
		${name}-${ptname}-${setname}"
	# If emulating always load a qemu-blacklist as it has special needs.
	[ ${QEMU_EMULATING} -eq 1 ] && bl="${bl} qemu"
	for b in ${bl} ; do
		if [ "${b}" = "-" ]; then
			unset b
		fi
		bfile=${b:+${b}-}blacklist
		[ -f ${POUDRIERED}/${bfile} ] || continue
		for port in $(grep -h -v -E '(^[[:space:]]*#|^[[:space:]]*$)' \
		    ${POUDRIERED}/${bfile} | sed -e 's|[[:space:]]*#.*||'); do
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
	local makeconf opt plugin_dir
	local arch host_arch

	get_host_arch host_arch
	# The jail may be empty for poudriere-options.
	if [ -n "${name}" ]; then
		_jget arch "${name}" arch
	elif [ -n "${ARCH}" ]; then
		arch="${ARCH}"
	fi

	if [ -n "${arch}" ]; then
		if need_cross_build "${host_arch}" "${arch}"; then
			cat >> "${dst_makeconf}" <<-EOF
			MACHINE=${arch%.*}
			MACHINE_ARCH=${arch#*.}
			ARCH=\${MACHINE_ARCH}
			EOF
		fi
	fi

	makeconf="- ${setname} ${ptname} ${name}"
	[ -n "${setname}" ] && makeconf="${makeconf} ${ptname}-${setname}"
	makeconf="${makeconf} ${name}-${ptname}"
	[ -n "${setname}" ] && makeconf="${makeconf} ${name}-${setname} \
		    ${name}-${ptname}-${setname}"
	for opt in ${makeconf}; do
		append_make "${POUDRIERED}" "${opt}" "${dst_makeconf}"
	done

	# Check for and load plugin make.conf files
	if [ -d "${HOOKDIR}/plugins" ]; then
		for plugin_dir in ${HOOKDIR}/plugins/*; do
			# Check empty dir
			case "${plugin_dir}" in
			"${HOOKDIR}/plugins/*") break ;;
			esac
			append_make "${plugin_dir}" "-" "${dst_makeconf}"
		done
	fi

	# We will handle DEVELOPER for testing when appropriate
	if grep -q '^DEVELOPER=' ${dst_makeconf}; then
		msg_warn "DEVELOPER=yes ignored from make.conf. Use 'bulk -t' or 'testport' for testing instead."
		sed -i '' '/^DEVELOPER=/d' ${dst_makeconf}
	fi
}

include_poudriere_confs() {
	local files file flag args_hack debug

	# msg_debug is not properly setup this early for VERBOSE to be set
	# so spy on -v and set debug and use it locally instead.
	debug=0
	# Spy on cmdline arguments so this function is not needed in
	# every new sub-command file, which could lead to missing it.
	args_hack=$(echo " $@"|grep -Eo -- ' -[^jpvz ]*([jpz] ?[^ ]*|v+)'|tr '\n' ' '|sed -Ee 's, -[^jpvz ]*([jpz]|v+) ?([^ ]*),-\1 \2,g')
	set -- ${args_hack}
	while getopts "j:p:vz:" flag; do
		case ${flag} in
			j) jail="${OPTARG}" ;;
			p) ptname="${OPTARG}" ;;
			v) debug=$((debug+1)) ;;
			z) setname="${OPTARG}" ;;
			*) ;;
		esac
	done

	if [ -r "${POUDRIERE_ETC}/poudriere.conf" ]; then
		. "${POUDRIERE_ETC}/poudriere.conf"
		[ ${debug} -gt 1 ] && msg_debug "Reading ${POUDRIERE_ETC}/poudriere.conf"
	elif [ -r "${POUDRIERED}/poudriere.conf" ]; then
		. "${POUDRIERED}/poudriere.conf"
		[ ${debug} -gt 1 ] && msg_debug "Reading ${POUDRIERED}/poudriere.conf"
	else
		err 1 "Unable to find a readable poudriere.conf in ${POUDRIERE_ETC} or ${POUDRIERED}"
	fi

	files="${setname} ${ptname} ${jail}"
	[ -n "${ptname}" -a -n "${setname}" ] && \
	    files="${files} ${ptname}-${setname}"
	[ -n "${jail}" -a -n "${ptname}" ] && \
	    files="${files} ${jail}-${ptname}"
	[ -n "${jail}" -a -n "${setname}" ] && \
	    files="${files} ${jail}-${setname}"
	[ -n "${jail}" -a -n "${setname}" -a -n "${ptname}" ] && \
	    files="${files} ${jail}-${ptname}-${setname}"
	for file in ${files}; do
		file="${POUDRIERED}/${file}-poudriere.conf"
		if [ -r "${file}" ]; then
			[ ${debug} -gt 1 ] && msg_debug "Reading ${file}"
			. "${file}"
		fi
	done

	return 0
}

jail_stop() {
	[ $# -ne 0 ] && eargs jail_stop
	local last_status

	# Make sure CWD is not inside the jail or MASTERMNT/.p, which may
	# cause EBUSY from umount.
	cd /tmp

	stop_builders >/dev/null || :
	if [ ${USE_CACHED} = "yes" ]; then
		pkill -15 -F ${CACHEPID} >/dev/null 2>&1 || :
	fi
	run_hook jail stop
	jstop || :
	msg "Unmounting file systems"
	destroyfs ${MASTERMNT} jail || :
	if [ ${TMPFS_ALL} -eq 1 ]; then
		if ! umount ${UMOUNT_NONBUSY} "${MASTERMNTROOT}" 2>/dev/null; then
			umount -f "${MASTERMNTROOT}" 2>/dev/null || :
		fi
	fi
	rm -rfx ${MASTERMNT}/../
	export STATUS=0

	# Don't override if there is a failure to grab the last status.
	_bget last_status status 2>/dev/null || :
	[ -n "${last_status}" ] && bset status "stopped:${last_status}" \
	    2>/dev/null || :
}

jail_cleanup() {
	local wait_pids

	[ -n "${CLEANED_UP}" ] && return 0
	msg "Cleaning up"

	# Only bother with this if using jails as this may be being ran
	# from queue.sh or daemon.sh, etc.
	if [ -n "${MASTERMNT}" -a -n "${MASTERNAME}" ] && was_a_jail_run; then
		# If this is a builder, don't cleanup, the master will handle that.
		if [ -n "${MY_JOBID}" ]; then
			if [ -n "${PKGNAME}" ]; then
				clean_pool "${PKGNAME}" "" "failed" || :
			fi
			return 0
		fi

		if [ -d ${MASTERMNT}/.p/var/run ]; then
			for pid in ${MASTERMNT}/.p/var/run/*.pid; do
				# Ensure there is a pidfile to read or break
				[ "${pid}" = "${MASTERMNT}/.p/var/run/*.pid" ] && break
				pkill -15 -F ${pid} >/dev/null 2>&1 || :
				wait_pids="${wait_pids} ${pid}"
			done
			_wait ${wait_pids} || :
		fi

		jail_stop

		rm -rf \
		    ${PACKAGES}/.npkg \
		    ${POUDRIERE_DATA}/packages/${MASTERNAME}/.latest/.npkg \
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
	[ $# -eq 1 ] || eargs sanity_check_pkg pkg
	local pkg="$1"
	local compiled_deps_pkgnames pkgname dep_pkgname

	pkgname="${pkg##*/}"
	pkgname="${pkgname%.*}"
	pkgbase_is_needed "${pkgname}" || return 0
	pkg_get_dep_origin_pkgnames '' compiled_deps_pkgnames "${pkg}"
	for dep_pkgname in ${compiled_deps_pkgnames}; do
		if [ ! -e "${PACKAGES}/All/${dep_pkgname}.${PKG_EXT}" ]; then
			msg_debug "${pkg} needs missing ${PACKAGES}/All/${dep_pkgname}.${PKG_EXT}"
			msg "Deleting ${pkg##*/}: missing dependency: ${dep_pkgname}"
			delete_pkg "${pkg}"
			return 65	# Package deleted, need another pass
		fi
	done

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
	[ $# -eq 1 ] || eargs check_leftovers mnt
	local mnt="${1}"

	( cd "${mnt}" && \
	    mtree -X ${mnt}/.p/mtree.preinstexclude -f ${mnt}/.p/mtree.preinst \
	    -p . ) | while read l; do
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
	[ $# -eq 6 ] || eargs check_fs_violation mnt mtree_target originspec \
	    status_msg err_msg status_value
	local mnt="$1"
	local mtree_target="$2"
	local originspec="$3"
	local status_msg="$4"
	local err_msg="$5"
	local status_value="$6"
	local tmpfile=$(mktemp -t check_fs_violation)
	local ret=0

	msg_n "${status_msg}..."
	( cd "${mnt}" && mtree -X ${mnt}/.p/mtree.${mtree_target}exclude \
		-f ${mnt}/.p/mtree.${mtree_target} \
		-p . ) >> ${tmpfile}
	echo " done"

	if [ -s ${tmpfile} ]; then
		msg "Error: ${err_msg}"
		cat ${tmpfile}
		bset_job_status "${status_value}" "${originspec}"
		job_msg_verbose "Status   ${COLOR_PORT}${originspec} | ${PKGNAME}${COLOR_RESET}: ${status_value}"
		ret=1
	fi
	unlink ${tmpfile}

	return $ret
}

gather_distfiles() {
	[ $# -eq 3 ] || eargs gather_distfiles originspec from to
	local originspec="$1"
	local from=$(realpath $2)
	local to=$(realpath $3)
	local sub dists d tosubd specials special origin
	local dep_originspec pkgname flavor

	port_var_fetch_originspec "${originspec}" \
	    DIST_SUBDIR sub \
	    ALLFILES dists || \
	    err 1 "Failed to lookup distfiles for ${originspec}"

	originspec_decode "${originspec}" origin '' flavor
	if [ "${ORIGINSPEC}" = "${originspec}" ]; then
		# Building main port
		pkgname="${PKGNAME}"
	else
		# Recursive gather_distfiles()
		shash_get originspec-pkgname "${originspec}" pkgname || \
		    err 1 "gather_distfiles: Could not find PKGNAME for ${originspec}"
	fi
	shash_get pkgname-depend_specials "${pkgname}" specials || specials=

	job_msg_dev "${COLOR_PORT}${origin}${flavor:+@${flavor}} | ${PKGNAME}${COLOR_RESET}: distfiles ${from} -> ${to}"
	for d in ${dists}; do
		[ -f ${from}/${sub}/${d} ] || continue
		tosubd=${to}/${sub}/${d}
		mkdir -p ${tosubd%/*} || return 1
		do_clone "${from}/${sub}/${d}" "${to}/${sub}/${d}" || return 1
	done

	for special in ${specials}; do
		gather_distfiles "${special}" "${from}" "${to}"
	done

	return 0
}

# Build+test port and return 1 on first failure
# Return 2 on test failure if PORTTESTING_FATAL=no
_real_build_port() {
	[ $# -ne 1 ] && eargs _real_build_port originspec
	local originspec="$1"
	local port flavor portdir
	local mnt
	local log
	local network
	local hangstatus
	local pkgenv phaseenv jpkg
	local targets install_order
	local jailuser
	local testfailure=0
	local max_execution_time allownetworking
	local _need_root NEED_ROOT PREFIX max_files

	_my_path mnt
	_log_path log

	originspec_decode "${originspec}" port '' flavor
	portdir="/usr/ports/${port}"

	if [ "${BUILD_AS_NON_ROOT}" = "yes" ]; then
		_need_root="NEED_ROOT NEED_ROOT"
	fi
	port_var_fetch_originspec "${originspec}" \
	    ${PORT_FLAGS} \
	    PREFIX PREFIX \
	    ${_need_root}

	# Use bootstrap PKG when not building pkg itself.
	if false && [ ${QEMU_EMULATING} -eq 1 ]; then
		case "${port}" in
		ports-mgmt/pkg|ports-mgmt/pkg-devel) ;;
		*)
			if ensure_pkg_installed; then
				export PKG_BIN="/.p/pkg-static"
			fi
			;;
		esac
	fi

	allownetworking=0
	for jpkg in ${ALLOW_NETWORKING_PACKAGES}; do
		case "${PKGBASE}" in
		${jpkg})
			job_msg_warn "ALLOW_NETWORKING_PACKAGES: Allowing full network access for ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${PKGNAME}${COLOR_RESET}"
			msg_warn "ALLOW_NETWORKING_PACKAGES: Allowing full network access for ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${PKGNAME}${COLOR_RESET}"
			allownetworking=1
			JNETNAME="n"
			break
			;;
		esac
	done

	# Must install run-depends as 'actual-package-depends' and autodeps
	# only consider installed packages as dependencies
	jailuser=root
	if [ "${BUILD_AS_NON_ROOT}" = "yes" ] && [ -z "${NEED_ROOT}" ]; then
		jailuser=${PORTBUILD_USER}
	fi
	# XXX: run-depends can come out of here with some bsd.port.mk
	# changes. Easier once pkg_install is EOL.
	install_order="run-depends stage package"
	# Don't need to install if only making packages and not
	# testing.
	[ -n "${PORTTESTING}" ] && \
	    install_order="${install_order} install"
	targets="check-sanity pkg-depends fetch-depends fetch checksum \
		  extract-depends extract patch-depends patch build-depends \
		  lib-depends configure build ${install_order} \
		  ${PORTTESTING:+deinstall}"

	# If not testing, then avoid rechecking deps in build/install;
	# When testing, check depends twice to ensure they depend on
	# proper files, otherwise they'll hit 'package already installed'
	# errors.
	if [ -z "${PORTTESTING}" ]; then
		PORT_FLAGS="${PORT_FLAGS} NO_DEPENDS=yes"
	else
		PORT_FLAGS="${PORT_FLAGS} STRICT_DEPENDS=yes"
	fi

	for phase in ${targets}; do
		max_execution_time=${MAX_EXECUTION_TIME}
		phaseenv=
		JUSER=${jailuser}
		bset_job_status "${phase}" "${originspec}"
		job_msg_verbose "Status   ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${PKGNAME}${COLOR_RESET}: ${COLOR_PHASE}${phase}"
		[ -n "${PORTTESTING}" ] && \
		    phaseenv="${phaseenv} DEVELOPER_MODE=yes"
		case ${phase} in
		check-sanity)
			[ -n "${PORTTESTING}" ] && \
			    phaseenv="${phaseenv} DEVELOPER=1"
			;;
		fetch)
			mkdir -p ${mnt}/portdistfiles
			if [ "${DISTFILES_CACHE}" != "no" ]; then
				echo "DISTDIR=/portdistfiles" >> ${mnt}/etc/make.conf
				gather_distfiles "${originspec}" \
				    ${DISTFILES_CACHE} ${mnt}/portdistfiles \
				    || return 1
			fi
			JNETNAME="n"
			JUSER=root
			;;
		extract)
			max_execution_time=${MAX_EXECUTION_TIME_EXTRACT}
			if [ "${JUSER}" != "root" ]; then
				chown -R ${JUSER} ${mnt}/wrkdirs
			fi
			;;
		configure) [ -n "${PORTTESTING}" ] && markfs prebuild ${mnt} ;;
		run-depends)
			JUSER=root
			if [ -n "${PORTTESTING}" ]; then
				check_fs_violation ${mnt} prebuild \
				    "${originspec}" \
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
		checksum|*-depends) JUSER=root ;;
		stage) [ -n "${PORTTESTING}" ] && markfs prestage ${mnt} ;;
		install)
			max_execution_time=${MAX_EXECUTION_TIME_INSTALL}
			JUSER=root
			[ -n "${PORTTESTING}" ] && markfs preinst ${mnt}
			;;
		package)
			max_execution_time=${MAX_EXECUTION_TIME_PACKAGE}
			if [ -n "${PORTTESTING}" ]; then
				check_fs_violation ${mnt} prestage \
				    "${originspec}" \
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
			max_execution_time=${MAX_EXECUTION_TIME_DEINSTALL}
			JUSER=root
			# Skip for all linux ports, they are not safe
			if [ "${PKGNAME%%*linux*}" != "" ]; then
				msg "Checking shared library dependencies"
				# Not using PKG_BIN to avoid bootstrap issues.
				injail "${LOCALBASE}/sbin/pkg" query '%Fp' "${PKGNAME}" | \
				    injail xargs readelf -d 2>/dev/null | \
				    grep NEEDED | sort -u
			fi
			;;
		esac

		print_phase_header ${phase}

		if [ "${phase}" = "package" ]; then
			echo "PACKAGES=/.npkg" >> ${mnt}/etc/make.conf
			# Create sandboxed staging dir for new package for this build
			rm -rf "${PACKAGES}/.npkg/${PKGNAME}"
			mkdir -p "${PACKAGES}/.npkg/${PKGNAME}"
			${NULLMOUNT} \
				"${PACKAGES}/.npkg/${PKGNAME}" \
				${mnt}/.npkg
			chown -R ${JUSER} ${mnt}/.npkg
			:> "${mnt}/.npkg_mounted"
		fi

		if [ "${JUSER}" = "root" ]; then
			export UID=0
			export GID=0
		else
			export UID=${PORTBUILD_UID}
			export GID=${PORTBUILD_UID}
		fi

		if [ "${phase#*-}" = "depends" ]; then
			# No need for nohang or PORT_FLAGS for *-depends
			injail /usr/bin/env USE_PACKAGE_DEPENDS_ONLY=1 ${phaseenv} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    ${phase} || return 1
		else
			# Only set PKGENV during 'package' to prevent
			# testport-built packages from going into the main repo
			# Also enable during stage/install since it now
			# uses a pkg for pkg_tools
			if [ "${phase}" = "package" ]; then
				pkgenv="${PKGENV}"
			else
				pkgenv=
			fi

			nohang ${max_execution_time} ${NOHANG_TIME} \
				${log}/logs/${PKGNAME}.log \
				${MASTERMNT}/.p/var/run/${MY_JOBID:-00}_nohang.pid \
				injail /usr/bin/env ${pkgenv} ${phaseenv} ${PORT_FLAGS} \
				/usr/bin/make -C ${portdir} ${MAKE_ARGS} \
				${phase}
			hangstatus=$? # This is done as it may return 1 or 2 or 3
			if [ $hangstatus -ne 0 ]; then
				# 1 = cmd failed, not a timeout
				# 2 = log timed out
				# 3 = cmd timeout
				if [ $hangstatus -eq 2 ]; then
					msg "Killing runaway build after ${NOHANG_TIME} seconds with no output"
					bset_job_status "${phase}/runaway" "${originspec}"
					job_msg_verbose "Status   ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${PKGNAME}${COLOR_RESET}: ${COLOR_PHASE}runaway"
				elif [ $hangstatus -eq 3 ]; then
					msg "Killing timed out build after ${max_execution_time} seconds"
					bset_job_status "${phase}/timeout" "${originspec}"
					job_msg_verbose "Status   ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${PKGNAME}${COLOR_RESET}: ${COLOR_PHASE}timeout"
				fi
				return 1
			fi
		fi

		if [ "${phase}" = "checksum" ] && \
		    [ ${allownetworking} -eq 0 ]; then
			JNETNAME=""
		fi
		print_phase_footer

		if [ "${phase}" = "checksum" -a "${DISTFILES_CACHE}" != "no" ]; then
			gather_distfiles "${originspec}" ${mnt}/portdistfiles \
			    ${DISTFILES_CACHE} || return 1
		fi

		if [ "${phase}" = "stage" -a -n "${PORTTESTING}" ]; then
			local die=0

			bset_job_status "stage-qa" "${originspec}"
			if ! injail /usr/bin/env DEVELOPER=1 ${PORT_FLAGS} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    stage-qa; then
				msg "Error: stage-qa failures detected"
				[ "${PORTTESTING_FATAL}" != "no" ] &&
					return 1
				die=1
			fi

			bset_job_status "check-plist" "${originspec}"
			if ! injail /usr/bin/env DEVELOPER=1 ${PORT_FLAGS} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    check-plist; then
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
			local add=$(mktemp -t lo.add)
			local add1=$(mktemp -t lo.add1)
			local del=$(mktemp -t lo.del)
			local del1=$(mktemp -t lo.del1)
			local mod=$(mktemp -t lo.mod)
			local mod1=$(mktemp -t lo.mod1)
			local die=0

			msg "Checking for extra files and directories"
			bset_job_status "leftovers" "${originspec}"

			if [ -f "${mnt}${PORTSDIR}/Mk/Scripts/check_leftovers.sh" ]; then
				check_leftovers ${mnt} | sed -e "s|${mnt}||" |
				    injail /usr/bin/env PORTSDIR=${PORTSDIR} \
				    ${PORT_FLAGS} /bin/sh \
				    ${PORTSDIR}/Mk/Scripts/check_leftovers.sh \
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
				plistsub_sed=$(injail /usr/bin/env ${PORT_FLAGS} /usr/bin/make -C ${portdir} -V'PLIST_SUB:C/"//g:NLIB32*:NPERL_*:NPREFIX*:N*="":N*="@comment*:C/(.*)=(.*)/-es!\2!%%\1%%!g/')

				users=$(injail /usr/bin/make -C ${portdir} -VUSERS)
				homedirs=""
				for user in ${users}; do
					user=$(grep ^${user}: ${mnt}${PORTSDIR}/UIDs | cut -f 9 -d : | sed -e "s|/usr/local|${PREFIX}| ; s|^|${mnt}|")
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
			[ ${die} -eq 1 -a "${PREFIX}" != "${LOCALBASE}" ] && \
			    was_a_testport_run && msg \
			    "This test was done with PREFIX!=LOCALBASE which \
may show failures if the port does not respect PREFIX."
			rm -f ${add} ${add1} ${del} ${del1} ${mod} ${mod1}
			[ $die -eq 0 ] || if [ "${PORTTESTING_FATAL}" != "no" ]; then
				return 1
			else
				testfailure=2
			fi
		fi
	done

	if [ -d "${PACKAGES}/.npkg/${PKGNAME}" ]; then
		# everything was fine we can copy the package to the package
		# directory
		find ${PACKAGES}/.npkg/${PKGNAME} \
			-mindepth 1 \( -type f -or -type l \) | while read pkg_path; do
			pkg_file=${pkg_path#${PACKAGES}/.npkg/${PKGNAME}}
			pkg_base=${pkg_file%/*}
			mkdir -p ${PACKAGES}/${pkg_base}
			mv ${pkg_path} ${PACKAGES}/${pkg_base}
		done
	fi

	bset_job_status "build_port_done" "${originspec}"
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
	[ $# -ne 5 ] && eargs save_wrkdir mnt originspec pkgname portdir phase
	local mnt=$1
	local originspec="$2"
	local pkgname="$3"
	local portdir="$4"
	local phase="$5"
	local tardir=${POUDRIERE_DATA}/wrkdirs/${MASTERNAME}/${PTNAME}
	local tarname=${tardir}/${pkgname}.${WRKDIR_ARCHIVE_FORMAT}
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
	unlink ${tarname}
	tar -s ",${mnted_portdir},," -c${COMPRESSKEY}f ${tarname} ${mnted_portdir}/work > /dev/null 2>&1

	job_msg "Saved ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET} wrkdir to: ${tarname}"
}

start_builder() {
	local id=$1
	local arch=$2
	local mnt MY_JOBID

	MY_JOBID=${id}
	_my_path mnt

	# Jail might be lingering from previous build. Already recursively
	# destroyed all the builder datasets, so just try stopping the jail
	# and ignore any errors
	stop_builder "${id}"
	mkdir -p "${mnt}"
	clonefs ${MASTERMNT} ${mnt} prepkg
	markfs prepkg ${mnt} >/dev/null
	do_jail_mounts "${MASTERMNT}" ${mnt} ${arch} ${jname}
	do_portbuild_mounts ${mnt} ${jname} ${ptname} ${setname}
	jstart
	bset ${id} status "idle:"
	run_hook builder start "${id}" "${mnt}"
}

start_builders() {
	local arch=$(injail uname -p)

	msg "Starting/Cloning builders"
	bset status "starting_jobs:"
	run_hook start_builders start

	bset builders "${JOBS}"
	bset status "starting_builders:"
	parallel_start
	for j in ${JOBS}; do
		parallel_run start_builder ${j} ${arch}
	done
	parallel_stop

	run_hook start_builders stop
}

stop_builder() {
	[ $# -eq 1 ] || eargs stop_builder jobid
	local jobid="$1"
	local mnt MY_JOBID

	MY_JOBID="${jobid}"
	_my_path mnt
	run_hook builder stop "${jobid}" "${mnt}"
	jstop
	destroyfs "${mnt}" jail
}

stop_builders() {
	local PARALLEL_JOBS real_parallel_jobs

	# wait for the last running processes
	cat ${MASTERMNT}/.p/var/run/*.pid 2>/dev/null | xargs pwait 2>/dev/null

	if [ ${PARALLEL_JOBS} -ne 0 ]; then
		msg "Stopping ${PARALLEL_JOBS} builders"

		real_parallel_jobs=${PARALLEL_JOBS}
		if [ ${UMOUNT_BATCHING} -eq 0 ]; then
			# Limit builders
			PARALLEL_JOBS=2
		fi
		parallel_start
		for j in ${JOBS-$(jot -w %02d ${real_parallel_jobs})}; do
			parallel_run stop_builder "${j}"
		done
		parallel_stop
	fi

	# No builders running, unset JOBS
	JOBS=""
}

pkgqueue_sanity_check() {
	local always_fail=${1:-1}
	local crashed_packages dependency_cycles deps pkgname origin
	local failed_phase pwd dead_all dead_deps dead_top dead_packages

	pwd="${PWD}"
	cd "${MASTERMNT}/.p"

	# If there are still packages marked as "building" they have crashed
	# and it's likely some poudriere or system bug
	crashed_packages=$( \
		find building -type d -mindepth 1 -maxdepth 1 | \
		sed -e "s,^building/,," | tr '\n' ' ' \
	)
	[ -z "${crashed_packages}" ] ||	\
		err 1 "Crashed package builds detected: ${crashed_packages}"

	# Check if there's a cycle in the need-to-build queue
	dependency_cycles=$(\
		find deps -mindepth 3 | \
		sed -e "s,^deps/[^/]*/,," -e 's:/: :' | \
		# Only cycle errors are wanted
		tsort 2>&1 >/dev/null | \
		sed -e 's/tsort: //' | \
		awk -f ${AWKPREFIX}/dependency_loop.awk \
	)

	if [ -n "${dependency_cycles}" ]; then
		err 1 "Dependency loop detected:
${dependency_cycles}"
	fi

	dead_all=$(mktemp -t dead_packages.all)
	dead_deps=$(mktemp -t dead_packages.deps)
	dead_top=$(mktemp -t dead_packages.top)
	find deps -mindepth 2 > "${dead_all}"
	# All packages in the queue
	cut -d / -f 3 "${dead_all}" | sort -u > "${dead_top}"
	# All packages with dependencies
	cut -d / -f 4 "${dead_all}" | sort -u | sed -e '/^$/d' > "${dead_deps}"
	# Find all packages only listed as dependencies (not in queue)
	dead_packages=$(comm -13 "${dead_top}" "${dead_deps}")
	rm -f "${dead_all}" "${dead_deps}" "${dead_top}" || :

	if [ ${always_fail} -eq 0 ]; then
		if [ -n "${dead_packages}" ]; then
			err 1 "Packages stuck in queue (depended on but not in queue): ${dead_packages}"
		fi
		cd "${pwd}"
		return 0
	fi

	if [ -n "${dead_packages}" ]; then
		failed_phase="stuck_in_queue"
		for pkgname in ${dead_packages}; do
			crashed_build "${pkgname}" "${failed_phase}"
		done
		cd "${pwd}"
		return 0
	fi

	# No cycle, there's some unknown poudriere bug
	err 1 "Unknown stuck queue bug detected. Please submit the entire build output to poudriere developers.
$(find ${MASTERMNT}/.p/building ${MASTERMNT}/.p/pool ${MASTERMNT}/.p/deps ${MASTERMNT}/.p/cleaning)"
}

pkgqueue_empty() {
	[ "${PWD}" = "${MASTERMNT}/.p/pool" ] || \
	    err 1 "pkgqueue_empty requires PWD=${MASTERMNT}/.p/pool"
	local pool_dir dirs
	local n

	if [ -z "${ALL_DEPS_DIRS}" ]; then
		ALL_DEPS_DIRS=$(find ../deps -mindepth 1 -maxdepth 1 -type d)
	fi

	dirs="${ALL_DEPS_DIRS} ${POOL_BUCKET_DIRS}"

	n=0
	# Check twice that the queue is empty. This avoids racing with
	# pkgqueue_done() and balance_pool() moving files between the dirs.
	while [ ${n} -lt 2 ]; do
		for pool_dir in ${dirs}; do
			if ! dirempty ${pool_dir}; then
				return 1
			fi
		done
		n=$((n + 1))
	done

	# Queue is empty
	return 0
}

job_done() {
	[ "${PWD}" = "${MASTERMNT}/.p/pool" ] || \
	    err 1 "job_done requires PWD=${MASTERMNT}/.p/pool"
	[ $# -eq 1 ] || eargs job_done j
	local j="$1"
	local pkgname status

	# CWD is MASTERMNT/.p/pool

	# Failure to find this indicates the job is already done.
	hash_remove builder_pkgnames "${j}" pkgname || return 1
	hash_unset builder_pids "${j}"
	unlink "../var/run/${j}.pid"
	_bget status ${j} status
	rmdir "../building/${pkgname}"
	if [ "${status%%:*}" = "done" ]; then
		bset ${j} status "idle:"
	else
		# Try to cleanup and mark build crashed
		MY_JOBID="${j}" crashed_build "${pkgname}" "${status%%:*}"
		MY_JOBID="${j}" jkill
		bset ${j} status "crashed:"
	fi
}

build_queue() {
	[ "${PWD}" = "${MASTERMNT}/.p/pool" ] || \
	    err 1 "build_queue requires PWD=${MASTERMNT}/.p/pool"
	local j jobid pid pkgname builders_active queue_empty
	local builders_idle idle_only timeout log

	_log_path log

	run_hook build_queue start

	mkfifo ${MASTERMNT}/.p/builders.pipe
	exec 6<> ${MASTERMNT}/.p/builders.pipe
	unlink ${MASTERMNT}/.p/builders.pipe
	queue_empty=0

	msg "Hit CTRL+t at any time to see build progress and stats"

	idle_only=0
	while :; do
		builders_active=0
		builders_idle=0
		timeout=30
		for j in ${JOBS}; do
			# Check if pid is alive. A job will have no PID if it
			# is idle. idle_only=1 is a quick check for giving
			# new work only to idle workers.
			if hash_get builder_pids "${j}" pid; then
				if [ ${idle_only} -eq 1 ] ||
				    kill -0 ${pid} 2>/dev/null; then
					# Job still active or skipping busy.
					builders_active=1
					continue
				fi
				job_done "${j}"
				# Set a 0 timeout to quickly rescan for idle
				# builders to toss a job at since the queue
				# may now be unblocked.
				[ ${queue_empty} -eq 0 -a \
				    ${builders_idle} -eq 1 ] && timeout=0
			fi

			# This builder is idle and needs work.

			[ ${queue_empty} -eq 0 ] || continue

			pkgqueue_get_next pkgname || \
			    err 1 "Failed to find a package from the queue."

			if [ -z "${pkgname}" ]; then
				# Check if the ready-to-build pool and need-to-build pools
				# are empty
				pkgqueue_empty && queue_empty=1

				builders_idle=1
			else
				MY_JOBID="${j}" \
				    PORTTESTING=$(get_porttesting "${pkgname}") \
				    spawn_protected build_pkg "${pkgname}"
				pid=$!
				echo "${pid}" > "../var/run/${j}.pid"
				hash_set builder_pids "${j}" "${pid}"
				hash_set builder_pkgnames "${j}" "${pkgname}"

				builders_active=1
			fi
		done

		if [ ${queue_empty} -eq 1 ]; then
			if [ ${builders_active} -eq 1 ]; then
				# The queue is empty, but builds are still
				# going. Wait on them below.

				# FALLTHROUGH
			else
				# All work is done
				pkgqueue_sanity_check 0
				break
			fi
		fi

		# If builders are idle then there is a problem.
		[ ${builders_active} -eq 1 ] || pkgqueue_sanity_check

		if [ "${HTML_TRACK_REMAINING}" = "yes" ]; then
			pkgqueue_remaining > \
			    "${log}/.poudriere.ports.remaining.tmp%"
			mv -f "${log}/.poudriere.ports.remaining.tmp%" \
			    "${log}/.poudriere.ports.remaining"
		fi

		# Wait for an event from a child. All builders are busy.
		unset jobid; until trappedinfo=; read -t ${timeout} jobid <&6 ||
			[ -z "$trappedinfo" ]; do :; done
		if [ -n "${jobid}" ]; then
			# A job just finished.
			if job_done "${jobid}"; then
				# Do a quick scan to try dispatching
				# ready-to-build to idle builders.
				idle_only=1
			else
				# The job is already done. It was found to be
				# done by a kill -0 check in a scan.
			fi
		else
			# No event found. The next scan will check for
			# crashed builders and deadlocks by validating
			# every builder is really non-idle.
			idle_only=0
		fi
	done
	exec 6<&- 6>&-

	run_hook build_queue stop
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

calculate_elapsed_from_log() {
	[ $# -eq 2 ] || eargs calculate_elapsed_from_log now log
	local now="$1"
	local log="$2"

	[ -f "${log}/.poudriere.status" ] || return 1
	start_end_time=$(stat -f '%B %m' \
	    "${log}/.poudriere.status.journal%" 2>/dev/null || \
	    stat -f '%B %m' "${log}/.poudriere.status")
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

calculate_duration() {
	[ $# -eq 2 ] || eargs calculate_duration var_return elapsed
	local var_return="$1"
	local _elapsed="$2"
	local seconds minutes hours _duration

	seconds=$((${_elapsed} % 60))
	minutes=$(((${_elapsed} / 60) % 60))
	hours=$((${_elapsed} / 3600))

	_duration=$(printf "%02d:%02d:%02d" ${hours} ${minutes} ${seconds})

	setvar "${var_return}" "${_duration}"
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
	was_a_testport_run && \
	    nremaining=$((${nremaining} - 1))

	# If pool is empty, just return
	[ ${nremaining} -eq 0 ] && return 0

	# Minimize PARALLEL_JOBS to queue size
	[ ${PARALLEL_JOBS} -gt ${nremaining} ] && PARALLEL_JOBS=${nremaining##* }

	msg "Building ${nremaining} packages using ${PARALLEL_JOBS} builders"
	JOBS="$(jot -w %02d ${PARALLEL_JOBS})"

	start_builders

	coprocess_start pkg_cacher

	bset status "parallel_build:"

	[ ! -d "${MASTERMNT}/.p/pool" ] && err 1 "Build pool is missing"
	cd "${MASTERMNT}/.p/pool"

	build_queue

	cd ..

	bset status "stopping_jobs:"
	stop_builders

	bset status "updating_stats:"
	update_stats || msg_warn "Error updating build stats"
	update_stats_done=1

	bset status "idle:"

	# Restore PARALLEL_JOBS
	PARALLEL_JOBS=${real_parallel_jobs}

	return 0
}

crashed_build() {
	[ $# -eq 2 ] || eargs crashed_build pkgname failed_phase
	local pkgname="$1"
	local failed_phase="$2"
	local origin originspec log

	_log_path log
	get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" origin '' ''

	echo "Build crashed: ${failed_phase}" >> "${log}/logs/${pkgname}.log"

	# If the file already exists then all of this handling was done in
	# build_pkg() already; The port failed already. What crashed
	# came after.
	if ! [ -e "${log}/logs/errors/${pkgname}.log" ]; then
		# Symlink the buildlog into errors/
		ln -s "../${pkgname}.log" "${log}/logs/errors/${pkgname}.log"
		badd ports.failed \
		    "${originspec} ${pkgname} ${failed_phase} ${failed_phase}"
		COLOR_ARROW="${COLOR_FAIL}" job_msg \
		    "${COLOR_FAIL}Finished ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_FAIL}: Failed: ${COLOR_PHASE}${failed_phase}"
		run_hook pkgbuild failed "${origin}" "${pkgname}" \
		    "${failed_phase}" \
		    "${log}/logs/errors/${pkgname}.log"
	fi
	clean_pool "${pkgname}" "${originspec}" "${failed_phase}"
	stop_build "${pkgname}" "${originspec}" 1 >> "${log}/logs/${pkgname}.log"
}

clean_pool() {
	[ $# -ne 3 ] && eargs clean_pool pkgname originspec clean_rdepends
	local pkgname=$1
	local originspec=$2
	local clean_rdepends="$3"
	local origin skipped_originspec skipped_origin

	[ -n "${MY_JOBID}" ] && bset ${MY_JOBID} status "clean_pool:"

	[ -z "${originspec}" -a -n "${clean_rdepends}" ] && \
	    get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" origin '' ''

	# Cleaning queue (pool is cleaned here)
	pkgqueue_done "${pkgname}" "${clean_rdepends}" | \
	    while read skipped_pkgname; do
		get_originspec_from_pkgname skipped_originspec "${skipped_pkgname}"
		originspec_decode "${skipped_originspec}" skipped_origin '' ''
		badd ports.skipped "${skipped_originspec} ${skipped_pkgname} ${pkgname}"
		COLOR_ARROW="${COLOR_SKIP}" \
		    job_msg "${COLOR_SKIP}Skipping ${COLOR_PORT}${skipped_originspec} | ${skipped_pkgname}${COLOR_SKIP}: Dependent port ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_SKIP} ${clean_rdepends}"
		if [ ${OUTPUT_REDIRECTED:-0} -eq 1 ]; then
			# Send to true stdout (not any build log)
			run_hook pkgbuild skipped "${skipped_origin}" \
			    "${skipped_pkgname}" "${origin}" >&3
		else
			run_hook pkgbuild skipped "${skipped_origin}" \
			    "${skipped_pkgname}" "${origin}"
		fi
	done

	(
		cd "${MASTERMNT}/.p"
		balance_pool || :
	)
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
	local clean_rdepends
	local log
	local ignore
	local errortype
	local ret=0
	local elapsed now jpkg

	_my_path mnt
	_my_name name
	_log_path log
	clean_rdepends=
	trap '' SIGTSTP
	PKGNAME="${pkgname}" # set ASAP so jail_cleanup() can use it
	PKGBASE="${PKGNAME%-*}"
	setproctitle "build_pkg (${pkgname})" || :

	# Don't show timestamps in msg() which goes to logs, only job_msg()
	# which goes to master
	NO_ELAPSED_IN_MSG=1
	TIME_START_JOB=$(clock -monotonic)
	colorize_job_id COLOR_JOBID "${MY_JOBID}"

	get_originspec_from_pkgname ORIGINSPEC "${pkgname}"
	originspec_decode "${ORIGINSPEC}" port DEPENDS_ARGS FLAVOR
	bset_job_status "starting" "${ORIGINSPEC}"
	if [ -z "${FLAVOR}" ]; then
		shash_get pkgname-flavor "${pkgname}" FLAVOR || FLAVOR=
	fi
	job_msg "Building ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${PKGNAME}${COLOR_RESET}"

	MAKE_ARGS="${DEPENDS_ARGS}${FLAVOR:+ FLAVOR=${FLAVOR}}"
	if [ -n "${DEPENDS_ARGS}" ]; then
		PKGENV="${PKGENV:+${PKGENV} }PKG_NOTES=depends_args PKG_NOTE_depends_args=${DEPENDS_ARGS}"
	fi
	portdir="${PORTSDIR}/${port}"

	_gsub "${PKGBASE}" "${HASH_VAR_NAME_SUB_GLOB}" '_'
	eval "MAX_FILES=\${MAX_FILES_${_gsub}:-${DEFAULT_MAX_FILES}}"
	if [ -n "${MAX_MEMORY_BYTES}" -o -n "${MAX_FILES}" ]; then
		JEXEC_LIMITS=1
	fi

	if [ ${TMPFS_LOCALBASE} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		if [ -f "${mnt}/${LOCALBASE:-/usr/local}/.mounted" ]; then
			umount ${UMOUNT_NONBUSY} ${mnt}/${LOCALBASE:-/usr/local} || \
			    umount -f ${mnt}/${LOCALBASE:-/usr/local}
		fi
		mnt_tmpfs localbase ${mnt}/${LOCALBASE:-/usr/local}
		do_clone -r "${MASTERMNT}/${LOCALBASE:-/usr/local}" \
		    "${mnt}/${LOCALBASE:-/usr/local}"
		:> "${mnt}/${LOCALBASE:-/usr/local}/.mounted"
	fi

	[ -f ${mnt}/.need_rollback ] && rollbackfs prepkg ${mnt}
	[ -f ${mnt}/.need_rollback ] && \
	    err 1 "Failed to rollback ${mnt} to prepkg"
	:> ${mnt}/.need_rollback

	case " ${BLACKLIST} " in
	*\ ${port}\ *) ignore="Blacklisted" ;;
	esac
	if [ -z "${ignore}" ]; then
		# If this port is IGNORED, skip it
		# This is checked here due to historical reasons and
		# will later be moved up into the queue creation.
		shash_get pkgname-ignore "${pkgname}" ignore || ignore=
	fi

	rm -rf ${mnt}/wrkdirs/* || :

	log_start 0
	msg "Building ${port}"

	for jpkg in ${ALLOW_MAKE_JOBS_PACKAGES}; do
		case "${PKGBASE}" in
		${jpkg})
			job_msg_verbose "Allowing MAKE_JOBS for ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${PKGNAME}${COLOR_RESET}"
			sed -i '' '/DISABLE_MAKE_JOBS=poudriere/d' \
			    "${mnt}/etc/make.conf"
			break
			;;
		esac
	done

	buildlog_start "${ORIGINSPEC}"

	# Ensure /dev/null exists (kern/139014)
	[ ${JAILED} -eq 0 ] && ! [ -c "${mnt}/dev/null" ] && \
	    devfs -m ${mnt}/dev rule apply path null unhide

	if [ -n "${ignore}" ]; then
		msg "Ignoring ${port}: ${ignore}"
		badd ports.ignored "${ORIGINSPEC} ${PKGNAME} ${ignore}"
		COLOR_ARROW="${COLOR_IGNORE}" job_msg "${COLOR_IGNORE}Finished ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${PKGNAME}${COLOR_IGNORE}: Ignored: ${ignore}"
		clean_rdepends="ignored"
		run_hook pkgbuild ignored "${port}" "${PKGNAME}" "${ignore}" >&3
	else
		build_port "${ORIGINSPEC}" || ret=$?
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

			save_wrkdir "${mnt}" "${ORIGINSPEC}" "${PKGNAME}" \
			    "${portdir}" "${failed_phase}" || :
		elif [ -f ${mnt}/${portdir}/.keep ]; then
			save_wrkdir "${mnt}" "${ORIGINSPEC}" "${PKGNAME}" \
			    "${portdir}" "noneed" ||:
		fi

		now=$(clock -monotonic)
		elapsed=$((${now} - ${TIME_START_JOB}))

		if [ ${build_failed} -eq 0 ]; then
			badd ports.built "${ORIGINSPEC} ${PKGNAME} ${elapsed}"
			COLOR_ARROW="${COLOR_SUCCESS}" job_msg "${COLOR_SUCCESS}Finished ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${PKGNAME}${COLOR_SUCCESS}: Success"
			run_hook pkgbuild success "${port}" "${PKGNAME}" >&3
			# Cache information for next run
			pkg_cacher_queue "${port}" "${pkgname}" \
			    "${DEPENDS_ARGS}" "${FLAVOR}" || :
		else
			# Symlink the buildlog into errors/
			ln -s ../${PKGNAME}.log ${log}/logs/errors/${PKGNAME}.log
			errortype=$(/bin/sh ${SCRIPTPREFIX}/processonelog.sh \
				${log}/logs/errors/${PKGNAME}.log \
				2> /dev/null)
			badd ports.failed "${ORIGINSPEC} ${PKGNAME} ${failed_phase} ${errortype} ${elapsed}"
			COLOR_ARROW="${COLOR_FAIL}" job_msg "${COLOR_FAIL}Finished ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${PKGNAME}${COLOR_FAIL}: Failed: ${COLOR_PHASE}${failed_phase}"
			run_hook pkgbuild failed "${port}" "${PKGNAME}" "${failed_phase}" \
				"${log}/logs/errors/${PKGNAME}.log" >&3
			# ret=2 is a test failure
			if [ ${ret} -eq 2 ]; then
				clean_rdepends=
			else
				clean_rdepends="failed"
			fi
		fi

		msg "Cleaning up wrkdir"
		injail /usr/bin/make -C "${portdir}" ${MAKE_ARGS} \
		    -DNOCLEANDEPENDS clean || :
		rm -rf ${mnt}/wrkdirs/* || :
	fi

	clean_pool "${PKGNAME}" "${ORIGINSPEC}" "${clean_rdepends}"

	stop_build "${PKGNAME}" "${ORIGINSPEC}" ${build_failed}

	log_stop

	bset ${MY_JOBID} status "done:"

	echo ${MY_JOBID} >&6
}

stop_build() {
	[ $# -eq 3 ] || eargs stop_build pkgname originspec build_failed
	local pkgname="$1"
	local originspec="$2"
	local build_failed="$3"
	local mnt

	if [ -n "${MY_JOBID}" ]; then
		_my_path mnt

		if [ -f "${mnt}/.npkg_mounted" ]; then
			umount ${UMOUNT_NONBUSY} "${mnt}/.npkg" || \
			    umount -f "${mnt}/.npkg"
			unlink "${mnt}/.npkg_mounted"
		fi
		rm -rf "${PACKAGES}/.npkg/${PKGNAME}"

		if [ -n "${PORTTESTING}" ]; then
			if jail_has_processes; then
				msg_warn "Leftover processes:"
				injail ps auxwwd | egrep -v '(ps auxwwd|jexecd)'
				jkill_wait
			fi
			if JNETNAME="n" jail_has_processes; then
				msg_warn "Leftover processes (network jail):"
				JNETNAME="n" injail ps auxwwd | egrep -v '(ps auxwwd|jexecd)'
				JNETNAME="n" jkill_wait
			fi
		else
			jkill
		fi
	fi

	buildlog_stop "${pkgname}" "${originspec}" ${build_failed}
}

prefix_stderr_quick() {
	local -; set +x
	local extra="$1"
	local MSG_NESTED_STDERR
	shift 1

	{
		{
			MSG_NESTED_STDERR=1
			"$@"
		} 2>&1 1>&3 | {
			setproctitle "${PROC_TITLE} (prefix_stderr_quick)"
			while read -r line; do
				msg_warn "${extra}: ${line}"
			done
		}
	} 3>&1
}

prefix_stderr() {
	local extra="$1"
	shift 1
	local prefixpipe prefixpid ret
	local MSG_NESTED_STDERR

	prefixpipe=$(mktemp -ut prefix_stderr.pipe)
	mkfifo "${prefixpipe}"
	(
		set +x
		setproctitle "${PROC_TITLE} (prefix_stderr)"
		while read -r line; do
			msg_warn "${extra}: ${line}"
		done
	) < ${prefixpipe} &
	prefixpid=$!
	exec 4>&2
	exec 2> "${prefixpipe}"
	unlink "${prefixpipe}"

	MSG_NESTED_STDERR=1
	ret=0
	"$@" || ret=$?

	exec 2>&4 4>&-
	wait ${prefixpid}

	return ${ret}
}

prefix_stdout() {
	local extra="$1"
	shift 1
	local prefixpipe prefixpid ret
	local MSG_NESTED

	prefixpipe=$(mktemp -ut prefix_stdout.pipe)
	mkfifo "${prefixpipe}"
	(
		set +x
		setproctitle "${PROC_TITLE} (prefix_stdout)"
		while read -r line; do
			msg "${extra}: ${line}"
		done
	) < ${prefixpipe} &
	prefixpid=$!
	exec 3>&1
	exec > "${prefixpipe}"
	unlink "${prefixpipe}"

	MSG_NESTED=1
	ret=0
	"$@" || ret=$?

	exec 1>&3 3>&-
	wait ${prefixpid}

	return ${ret}
}

prefix_output() {
	local extra="$1"
	shift 1

	prefix_stderr "${extra}" prefix_stdout "${extra}" "$@"
}

: ${ORIGINSPEC_SEP:="@"}
: ${FLAVOR_DEFAULT:="-"}
: ${FLAVOR_ALL:="all"}

build_all_flavors() {
	[ $# -eq 1 ] || eargs build_all_flavors originspec
	local originspec="$1"
	local origin build_all

	[ "${ALL}" -eq 1 ] && return 0
	[ "${FLAVOR_DEFAULT_ALL}" = "yes" ] && return 0
	originspec_decode "${originspec}" origin '' ''
	shash_get origin-flavor-all "${origin}" build_all || build_all=0
	[ "${build_all}" -eq 1 ] && return 0

	# bulk and testport
	return 1
}

# ORIGINSPEC is: ORIGIN@FLAVOR@DEPENDS_ARGS
originspec_decode() {
	local -; set +x
	[ $# -ne 4 ] && eargs originspec_decode originspec \
	    var_return_origin var_return_dep_args var_return_flavor
	local _originspec="$1"
	local var_return_origin="$2"
	local var_return_dep_args="$3"
	local var_return_flavor="$4"
	local __origin __dep_args __flavor IFS

	IFS="${ORIGINSPEC_SEP}"
	set -- ${_originspec}

	__origin="${1}"
	__flavor="${2}"
	__dep_args="${3}"

	if [ -n "${var_return_origin}" ]; then
		setvar "${var_return_origin}" "${__origin}"
	fi
	if [ -n "${var_return_dep_args}" ]; then
		setvar "${var_return_dep_args}" "${__dep_args}"
	fi
	if [ -n "${var_return_flavor}" ]; then
		setvar "${var_return_flavor}" "${__flavor}"
	fi
}

# !!! NOTE that the encoded originspec may not match the parameter ordering.
originspec_encode() {
	local -; set +x
	[ $# -ne 4 ] && eargs originspec_encode var_return origin dep_args \
	    flavor
	local _var_return="$1"
	local _origin_in="$2"
	local _dep_args="$3"
	local _flavor="$4"
	local output

	output="${_origin_in}"
	# Only add in FLAVOR and DEPENDS_ARGS if they are needed,
	# if neither are then don't even add in the ORIGINSPEC_SEP.
	if [ -n "${_dep_args}" -o -n "${_flavor}" ]; then
		[ -n "${_dep_args}" -a -n "${_flavor}" ] && \
		    err 1 "originspec_encode: Origin ${origin} incorrectly trying to use FLAVOR=${_flavor} and DEPENDS_ARGS=${_dep_args}"
		output="${output}${ORIGINSPEC_SEP}${_flavor}${_dep_args:+${ORIGINSPEC_SEP}${_dep_args}}"
	fi
	setvar "${_var_return}" "${output}"
}

# Apply my (pkgname) own DEPENDS_ARGS to the given origin if I have any and
# the dep should be allowed to use it.
maybe_apply_my_own_dep_args() {
	[ $# -eq 4 ] || eargs maybe_apply_my_own_dep_args \
	    pkgname var_return_originspec originspec \
	    dep_args
	local pkgname="$1"
	local var_return_originspec="$2"
	local originspec="$3"
	local _my_dep_args="$4"
	local _my_origin _flavor

	# No DEPENDS_ARGS to apply.
	[ -n "${_my_dep_args}" ] || return 1
	originspec_decode "${originspec}" _my_origin '' _flavor
	origin_should_use_dep_args "${_my_origin}" || return 1
	# It's possible the originspec already had DEPENDS_ARGS due to earlier
	# calls to map_py_slave_port() in deps_fetch_vars().  Still overwrite
	# it though with our own.
	originspec_encode "${var_return_originspec}" \
	    "${_my_origin}" "${_my_dep_args}" "${_flavor}"
}

# Apply our own DEPENDS_ARGS to each of our dependencies,
# Also deal with py3 slave port hack first.
fixup_dependencies_dep_args() {
	[ $# -ne 4 ] && eargs fixup_dependencies_dep_args var_return \
	    pkgname raw_deps dep_args
	local var_return="$1"
	local pkgname="$2"
	local raw_deps="$3"
	local dep_args="$4"
	local _new_deps _dep _origin _pkgname _target

	have_ports_feature DEPENDS_ARGS || return 0
	[ -n "${raw_deps}" ] || return 0

	for _dep in ${raw_deps}; do
		# We either have <origin> or <*:origin[:*]>
		case "${_dep}" in
		*:*:*)
			_pkgname="${_dep%%:*}"
			_origin="${_dep%:*}"
			_origin="${_origin#*:}"
			_target="${_dep##*:}"
			;;
		*:*)
			_pkgname="${_dep%:*}"
			_origin="${_dep#*:}"
			_target=
			;;
		*)
			_pkgname=
			_origin="${_dep}"
			_target=
			;;
		esac
		case "${_origin}" in
		${PORTSDIR}/*)
			_origin="${_origin#${PORTSDIR}/}" ;;
		esac
		map_py_slave_port "${_origin}" _origin || :
		maybe_apply_my_own_dep_args "${pkgname}" \
		    _origin "${_origin}" "${dep_args}" || :
		_dep="${_pkgname:+${_pkgname}:}${_origin}${_target:+:${_target}}"
		_new_deps="${_new_deps:+${_new_deps} }${_dep}"
	done

	setvar "${var_return}" "${_new_deps}"
}

deps_fetch_vars() {
	[ $# -ne 6 ] && eargs deps_fetch_vars originspec deps_var \
	    pkgname_var dep_args_var flavor_var flavors_var
	local originspec="$1"
	local deps_var="$2"
	local pkgname_var="$3"
	local dep_args_var="$4"
	local flavor_var="$5"
	local flavors_var="$6"
	local _pkgname _pkg_deps _lib_depends= _run_depends= _selected_options=
	local _changed_options= _changed_deps= _depends_args= _lookup_flavors=
	local _existing_origin _existing_originspec categories _ignore
	local _default_originspec _default_pkgname _orig_ignore
	local origin _origin_dep_args _dep_args _dep _new_pkg_deps
	local _origin_flavor _flavor _flavors _dep_arg _new_dep_args
	local _depend_specials=

	originspec_decode "${originspec}" origin _origin_dep_args \
	    _origin_flavor
	# If we were passed in a FLAVOR then we better have already looked up
	# the default for this port.  This is to avoid making the default port
	# become superfluous.  Bulk -a would have already visited from the
	# category Makefiles.  The main port would have been looked up
	# potentially by the 'metadata' hack.
	# DEPENDS_ARGS can fall into this as well but it is unlikely to
	# actually be superfluous due to the conditional application of
	# DEPENDS_ARGS in most cases.  So don't waste time looking it up
	# or enforcing the rule until it is found superfluous.  www/py-yarl
	# triggers this with www/py-multidict since it tries to add DEPENDS_ARGS
	# onto its multidict dependency but later finds that multidict is
	# already forcing Python 3 and the DEPENDS_ARGS does nothing.
	if [ ${ALL} -eq 0 ] && \
	    [ -n "${_origin_flavor}" ]; then
		originspec_encode _default_originspec "${origin}" '' ''
		shash_get originspec-pkgname "${_default_originspec}" \
		    _default_pkgname || \
		    err 1 "deps_fetch_vars: Lookup of ${originspec} failed to already have ${_default_originspec}"
	fi

	if [ "${CHECK_CHANGED_OPTIONS}" != "no" ] && \
	    have_ports_feature SELECTED_OPTIONS; then
		_changed_options="SELECTED_OPTIONS:O _selected_options"
	fi
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		_changed_deps="LIB_DEPENDS _lib_depends RUN_DEPENDS _run_depends"
	fi
	if have_ports_feature FLAVORS; then
		_lookup_flavors="FLAVOR _flavor FLAVORS _flavors"
		[ -n "${_origin_dep_args}" ] && \
		    err 1 "deps_fetch_vars: Using FLAVORS but attempted lookup on ${originspec}"
	elif have_ports_feature DEPENDS_ARGS; then
		_depends_args="DEPENDS_ARGS _dep_args"
		[ -n "${_origin_flavor}" ] && \
		    err 1 "deps_fetch_vars: Using DEPENDS_ARGS but attempted lookup on ${originspec}"
	fi
	if ! port_var_fetch_originspec "${originspec}" \
	    PKGNAME _pkgname \
	    ${_depends_args} \
	    ${_lookup_flavors} \
	    '${_DEPEND_SPECIALS:C,^${PORTSDIR}/,,}' _depend_specials \
	    CATEGORIES categories \
	    IGNORE _ignore \
	    ${_changed_deps} \
	    ${_changed_options} \
	    _PDEPS='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}' \
	    '${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
	    _pkg_deps; then
		msg_error "Error fetching dependencies for ${COLOR_PORT}${originspec}${COLOR_RESET}"
		return 1
	fi

	[ -n "${_pkgname}" ] || \
	    err 1 "deps_fetch_vars: failed to get PKGNAME for ${originspec}"

	# Validate CATEGORIES is proper to avoid:
	# - Pkg not registering the dependency
	# - Having delete_old_pkg later remove it due to the origin fetched
	#   from pkg-query not existing.
	if [ "${categories%% *}" != "${origin%%/*}" ]; then
		msg_error "${COLOR_PORT}${origin}${COLOR_RESET} has incorrect CATEGORIES, first should be '${origin%%/*}'.  Please contact maintainer of the port to fix this."
		return 1
	fi

	if have_ports_feature DEPENDS_ARGS; then
		# Determine if the port's claimed DEPENDS_ARGS even matter.
		# If it matches the PYTHON_DEFAULT_VERSION then we can ignore
		# it.  If it is for RUBY then it can be ignored as well since
		# it was never implemented in the tree.  If it is anything
		# else it is an error.
		_new_dep_args=
		for _dep_arg in ${_dep_args}; do
			case "${_dep_arg}" in
			PYTHON_VERSION=${P_PYTHON_DEFAULT_VERSION})
				# Matches the default, no reason to waste time
				# looking up dependencies with this bogus value.
				msg_debug "deps_fetch_vars: Trimmed superfluous DEPENDS_ARGS=${_dep_arg} for ${originspec}"
				_dep_arg=
				;;
			PYTHON_VERSION=*)
				# It wants to use a non-default Python.  We'll
				# allow it.
				;;
			RUBY_VER=*)
				# Ruby never used this so just trim it.
				_dep_arg=
				;;
			*WITH_*=yes)
				# dns/unbound had these but they do nothing
				# anymore, ignore.
				_dep_arg=
				;;
			'')
				# Blank value, great!
				;;
			*)
				err 1 "deps_fetch_vars: Unknown or invalid DEPENDS_ARGS (${_dep_arg}) for ${originspec}"
				;;
			esac
			_new_dep_args="${_new_dep_args}${_new_dep_args:+ }${_dep_arg}"
		done
		_dep_args="${_new_dep_args}"

		# Apply our own DEPENDS_ARGS to each of our dependencies,
		# Also deal with py3 slave port hack first.
		if [ -n "${_pkg_deps}" ]; then
			unset _new_pkg_deps
			for _dep in ${_pkg_deps}; do
				map_py_slave_port "${_dep}" _dep || :
				maybe_apply_my_own_dep_args "${_pkgname}" \
				    _dep "${_dep}" "${_dep_args}" || :
				_new_pkg_deps="${_new_pkg_deps:+${_new_pkg_deps} }${_dep}"
			done
			_pkg_deps="${_new_pkg_deps}"
		fi
	fi
	setvar "${pkgname_var}" "${_pkgname}"
	setvar "${deps_var}" "${_pkg_deps}"
	setvar "${dep_args_var}" "${_dep_args}"
	setvar "${flavor_var}" "${_flavor}"
	setvar "${flavors_var}" "${_flavors}"
	# Need all of the output vars set before potentially returning 2.

	# Check if this PKGNAME already exists, which is sometimes fatal.
	# Two different originspecs of the same origin but with
	# different DEPENDS_ARGS may result in the same PKGNAME.
	# It can happen if something like devel/foo@ does not
	# support python but is passed DEPENDS_ARGS=PYTHON_VERSION=3.2
	# from a reverse dependency. Just ignore it in that case.
	# Otherwise it is fatal due to duplicated PKGNAME.
	if ! noclobber shash_set pkgname-originspec "${_pkgname}" \
	    "${originspec}"; then
		shash_get pkgname-originspec "${_pkgname}" _existing_originspec
		[ "${_existing_originspec}" = "${originspec}" ] && \
		    err 1 "deps_fetch_vars: ${originspec} already known as ${pkgname}"
		originspec_decode "${_existing_originspec}" \
		    _existing_origin '' ''
		if [ "${_existing_origin}" = "${origin}" ]; then
			# We don't force having the main port looked up for
			# DEPENDS_ARGS uses, see explanation at first
			# originspec-pkgname lookup.
			if have_ports_feature DEPENDS_ARGS && \
			    [ -z "${_default_pkgname}" ] && \
			    [ -n "${_origin_dep_args}" ]; then
				originspec_encode _default_originspec \
				    "${origin}" '' ''
				shash_get originspec-pkgname \
				    "${_default_originspec}" \
				    _default_pkgname || \
				    err 1 "deps_fetch_vars: Lookup of ${originspec} failed to already have ${_default_originspec}"
			fi
			if [ "${_pkgname}" = "${_default_pkgname}" ]; then
				if have_ports_feature DEPENDS_ARGS && \
				    [ -n "${_origin_dep_args}" ]; then
					# If this port is IGNORE but the
					# main one was not then we're not
					# really superfluous.  This really
					# indicates an invalid py3 mapping
					# that needs ignored in
					# map_py_slave_port.
					if [ -n "${_ignore}" ] && \
					    ! shash_get pkgname-ignore \
					    "${_pkgname}" _orig_ignore; then
						err 1 "${originspec} is IGNORE but ${_existing_originspec} was not for ${_pkgname}: ${_ignore}"
					fi
					# Set this for later compute_deps lookups
					shash_set originspec-pkgname \
					    "${originspec}" "${_pkgname}"
				fi
				# This originspec is superfluous, just ignore.
				msg_debug "deps_fetch_vars: originspec ${originspec} is superfluous for PKGNAME ${_pkgname}"
				[ ${ALL} -eq 0 ] && return 2
				have_ports_feature DEPENDS_ARGS && \
				    [ -n "${_origin_dep_args}" ] && return 2
			fi
		fi
		err 1 "Duplicated origin for ${_pkgname}: ${COLOR_PORT}${originspec}${COLOR_RESET} AND ${COLOR_PORT}${_existing_originspec}${COLOR_RESET}. Rerun with -v to see which ports are depending on these."
	fi

	# Discovered a new originspec->pkgname mapping.
	msg_debug "deps_fetch_vars: discovered ${originspec} is ${_pkgname}"
	shash_set originspec-pkgname "${originspec}" "${_pkgname}"
	[ -n "${_flavor}" ] && \
	    shash_set pkgname-flavor "${_pkgname}" "${_flavor}"
	[ -n "${_flavors}" ] && \
	    shash_set pkgname-flavors "${_pkgname}" "${_flavors}"
	[ -n "${_ignore}" ] && \
	    shash_set pkgname-ignore "${_pkgname}" "${_ignore}"
	if [ -n "${_depend_specials}" ]; then
		fixup_dependencies_dep_args _depend_specials \
		    "${_pkgname}" \
		    "${_depend_specials}" \
		    "${_dep_args}"
		shash_set pkgname-depend_specials "${_pkgname}" \
		    "${_depend_specials}"
	fi
	shash_set pkgname-deps "${_pkgname}" "${_pkg_deps}"
	# Store for delete_old_pkg with CHECK_CHANGED_DEPS==yes
	if [ -n "${_lib_depends}" ]; then
		fixup_dependencies_dep_args _lib_depends \
		    "${_pkgname}" \
		    "${_lib_depends}" \
		    "${_dep_args}"
		shash_set pkgname-lib_deps "${_pkgname}" "${_lib_depends}"
	fi
	if [ -n "${_run_depends}" ]; then
		fixup_dependencies_dep_args _run_depends \
		    "${_pkgname}" \
		    "${_run_depends}" \
		    "${_dep_args}"
		shash_set pkgname-run_deps "${_pkgname}" "${_run_depends}"
	fi
	if [ -n "${_selected_options}" ]; then
		shash_set pkgname-options "${_pkgname}" "${_selected_options}"
	fi
}

pkg_get_origin() {
	[ $# -lt 2 ] && eargs pkg_get_origin var_return pkg [origin]
	local var_return="$1"
	local pkg="$2"
	local _origin=$3
	local SHASH_VAR_PATH

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'origin' _origin; then
		if [ -z "${_origin}" ]; then
			_origin=$(injail ${PKG_BIN} query -F \
			    "/packages/All/${pkg##*/}" "%o")
		fi
		shash_set 'pkg' 'origin' "${_origin}"
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_origin}"
	fi
}

pkg_get_flavor() {
	[ $# -lt 2 ] && eargs pkg_get_flavor var_return pkg [flavor]
	local var_return="$1"
	local pkg="$2"
	local _flavor="$3"
	local SHASH_VAR_PATH

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'flavor' _flavor; then
		if [ -z "${_flavor}" ]; then
			_flavor=$(injail ${PKG_BIN} query -F \
				"/packages/All/${pkg##*/}" \
				'%At %Av' | \
				awk '$1 == "flavor" {print $2}')
		fi
		shash_set 'pkg' 'flavor' "${_flavor}"
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_flavor}"
	fi
}

pkg_get_dep_args() {
	[ $# -lt 2 ] && eargs pkg_get_dep_args var_return pkg [dep_args]
	local var_return="$1"
	local pkg="$2"
	local _dep_args="$3"
	local SHASH_VAR_PATH

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'dep_args' _dep_args; then
		if [ -z "${_dep_args}" ]; then
			_dep_args=$(injail ${PKG_BIN} query -F \
				"/packages/All/${pkg##*/}" \
				'%At %Av' | \
				awk '$1 == "depends_args" {print $2}')
		fi
		shash_set 'pkg' 'dep_args' "${_dep_args}"
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_dep_args}"
	fi
}

pkg_get_dep_origin_pkgnames() {
	[ $# -ne 3 ] && eargs pkg_get_dep_origin_pkgnames var_return_origins \
	    var_return_pkgnames pkg
	local var_return_origins="$1"
	local var_return_pkgnames="$2"
	local pkg="$3"
	local SHASH_VAR_PATH
	local fetched_data compiled_dep_origins compiled_dep_pkgnames
	local origin pkgname

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'deps' fetched_data; then
		fetched_data=$(injail ${PKG_BIN} query -F \
			"/packages/All/${pkg##*/}" '%do %dn-%dv' | tr '\n' ' ')
		shash_set 'pkg' 'deps' "${fetched_data}"
	fi
	[ -n "${var_return_origins}" -o -n "${var_return_pkgnames}" ] || \
	    return 0
	# Split the data
	set -- ${fetched_data}
	while [ $# -ne 0 ]; do
		origin="$1"
		pkgname="$2"
		compiled_dep_origins="${compiled_dep_origins}${compiled_dep_origins:+ }${origin}"
		compiled_dep_pkgnames="${compiled_dep_pkgnames}${compiled_dep_pkgnames:+ }${pkgname}"
		shift 2
	done
	if [ -n "${var_return_origins}" ]; then
		setvar "${var_return_origins}" "${compiled_dep_origins}"
	fi
	if [ -n "${var_return_pkgnames}" ]; then
		setvar "${var_return_pkgnames}" "${compiled_dep_pkgnames}"
	fi
}

pkg_get_options() {
	[ $# -ne 2 ] && eargs pkg_get_options var_return pkg
	local var_return="$1"
	local pkg="$2"
	local SHASH_VAR_PATH
	local _compiled_options

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'options' _compiled_options; then
		_compiled_options=
		while read key value; do
			case "${value}" in
				off|false) continue ;;
			esac
			_compiled_options="${_compiled_options}${_compiled_options:+ }${key}"
		done <<-EOF
		$(injail ${PKG_BIN} query -F "/packages/All/${pkg##*/}" '%Ok %Ov' | sort)
		EOF
		# Compat with pretty-print-config
		if [ -n "${_compiled_options}" ]; then
			_compiled_options="${_compiled_options} "
		fi
		shash_set 'pkg' 'options' "${_compiled_options}"
	else
		# Space on end to match 'pretty-print-config' in delete_old_pkg
		[ -n "${_compiled_options}" ] &&
		    _compiled_options="${_compiled_options} "
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_compiled_options}"
	fi
}

ensure_pkg_installed() {
	local force="$1"
	local mnt

	_my_path mnt
	[ -z "${force}" ] && [ -x "${mnt}${PKG_BIN}" ] && return 0
	# Hack, speed up QEMU usage on pkg-repo.
	if [ ${QEMU_EMULATING} -eq 1 ] && \
	    [ -f /usr/local/sbin/pkg-static ]; then
		cp -f /usr/local/sbin/pkg-static "${mnt}/.p/pkg-static"
		return 0
	fi
	[ -e ${MASTERMNT}/packages/Latest/pkg.txz ] || return 1 #pkg missing
	injail tar xf /packages/Latest/pkg.txz -C / \
		-s ",/.*/,.p/,g" "*/pkg-static"
	return 0
}

pkg_cache_data() {
	[ $# -eq 4 ] || eargs pkg_cache_data pkg origin dep_args flavor
	local pkg="$1"
	local origin="$2"
	local dep_args="$3"
	local flavor="$4"
	local _ignored

	ensure_pkg_installed || return 1
	pkg_get_options '' "${pkg}" > /dev/null
	pkg_get_origin '' "${pkg}" "${origin}" > /dev/null
	if have_ports_feature FLAVORS; then
		pkg_get_flavor '' "${pkg}" "${flavor}" > /dev/null
	elif have_ports_feature DEPENDS_ARGS; then
		pkg_get_dep_args '' "${pkg}" "${dep_args}" > /dev/null
	fi
	pkg_get_dep_origin_pkgnames '' '' "${pkg}" > /dev/null
}

pkg_cacher_queue() {
	[ $# -eq 4 ] || eargs pkg_cacher_queue origin pkgname dep_args flavor
	local encoded_data

	encode_args encoded_data "$@"

	echo "${encoded_data}" > ${MASTERMNT}/.p/pkg_cacher.pipe
}

pkg_cacher_main() {
	local pkg work pkgname origin dep_args flavor

	mkfifo ${MASTERMNT}/.p/pkg_cacher.pipe
	exec 6<> ${MASTERMNT}/.p/pkg_cacher.pipe

	trap exit TERM
	trap pkg_cacher_cleanup EXIT

	# Wait for packages to process.
	while :; do
		read -r work <&6
		eval $(decode_args work)
		origin="$1"
		pkgname="$2"
		dep_args="$3"
		flavor="$4"
		pkg="${PACKAGES}/All/${pkgname}.${PKG_EXT}"
		if [ -f "${pkg}" ]; then
			pkg_cache_data "${pkg}" "${origin}" "${dep_args}" \
			    "${flavor}"
		fi
	done
}

pkg_cacher_cleanup() {
	unlink ${MASTERMNT}/.p/pkg_cacher.pipe
}

get_cache_dir() {
	setvar "${1}" ${POUDRIERE_DATA}/cache/${MASTERNAME}
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
	local pkg_mtime=

	get_cache_dir cache_dir

	[ ${use_mtime} -eq 1 ] && pkg_mtime=$(stat -f %m "${pkg}")

	pkg_dir="${cache_dir}/${pkg_file}/${pkg_mtime}"

	if [ ${use_mtime} -eq 1 ]; then
		[ -d "${pkg_dir}" ] || mkdir -p "${pkg_dir}"
	fi

	setvar "${var_return}" "${pkg_dir}"
}

clear_pkg_cache() {
	[ $# -ne 1 ] && eargs clear_pkg_cache pkg
	local pkg="$1"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	rm -fr "${pkg_cache_dir}"
	# XXX: Need shash_unset with glob
}

delete_pkg() {
	[ $# -ne 1 ] && eargs delete_pkg pkg
	local pkg="$1"

	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	unlink "${pkg}"
	clear_pkg_cache "${pkg}"
}

# Keep in sync with delete_pkg
delete_pkg_xargs() {
	[ $# -ne 2 ] && eargs delete_pkg listfile pkg
	local listfile="$1"
	local pkg="$2"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	{
		echo "${pkg}"
		echo "${pkg_cache_dir}"
	} >> "${listfile}"
	# XXX: May need clear_pkg_cache here if shash changes from file.
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
	local mnt pkgname new_pkgname
	local origin v v2 compiled_options current_options current_deps
	local td d key dpath dir found raw_deps compiled_deps
	local pkg_origin compiled_deps_pkgnames compiled_deps_pkgbases
	local compiled_deps_pkgname compiled_deps_origin compiled_deps_new
	local pkgbase new_pkgbase flavor pkg_flavor originspec
	local dep_pkgname dep_pkgbase dep_origin dep_flavor dep_dep_args
	local new_origin stale_pkg dep_args pkg_dep_args

	pkgname="${pkg##*/}"
	pkgname="${pkgname%.*}"

	# Some expensive lookups are delayed until the last possible
	# moment as cheaper checks may weed out this package before.

	pkg_flavor=
	pkg_dep_args=
	originspec=
	pkg_get_origin origin "${pkg}"
	if ! pkgbase_is_needed "${pkgname}"; then
		# We don't expect this PKGBASE but it may still be an
		# origin that is expected and just renamed.  Need to
		# get the origin and flavor out of the package to
		# determine that.
		if have_ports_feature FLAVORS; then
			pkg_get_flavor pkg_flavor "${pkg}"
		elif have_ports_feature DEPENDS_ARGS; then
			pkg_get_dep_args pkg_dep_args "${pkg}"
		fi
		originspec_encode originspec "${origin}" "${pkg_dep_args}" \
		    "${pkg_flavor}"
		if ! originspec_is_needed "${originspec}"; then
			msg_debug "delete_old_pkg: Skip unqueued ${pkg} ${origin} ${pkg_flavor}${pkg_dep_args} ${originspec}"
			return 0
		fi
		# Apparently we expect this package via its origin and flavor.
	fi

	if shash_get origin-moved "${origin}" new_origin; then
		if [ "${new_origin}" = "EXPIRED" ]; then
			local expired_reason

			shash_get origin-moved-expired "${origin}" \
			    expired_reason || expired_reason=
			msg "Deleting ${pkg##*/}: ${COLOR_PORT}${origin}${COLOR_RESET} ${expired_reason}"
		else
			msg "Deleting ${pkg##*/}: ${COLOR_PORT}${origin}${COLOR_RESET} moved to ${COLOR_PORT}${new_origin}${COLOR_RESET}"
		fi
		delete_pkg "${pkg}"
		return 0
	fi

	_my_path mnt

	if [ ! -d "${mnt}${PORTSDIR}/${origin}" ]; then
		msg "Deleting ${pkg##*/}: stale package: nonexistent origin ${COLOR_PORT}${origin}${COLOR_RESET}"
		delete_pkg "${pkg}"
		return 0
	fi

	if [ -z "${originspec}" ]; then
		if have_ports_feature FLAVORS; then
			pkg_get_flavor pkg_flavor "${pkg}"
		elif have_ports_feature DEPENDS_ARGS; then
			pkg_get_dep_args pkg_dep_args "${pkg}"
		fi
		originspec_encode originspec "${origin}" "${pkg_dep_args}" \
		    "${pkg_flavor}"
	fi

	v="${pkgname##*-}"
	# Check if any packages were queried for this origin to map it to a
	# new pkgname/version.
	stale_pkg=0
	if have_ports_feature FLAVORS && \
	    ! get_pkgname_from_originspec "${originspec}" new_pkgname; then
		stale_pkg=1
	elif have_ports_feature DEPENDS_ARGS; then
		map_py_slave_port "${originspec}" originspec || :
		if ! shash_get originspec-pkgname "${originspec}" \
		    new_pkgname; then
			stale_pkg=1
		fi
	fi
	if [ ${stale_pkg} -eq 1 ]; then
		# This origin was not looked up in gather_port_vars.  It is
		# a stale package with the same PKGBASE as one we want, but
		# with a different origin.  Such as lang/perl5.20 vs
		# lang/perl5.22 both with 'perl5' as PKGBASE.  A pkgclean
		# would handle removing this.
		msg "Deleting ${pkg##*/}: stale package: unwanted origin ${COLOR_PORT}${originspec}${COLOR_RESET}"
		delete_pkg "${pkg}"
		return 0
	fi
	pkgbase="${pkgname%-*}"
	new_pkgbase="${new_pkgname%-*}"

	# Check for changed PKGNAME before version as otherwise a new
	# version may show for a stale package that has been renamed.
	# XXX: Check if the pkgname has changed and rename in the repo
	if [ "${pkgbase}" != "${new_pkgbase}" ]; then
		msg "Deleting ${pkg##*/}: package name changed to '${new_pkgbase}'"
		delete_pkg "${pkg}"
		return 0
	fi

	v2=${new_pkgname##*-}
	if [ "$v" != "$v2" ]; then
		msg "Deleting ${pkg##*/}: new version: ${v2}"
		delete_pkg "${pkg}"
		return 0
	fi

	if have_ports_feature FLAVORS; then
		shash_get pkgname-flavor "${pkgname}" flavor || flavor=
		if [ "${pkg_flavor}" != "${flavor}" ]; then
			msg "Deleting ${pkg##*/}: FLAVOR changed to '${flavor}' from '${pkg_flavor}'"
			delete_pkg "${pkg}"
			return 0
		fi
	fi

	# Detect ports that have new dependencies that the existing packages
	# do not have and delete them.
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		current_deps=""
		# FIXME: Move into Infrastructure/scripts and 
		# 'make actual-run-depends-list' after enough testing,
		# which will avoida all of the injail hacks

		for td in lib run; do
			shash_get pkgname-${td}_deps "${new_pkgname}" raw_deps || raw_deps=
			for d in ${raw_deps}; do
				key="${d%:*}"
				# Technically we need to apply our own
				# DEPENDS_ARGS to all of the current_deps but
				# it has no practical impact since
				# map_py_slave_port will apply it as
				# needed.
				found=
				case "${td}" in
				lib)
					case "${key}" in
					lib*)
						# libfoo.so
						# libfoo.so.x
						# libfoo.so.x.y
						for dir in /lib /usr/lib ; do
							if injail test -f "${dir}/${key}"; then
								found=yes
								break
							fi
						done
						;;
					*.*)
						# foo.x
						# Unsupported since r362031 / July 2014
						# Keep for backwards-compatibility
						[ -n "${CHANGED_DEPS_LIBLIST}" ] \
						    err 1 "CHANGED_DEPS_LIBLIST not set"
						case " ${CHANGED_DEPS_LIBLIST} " in
							*\ ${key}\ *)
								found=yes
								;;
							*) ;;
						esac
						;;
					*)
						for dir in /lib /usr/lib ; do
							if injail test -f "${dir}/lib${key}.so"; then
								found=yes
								break
							fi
						done
						;;
					esac
					;;
				run)
					case "${key}" in
					/*) [ -e ${mnt}/${key} ] && found=yes ;;
					*) [ -n "$(injail which ${key})" ] && \
					    found=yes
					esac
					;;
				esac
				if [ -z "${found}" ]; then
					dpath="${d#*:}"
					case "${dpath}" in
					${PORTSDIR}/*)
						dpath="${dpath#${PORTSDIR}/}"
						;;
					esac
					[ -n "${dpath}" ] || \
					    err 1 "Invalid dependency for ${pkgname}: ${d}"
					current_deps="${current_deps} ${dpath}"
				fi
			done
		done
		if [ -n "${current_deps}" ]; then
			pkg_get_dep_origin_pkgnames \
			    compiled_deps compiled_deps_pkgnames "${pkg}"
			for compiled_deps_pkgname in \
			    ${compiled_deps_pkgnames}; do
				compiled_deps_pkgbases="${compiled_deps_pkgbases:+${compiled_deps_pkgbases} }${compiled_deps_pkgname%-*}"
			done
			# Handle MOVED
			for compiled_deps_origin in ${compiled_deps}; do
				shash_get origin-moved \
				    "${compiled_deps_origin}" \
				    new_origin && \
				    compiled_deps_origin="${new_origin}"
				[ "${compiled_deps_origin}" = "EXPIRED" ] && \
				    continue
				compiled_deps_new="${compiled_deps_new:+${compiled_deps_new} }${compiled_deps_origin}"
			done
			compiled_deps="${compiled_deps_new}"
		fi
		# To handle FLAVOR/DEPENDS_ARGS here we can't just use
		# a simple origin comparison, which is what is in deps now.
		# We need to map all of the deps to PKGNAMEs which is
		# relatively expensive.  First try to match on an origin
		# and then verify the PKGNAME is a match which assumes
		# that is enough to account for FLAVOR/DEPENDS_ARGS.
		for d in ${current_deps}; do
			dep_pkgname=
			case " ${compiled_deps} " in
			# Matches an existing origin (no FLAVOR/DEPENDS_ARGS)
			*\ ${d}\ *) ;;
			*)
				# Unknown, but if this origin has a FLAVOR or
				# DEPENDS_ARGS then we need to fallback to a
				# PKGBASE comparison first.
				originspec_decode "${d}" dep_origin \
				    dep_dep_args dep_flavor
				if [ -n "${dep_dep_args}" ] || \
				    [ -n "${dep_flavor}" ]; then
					get_pkgname_from_originspec \
					    "${d}" dep_pkgname || \
					    err 1 "delete_old_pkg: Failed to lookup PKGNAME for ${d}"
					dep_pkgbase="${dep_pkgname%-*}"
					# Now need to map all of the package's
					# dependencies to PKGBASES.
					case " ${compiled_deps_pkgbases} " in
					# Matches an existing pkgbase
					*\ ${dep_pkgbase}\ *) continue ;;
					# New dep
					*) ;;
					esac
				fi
				msg "Deleting ${pkg##*/}: new dependency: ${d}"
				delete_pkg "${pkg}"
				return 0
				;;
			esac
		done
	fi

	# Check if the compiled options match the current options from make.conf and /var/db/ports
	if [ "${CHECK_CHANGED_OPTIONS}" != "no" ]; then
		if have_ports_feature SELECTED_OPTIONS; then
			shash_get pkgname-options "${new_pkgname}" \
			    current_options || current_options=
			# pretty-print-config has a trailing space, so
			# pkg_get_options does as well.  Add in for compat.
			if [ -n "${current_options}" ]; then
				current_options="${current_options} "
			fi
		else
			# Backwards-compat: Fallback on pretty-print-config.
			# XXX: If we know we can use bmake then this would work
			# make _SELECTED_OPTIONS='${ALL_OPTIONS:@opt@${PORT_OPTIONS:M${opt}}@} ${MULTI GROUP SINGLE RADIO:L:@otype@${OPTIONS_${otype}:@m@${OPTIONS_${otype}_${m}:@opt@${PORT_OPTIONS:M${opt}}@}@}@}' -V _SELECTED_OPTIONS:O
			current_options=$(injail /usr/bin/make -C \
			    ${PORTSDIR}/${origin} \
			    pretty-print-config | tr ' ' '\n' | \
			    sed -n 's/^\+\(.*\)/\1/p' | sort -u | tr '\n' ' ')
		fi
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
}

delete_old_pkgs() {

	msg "Checking packages for incremental rebuild needs"
	run_hook delete_old_pkgs start

	if package_dir_exists_and_has_packages; then
		parallel_start
		for pkg in ${PACKAGES}/All/*.${PKG_EXT}; do
			parallel_run delete_old_pkg "${pkg}"
		done
		parallel_stop
	fi

	run_hook delete_old_pkgs stop
}

## Pick the next package from the "ready to build" queue in pool/
## Then move the package to the "building" dir in building/
## This is only ran from 1 process
pkgqueue_get_next() {
	[ "${PWD}" = "${MASTERMNT}/.p/pool" ] || \
	    err 1 "pkgqueue_get_next requires PWD=${MASTERMNT}/.p/pool"
	local var_return="$1"
	local p _pkgname ret

	# CWD is MASTERMNT/.p/pool

	p=$(find ${POOL_BUCKET_DIRS} -type d -depth 1 -empty -print -quit || :)
	if [ -n "$p" ]; then
		_pkgname=${p##*/}
		if ! rename "${p}" "../building/${_pkgname}" \
		    2>/dev/null; then
			# Was the failure from /unbalanced?
			if [ -z "${p%%*unbalanced/*}" ]; then
				# We lost the race with a child running
				# balance_pool(). The file is already
				# gone and moved to a bucket. Try again.
				ret=0
				pkgqueue_get_next "${var_return}" || ret=$?
				return ${ret}
			else
				# Failure to move a balanced item??
				err 1 "pkgqueue_get_next: Failed to mv ${p} to ${MASTERMNT}/.p/building/${_pkgname}"
			fi
		fi
		# Update timestamp for buildtime accounting
		touch "../building/${_pkgname}"
	fi

	setvar "${var_return}" "${_pkgname}"
}

slock_acquire() {
	[ $# -ge 1 ] || eargs slock_acquire lockname [waittime]

	mkdir -p "${SHARED_LOCK_DIR}" >/dev/null 2>&1 || :
	POUDRIERE_TMPDIR="${SHARED_LOCK_DIR}" MASTERNAME=poudriere-shared \
	    lock_acquire "$@"
}

pkgqueue_init() {
	mkdir -p "${MASTERMNT}/.p/building" \
		"${MASTERMNT}/.p/pool" \
		"${MASTERMNT}/.p/pool/unbalanced" \
		"${MASTERMNT}/.p/deps" \
		"${MASTERMNT}/.p/rdeps" \
		"${MASTERMNT}/.p/cleaning/deps" \
		"${MASTERMNT}/.p/cleaning/rdeps"
}

pkgqueue_contains() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_contains requires PWD=${MASTERMNT}/.p"
	[ $# -eq 1 ] || eargs pkgqueue_contains pkgname
	local pkgname="$1"
	local pkg_dir_name

	pkgqueue_dir pkg_dir_name "${pkgname}"
	[ -d "deps/${pkg_dir_name}" ]
}

pkgqueue_add() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_add requires PWD=${MASTERMNT}/.p"
	[ $# -eq 1 ] || eargs pkgqueue_add pkgname
	local pkgname="$1"
	local pkg_dir_name

	pkgqueue_dir pkg_dir_name "${pkgname}"
	mkdir -p "deps/${pkg_dir_name}"
}

pkgqueue_add_dep() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_add_dep requires PWD=${MASTERMNT}/.p"
	[ $# -eq 2 ] || eargs pkgqueue_add_dep pkgname dep_pkgname
	local pkgname="$1"
	local dep_pkgname="$2"
	local pkg_dir_name

	pkgqueue_dir pkg_dir_name "${pkgname}"
	:> "deps/${pkg_dir_name}/${dep_pkgname}"
}

# Remove myself from the remaining list of dependencies for anything
# depending on this package. If clean_rdepends is set, instead cleanup
# anything depending on me and skip them.
pkgqueue_clean_rdeps() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_clean_rdeps requires PWD=${MASTERMNT}/.p"
	[ $# -eq 2 ] || eargs pkgqueue_clean_rdeps clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"
	local dep_dir dep_pkgname pkg_dir_name
	local deps_to_check deps_to_clean
	local rdep_dir rdep_dir_name

	rdep_dir="cleaning/rdeps/${pkgname}"

	# Exclusively claim the rdeps dir or return, another pkgqueue_done()
	# owns it or there were no reverse deps for this package.
	pkgqueue_dir rdep_dir_name "${pkgname}"
	rename "rdeps/${rdep_dir_name}" "${rdep_dir}" 2>/dev/null ||
	    return 0

	# Cleanup everything that depends on my package
	# Note 2 loops here to avoid rechecking clean_rdepends every loop.
	if [ -n "${clean_rdepends}" ]; then
		# Recursively cleanup anything that depends on my package.
		for dep_dir in ${rdep_dir}/*; do
			# May be empty if all my reverse deps are now skipped.
			case "${dep_dir}" in "${rdep_dir}/*") break ;; esac
			dep_pkgname=${dep_dir##*/}

			# clean_pool() in common.sh will pick this up and add to SKIPPED
			echo "${dep_pkgname}"

			pkgqueue_clean_pool ${dep_pkgname} "${clean_rdepends}"
		done
	else
		for dep_dir in ${rdep_dir}/*; do
			dep_pkgname=${dep_dir##*/}
			pkgqueue_dir pkg_dir_name "${dep_pkgname}"
			deps_to_check="${deps_to_check} deps/${pkg_dir_name}"
			deps_to_clean="${deps_to_clean} deps/${pkg_dir_name}/${pkgname}"
		done

		# Remove this package from every package depending on this.
		# This is removing: deps/<dep_pkgname>/<this pkg>.
		# Note that this is not needed when recursively cleaning as
		# the entire /deps/<pkgname> for all my rdeps will be removed.
		echo ${deps_to_clean} | xargs rm -f >/dev/null 2>&1 || :

		# Look for packages that are now ready to build. They have no
		# remaining dependencies. Move them to /unbalanced for later
		# processing.
		echo ${deps_to_check} | \
		    xargs -J % \
		    find % -type d -maxdepth 0 -empty 2>/dev/null | \
		    xargs -J % mv % "pool/unbalanced" \
		    2>/dev/null || :
	fi

	rm -rf "${rdep_dir}" >/dev/null 2>&1 &

	return 0
}

# Remove my /deps/<pkgname> dir and any references to this dir in /rdeps/
pkgqueue_clean_deps() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_clean_deps requires PWD=${MASTERMNT}/.p"
	[ $# -eq 2 ] || eargs pkgqueue_clean_deps clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"
	local dep_dir rdep_pkgname pkg_dir_name
	local deps_to_check rdeps_to_clean
	local dir rdep_dir_name

	dep_dir="cleaning/deps/${pkgname}"

	# Exclusively claim the deps dir or return, another pkgqueue_done()
	# owns it
	pkgqueue_dir pkg_dir_name "${pkgname}"
	rename "deps/${pkg_dir_name}" "${dep_dir}" 2>/dev/null ||
	    return 0

	# Remove myself from all my dependency rdeps to prevent them from
	# trying to skip me later

	for dir in ${dep_dir}/*; do
		rdep_pkgname=${dir##*/}
		pkgqueue_dir rdep_dir_name "${rdep_pkgname}"
		rdeps_to_clean="${rdeps_to_clean} rdeps/${rdep_dir_name}/${pkgname}"
	done

	echo ${rdeps_to_clean} | xargs rm -f >/dev/null 2>&1 || :

	rm -rf "${dep_dir}" >/dev/null 2>&1 &

	return 0
}

pkgqueue_clean_pool() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_clean_pool requires PWD=${MASTERMNT}/.p"
	[ $# -eq 2 ] || eargs pkgqueue_clean_pool clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"

	pkgqueue_clean_rdeps "${pkgname}" "${clean_rdepends}"

	# Remove this pkg from the needs-to-build list. It will not exist
	# if this build was sucessful. It only exists if pkgqueue_clean_pool is
	# being called recursively to skip items and in that case it will
	# not be empty.
	[ -n "${clean_rdepends}" ] &&
	    pkgqueue_clean_deps "${pkgname}" "${clean_rdepends}"

	return 0
}

pkgqueue_done() {
	[ $# -eq 2 ] || eargs pkgqueue_done pkgname clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"

	(
		cd "${MASTERMNT}/.p"
		pkgqueue_clean_pool "${pkgname}" "${clean_rdepends}"
	) | sort -u

	# Outputs skipped_pkgnames
}

pkgqueue_list() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_list requires PWD=${MASTERMNT}/.p"
	[ $# -eq 0 ] || eargs pkgqueue_list

	find deps -type d -depth 2 | cut -d / -f 3
}

# Create a pool of ready-to-build from the deps pool
pkgqueue_move_ready_to_pool() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_move_ready_to_pool requires PWD=${MASTERMNT}/.p"
	[ $# -eq 0 ] || eargs pkgqueue_move_ready_to_pool

	find deps -type d -depth 2 -empty | \
	    xargs -J % mv % pool/unbalanced
}

# Remove all packages from queue sent in STDIN
pkgqueue_remove_many_pipe() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_remove_many_pipe requires PWD=${MASTERMNT}/.p"
	[ $# -eq 0 ] || eargs pkgqueue_remove_many_pipe [pkgnames stdin]
	local pkgname

	while read pkgname; do
		pkgqueue_find_all_pool_references "${pkgname}"
	done | xargs rm -rf
}

# Compute back references for quickly finding things to skip if this job
# fails.
pkgqueue_compute_rdeps() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_compute_rdeps requires PWD=${MASTERMNT}/.p"
	[ $# -eq 1 ] || eargs pkgqueue_compute_rdeps pkg_deps
	local pkg_deps="$1"
	local job rdep_dir_name dep

	bset status "computingrdeps:"
	# cd into rdeps to allow xargs mkdir to have more args.
	(
		cd "rdeps"
		awk '{print $2}' "../${pkg_deps}" | sort -u | \
		    while read job; do
			pkgqueue_dir rdep_dir_name "${job}"
			echo "${rdep_dir_name}"
		done | xargs mkdir -p
		awk '{print $2 " " $1}' "../${pkg_deps}" | \
		    while read job dep; do
			pkgqueue_dir rdep_dir_name "${job}"
			echo "${rdep_dir_name}/${dep}"
		done | xargs touch
	)
}

pkgqueue_remaining() {
	[ "${PWD}" = "${MASTERMNT}/.p/pool" ] || \
	    err 1 "pkgqueue_remaining requires PWD=${MASTERMNT}/.p/pool"
	[ $# -eq 0 ] || eargs pkgqueue_remaining
	{
		# Find items in pool ready-to-build
		find . -type d -depth 2 | \
		    sed -e 's,$, ready-to-build,'
		# Find items in queue not ready-to-build.
		( cd ..; pkgqueue_list ) | \
		    sed -e 's,$, waiting-on-dependency,'
	} 2>/dev/null | sed -e 's,.*/,,'
}

# Return directory name for given job
pkgqueue_dir() {
	[ $# -eq 2 ] || eargs pkgqueue_dir var_return dir
	local var_return="$1"
	local dir="$2"

	setvar "${var_return}" "$(printf "%.1s/%s" "${dir}" "${dir}")"
}

lock_acquire() {
	[ $# -ge 1 ] || eargs lock_acquire lockname [waittime]
	local lockname="$1"
	local waittime="${2:-30}"

	# Don't take locks inside siginfo_handler
	[ ${in_siginfo_handler} -eq 1 ] && lock_have "${lockname}" && \
	    return 1

	if ! locked_mkdir "${waittime}" \
	    "${POUDRIERE_TMPDIR}/lock-${MASTERNAME}-${lockname}" "$$"; then
		msg_warn "Failed to acquire ${lockname} lock"
		return 1
	fi
	hash_set have_lock "${lockname}" 1

	# Delay TERM/INT while holding the lock
	critical_start
}

slock_release() {
	[ $# -ne 1 ] && eargs slock_release lockname
	POUDRIERE_TMPDIR="${SHARED_LOCK_DIR}" MASTERNAME=poudriere-shared \
	    lock_release "$@"
}

lock_release() {
	[ $# -ne 1 ] && eargs lock_release lockname
	local lockname="$1"

	hash_unset have_lock "${lockname}" || \
	    err 1 "Releasing unheld lock ${lockname}"
	rmdir "${POUDRIERE_TMPDIR}/lock-${MASTERNAME}-${lockname}" 2>/dev/null

	# Restore and deliver INT/TERM signals
	critical_end
}

lock_have() {
	[ $# -ne 1 ] && eargs lock_have lockname
	local lockname="$1"

	hash_isset have_lock "${lockname}"
}

have_ports_feature() {
	[ -z "${P_PORTS_FEATURES%%*${1}*}" ]
}

# Fetch vars from the Makefile and set them locally.
# port_var_fetch ports-mgmt/pkg PKGNAME pkgname PKGBASE pkgbase ...
# Assignments are supported as well, without a subsequent variable for storage.
port_var_fetch() {
	local -; set +x
	[ $# -ge 3 ] || eargs port_var_fetch origin PORTVAR var_set ...
	local origin="$1"
	local _make_origin _makeflags _vars
	local _portvar _var _line _errexit shiftcnt varcnt
	# Use a tab rather than space to allow FOO='BLAH BLAH' assignments
	# and lookups like -V'${PKG_DEPENDS} ${BUILD_DEPENDS}'
	local IFS sep=$'\t'
	# Use invalid shell var character '!' to ensure we
	# don't setvar it later.
	local assign_var="!"

	if [ -n "${origin}" ]; then
		_make_origin="-C${sep}${PORTSDIR}/${origin}"
	else
		_make_origin="-f${sep}${PORTSDIR}/Mk/bsd.port.mk${sep}PORTSDIR=${PORTSDIR}"
	fi

	shift

	while [ $# -gt 0 ]; do
		_portvar="$1"
		_var="$2"
		if [ -z "${_portvar%%*=*}" ]; then
			# This is an assignment, no associated variable
			# for storage.
			_makeflags="${_makeflags}${_makeflags:+${sep}}${_portvar}"
			_vars="${_vars}${_vars:+ }${assign_var}"
			shift 1
		else
			[ $# -eq 1 ] && break
			_makeflags="${_makeflags}${_makeflags:+${sep}}-V${_portvar}"
			_vars="${_vars}${_vars:+ }${_var}"
			shift 2
		fi
	done

	[ $# -eq 0 ] || eargs port_var_fetch origin PORTVAR var_set ...

	_errexit="!errexit!"
	ret=0

	set -- ${_vars}
	varcnt=$#
	shiftcnt=0
	while read -r _line; do
		if [ "${_line% *}" = "${_errexit}" ]; then
			ret=${_line#* }
			# Encountered an error, abort parsing anything further.
			# Cleanup already-set vars of 'make: stopped in'
			# stuff in case the caller is ignoring our non-0
			# return status.  The shiftcnt handler can deal with
			# this all itself.
			shiftcnt=0
			break
		fi
		# This var was just an assignment, no actual value to read from
		# stdout.  Shift until we find an actual -V var.
		while [ "${1}" = "${assign_var}" ]; do
			shift
			shiftcnt=$((shiftcnt + 1))
		done
		# We may have more lines than expected on an error, but our
		# errexit output is last, so keep reading until then.
		if [ $# -gt 0 ]; then
			setvar "$1" "${_line}" || return $?
			shift
			shiftcnt=$((shiftcnt + 1))
		fi
	done <<-EOF
	$(IFS="${sep}"; injail /usr/bin/make ${_make_origin} ${_makeflags} || echo "${_errexit} $?")
	EOF

	# If the entire output was blank, then $() ate all of the excess
	# newlines, which resulted in some vars not getting setvar'd.
	# This could also be cleaning up after the errexit case.
	if [ ${shiftcnt} -ne ${varcnt} ]; then
		set -- ${_vars}
		# Be sure to start at the last setvar'd value.
		if [ ${shiftcnt} -gt 0 ]; then
			shift ${shiftcnt}
		fi
		while [ $# -gt 0 ]; do
			# Skip assignment vars
			while [ "${1}" = "${assign_var}" ]; do
				shift
			done
			if [ $# -gt 0 ]; then
				setvar "$1" "" || return $?
				shift
			fi
		done
	fi

	return ${ret}
}

port_var_fetch_originspec() {
	local -; set +x
	[ $# -ge 3 ] || eargs port_var_fetch_originspec originspec \
	    PORTVAR var_set ...
	local originspec="$1"
	shift
	local origin dep_args flavor

	originspec_decode "${originspec}" origin dep_args flavor
	if [ -n "${dep_args}" ]; then
		msg_debug "port_var_fetch_originspec: processing ${originspec}"
	fi
	port_var_fetch "${origin}" "$@" ${dep_args} ${flavor:+FLAVOR=${flavor}}
}

get_originspec_from_pkgname() {
	[ $# -ne 2 ] && eargs get_originspec_from_pkgname var_return pkgname
	local var_return="$1"
	local pkgname="$2"

	shash_get pkgname-originspec "${pkgname}" "${var_return}"
}

get_origin_from_pkgname() {
	[ $# -ne 2 ] && eargs get_origin_from_pkgname var_return pkgname
	local var_return="$1"
	local pkgname="$2"
	local originspec

	get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" "${var_return}" '' ''
}

# Look for PKGNAME and strip away @DEFAULT if it is the default FLAVOR.
get_pkgname_from_originspec() {
	[ $# -eq 2 ] || eargs get_pkgname_from_originspec originspec var_return
	local _originspec="$1"
	local var_return="$2"
	local _pkgname _origin _dep_args _flavor _default_flavor _flavors

	# This function is primarily for FLAVORS handling.
	if ! have_ports_feature FLAVORS; then
		shash_get originspec-pkgname "${_originspec}" \
		    "${var_return}" || return 1
		return 0
	fi

	# Trim away FLAVOR_DEFAULT if present
	originspec_decode "${_originspec}" _origin _dep_args _flavor
	if [ "${_flavor}" = "${FLAVOR_DEFAULT}" ]; then
		_flavor=
		originspec_encode _originspec "${_origin}" '' "${_flavor}"
	fi
	shash_get originspec-pkgname "${_originspec}" "${var_return}" && \
	    return 0
	# If the FLAVOR is empty then it is fatal to not have a result yet.
	[ -z "${_flavor}" ] && return 1
	# See if the FLAVOR is the default and lookup that PKGNAME if so.
	originspec_encode _originspec "${_origin}" "${_dep_args}" ''
	shash_get originspec-pkgname "${_originspec}" _pkgname || return 1
	# Great, compare the flavors and validate we had the default.
	shash_get pkgname-flavors "${_pkgname}" _flavors || return 1
	[ -z "${_flavors}" ] && return 1
	_default_flavor="${_flavors%% *}"
	[ "${_default_flavor}" = "${_flavor}" ] || return 1
	# Yup, this was the default FLAVOR
	setvar "${var_return}" "${_pkgname}"
}

set_dep_fatal_error() {
	[ -n "${DEP_FATAL_ERROR}" ] && return 0
	DEP_FATAL_ERROR=1
	# Mark the fatal error flag. Must do it like this as this may be
	# running in a sub-shell.
	: > ${DEP_FATAL_ERROR_FILE}
}

clear_dep_fatal_error() {
	unset DEP_FATAL_ERROR
	unlink ${DEP_FATAL_ERROR_FILE} 2>/dev/null || :
	export ERRORS_ARE_DEP_FATAL=1
}

check_dep_fatal_error() {
	unset ERRORS_ARE_DEP_FATAL
	[ -n "${DEP_FATAL_ERROR}" ] || [ -f ${DEP_FATAL_ERROR_FILE} ]
}

gather_port_vars() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "gather_port_vars requires PWD=${MASTERMNT}/.p"
	local origin qorigin log originspec dep_args flavor rdep qlist

	# A. Lookup all port vars/deps from the given list of ports.
	# B. For every dependency found (depqueue):
	#   1. Add it into the depqueue, which will then process
	#      each dependency into the gatherqueue if it was not
	#      already gathered by the previous iteration.
	# C. Lookup all port vars/deps from the gatherqueue
	# D. If the depqueue is empty, done, otherwise go to B.
	#
	# This 2-queue solution is to avoid excessive races that cause
	# make -V to be ran multiple times per port.  We only want to
	# process each port once without explicit locking.
	# For the -a case the depqueue is only used for non-default originspecs
	# as the default originspecs will be visited once in the first pass
	# and make it into the gatherqueue.
	#
	# This idea was extended with a flavorqueue that allows originspec
	# items to be processed.  It is possible that a DEPENDS_ARGS or
	# FLAVOR argument to an origin matches the default, and thus we
	# just want to ignore it.  If it provides a new unique PKGNAME though
	# we want to keep it.  This separate queue is done to again avoid
	# processing the same origin concurrently in the previous queues.
	# For the -a case the flavorqueue is not needed since all ports
	# are visited in the gatherqueue for *their default* originspec
	# before processing any dependencies.

	msg "Gathering ports metadata"
	bset status "gatheringportvars:"
	run_hook gather_port_vars start

	:> "all_pkgs"
	[ ${ALL} -eq 0 ] && :> "all_pkgbases"

	rm -rf gqueue dqueue mqueue fqueue 2>/dev/null || :
	mkdir gqueue dqueue mqueue fqueue
	qlist=$(mktemp -t poudriere.qlist)

	clear_dep_fatal_error
	parallel_start
	for originspec in $(listed_ports show_moved); do
		originspec_decode "${originspec}" origin dep_args flavor
		rdep="listed"
		# For -a we skip the initial gatherqueue
		if [ ${ALL} -eq 1 ]; then
			[ -n "${flavor}" ] && \
			    err 1 "Flavor ${originspec} with ALL=1"
			parallel_run \
			    prefix_stderr_quick \
			    "(${COLOR_PORT}${originspec}${COLOR_RESET})${COLOR_WARN}" \
			    gather_port_vars_port "${originspec}" \
			    "${rdep}" || \
			    set_dep_fatal_error
			continue
		fi
		# Otherwise let's utilize the gatherqueue to simplify
		# FLAVOR handling.
		qorigin="gqueue/${origin%/*}!${origin#*/}"

		# For FLAVOR=all cache that request somewhere for
		# gather_port_vars_port to use later.  Other
		# methods of passing it down the queue are too complex.
		if [ "${flavor}" = "${FLAVOR_ALL}" ]; then
			unset flavor
			if [ "${FLAVOR_DEFAULT_ALL}" != "yes" ]; then
				shash_set origin-flavor-all "${origin}" 1
			fi
		fi

		# If we were passed a FLAVOR-specific origin, we
		# need to delay it into the flavorqueue because
		# it is possible the list has multiple FLAVORS
		# of the origin specified or even the main port.
		# We want to ensure that the main port is looked up
		# first and then FLAVOR-specific ones are processed.
		if [ -n "${flavor}" ] || [ -n "${dep_args}" ]; then
			# We will delay the FLAVOR-specific into
			# the flavorqueue and process the main port
			# here as long as it hasn't already.
			# Don't worry about duplicates from user list.
			mkdir -p \
			    "fqueue/${originspec%/*}!${originspec#*/}"
			echo "${rdep}" > \
			    "fqueue/${originspec%/*}!${originspec#*/}/rdep"
			msg_debug "queueing ${originspec} into flavorqueue (rdep=${rdep})"
			# For DEPENDS_ARGS we can skip bothering with
			# the gatherqueue just simply delay into the
			# flavorqueue.
			if [ -n "${dep_args}" ]; then
				continue
			fi

			# Testport already looked up the main FLAVOR
			if was_a_testport_run && \
			    [ -n "${ORIGIN}" ] && \
			    [ "${origin}" = "${ORIGIN}" ]; then
				continue
			fi

			# Now handle adding the main port without
			# FLAVOR.  Only do this if the main port
			# wasn't already listed.  The 'metadata'
			# will cause gather_port_vars_port to not
			# actually queue it for build unless it
			# is discovered to be the default.
			if [ -d "${qorigin}" ]; then
				rdep=
			elif [ -n "${flavor}" ]; then
				rdep="metadata ${flavor} listed"
			fi
		fi

		# Duplicate are possible from a user list, it's fine.
		mkdir -p "${qorigin}"
		msg_debug "queueing ${origin} into gatherqueue (rdep=${rdep})"
		[ -n "${rdep}" ] && echo "${rdep}" > "${qorigin}/rdep"
	done
	if ! parallel_stop || check_dep_fatal_error; then
		err 1 "Fatal errors encountered gathering initial ports metadata"
	fi

	until dirempty dqueue && dirempty gqueue && dirempty mqueue && \
	    dirempty fqueue; do
		# Process all newly found deps into the gatherqueue
		if ! dirempty dqueue; then
			msg_debug "Processing depqueue"
			:> "${qlist}"
			clear_dep_fatal_error
			parallel_start
			for qorigin in dqueue/*; do
				case "${qorigin}" in
				"dqueue/*") break ;;
				esac
				echo "${qorigin}" >> "${qlist}"
				origin="${qorigin#*/}"
				# origin is really originspec, but fixup
				# the substitued '/'
				originspec="${origin%!*}/${origin#*!}"
				parallel_run \
				    gather_port_vars_process_depqueue \
				    "${originspec}" || \
				    set_dep_fatal_error
			done
			if ! parallel_stop || check_dep_fatal_error; then
				err 1 "Fatal errors encountered processing gathered ports metadata"
			fi
			cat "${qlist}" | tr '\n' '\000' | xargs -0 rmdir
		fi

		# Now process the gatherqueue

		# Now rerun until the work queue is empty
		# XXX: If the initial run were to use an efficient work queue then
		#      this could be avoided.
		if ! dirempty gqueue; then
			msg_debug "Processing gatherqueue"
			:> "${qlist}"
			clear_dep_fatal_error
			parallel_start
			for qorigin in gqueue/*; do
				case "${qorigin}" in
				"gqueue/*") break ;;
				esac
				echo "${qorigin}" >> "${qlist}"
				origin="${qorigin#*/}"
				# origin is really originspec, but fixup
				# the substitued '/'
				originspec="${origin%!*}/${origin#*!}"
				read_line rdep "${qorigin}/rdep" || \
				    err 1 "gather_port_vars: Failed to read rdep for ${originspec}"
				parallel_run \
				    prefix_stderr_quick \
				    "(${COLOR_PORT}${originspec}${COLOR_RESET})${COLOR_WARN}" \
				    gather_port_vars_port \
				    "${originspec}" "${rdep}" || \
				    set_dep_fatal_error
			done
			if ! parallel_stop || check_dep_fatal_error; then
				err 1 "Fatal errors encountered gathering ports metadata"
			fi
			cat "${qlist}" | tr '\n' '\000' | xargs -0 rm -rf
		fi

		if ! dirempty gqueue || ! dirempty dqueue; then
			continue
		fi
		if ! dirempty mqueue; then
			msg_debug "Processing metaqueue"
			find mqueue -depth 1 -print0 | \
			    xargs -J % -0 mv % gqueue/ || \
			    err 1 "Failed moving mqueue items to gqueue"
		fi
		if ! dirempty gqueue; then
			continue
		fi
		# Process flavor queue to lookup newly discovered originspecs
		if ! dirempty fqueue; then
			msg_debug "Processing flavorqueue"
			# Just move all items to the gatherqueue.  We've
			# looked up the default flavor for each of these
			# origins already and can now try to identify alt
			# flavors for the origins.
			find fqueue -depth 1 -print0 | \
			    xargs -J % -0 mv % gqueue/ || \
			    err 1 "Failed moving fqueue items to gqueue"
		fi
	done

	if ! rmdir gqueue || ! rmdir dqueue || ! rmdir mqueue || \
	    ! rmdir fqueue; then
		ls gqueue dqueue mqueue fqueue 2>/dev/null || :
		err 1 "Gather port queues not empty"
	fi
	unlink "${qlist}" || :
	run_hook gather_port_vars stop
}

# Dependency policy/assertions.
deps_sanity() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "deps_sanity requires PWD=${MASTERMNT}/.p"
	[ $# -eq 2 ] || eargs deps_sanity originspec deps
	local originspec="${1}"
	local deps="${2}"
	local origin dep_originspec dep_origin dep_flavor ret
	local new_origin moved_reason

	originspec_decode "${originspec}" origin '' ''

	ret=0
	for dep_originspec in ${deps}; do
		originspec_decode "${dep_originspec}" dep_origin '' dep_flavor
		msg_verbose "${COLOR_PORT}${originspec}${COLOR_RESET} depends on ${COLOR_PORT}${dep_originspec}"
		if [ "${origin}" = "${dep_origin}" ]; then
			msg_error "${COLOR_PORT}${origin}${COLOR_RESET} incorrectly depends on itself. Please contact maintainer of the port to fix this."
			ret=1
		fi
		# Detect bad cat/origin/ dependency which pkg will not register properly
		if ! [ "${dep_origin}" = "${dep_origin%/}" ]; then
			msg_error "${COLOR_PORT}${origin}${COLOR_RESET} depends on bad origin '${COLOR_PORT}${dep_origin}${COLOR_RESET}'; Please contact maintainer of the port to fix this."
			ret=1
		fi
		if ! [ -d "../${PORTSDIR}/${dep_origin}" ]; then
			# Was it moved? We cannot map it here due to the ports
			# framework not supporting it later on, and the
			# PKGNAME would be wrong, but we can at least
			# advise the user about it.
			shash_get origin-moved "${dep_origin}" \
			    new_origin || new_origin=
			if [ "${new_origin}" = "EXPIRED" ]; then
				moved_reason="port EXPIRED"
			else
				moved_reason="moved to ${COLOR_PORT}${new_origin}${COLOR_RESET}"
			fi
			msg_error "${COLOR_PORT}${origin}${COLOR_RESET} depends on nonexistent origin '${COLOR_PORT}${dep_origin}${COLOR_RESET}'${moved_reason:+ (${moved_reason})}; Please contact maintainer of the port to fix this."
			ret=1
		fi
		if have_ports_feature FLAVORS && [ -z "${dep_flavor}" ] && \
		    [ "${dep_originspec}" != "${dep_origin}" ]; then
			msg_error "${COLOR_PORT}${origin}${COLOR_RESET} has dependency on ${COLOR_PORT}${dep_origin}${COLOR_RESET} with invalid empty FLAVOR; Please contact maintainer of the port to fix this."
			ret=1
		fi
	done
	return ${ret}
}

gather_port_vars_port() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "gather_port_vars_port requires SHASH_VAR_PATH=var/cache"
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "gather_port_vars_port requires PWD=${MASTERMNT}/.p"
	[ $# -eq 2 ] || eargs gather_port_vars_port originspec rdep
	local originspec="$1"
	local rdep="$2"
	local dep_origin deps pkgname dep_args dep_originspec
	local dep_ret log flavor flavors dep_flavor
	local origin origin_dep_args origin_flavor default_flavor

	msg_debug "gather_port_vars_port (${originspec}): LOOKUP"
	originspec_decode "${originspec}" origin origin_dep_args origin_flavor
	[ -n "${origin_dep_args}" ] && ! have_ports_feature DEPENDS_ARGS && \
	    err 1 "gather_port_vars_port: Looking up ${originspec} without DEPENDS_ARGS support in ports"
	[ -n "${origin_flavor}" ] && ! have_ports_feature FLAVORS && \
	    err 1 "gather_port_vars_port: Looking up ${originspec} without FLAVORS support in ports"

	# Trim away FLAVOR_DEFAULT and restore it later
	if [ "${origin_flavor}" = "${FLAVOR_DEFAULT}" ]; then
		originspec_encode originspec "${origin}" "${origin_dep_args}" \
		    ''
	fi

	# A metadata lookup may have been queued for this port that is no
	# longer needed.
	if [ ${ALL} -eq 0 ] && [ "${rdep%% *}" != "metadata" ] && \
	    [ -d "mqueue/${originspec%/*}!${originspec#*/}" ]; then
		rm -rf "mqueue/${originspec%/*}!${originspec#*/}"
	fi
	if shash_get originspec-pkgname "${originspec}" pkgname; then
		# We already fetched the vars for this port, but did
		# we actually queue it? We only care if the rdep isn't
		# currently 'metadata' (which can't happen here) and
		# if not -a since it can't happen in that case either.
		# This is the opposite of the check later.
		is_failed_metadata_lookup "${pkgname}" "${rdep}" || \
		    err 1 "gather_port_vars_port: Already had ${originspec} (rdep=${rdep})"

		shash_get pkgname-deps "${pkgname}" deps || deps=
		shash_get pkgname-flavor "${pkgname}" flavor || flavor=
		shash_get pkgname-flavors "${pkgname}" flavors || flavors=
		# DEPENDS_ARGS not fetched since it is not possible to be
		# in this situation with them.  The 'metadata' hack is
		# only used for FLAVOR lookups.
	else
		dep_ret=0
		deps_fetch_vars "${originspec}" deps pkgname dep_args flavor \
		    flavors || dep_ret=$?
		case ${dep_ret} in
		0) ;;
		# Non-fatal duplicate should be ignored
		2)
			# If this a superfluous DEPENDS_ARGS then there's
			# nothing more to do - it's already queued.
			[ -n "${origin_dep_args}" ] && return 0
			# The previous depqueue run may have readded
			# this originspec into the flavorqueue.
			# Expunge it.
			if [ -d \
			    "fqueue/${originspec%/*}!${originspec#*/}" ]; then
				rm -rf "fqueue/${originspec%/*}!${originspec#*/}"
			fi
			# If this is the default FLAVOR and we're not already
			# queued then we're the victim of the 'metadata' hack.
			# Fix it.
			default_flavor="${flavors%% *}"
			[ "${origin_flavor}" = "${FLAVOR_DEFAULT}" ] && \
			    origin_flavor="${default_flavor}"
			if ! [ -n "${flavors}" -a \
			    "${origin_flavor}" = "${default_flavor}" ]; then
				# Not the default FLAVOR.
				# Is it even a valid FLAVOR though?
				case " ${flavors} " in
				*\ ${origin_flavor}\ *)
					# A superfluous valid FLAVOR, nothing
					# more to do.
					return 0
					;;
				esac
				# The FLAVOR is invalid.  It will be marked
				# IGNORE but we process it far too late.
				# There is no unique PKGNAME for this lookup
				# so we must fail now.
				err 1 "Invalid FLAVOR '${origin_flavor}' for ${COLOR_PORT}${origin}${COLOR_RESET}"
			fi
			if pkgname_is_queued "${pkgname}"; then
				# Nothing more do to.
				return 0
			fi
			msg_debug "gather_port_vars_port: Fixing up from metadata hack on ${originspec}"
			# Queue us as the main port
			originspec_encode originspec "${origin}" \
			    "${origin_dep_args}" ''
			# Having $origin_flavor set prevents looping later.
			;;
		# Fatal error
		*)
			# An error is printed from deps_fetch_vars
			set_dep_fatal_error
			return 1
			;;
		esac
	fi

	# If this originspec was added purely for metadata lookups then
	# there's nothing more to do.  Unless it is the default FLAVOR
	# which is also listed to build since the FLAVOR-specific one
	# will be found superfluous later.  None of this is possible with -a
	if [ ${ALL} -eq 0 ] && [ "${rdep%% *}" = "metadata" ]; then
		# rdep is: metadata flavor original_rdep
		if [ -z "${flavors}" ]; then
			msg_debug "SKIPPING ${originspec} - no FLAVORS"
			return 0
		fi
		local queued_flavor queuespec

		default_flavor="${flavors%% *}"
		rdep="${rdep#* }"
		queued_flavor="${rdep% *}"
		[ "${queued_flavor}" = "${FLAVOR_DEFAULT}" ] && \
		    queued_flavor="${default_flavor}"
		# Check if we have the default FLAVOR sitting in the
		# flavorqueue and don't skip if so.
		if [ "${queued_flavor}" != "${default_flavor}" ]; then
			msg_debug "SKIPPING ${originspec} - metadata lookup queued=${queued_flavor} default=${default_flavor}"
			return 0
		fi
		# We're keeping this metadata lookup as its original rdep
		# but we need to prevent forcing all FLAVORS to build
		# later, so reset our flavor and originspec.
		rdep="${rdep#* }"
		origin_flavor="${queued_flavor}"
		originspec_encode queuespec "${origin}" "${origin_dep_args}" \
		    "${origin_flavor}"
		msg_debug "gather_port_vars_port: Fixing up ${originspec} to be ${queuespec}"
		if [ -d "fqueue/${queuespec%/*}!${queuespec#*/}" ]; then
			rm -rf "fqueue/${queuespec%/*}!${queuespec#*/}"
		fi
		# Remove the @FLAVOR_DEFAULT too
		originspec_encode queuespec "${origin}" "${origin_dep_args}" \
		    "${FLAVOR_DEFAULT}"
		if [ -d "fqueue/${queuespec%/*}!${queuespec#*/}" ]; then
			rm -rf "fqueue/${queuespec%/*}!${queuespec#*/}"
		fi
	fi

	msg_debug "WILL BUILD ${originspec}"
	echo "${pkgname} ${originspec} ${rdep}" >> "all_pkgs"
	[ ${ALL} -eq 0 ] && echo "${pkgname%-*}" >> "all_pkgbases"

	# Add all of the discovered FLAVORS into the flavorqueue if
	# this was the default originspec and this originspec was
	# listed to build.
	if [ "${rdep}" = "listed" -a \
	    -z "${origin_flavor}" -a -n "${flavors}" ] && \
	    build_all_flavors "${originspec}"; then
		msg_verbose "Will build all flavors for ${COLOR_PORT}${originspec}${COLOR_RESET}: ${flavors}"
		for dep_flavor in ${flavors}; do
			# Skip default FLAVOR
			[ "${flavor}" = "${dep_flavor}" ] && continue
			originspec_encode dep_originspec "${origin}" \
			    "${origin_dep_args}" "${dep_flavor}"
			msg_debug "gather_port_vars_port (${originspec}): Adding to flavorqueue FLAVOR=${dep_flavor}${dep_args:+ (DEPENDS_ARGS=${dep_args})}"
			mkdir -p "fqueue/${dep_originspec%/*}!${dep_originspec#*/}" || \
				err 1 "gather_port_vars_port: Failed to add ${dep_originspec} to flavorqueue"
			# Copy our own reverse dep over.  This should always
			# just be "listed" in this case ($rdep == listed) but
			# use the actual value to reduce maintenance.
			echo "${rdep}" > \
			    "fqueue/${dep_originspec%/*}!${dep_originspec#*/}/rdep"
		done

	fi

	# If there are no deps for this port then there's nothing left to do.
	[ -z "${deps}" ] && return 0

	# Assert some policy before proceeding to process these deps
	# further.
	if ! deps_sanity "${originspec}" "${deps}"; then
		set_dep_fatal_error
		return 1
	fi

	# In the -a case, there's no need to use the depqueue to add
	# dependencies into the gatherqueue for those without a DEPENDS_ARGS
	# for them since the default ones will be visited from the category
	# Makefiles anyway.
	if [ ${ALL} -eq 0 ] || [ -n "${dep_args}" ] ; then
		msg_debug "gather_port_vars_port (${originspec}): Adding to depqueue${dep_args:+ (DEPENDS_ARGS=${dep_args})}"
		mkdir "dqueue/${originspec%/*}!${originspec#*/}" || \
			err 1 "gather_port_vars_port: Failed to add ${originspec} to depqueue"
	fi
}

# Annoying hack for dealing with FLAVORs not queueing properly due
# to shoehorning the main port in the 'metadata' lookup hack.  This is
# just common code.
is_failed_metadata_lookup() {
	[ $# -eq 2 ] || eargs is_failed_metadata_lookup pkgname rdep
	local pkgname="$1"
	local rdep="$2"

	if ! have_ports_feature FLAVORS || \
	    [ ${ALL} -eq 1 ] || [ "${rdep%% *}" = "metadata" ] || \
	    pkgname_is_queued "${pkgname}"; then
		return 1
	else
		return 0
	fi
}

gather_port_vars_process_depqueue_enqueue() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "gather_port_vars_process_depqueue_enqueue requires SHASH_VAR_PATH=var/cache"
	[ $# -ne 4 ] && eargs gather_port_vars_process_depqueue_enqueue \
	    originspec dep_originspec queue rdep
	local originspec="$1"
	local dep_originspec="$2"
	local queue="$3"
	local rdep="$4"
	local origin dep_pkgname

	# Add this origin into the gatherqueue if not already done.
	if shash_get originspec-pkgname "${dep_originspec}" dep_pkgname; then
		if ! is_failed_metadata_lookup "${dep_pkgname}" \
		    "${rdep}"; then
			msg_debug "gather_port_vars_process_depqueue_enqueue (${originspec}): Already had ${dep_originspec}, not enqueueing into ${queue} (rdep=${rdep})"
			return 0
		fi
		# The package isn't queued but is needed and already known.
		# That means we did a 'metadata' lookup hack on it already.
		# Ensure we process it.
	fi

	msg_debug "gather_port_vars_process_depqueue_enqueue (${originspec}): Adding ${dep_originspec} into the ${queue} (rdep=${rdep})"
	# Another worker may have created it
	if mkdir "${queue}/${dep_originspec%/*}!${dep_originspec#*/}" \
	    2>/dev/null; then
		originspec_decode "${originspec}" origin '' ''

		echo "${rdep}" > \
		    "${queue}/${dep_originspec%/*}!${dep_originspec#*/}/rdep"
	fi
}

gather_port_vars_process_depqueue() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "gather_port_vars_process_depqueue requires SHASH_VAR_PATH=var/cache"
	[ $# -ne 1 ] && eargs gather_port_vars_process_depqueue originspec
	local originspec="$1"
	local origin pkgname deps dep_origin
	local dep_args dep_originspec dep_flavor queue rdep

	msg_debug "gather_port_vars_process_depqueue (${originspec})"

	# Add all of this origin's deps into the gatherqueue to reprocess
	shash_get originspec-pkgname "${originspec}" pkgname || \
	    err 1 "gather_port_vars_process_depqueue failed to find pkgname for origin ${originspec}"
	shash_get pkgname-deps "${pkgname}" deps || \
	    err 1 "gather_port_vars_process_depqueue failed to find deps for pkg ${pkgname}"

	originspec_decode "${originspec}" origin '' ''
	for dep_originspec in ${deps}; do
		originspec_decode "${dep_originspec}" dep_origin \
		    dep_args dep_flavor
		# First queue the default origin into the gatherqueue if
		# needed.  For the -a case we're guaranteed to already
		# have done this via the category Makefiles.
		if [ ${ALL} -eq 0 ] && [ -z "${dep_args}" ]; then
			if [ -n "${dep_flavor}" ]; then
				queue=mqueue
				rdep="metadata ${dep_flavor} ${originspec}"
			else
				queue=gqueue
				rdep="${originspec}"
			fi

			msg_debug "Want to enqueue default ${dep_origin} rdep=${rdep} into ${queue}"
			gather_port_vars_process_depqueue_enqueue \
			    "${originspec}" "${dep_origin}" "${queue}" \
			    "${rdep}"
		fi

		# And place any DEPENDS_ARGS-specific origin into the
		# flavorqueue
		if [ -n "${dep_args}" -o -n "${dep_flavor}" ]; then
			# For the -a case we can skip the flavorqueue since
			# we've already processed all default origins
			if [ ${ALL} -eq 1 ]; then
				queue=gqueue
			else
				queue=fqueue
			fi
			msg_debug "Want to enqueue ${dep_originspec} rdep=${origin} into ${queue}"
			gather_port_vars_process_depqueue_enqueue \
			    "${originspec}" "${dep_originspec}" "${queue}" \
			    "${originspec}"
		fi
	done
}


compute_deps() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "compute_deps requires PWD=${MASTERMNT}/.p"
	local pkgname originspec dep_pkgname _ignored

	msg "Calculating ports order and dependencies"
	bset status "computingdeps:"
	run_hook compute_deps start

	:> "pkg_deps.unsorted"

	clear_dep_fatal_error
	parallel_start
	while read pkgname originspec _ignored; do
		parallel_run compute_deps_pkg "${pkgname}" "${originspec}" \
		    "pkg_deps.unsorted" || set_dep_fatal_error
	done < "all_pkgs"
	if ! parallel_stop || check_dep_fatal_error; then
		err 1 "Fatal errors encountered calculating dependencies"
	fi

	sort -u "pkg_deps.unsorted" > "pkg_deps"
	unlink "pkg_deps.unsorted"

	pkgqueue_compute_rdeps "pkg_deps"

	run_hook compute_deps stop
	return 0
}

compute_deps_pkg() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "compute_deps_pkg requires SHASH_VAR_PATH=var/cache"
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "compute_deps_pkgname requires PWD=${MASTERMNT}/.p"
	[ $# -ne 3 ] && eargs compute_deps_pkg pkgname originspec pkg_deps
	local pkgname="$1"
	local originspec="$2"
	local pkg_deps="$3"
	local deps dep_pkgname dep_originspec dep_origin dep_flavor
	local raw_deps d key dpath dep_real_pkgname err_type

	# Safe to remove pkgname-deps now, it won't be needed later.
	shash_remove pkgname-deps "${pkgname}" deps || \
	    err 1 "compute_deps_pkg failed to find deps for ${pkgname}"

	msg_debug "compute_deps_pkg: Will build ${pkgname}"
	pkgqueue_add "${pkgname}" || \
	    err 1 "compute_deps_pkg: Error creating queue entry for ${pkgname}: There may be a duplicate origin in a category Makefile"

	for dep_originspec in ${deps}; do
		if ! get_pkgname_from_originspec "${dep_originspec}" \
		    dep_pkgname; then
			originspec_decode "${dep_originspec}" dep_origin '' \
			    dep_flavor
			[ ${ALL} -eq 0 ] && \
			    err 1 "compute_deps_pkg failed to lookup pkgname for ${dep_originspec} processing package ${pkgname} from ${originspec} -- Does ${dep_origin} provide the '${dep_flavor}' FLAVOR?"
			err 1 "compute_deps_pkg failed to lookup pkgname for ${dep_originspec} processing package ${pkgname} from ${originspec} -- Is SUBDIR+=${dep_originspec#*/} missing in ${dep_originspec%/*}/Makefile and does the port provide the '${dep_flavor}' FLAVOR?"
		fi
		msg_debug "compute_deps_pkg: Will build ${dep_originspec} for ${pkgname}"
		pkgqueue_add_dep "${pkgname}" "${dep_pkgname}"
		echo "${pkgname} ${dep_pkgname}" >> "${pkg_deps}"
		if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
			# Cache for call later in this func
			hash_set compute_deps_originspec-pkgname \
			    "${dep_originspec}" "${dep_pkgname}"
		fi
	done
	# Check for invalid PKGNAME dependencies which break later incremental
	# 'new dependency' detection.  This is done here rather than
	# delete_old_pkgs since that only covers existing packages, but we
	# need to detect the problem for all new package builds.
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		if [ "${BAD_PKGNAME_DEPS_ARE_FATAL}" = "yes" ]; then
			err_type="err 1"
		else
			err_type="msg_warn"
		fi
		shash_get pkgname-run_deps "${pkgname}" raw_deps || raw_deps=
		for d in ${raw_deps}; do
			key="${d%:*}"
			# Validate that there is not an incorrect
			# PKGNAME dependency that does not match the
			# actual PKGNAME.  This would otherwise cause
			# the next build to delete the package due
			# to having a 'new dependency' since pkg would
			# not record it due to being invalid.
			case "${key}" in
			*\>*|*\<*|*=*)
				dep_pkgname="${key%%[><=]*}"
				dpath="${d#*:}"
				case "${dpath}" in
				${PORTSDIR}/*)
					dpath=${dpath#${PORTSDIR}/} ;;
				esac
				[ -n "${dpath}" ] || \
				    err 1 "Invalid dependency line for ${pkgname}: ${d}"
				hash_get \
				    compute_deps_originspec-pkgname \
				    "${dpath}" dep_real_pkgname || \
				    err 1 "compute_deps_pkg failed to lookup existing pkgname for ${dpath} processing package ${pkgname}"
				case "${dep_real_pkgname%-*}" in
				${dep_pkgname}) ;;
				*)
					${err_type} "${COLOR_PORT}${originspec}${COLOR_WARN} dependency on ${COLOR_PORT}${dpath}${COLOR_WARN} has wrong PKGNAME of '${dep_pkgname}' but should be '${dep_real_pkgname%-*}'"
					;;
				esac
				;;
			*) ;;
			esac
		done
	fi

	return 0
}

# Before Poudriere added DEPENDS_ARGS and FLAVORS support many slave ports
# were added that are now redundant.  Replace them with the proper main port
# dependency.
map_py_slave_port() {
	[ $# -eq 2 ] || eargs map_py_slave_port originspec \
	    var_return_originspec
	local _originspec="$1"
	local var_return_originspec="$2"
	local origin dep_args flavor mapped_origin pyreg pyver

	originspec_decode "${_originspec}" origin dep_args flavor

	have_ports_feature DEPENDS_ARGS || return 1
	have_ports_feature FLAVORS && return 1
	[ "${P_PYTHON_MAJOR_VER}" = "2" ] || return 1

	# If there's already a DEPENDS_ARGS or FLAVOR just assume it
	# is working with the new framework or is not in need of
	# remapping.
	if [ -n "${dep_args}" ] || [ -n "${flavor}" ]; then
		return 1
	fi

	# Some ports don't need mapping.  They need to be renamed in ports.
	case "${origin}" in
		accessibility/py3-speech-dispatcher)	return 1 ;;
		devel/py*-setuptools)			return 1 ;;
		devel/py3-threema-msgapi)		return 1 ;;
		net-mgmt/py3-dnsdiag)			return 1 ;;
		textproc/py3-asciinema)			return 1 ;;
		textproc/py3-pager)			return 1 ;;
	esac

	# These ports need to have their main port properly made into
	# a variable port - which comes naturally with the FLAVORS
	# conversion.  They have no MASTERDIR now but seemingly do --
	# OR they have a MASTERDIR that is not otherwise a dependency
	# for anything and does not cause a DEPENDS_ARGS-generated py3
	# package.
	case "${origin}" in
		accessibility/py3-atspi)	return 1 ;;
		audio/py3-pylast)		return 1 ;;
		devel/py3-babel)		return 1 ;;
		devel/py3-dbus)			return 1 ;;
		devel/py3-gobject3)		return 1 ;;
		devel/py3-jsonschema)		return 1 ;;
		devel/py3-libpeas)		return 1 ;;
		devel/py3-vcversioner)		return 1 ;;
		devel/py3-xdg)			return 1 ;;
		graphics/py3-cairo)		return 1 ;;
		multimedia/py3-gstreamer1)	return 1 ;;
		sysutils/py3-iocage)		return 1 ;;
		textproc/py3-libxml2)		return 1 ;;
		# It only supports up to 3.3
		devel/py3-enum34)		return 1 ;;
	esac

	[ -n "${P_PYTHON3_DEFAULT}" ] || \
	    err 1 "P_PYTHON3_DEFAULT not set"

	case "${origin}" in
		*/py3-*)
			pyver="${P_PYTHON3_DEFAULT}"
			pyreg='/py3-'
			pymaster_prefix='py-'
			;;
		*/py3[0-9]-*)
			pyreg='/py3[0-9]-'
			pyver="${origin#*py3}"
			pyver="3.${pyver%%-*}"
			pymaster_prefix='py-'
			;;
		*) return 1 ;;
	esac
	mapped_origin="${origin%%${pyreg}*}/${pymaster_prefix}${origin#*${pyreg}}${pymaster_suffix}"
	# Verify the port even exists or else we need a special case above.
	[ -d "${MASTERMNT}${PORTSDIR}/${mapped_origin}" ] || \
	    err 1 "map_py_slave_port: Mapping ${_originspec} found no existing ${mapped_origin}"
	dep_args="PYTHON_VERSION=python${pyver}"
	msg_debug "Mapping ${origin} to ${mapped_origin} with DEPENDS_ARGS=${dep_args}"
	originspec_encode "${var_return_originspec}" "${mapped_origin}" \
	    "${dep_args}" ''
	return 0
}

origin_should_use_dep_args() {
	[ $# -eq 1 ] || eargs _origin_should_use_dep_args origin
	local origin="${1}"

	have_ports_feature DEPENDS_ARGS || return 1
	have_ports_feature FLAVORS && return 1
	[ "${P_PYTHON_MAJOR_VER}" = "2" ] || return 1

	case "${origin}" in
	# Only use DEPENDS_ARGS on py- ports where it will
	# make an impact.  It can still result in superfluous
	# PKGNAMES as some py- ports are really 3+.  This
	# matching is done to at least reduce the number of
	# superfluous lookups for optimization.
	*/python*) ;;
	*/py-*) return 0 ;;
	esac
	return 1
}

listed_ports() {
	if have_ports_feature DEPENDS_ARGS; then
		_listed_ports "$@" | while read originspec; do
			map_py_slave_port "${originspec}" originspec || :
			echo "${originspec}"
		done
		return
	fi
	_listed_ports "$@"
}
_listed_ports() {
	local tell_moved="${1}"
	local portsdir origin file

	if [ ${ALL} -eq 1 ]; then
		_pget portsdir ${PTNAME} mnt
		[ -d "${portsdir}/ports" ] && portsdir="${portsdir}/ports"
		for cat in $(awk -F= '$1 ~ /^[[:space:]]*SUBDIR[[:space:]]*\+/ {gsub(/[[:space:]]/, "", $2); print $2}' ${portsdir}/Makefile); do
			awk -F= -v cat=${cat} '$1 ~ /^[[:space:]]*SUBDIR[[:space:]]*\+/ {gsub(/[[:space:]]/, "", $2); print cat"/"$2}' ${portsdir}/${cat}/Makefile
		done | while read origin; do
			if ! [ -d "${portsdir}/${origin}" ]; then
				msg_warn "Nonexistent origin listed in category Makefiles: ${COLOR_PORT}${origin}${COLOR_RESET} (skipping)"
				continue
			fi
			echo "${origin}"
		done
		return 0
	fi

	{
		# -f specified
		if [ -z "${LISTPORTS}" ]; then
			for file in ${LISTPKGS}; do
				while read origin; do
					# Skip blank lines and comments
					[ -z "${origin%%#*}" ] && continue
					# Remove excess slashes for mistakes
					origin="${origin#/}"
					echo "${origin%/}"
				done < "${file}"
			done
		else
			# Ports specified on cmdline
			for origin in ${LISTPORTS}; do
				# Remove excess slashes for mistakes
				origin="${origin#/}"
				echo "${origin%/}"
			done
		fi
	} | sort -u | while read originspec; do
		originspec_decode "${originspec}" origin '' flavor
		if [ -n "${flavor}" ] && ! have_ports_feature FLAVORS; then
			msg_error "Trying to build FLAVOR-specific ${originspec} but ports tree has no FLAVORS support."
			set_dep_fatal_error
			continue
		fi
		origin_listed="${origin}"
		if shash_get origin-moved "${origin}" new_origin; then
			if [ "${new_origin}" = "EXPIRED" ]; then
				shash_get origin-moved-expired "${origin}" \
				    expired_reason || expired_reason=
				msg_error "MOVED: ${origin} ${expired_reason}"
				set_dep_fatal_error
				continue
			fi
			originspec="${new_origin}"
			originspec_decode "${originspec}" origin '' flavor
		else
			unset new_origin
		fi
		if ! [ -d "../${PORTSDIR}/${origin}" ]; then
			msg_error "Nonexistent origin listed: ${COLOR_PORT}${origin_listed}${new_origin:+${COLOR_RESET} (moved to nonexistent ${COLOR_PORT}${new_origin}${COLOR_RESET})}"
			set_dep_fatal_error
			continue
		fi
		[ -n "${tell_moved}" ] && [ -n "${new_origin}" ] && msg_warn \
			    "MOVED: ${COLOR_PORT}${origin_listed}${COLOR_RESET} renamed to ${COLOR_PORT}${new_origin}${COLOR_RESET}"
		echo "${originspec}"
	done
}

listed_pkgnames() {
	awk '$3 == "listed" { print $1 }' "${MASTERMNT}/.p/all_pkgs"
}

# Pkgname was in queue
pkgname_is_queued() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgname_is_queued requires PWD=${MASTERMNT}/.p"
	[ $# -eq 1 ] || eargs pkgname_is_queued pkgname
	local pkgname="$1"

	awk -vpkgname="${pkgname}" '
	    $1 == pkgname {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "all_pkgs"
}

# Pkgname was listed to be built
pkgname_is_listed() {
	[ $# -eq 1 ] || eargs pkgname_is_listed pkgname
	local pkgname="$1"

	[ ${ALL} -eq 1 ] && return 0

	awk -vpkgname="${pkgname}" '
	    $3 == "listed" && $1 == pkgname {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTERMNT}/.p/all_pkgs"
}

# PKGBASE was requested to be built, or is needed by a port requested to be built
pkgbase_is_needed() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgbase_is_needed requires PWD=${MASTERMNT}/.p"
	[ $# -eq 1 ] || eargs pkgbase_is_needed pkgname
	local pkgname="$1"
	local pkgbase

	[ ${ALL} -eq 1 ] && return 0

	# We check on PKGBASE rather than PKGNAME from pkg_deps
	# since the caller may be passing in a different version
	# compared to what is in the queue to build for.
	pkgbase="${pkgname%-*}"

	awk -vpkgbase="${pkgbase}" '
	    $1 == pkgbase {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "all_pkgbases"
}

# Port was requested to be built, or is needed by a port requested to be built
originspec_is_needed() {
       [ "${PWD}" = "${MASTERMNT}/.p" ] || \
           err 1 "originspec_is_needed requires PWD=${MASTERMNT}/.p"
       [ $# -eq 1 ] || eargs originspec_is_needed originspec
       local originspec="$1"

       [ ${ALL} -eq 1 ] && return 0

       awk -voriginspec="${originspec}" '
           $2 == originspec {
               found=1
               exit 0
           }
           END {
               if (found != 1)
                       exit 1
           }' "all_pkgs"
}

get_porttesting() {
	[ $# -eq 1 ] || eargs get_porttesting pkgname
	local pkgname="$1"
	local porttesting

	porttesting=
	if [ -n "${PORTTESTING}" ]; then
		if [ ${ALL} -eq 1 -o ${PORTTESTING_RECURSIVE} -eq 1 ]; then
			porttesting=1
		elif pkgname_is_listed "${pkgname}"; then
			porttesting=1
		fi
	fi
	echo "${porttesting}"
}

# List deps from pkgnames in STDIN
pkgqueue_list_deps_pipe() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_list_deps_pipe requires PWD=${MASTERMNT}/.p"
	[ $# -eq 0 ] || eargs pkgqueue_list_deps_pipe [pkgnames stdin]
	local pkgname FIND_ALL_DEPS

	unset FIND_ALL_DEPS
	while read pkgname; do
		pkgqueue_list_deps_recurse "${pkgname}" | sort -u
	done | sort -u
}

pkgqueue_list_deps_recurse() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_list_deps_recurse requires PWD=${MASTERMNT}/.p"
	[ $# -ne 1 ] && eargs pkgqueue_list_deps_recurse pkgname
	local pkgname="$1"
	local dep_pkgname pkg_dir_name

	FIND_ALL_DEPS="${FIND_ALL_DEPS} ${pkgname}"

	#msg_debug "pkgqueue_list_deps_recurse ${pkgname}"

	pkgqueue_dir pkg_dir_name "${pkgname}"
	# Show deps/*/${pkgname}
	for pn in deps/${pkg_dir_name}/*; do
		dep_pkgname="${pn##*/}"
		case " ${FIND_ALL_DEPS} " in
			*\ ${dep_pkgname}\ *) continue ;;
		esac
		case "${pn}" in
			"deps/${pkg_dir_name}/*") break ;;
		esac
		echo "${dep_pkgname}"
		pkgqueue_list_deps_recurse "${dep_pkgname}"
	done
	echo "${pkgname}"
}

pkgqueue_find_all_pool_references() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "pkgqueue_find_all_pool_references requires PWD=${MASTERMNT}/.p"
	[ $# -ne 1 ] && eargs pkgqueue_find_all_pool_references pkgname
	local pkgname="$1"
	local rpn dep_pkgname rdep_dir_name pkg_dir_name dep_dir_name

	# Cleanup rdeps/*/${pkgname}
	pkgqueue_dir pkg_dir_name "${pkgname}"
	for rpn in deps/${pkg_dir_name}/*; do
		case "${rpn}" in
			"deps/${pkg_dir_name}/*")
				break ;;
		esac
		dep_pkgname=${rpn##*/}
		pkgqueue_dir rdep_dir_name "${dep_pkgname}"
		echo "rdeps/${rdep_dir_name}/${pkgname}"
	done
	echo "deps/${pkg_dir_name}"
	# Cleanup deps/*/${pkgname}
	pkgqueue_dir rdep_dir_name "${pkgname}"
	for rpn in rdeps/${rdep_dir_name}/*; do
		case "${rpn}" in
			"rdeps/${rdep_dir_name}/*")
				break ;;
		esac
		dep_pkgname=${rpn##*/}
		pkgqueue_dir dep_dir_name "${dep_pkgname}"
		echo "deps/${dep_dir_name}/${pkgname}"
	done
	echo "rdeps/${rdep_dir_name}"
}

delete_stale_symlinks_and_empty_dirs() {
	msg_n "Deleting stale symlinks..."
	find -L ${PACKAGES} -type l \
		-exec rm -f {} +
	echo " done"

	msg_n "Deleting empty directories..."
	find ${PACKAGES} -type d -mindepth 1 \
		-empty -delete
	echo " done"
}

load_moved() {
	if [ "${SCRIPTPATH##*/}" != "distclean.sh" ]; then
		[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
		    err 1 "load_moved requires SHASH_VAR_PATH=var/cache"
		[ "${PWD}" = "${MASTERMNT}/.p" ] || \
		    err 1 "load_moved requires PWD=${MASTERMNT}/.p"
	fi
	[ -f ${MASTERMNT}${PORTSDIR}/MOVED ] || return 0
	msg "Loading MOVED for ${MASTERMNT}${PORTSDIR}"
	bset status "loading_moved:"
	awk -f ${AWKPREFIX}/parse_MOVED.awk \
	    ${MASTERMNT}${PORTSDIR}/MOVED | \
	    while read old_origin new_origin expired_reason; do
		shash_set origin-moved "${old_origin}" "${new_origin}"
		if [ "${new_origin}" = "EXPIRED" ]; then
			shash_set origin-moved-expired "${old_origin}" \
			    "${expired_reason}"
		fi
	done
}

fetch_global_port_vars() {
	was_a_testport_run && [ -n "${P_PORTS_FEATURES}" ] && return 0
	# Before we start, determine the default PYTHON version to
	# deal with any use of DEPENDS_ARGS involving it.  DEPENDS_ARGS
	# was a hack only actually used for python ports.
	port_var_fetch '' \
	    'USES=python' \
	    PORTS_FEATURES P_PORTS_FEATURES \
	    PYTHON_MAJOR_VER P_PYTHON_MAJOR_VER \
	    PYTHON_DEFAULT_VERSION P_PYTHON_DEFAULT_VERSION \
	    PYTHON3_DEFAULT P_PYTHON3_DEFAULT || \
	    err 1 "Error looking up pre-build ports vars"
	# Ensure not blank so -z checks work properly
	[ -z "${P_PORTS_FEATURES}" ] && P_PORTS_FEATURES="none"
	# Add in pseduo 'DEPENDS_ARGS' feature if there's no FLAVORS support.
	have_ports_feature FLAVORS || \
	    P_PORTS_FEATURES="${P_PORTS_FEATURES:+${P_PORTS_FEATURES} }DEPENDS_ARGS"
	# Trim none if leftover from forcing in DEPENDS_ARGS
	P_PORTS_FEATURES="${P_PORTS_FEATURES#none }"
	# Determine if the ports tree supports SELECTED_OPTIONS from r403743
	if [ -f "${MASTERMNT}${PORTSDIR}/Mk/bsd.options.mk" ] && \
	    grep -m1 -q SELECTED_OPTIONS \
	    "${MASTERMNT}${PORTSDIR}/Mk/bsd.options.mk"; then
		P_PORTS_FEATURES="${P_PORTS_FEATURES:+${P_PORTS_FEATURES} }SELECTED_OPTIONS"
	fi
	[ "${P_PORTS_FEATURES}" != "none" ] && \
	    msg "Ports supports: ${P_PORTS_FEATURES}"
	export P_PORTS_FEATURES P_PYTHON_MAJOR_VER P_PYTHON_DEFAULT_VERSION \
	    P_PYTHON3_DEFAULT
}

clean_build_queue() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "clean_build_queue requires PWD=${MASTERMNT}/.p"
	local tmp pn port originspec

	bset status "cleaning:"
	msg "Cleaning the build queue"

	# Delete from the queue all that already have a current package.
	pkgqueue_list | while read pn; do
		[ -f "../packages/All/${pn}.${PKG_EXT}" ] && echo "${pn}"
	done | pkgqueue_remove_many_pipe

	# Delete from the queue orphaned build deps. This can happen if
	# the specified-to-build ports have all their deps satisifed
	# but one of their run deps has missing build deps packages which
	# causes the build deps to be in the queue at this point.

	if [ ${TRIM_ORPHANED_BUILD_DEPS} = "yes" -a ${ALL} -eq 0 ]; then
		tmp=$(mktemp -t queue)
		{
			listed_pkgnames
			# Pkg is a special case. It may not have been requested,
			# but it should always be rebuilt if missing.  The
			# originspec-pkgname lookup may fail if it wasn't
			# in the build queue.
			for port in ports-mgmt/pkg ports-mgmt/pkg-devel; do
				originspec_encode originspec "${port}" '' ''
				shash_get originspec-pkgname "${port}" \
				    pkgname && \
				    echo "${pkgname}"
			done
		} | pkgqueue_list_deps_pipe > "${tmp}"
		pkgqueue_list | sort > "${tmp}.actual"
		comm -13 ${tmp} ${tmp}.actual | pkgqueue_remove_many_pipe
		rm -f ${tmp} ${tmp}.actual
	fi
}

# PWD will be MASTERMNT/.p after this
prepare_ports() {
	local pkg
	local log log_top
	local n nbq resuming_build
	local cache_dir sflag delete_pkg_list

	_log_path log
	pkgqueue_init
	mkdir -p \
		"${MASTERMNT}/.p/var/run" \
		"${MASTERMNT}/.p/var/cache"

	cd "${MASTERMNT}/.p"
	SHASH_VAR_PATH="var/cache"
	# No prefix needed since we're unique in MASTERMNT.
	SHASH_VAR_PREFIX=
	# Allow caching values now
	USE_CACHE_CALL=1

	if [ -e "${log}/.poudriere.ports.built" ]; then
		resuming_build=1
	else
		resuming_build=0
	fi

	if was_a_testport_run; then
		local dep_originspec dep_origin dep_flavor dep_ret

		[ -z "${ORIGINSPEC}" ] && \
		    err 1 "testport+prepare_ports requires ORIGINSPEC set"
		if have_ports_feature FLAVORS; then
			# deps_fetch_vars really wants to have the main port
			# cached before being given a FLAVOR.
			originspec_decode "${ORIGINSPEC}" dep_origin \
			    '' dep_flavor
			if [ -n "${dep_flavor}" ]; then
				deps_fetch_vars "${dep_origin}" LISTPORTS \
				    PKGNAME DEPENDS_ARGS FLAVOR FLAVORS
			fi
		fi
		dep_ret=0
		deps_fetch_vars "${ORIGINSPEC}" LISTPORTS PKGNAME \
		    DEPENDS_ARGS FLAVOR FLAVORS || dep_ret=$?
		case ${dep_ret} in
		0) ;;
		# Non-fatal duplicate should be ignored
		2) ;;
		# Fatal error
		*)
			err ${dep_ret} "deps_fetch_vars failed for ${ORIGINSPEC}"
			;;
		esac
		if have_ports_feature FLAVORS; then
			if [ -n "${FLAVORS}" ] && \
			    [ "${FLAVOR_DEFAULT_ALL}" = "yes" ]; then
				msg_warn "Only testing first flavor '${FLAVOR}', use 'bulk -t' to test all flavors: ${FLAVORS}"
			fi
			if [ -n "${dep_flavor}" ]; then
				# Is it even a valid FLAVOR though?
				case " ${FLAVORS} " in
				*\ ${dep_flavor}\ *) ;;
				*)
					err 1 "Invalid FLAVOR '${dep_flavor}' for ${COLOR_PORT}${ORIGIN}${COLOR_RESET}"
					;;
				esac
			fi
		fi
		deps_sanity "${ORIGINSPEC}" "${LISTPORTS}" || \
		    err 1 "Error processing dependencies"
	fi

	if was_a_bulk_run; then
		_log_path_top log_top
		get_cache_dir cache_dir

		if [ ${resuming_build} -eq 0 ] || ! [ -d "${log}" ]; then
			# Sync in HTML files through a base dir
			install_html_files "${HTMLPREFIX}" "${log_top}/.html" \
			    "${log}"
			# Create log dirs
			mkdir -p ${log}/../../latest-per-pkg \
			    ${log}/../latest-per-pkg \
			    ${log}/logs \
			    ${log}/logs/errors \
			    ${cache_dir}
			# Link this build as the /latest
			ln -sfh ${BUILDNAME} ${log%/*}/latest

			# Record the SVN URL@REV in the build
			[ -d ${MASTERMNT}${PORTSDIR}/.svn ] && bset svn_url $(
				${SVN_CMD} info ${MASTERMNT}${PORTSDIR} | awk '
					/^URL: / {URL=substr($0, 6)}
					/Revision: / {REVISION=substr($0, 11)}
					END { print URL "@" REVISION }
				')

			bset mastername "${MASTERNAME}"
			bset jailname "${JAILNAME}"
			bset setname "${SETNAME}"
			bset ptname "${PTNAME}"
			bset buildname "${BUILDNAME}"
			bset started "${EPOCH_START}"
		fi

		show_log_info
		# Must acquire "update_stats" on shutdown to ensure
		# the process is not killed while holding it.
		if [ ${HTML_JSON_UPDATE_INTERVAL} -ne 0 ]; then
			coprocess_start html_json
		else
			msg "HTML UI updates are disabled by HTML_JSON_UPDATE_INTERVAL being 0"
		fi
	fi

	load_moved

	fetch_global_port_vars || \
	    err 1 "Failed to lookup global ports metadata"

	gather_port_vars

	compute_deps

	bset status "sanity:"

	if [ -f ${PACKAGES}/.jailversion ]; then
		if [ "$(cat ${PACKAGES}/.jailversion)" != \
		    "$(jget ${JAILNAME} version)" ]; then
			JAIL_NEEDS_CLEAN=1
		fi
	fi

	if was_a_bulk_run; then
		# Stash dependency graph
		cp -f "${MASTERMNT}/.p/pkg_deps" "${log}/.poudriere.pkg_deps%"
		cp -f "${MASTERMNT}/.p/all_pkgs" "${log}/.poudriere.all_pkgs%"

		if [ ${JAIL_NEEDS_CLEAN} -eq 1 ]; then
			msg_n "Cleaning all packages due to newer version of the jail..."
		elif [ ${CLEAN} -eq 1 ]; then
			msg_n "(-c) Cleaning all packages..."
		fi

		if [ ${JAIL_NEEDS_CLEAN} -eq 1 ] || [ ${CLEAN} -eq 1 ]; then
			rm -rf ${PACKAGES}/* ${cache_dir}
			echo " done"
		fi

		if [ ${CLEAN_LISTED} -eq 1 ]; then
			msg "(-C) Cleaning specified packages to build"
			delete_pkg_list=$(mktemp -t poudriere.cleanC)
			clear_dep_fatal_error
			listed_pkgnames | while read pkgname; do
				pkg="${PACKAGES}/All/${pkgname}.${PKG_EXT}"
				if [ -f "${pkg}" ]; then
					msg "(-C) Deleting existing package: ${pkg##*/}"
					delete_pkg_xargs "${delete_pkg_list}" \
					    "${pkg}"
				fi
			done
			check_dep_fatal_error && \
			    err 1 "Error processing -C packages"
			msg "(-C) Flushing package deletions"
			cat "${delete_pkg_list}" | tr '\n' '\000' | \
			    xargs -0 rm -rf
			unlink "${delete_pkg_list}" || :
		fi

		# If the build is being resumed then packages already
		# built/failed/skipped/ignored should not be rebuilt.
		if [ ${resuming_build} -eq 1 ]; then
			awk '{print $2}' \
			    ${log}/.poudriere.ports.built \
			    ${log}/.poudriere.ports.failed \
			    ${log}/.poudriere.ports.ignored \
			    ${log}/.poudriere.ports.skipped | \
			    pkgqueue_remove_many_pipe
		else
			# New build
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
		SKIPSANITY=2
	fi

	if [ $SKIPSANITY -eq 0 ]; then
		msg "Sanity checking the repository"

		for n in repo.txz digests.txz packagesite.txz; do
			pkg="${PACKAGES}/All/${n}"
			if [ -f "${pkg}" ]; then
				msg "Removing invalid pkg repo file: ${pkg}"
				unlink "${pkg}"
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
		[ ${SKIPSANITY} -eq 1 ] && sflag="(-s) "
		msg "${sflag}Skipping incremental rebuild and repository sanity checks"
	fi

	export LOCALBASE=${LOCALBASE:-/usr/local}

	clean_build_queue

	# Call the deadlock code as non-fatal which will check for cycles
	msg "Sanity checking build queue"
	bset status "pkgqueue_sanity_check:"
	pkgqueue_sanity_check 0

	if was_a_bulk_run; then
		if [ $resuming_build -eq 0 ]; then
			nbq=0
			nbq=$(pkgqueue_list | wc -l)
			# Add 1 for the main port to test
			was_a_testport_run && \
			    nbq=$((${nbq} + 1))
			bset stats_queued ${nbq##* }

			# Generate ports.queued list after the queue was
			# trimmed.
			local _originspec _pkgname _rdep tmp
			tmp=$(TMPDIR="${log}" mktemp -ut .queued)
			while read _pkgname _originspec _rdep; do
				pkgqueue_contains "${_pkgname}" && \
				    echo "${_originspec} ${_pkgname} ${_rdep}"
			done < "all_pkgs" | sort > "${tmp}"
			mv -f "${tmp}" "${log}/.poudriere.ports.queued"
		fi

		pkgqueue_move_ready_to_pool
		load_priorities
		msg "Balancing pool"
		balance_pool

		[ -n "${ALLOW_MAKE_JOBS}" ] || \
		    echo "DISABLE_MAKE_JOBS=poudriere" \
		    >> ${MASTERMNT}/etc/make.conf
		# Don't leak ports-env UID as it conflicts with BUILD_AS_NON_ROOT
		if [ "${BUILD_AS_NON_ROOT}" = "yes" ]; then
			sed -i '' '/^UID=0$/d' "${MASTERMNT}/etc/make.conf"
			sed -i '' '/^GID=0$/d' "${MASTERMNT}/etc/make.conf"
			# Will handle manually for now on until build_port.
			export UID=0
			export GID=0
		fi

		jget ${JAILNAME} version > ${PACKAGES}/.jailversion
		echo "${BUILDNAME}" > "${PACKAGES}/.buildname"

	fi
	unset P_PYTHON_MAJOR_VER P_PYTHON_DEFAULT_VERSION P_PYTHON3_DEFAULT

	return 0
}

load_priorities_tsortD() {
	local priority pkgname pkg_boost boosted origin
	local - # Keep set -f local

	tsort -D "pkg_deps" > "pkg_deps.depth"

	# Create buckets to satisfy the dependency chains, in reverse
	# order. Not counting here as there may be boosted priorities
	# at 99 or other high values.

	POOL_BUCKET_DIRS=$(awk '{print $1}' "pkg_deps.depth"|sort -run)

	set -f # for PRIORITY_BOOST
	boosted=0
	while read priority pkgname; do
		# Does this pkg have an override?
		for pkg_boost in ${PRIORITY_BOOST}; do
			case ${pkgname%-*} in
				${pkg_boost})
					pkgqueue_contains "${pkgname}" || \
					    continue
					get_origin_from_pkgname origin \
					    "${pkgname}"
					msg "Boosting priority: ${COLOR_PORT}${origin} | ${pkgname}"
					priority=${PRIORITY_BOOST_VALUE}
					boosted=1
					break
					;;
			esac
		done
		hash_set "priority" "${pkgname}" ${priority}
	done < "pkg_deps.depth"

	# Add ${PRIORITY_BOOST_VALUE} into the pool if needed.
	[ ${boosted} -eq 1 ] && POOL_BUCKET_DIRS="${PRIORITY_BOOST_VALUE} ${POOL_BUCKET_DIRS}"

	return 0
}

load_priorities_ptsort() {
	local priority pkgname originspec pkg_boost origin _ignored
	local - # Keep set -f local

	set -f # for PRIORITY_BOOST

	awk '{print $2 " " $1}' "pkg_deps" > "pkg_deps.ptsort"

	# Add in boosts before running ptsort
	while read pkgname originspec _ignored; do
		# Does this pkg have an override?
		for pkg_boost in ${PRIORITY_BOOST}; do
			case ${pkgname%-*} in
				${pkg_boost})
					pkgqueue_contains "${pkgname}" || \
					    continue
					originspec_decode "${originspec}" \
					    origin '' ''
					msg "Boosting priority: ${COLOR_PORT}${origin} | ${pkgname}"
					echo "${pkgname} ${PRIORITY_BOOST_VALUE}" >> \
					    "pkg_deps.ptsort"
					break
					;;
			esac
		done
	done < "all_pkgs"

	ptsort -p "pkg_deps.ptsort" > \
	    "pkg_deps.priority"

	# Create buckets to satisfy the dependency chain priorities.
	POOL_BUCKET_DIRS=$(awk '{print $1}' \
	    "pkg_deps.priority"|sort -run)

	# Read all priorities into the "priority" hash
	while read priority pkgname; do
		hash_set "priority" "${pkgname}" ${priority}
	done < "pkg_deps.priority"

	return 0
}

load_priorities() {
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "load_priorities requires PWD=${MASTERMNT}/.p"

	msg "Processing PRIORITY_BOOST"
	bset status "load_priorities:"

	POOL_BUCKET_DIRS=""

	if [ ${POOL_BUCKETS} -gt 0 ]; then
		if [ "${USE_PTSORT}" = "yes" ]; then
			load_priorities_ptsort
		else
			load_priorities_tsortD
		fi
	fi

	# If there are no buckets then everything to build will fall
	# into 0 as they depend on nothing and nothing depends on them.
	# I.e., pkg-devel in -ac or testport on something with no deps
	# needed.
	[ -z "${POOL_BUCKET_DIRS}" ] && POOL_BUCKET_DIRS="0"

	# Create buckets after loading priorities in case of boosts.
	( cd pool && mkdir ${POOL_BUCKET_DIRS} )

	# unbalanced is where everything starts at.  Items are moved in
	# balance_pool based on their priority in the "priority" hash.
	POOL_BUCKET_DIRS="${POOL_BUCKET_DIRS} unbalanced"

	return 0
}

balance_pool() {
	# Don't bother if disabled
	[ ${POOL_BUCKETS} -gt 0 ] || return 0
	[ "${PWD}" = "${MASTERMNT}/.p" ] || \
	    err 1 "balance_pool requires PWD=${MASTERMNT}/.p"

	local pkgname pkg_dir dep_count lock

	# Avoid running this in parallel, no need. Note that this lock is
	# not on the unbalanced/ dir, but only this function. pkgqueue_done()
	# writes to unbalanced/, pkgqueue_empty() reads from it, and
	# pkgqueue_get_next() moves from it.
	lock=.lock-balance_pool
	mkdir ${lock} 2>/dev/null || return 0

	if dirempty pool/unbalanced; then
		rmdir ${lock}
		return 0
	fi

	if [ -n "${MY_JOBID}" ]; then
		bset ${MY_JOBID} status "balancing_pool:"
	else
		bset status "balancing_pool:"
	fi

	# For everything ready-to-build...
	for pkg_dir in pool/unbalanced/*; do
		# May be empty due to racing with pkgqueue_get_next()
		case "${pkg_dir}" in
			"pool/unbalanced/*") break ;;
		esac
		pkgname=${pkg_dir##*/}
		hash_get "priority" "${pkgname}" dep_count || dep_count=0
		# This races with pkgqueue_get_next(), just ignore failure
		# to move it.
		rename "${pkg_dir}" \
		    "pool/${dep_count}/${pkgname}" \
		    2>/dev/null || :
	done
	# New files may have been added in unbalanced/ via pkgqueue_done() due
	# to not being locked. These will be picked up in the next run.

	rmdir ${lock}
}

append_make() {
	[ $# -ne 3 ] && eargs append_make srcdir src_makeconf dst_makeconf
	local srcdir="$1"
	local src_makeconf=$2
	local dst_makeconf=$3

	if [ "${src_makeconf}" = "-" ]; then
		src_makeconf="${srcdir}/make.conf"
	else
		src_makeconf="${srcdir}/${src_makeconf}-make.conf"
	fi

	[ -f "${src_makeconf}" ] || return 0
	src_makeconf="$(realpath ${src_makeconf} 2>/dev/null)"
	# Only append if not already done (-z -p or -j match)
	grep -q "# ${src_makeconf} #" ${dst_makeconf} && return 0
	msg "Appending to make.conf: ${src_makeconf}"
	echo "#### ${src_makeconf} ####" >> ${dst_makeconf}
	cat "${src_makeconf}" >> ${dst_makeconf}
}

read_packages_from_params()
{
	if [ $# -eq 0 -o -z "$1" ]; then
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
	umount ${UMOUNT_NONBUSY} ${MASTERMNT}/packages || \
	    umount -f ${MASTERMNT}/packages
	mount_packages
	injail /usr/bin/make -s -C ${PORTSDIR} -j ${PARALLEL_JOBS} \
	    RM="/bin/rm -fv" ECHO_MSG="true" clean-restricted
	# Remount ro
	umount ${UMOUNT_NONBUSY} ${MASTERMNT}/packages || \
	    umount -f ${MASTERMNT}/packages
	mount_packages -o ro
}

sign_pkg() {
	[ $# -eq 2 ] || eargs sign_pkg sigtype pkgfile
	local sigtype="$1"
	local pkgfile="$2"

	if [ "${sigtype}" = "fingerprint" ]; then
		unlink "${pkgfile}.sig"
		sha256 -q "${pkgfile}" | ${SIGNING_COMMAND} > "${pkgfile}.sig"
	elif [ "${sigtype}" = "pubkey" ]; then
		unlink "${pkgfile}.pubkeysig"
		echo -n $(sha256 -q "${pkgfile}") | \
		    openssl dgst -sha256 -sign "${PKG_REPO_SIGNING_KEY}" \
		    -binary -out "${pkgfile}.pubkeysig"
	fi
}

build_repo() {
	local origin

	msg "Creating pkg repository"
	bset status "pkgrepo:"
	ensure_pkg_installed force_extract || \
	    err 1 "Unable to extract pkg."
	run_hook pkgrepo sign "${PACKAGES}" "${PKG_REPO_SIGNING_KEY}" \
	    "${PKG_REPO_FROM_HOST:-no}" "${PKG_REPO_META_FILE}"
	if [ -r "${PKG_REPO_META_FILE:-/nonexistent}" ]; then
		PKG_META="-m /tmp/pkgmeta"
		PKG_META_MASTERMNT="-m ${MASTERMNT}/tmp/pkgmeta"
		install -m 0400 "${PKG_REPO_META_FILE}" \
		    ${MASTERMNT}/tmp/pkgmeta
	fi
	mkdir -p ${MASTERMNT}/tmp/packages
	if [ -n "${PKG_REPO_SIGNING_KEY}" ]; then
		install -m 0400 ${PKG_REPO_SIGNING_KEY} \
			${MASTERMNT}/tmp/repo.key
		injail ${PKG_BIN} repo -o /tmp/packages \
			${PKG_META} \
			/packages /tmp/repo.key
		unlink ${MASTERMNT}/tmp/repo.key
	elif [ "${PKG_REPO_FROM_HOST:-no}" = "yes" ]; then
		# Sometimes building repo from host is needed if
		# using SSH with DNSSEC as older hosts don't support
		# it.
		${MASTERMNT}${PKG_BIN} repo \
		    -o ${MASTERMNT}/tmp/packages ${PKG_META_MASTERMNT} \
		    ${MASTERMNT}/packages \
		    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
	else
		JNETNAME="n" injail ${PKG_BIN} repo \
		    -o /tmp/packages ${PKG_META} /packages \
		    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
	fi
	cp ${MASTERMNT}/tmp/packages/* ${PACKAGES}/

	# Sign the ports-mgmt/pkg package for bootstrap
	if [ -e "${PACKAGES}/Latest/pkg.txz" ]; then
		if [ -n "${SIGNING_COMMAND}" ]; then
			sign_pkg fingerprint "${PACKAGES}/Latest/pkg.txz"
		elif [ -n "${PKG_REPO_SIGNING_KEY}" ]; then
			sign_pkg pubkey "${PACKAGES}/Latest/pkg.txz"
		fi
	fi
}

calculate_size_in_mb() {
	case ${CALC_SIZE} in
	*p)
		CALC_SIZE=${CALC_SIZE%p}
		CALC_SIZE=$(( ${CALC_SIZE} << 10 ))
		;&
	*t)
		CALC_SIZE=${CALC_SIZE%t}
		CALC_SIZE=$(( ${CALC_SIZE} << 10 ))
		;&
	*g)
		CALC_SIZE=${CALC_SIZE%g}
		CALC_SIZE=$(( ${CALC_SIZE} << 10 ))
		;&
	*m)
		CALC_SIZE=${CALC_SIZE%m}
	esac
}

calculate_ospart_size() {
	local CALC_SIZE
	local FULL_CALC_SIZE
	local DATA_CALC_SIZE
	local CFG_CALC_SIZE

	# Figure out the size of the image in MB
	CALC_SIZE=${IMAGESIZE}
	calculate_size_in_mb
	FULL_CALC_SIZE=${CALC_SIZE}

	# Figure out the size of the /cfg partition
	CALC_SIZE=${CFG_SIZE}
	calculate_size_in_mb
	CFG_CALC_SIZE=${CALC_SIZE}

	# Figure out the size of the Data partition
	if [ $# -eq 3 -o -n ${DATA_SIZE} ]; then
		CALC_SIZE=${DATA_SIZE}
		calculate_size_in_mb
		DATA_CALC_SIZE=${CALC_SIZE}
	else
		DATA_CALC_SIZE=0
	fi

	OS_SIZE=$(( ( ${FULL_CALC_SIZE} - ${CFG_CALC_SIZE} - ${DATA_CALC_SIZE} ) / 2 ))
	msg "OS Partiton size: ${OS_SIZE}m"
}

# Builtin-only functions
_BUILTIN_ONLY=""
for _var in ${_BUILTIN_ONLY}; do
	if ! [ "$(type ${_var} 2>/dev/null)" = \
		"${_var} is a shell builtin" ]; then
		eval "${_var}() { return 0; }"
	fi
done
if [ "$(type setproctitle 2>/dev/null)" = "setproctitle is a shell builtin" ]; then
	setproctitle() {
		PROC_TITLE="$@"
		command setproctitle "poudriere${MASTERNAME:+[${MASTERNAME}]}${MY_JOBID:+[${MY_JOBID}]}: $@"
	}
else
	setproctitle() { }
fi

STATUS=0 # out of jail #
# cd into / to avoid foot-shooting if running from deleted dirs or
# NFS dir which root has no access to.
SAVED_PWD="${PWD}"
cd /tmp

. ${SCRIPTPREFIX}/include/colors.pre.sh
[ -z "${POUDRIERE_ETC}" ] &&
    POUDRIERE_ETC=$(realpath ${SCRIPTPREFIX}/../../etc)
# If this is a relative path, add in ${PWD} as a cd / is done.
[ "${POUDRIERE_ETC#/}" = "${POUDRIERE_ETC}" ] && \
    POUDRIERE_ETC="${SAVED_PWD}/${POUDRIERE_ETC}"
POUDRIERED=${POUDRIERE_ETC}/poudriere.d
include_poudriere_confs "$@"

AWKPREFIX=${SCRIPTPREFIX}/awk
HTMLPREFIX=${SCRIPTPREFIX}/html
HOOKDIR=${POUDRIERED}/hooks

# If the zfs module is not loaded it means we can't have zfs
[ -z "${NO_ZFS}" ] && lsvfs zfs >/dev/null 2>&1 || NO_ZFS=yes
# Short circuit to prevent running zpool(1) and loading zfs.ko
[ -z "${NO_ZFS}" ] && [ -z "$(zpool list -H -o name 2>/dev/null)" ] && NO_ZFS=yes

[ -z "${NO_ZFS}" -a -z ${ZPOOL} ] && err 1 "ZPOOL variable is not set"
[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"

trap sigpipe_handler SIGPIPE
trap sigint_handler SIGINT
trap sigterm_handler SIGTERM
trap exit_handler EXIT
enable_siginfo_handler() {
	was_a_bulk_run && trap siginfo_handler SIGINFO
	in_siginfo_handler=0
	return 0
}
enable_siginfo_handler

# Test if zpool exists
if [ -z "${NO_ZFS}" ]; then
	zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
fi

: ${SVN_HOST="svn.freebsd.org"}
: ${GIT_BASEURL="github.com/freebsd/freebsd.git"}
: ${GIT_PORTSURL="github.com/freebsd/freebsd-ports.git"}
: ${FREEBSD_HOST="https://download.FreeBSD.org"}
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

: ${USE_TMPFS:=no}
[ -n "${MFSSIZE}" -a "${USE_TMPFS}" != "no" ] && err 1 "You can't use both tmpfs and mdmfs"

for val in ${USE_TMPFS}; do
	case ${val} in
	wrkdir) TMPFS_WRKDIR=1 ;;
	data) TMPFS_DATA=1 ;;
	all) TMPFS_ALL=1 ;;
	localbase) TMPFS_LOCALBASE=1 ;;
	yes)
		TMPFS_WRKDIR=1
		TMPFS_DATA=1
		;;
	no) ;;
	*) err 1 "Unknown value for USE_TMPFS can be a combination of wrkdir,data,all,yes,no,localbase" ;;
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
		unlink ${POUDRIERED}/portstrees
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
# If in a nested jail we may not even have a loopback to use.
if [ ${JAILED} -eq 1 ]; then
	# !! Note these exit statuses are inverted
	ifconfig | \
	    awk -vip="${LOIP6}" '$1 == "inet6" && $2 == ip {exit 1}' && \
	    LOIP6=
	ifconfig | \
	    awk -vip="${LOIP4}" '$1 == "inet" && $2 == ip {exit 1}' && \
	    LOIP4=
fi
case $IPS in
01)
	localipargs="${LOIP6:+ip6.addr=${LOIP6}}"
	ipargs="ip6=inherit"
	;;
10)
	localipargs="${LOIP4:+ip4.addr=${LOIP4}}"
	ipargs="ip4=inherit"
	;;
11)
	localipargs="${LOIP4:+ip4.addr=${LOIP4} }${LOIP6:+ip6.addr=${LOIP6}}"
	ipargs="ip4=inherit ip6=inherit"
	;;
esac

NCPU=$(sysctl -n hw.ncpu)

# Check if parallel umount will contend on the vnode free list lock
if sysctl -n vfs.mnt_free_list_batch >/dev/null 2>&1; then
	# Nah, parallel umount should be fine.
	UMOUNT_BATCHING=1
else
	UMOUNT_BATCHING=0
fi
# Determine if umount -n can be used.
if grep -q "#define[[:space:]]MNT_NONBUSY" /usr/include/sys/mount.h \
    2>/dev/null; then
	UMOUNT_NONBUSY="-n"
fi

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
: ${SHARED_LOCK_DIR:=/var/run/poudriere}
: ${PORTBUILD_UID:=65532}
: ${PORTBUILD_GID:=${PORTBUILD_UID}}
: ${PORTBUILD_USER:=nobody}
: ${CCACHE_DIR_NON_ROOT_SAFE:=no}
if [ -n "${CCACHE_DIR}" ] && [ "${CCACHE_DIR_NON_ROOT_SAFE}" = "no" ]; then
	if [ "${BUILD_AS_NON_ROOT}" = "yes" ]; then
		msg_warn "BUILD_AS_NON_ROOT and CCACHE_DIR are potentially incompatible.  Disabling BUILD_AS_NON_ROOT"
		msg_warn "Either disable one or set CCACHE_DIR_NON_ROOT_SAFE=yes and chown -R CCACHE_DIR to the user ${PORTBUILD_USER} (uid: ${PORTBUILD_UID})"
	fi
	# Default off with CCACHE_DIR.
	: ${BUILD_AS_NON_ROOT:=no}
fi
: ${CCACHE_JAIL_PREFIX:=/ccache}
# Default on otherwise.
: ${BUILD_AS_NON_ROOT:=yes}
: ${DISTFILES_CACHE:=/nonexistent}
: ${SVN_CMD:=$(which svn 2>/dev/null || which svnlite 2>/dev/null)}
: ${GIT_CMD:=git}
: ${BINMISC:=/usr/sbin/binmiscctl}
: ${PATCHED_FS_KERNEL:=no}
: ${ALL:=0}
: ${CLEAN:=0}
: ${CLEAN_LISTED:=0}
: ${SKIPSANITY:=0}
: ${JAIL_NEEDS_CLEAN:=0}
: ${VERBOSE:=0}
: ${QEMU_EMULATING:=0}
: ${PORTTESTING_FATAL:=yes}
: ${PORTTESTING_RECURSIVE:=0}
: ${PRIORITY_BOOST_VALUE:=99}
: ${RESTRICT_NETWORKING:=yes}
: ${TRIM_ORPHANED_BUILD_DEPS:=yes}
: ${USE_JEXECD:=no}
: ${USE_PROCFS:=yes}
: ${USE_FDESCFS:=yes}
: ${USE_PTSORT:=yes}
: ${MUTABLE_BASE:=yes}
: ${HTML_JSON_UPDATE_INTERVAL:=2}
: ${HTML_TRACK_REMAINING:=no}
: ${FORCE_MOUNT_HASH:=no}
DRY_RUN=0

# Be sure to update poudriere.conf to document the default when changing these
: ${RESOLV_CONF="/etc/resolv.conf"}
: ${MAX_EXECUTION_TIME:=86400}         # 24 hours for 1 command (phase)
# Some phases have different timeouts.
: ${MAX_EXECUTION_TIME_EXTRACT:=3600}
: ${MAX_EXECUTION_TIME_INSTALL:=3600}
: ${MAX_EXECUTION_TIME_PACKAGE:=7200}
: ${MAX_EXECUTION_TIME_DEINSTALL:=3600}
: ${NOHANG_TIME:=7200}                 # 120 minutes with no log update
: ${QEMU_MAX_EXECUTION_TIME:=345600}   # 4 days for 1 command (phase)
: ${QEMU_NOHANG_TIME:=21600}           # 6 hours with no log update
: ${TIMESTAMP_LOGS:=no}
: ${ATOMIC_PACKAGE_REPOSITORY:=yes}
: ${KEEP_OLD_PACKAGES:=no}
: ${KEEP_OLD_PACKAGES_COUNT:=5}
: ${COMMIT_PACKAGES_ON_FAILURE:=yes}
: ${SAVE_WRKDIR:=no}
: ${CHECK_CHANGED_DEPS:=yes}
: ${BAD_PKGNAME_DEPS_ARE_FATAL:=no}
: ${CHECK_CHANGED_OPTIONS:=verbose}
: ${NO_RESTRICTED:=no}
: ${USE_COLORS:=yes}
: ${ALLOW_MAKE_JOBS_PACKAGES=pkg ccache}
: ${FLAVOR_DEFAULT_ALL:=no}

: ${POUDRIERE_TMPDIR:=$(command mktemp -dt poudriere)}
: ${SHASH_VAR_PATH_DEFAULT:=${POUDRIERE_TMPDIR}}
: ${SHASH_VAR_PATH:=${SHASH_VAR_PATH_DEFAULT}}
: ${SHASH_VAR_PREFIX:=sh-}

: ${USE_CACHED:=no}

: ${BUILDNAME_FORMAT:="%Y-%m-%d_%Hh%Mm%Ss"}
: ${BUILDNAME:=$(date +${BUILDNAME_FORMAT})}

: ${HTML_TYPE:=inline}

if [ -n "${MAX_MEMORY}" ]; then
	MAX_MEMORY_BYTES="$((${MAX_MEMORY} * 1024 * 1024 * 1024))"
fi
: ${MAX_FILES:=1024}
: ${DEFAULT_MAX_FILES:=${MAX_FILES}}
: ${DEP_FATAL_ERROR_FILE:=dep_fatal_error}
HAVE_FDESCFS=0
if [ "$(mount -t fdescfs | awk '$3 == "/dev/fd" {print $3}')" = "/dev/fd" ]; then
	HAVE_FDESCFS=1
fi

TIME_START=$(clock -monotonic)
EPOCH_START=$(clock -epoch)

. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/colors.sh
. ${SCRIPTPREFIX}/include/display.sh
. ${SCRIPTPREFIX}/include/html.sh
. ${SCRIPTPREFIX}/include/parallel.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/shared_hash.sh
. ${SCRIPTPREFIX}/include/cache.sh
. ${SCRIPTPREFIX}/include/fs.sh

if [ -z "${LOIP6}" -a -z "${LOIP4}" ]; then
	msg_warn "No loopback address defined, consider setting LOIP6/LOIP4 or assigning a loopback address to the jail."
fi

if [ -e /nonexistent ]; then
	err 1 "You may not have a /nonexistent.  Please remove it."
fi

if [ "${USE_CACHED}" = "yes" ]; then
	err 1 "USE_CACHED=yes is not supported."
fi
