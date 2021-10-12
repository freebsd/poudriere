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
EX_USAGE=64
EX_DATAERR=65
EX_SOFTWARE=70
SHFLAGS="$-"

# Return true if ran from bulk/testport, ie not daemon/status/jail
was_a_bulk_run() {
	[ "${SCRIPTNAME}" = "bulk.sh" ] || was_a_testport_run
}
was_a_testport_run() {
	[ "${SCRIPTNAME}" = "testport.sh" ]
}
# Return true if in a bulk or other jail run that needs to shutdown the jail
was_a_jail_run() {
	was_a_bulk_run ||  [ "${SCRIPTNAME}" = "pkgclean.sh" ] || \
	    [ "${SCRIPTNAME}" = "foreachport.sh" ]
}
schg_immutable_base() {
	[ "${IMMUTABLE_BASE}" = "schg" ] || return 1
	if [ ${TMPFS_ALL} -eq 0 ] && [ -z "${NO_ZFS}" ]; then
		return 1
	fi
	return 0
}
# Return true if output via msg() should show elapsed time
should_show_elapsed() {
	if [ -z "${TIME_START}" ]; then
		return 1
	fi
	if [ "${NO_ELAPSED_IN_MSG:-0}" -eq 1 ]; then
		return 1
	fi
	case "${SCRIPTNAME}" in
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
	if [ "${os}" = "${BSDPLATFORM}" ]; then
		err 1 "This is not supported on ${BSDPLATFORM}: $*"
	fi
}

_err() {
	if [ -n "${CRASHED:-}" ]; then
		echo "err: Recursive error detected: $2" >&2 || :
		exit "$1"
	fi
	case "${SHFLAGS}" in
	*x*) ;;
	*) local -; set +x ;;
	esac
	trap '' INFO
	export CRASHED=1
	if [ $# -ne 2 ]; then
		msg_error "err expects 2 arguments: exit_number \"message\": actual: '$'"
		exit ${EX_SOFTWARE}
	fi
	# Try to set status so other processes know this crashed
	# Don't set it from children failures though, only master
	if [ "${PARALLEL_CHILD:-0}" -eq 0 ] && was_a_bulk_run; then
		bset ${MY_JOBID-} status "${EXIT_STATUS:-crashed:}" || :
	fi
	if [ ${1} -eq 0 ]; then
		msg "$2" || :
	else
		msg_error "$2" || :
	fi
	if [ -n "${ERRORS_ARE_DEP_FATAL-}" ]; then
		set_dep_fatal_error
	fi
	# Avoid recursive err()->exit_handler()->err()... Just let
	# exit_handler() cleanup.
	if [ ${ERRORS_ARE_FATAL:-1} -eq 1 ]; then
		if was_a_bulk_run && [ -n "${POUDRIERE_BUILD_TYPE-}" ]; then
			show_build_summary >&2
			show_log_info >&2
		fi
		exit $1
	else
		return 0
	fi
}
if ! type err >/dev/null 2>&1; then
	alias err=_err
fi

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
		calculate_duration elapsed "$((now - ${TIME_START:-0}))"
		elapsed="[${elapsed}] "
		unset arrow
	else
		unset elapsed
		arrow="=>>"
	fi
	if [ -n "${COLOR_ARROW-}" ] || [ -z "${1##*\033[*}" ]; then
		printf "${COLOR_ARROW}${elapsed}${DRY_MODE-}${arrow:+${COLOR_ARROW}${arrow} }${COLOR_RESET}%b${COLOR_RESET}${NL}" "$*"
	else
		printf "${elapsed}${DRY_MODE-}${arrow:+${arrow} }%b${NL}" "$*"
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
	if [ -n "${MY_JOBID-}" ]; then
		# Send colored msg to bulk log...
		COLOR_ARROW="${COLOR_ERROR}" \
		    job_msg "${COLOR_ERROR}Error:${COLOR_RESET} $@"
		# And non-colored to buld log
		msg "Error: $@" >&2
	else
		# Send to true stderr
		COLOR_ARROW="${COLOR_ERROR}" \
		    msg "${COLOR_ERROR}Error:${COLOR_RESET} $@" \
		    >&${OUTPUT_REDIRECTED_STDERR:-2}
	fi
	return 0
}

msg_dev() {
	local -; set +x
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_DEV}" \
	    _msg_n "\n" "${COLOR_DEV}Dev:${COLOR_RESET} $@" >&2
}

msg_debug() {
	local -; set +x
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_DEBUG}" \
	    _msg_n "\n" "${COLOR_DEBUG}Debug:${COLOR_RESET} $@" >&2
}

msg_warn() {
	local -; set +x
	local MSG_NESTED MSG_NESTED_STDERR prefix

	: "${MSG_NESTED_STDERR:=0}"
	MSG_NESTED="${MSG_NESTED_STDERR}"
	if [ "${MSG_NESTED_STDERR}" -eq 0 ]; then
		prefix="Warning: "
	else
		unset prefix
	fi
	COLOR_ARROW="${COLOR_WARN}" \
	    _msg_n "\n" "${COLOR_WARN}${prefix}${COLOR_RESET}$@" >&2
}

job_msg() {
	local -; set +x
	local now elapsed NO_ELAPSED_IN_MSG output

	if [ -n "${MY_JOBID-}" ]; then
		NO_ELAPSED_IN_MSG=0
		now=$(clock -monotonic)
		calculate_duration elapsed "$((now - ${TIME_START_JOB:-${TIME_START:-0}}))"
		output="[${COLOR_JOBID}${MY_JOBID}${COLOR_RESET}] [${elapsed}] $@"
	else
		output="$@"
	fi
	_msg_n "\n" "${output}" >&${OUTPUT_REDIRECTED_STDOUT:-1}
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
		msg_dev() { :; }
		job_msg_dev() { :; }
	fi
	if ! [ ${VERBOSE} -gt 1 ]; then
		msg_debug() { :; }
		job_msg_debug() { :; }
	fi
	if ! [ ${VERBOSE} -gt 0 ]; then
		msg_verbose() { :; }
		job_msg_verbose() { :; }
	fi
}

_mastermnt() {
	local -; set -u
	local hashed_name mnt mnttest mnamelen testpath mastername

	mnamelen=$(grep "#define[[:space:]]MNAMELEN" \
	    /usr/include/sys/mount.h 2>/dev/null | awk '{print $3}')
	: ${mnamelen:=88}

	# Avoid : which causes issues with PATH for non-jailed commands
	# like portlint in testport.
	mastername="${MASTERNAME}"
	_gsub_badchars "${mastername}" ":" mastername
	mnt="${POUDRIERE_DATA}/.m/${mastername}/ref"
	if [ -z "${NOLINUX-}" ]; then
		testpath="/compat/linux/proc"
	else
		testpath="/var/db/ports"
	fi
	mnttest="${mnt}${testpath}"

	if [ "${FORCE_MOUNT_HASH}" = "yes" ] || \
	    [ ${#mnttest} -ge $((mnamelen - 1)) ]; then
		hashed_name=$(sha256 -qs "${MASTERNAME}" | \
		    awk '{print substr($0, 0, 6)}')
		mnt="${POUDRIERE_DATA}/.m/${hashed_name}/ref"
		mnttest="${mnt}${testpath}"
		if [ ${#mnttest} -ge $((mnamelen - 1)) ]; then
			err 1 "Mountpath '${mnt}' exceeds system MNAMELEN limit of ${mnamelen}. Unable to mount. Try shortening BASEFS."
		fi
		msg_warn "MASTERNAME '${MASTERNAME}' too long for mounting, using hashed version of '${hashed_name}'"
	fi

	# MASTERMNT=
	setvar "$1" "${mnt}"
	MASTERMNTREL="${mnt}"
	add_relpath_var MASTERMNTREL
	# MASTERMNTROOT=
	setvar "${1}ROOT" "${mnt%/ref}"
}

_my_path() {
	local -; set -u +x

	if [ -z "${MY_JOBID-}" ]; then
		setvar "$1" "${MASTERMNT}"
	elif [ -n "${MASTERMNTROOT}" ]; then
		setvar "$1" "${MASTERMNTROOT}/${MY_JOBID}"
	else
		setvar "$1" "${MASTERMNT}/../${MY_JOBID}"

	fi
}

_my_name() {
	local -; set -u +x

	setvar "$1" "${MASTERNAME}${MY_JOBID:+-job-${MY_JOBID}}"
}

_logfile() {
	local -; set -u +x
	[ $# -eq 2 ] || eargs _logfile var_return pkgname
	local var_return="$1"
	local pkgname="$2"
	local _log _log_top _latest_log _logfile

	_log_path _log
	_logfile="${_log}/logs/${pkgname}.log"
	if [ ! -r "${_logfile}" ]; then
		_log_path_top _log_top

		_latest_log="${_log_top}/latest-per-pkg/${pkgname%-*}/${pkgname##*-}"

		# These 4 operations can race with logclean which mitigates
		# the issue by looking for files older than 1 minute.

		# Make sure directory exists
		mkdir -p "${_log}/logs" "${_latest_log}"

		:> "${_logfile}"

		# Link to BUILD_TYPE/latest-per-pkg/PORTNAME/PKGVERSION/MASTERNAME.log
		ln -f "${_logfile}" "${_latest_log}/${MASTERNAME}.log"

		# Link to JAIL/latest-per-pkg/PKGNAME.log
		ln -f "${_logfile}" "${_log}/../latest-per-pkg/${pkgname}.log"
	fi

	setvar "${var_return}" "${_logfile}"
}

logfile() {
	local -; set -u +x
	[ $# -eq 1 ] || eargs logfile pkgname
	local pkgname="$1"

	_logfile logfile "${pkgname}"
	echo "${logfile}"
}
 
_log_path_top() {
	local -; set -u +x

	setvar "$1" "${POUDRIERE_DATA}/logs/${POUDRIERE_BUILD_TYPE}"
}

_log_path_jail() {
	local -; set -u +x
	local log_path_top

	_log_path_top log_path_top
	setvar "$1" "${log_path_top}/${MASTERNAME}"
}

_log_path() {
	local -; set -u +x
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
		if [ "${MASTERNAME}" = "latest-per-pkg" ]; then
			continue
		fi
		if [ ${SHOW_FINISHED} -eq 0 ] && \
		    ! jail_runs ${MASTERNAME}; then
			continue
		fi

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
				if _bget jailname jailname; then
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
				if _bget ptname ptname; then
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
				if _bget setname setname; then
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
			if [ "${buildname}" = "latest-done" ]; then
				_bget BUILDNAME buildname
			fi
			if [ "${buildname}" = "latest" ]; then
				_bget BUILDNAME buildname
			fi
			# May be blank if build is still starting up
			if [ -z "${BUILDNAME}" ]; then
				continue 2
			fi

			found_jobs=$((found_jobs + 1))

			# Lookup jailname/setname/ptname if needed. Delayed
			# from earlier for performance for -a
			if [ -z "${jailname+null}" ]; then
				_bget jailname jailname || :
			fi
			if [ -z "${setname+null}" ]; then
				_bget setname setname || :
			fi
			if [ -z "${ptname+null}" ]; then
				_bget ptname ptname || :
			fi
			log=${mastername}/${BUILDNAME}

			${action} || ret=$?
			# Skip the rest of this build if return = 100
			if [ "${ret}" -eq 100 ]; then
				continue 2
			fi
			# Halt if the function requests it
			if [ "${ret}" -eq 101 ]; then
				break 2
			fi
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
	local file_cnt count hsize ret

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
	count=$(cat ${filelist} | wc -l)
	count="${count##* }"
	msg "Removing these ${count} ${reason} will free: ${hsize}"

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
		    xargs -0 rm -rf
		echo " done"
		ret=1
	fi
	return ${ret}
}

injail() {
	local -; set +x
	if [ "${DISALLOW_NETWORKING}" = "yes" ]; then
	    local JNETNAME=
	fi

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

	if [ "${DISALLOW_NETWORKING}" = "yes" ]; then
	    local JNETNAME=
	fi

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
		path=${MASTERMNT}${MY_JOBID:+/../${MY_JOBID}} \
		host.hostname=${BUILDER_HOSTNAME-${name}} \
		${network} ${JAIL_PARAMS}
	if [ "${USE_JEXECD}" = "yes" ]; then
		jexecd -j ${name} -d ${MASTERMNT}/../ \
		    ${MAX_MEMORY_BYTES+-m ${MAX_MEMORY_BYTES}} \
		    ${MAX_FILES+-n ${MAX_FILES}}
	fi
	# Allow networking in -n jail
	jail -c persist name=${name}-n \
		path=${MASTERMNT}${MY_JOBID:+/../${MY_JOBID}} \
		host.hostname=${BUILDER_HOSTNAME-${name}} \
		${ipargs} ${JAIL_PARAMS} ${JAIL_NET_PARAMS}
	if [ "${USE_JEXECD}" = "yes" ]; then
		jexecd -j ${name}-n -d ${MASTERMNT}/../ \
		    ${MAX_MEMORY_BYTES+-m ${MAX_MEMORY_BYTES}} \
		    ${MAX_FILES+-n ${MAX_FILES}}
	fi
	return 0
}

jail_has_processes() {
	local pscnt

	# 2 = HEADER+ps itself
	pscnt=2
	if [ "${USE_JEXECD}" = "yes" ]; then
		pscnt=4
	fi
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
	if [ "${USE_JEXECD}" = "yes" ]; then
		return 0
	fi
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
	local -; set +x
	[ $# -ge 2 ] || eargs run_hook hook event args
	local hook="$1"
	local event="$2"
	local build_url log log_url plugin_dir

	shift 2

	build_url build_url || :
	log_url log_url || :
	if [ -n "${POUDRIERE_BUILD_TYPE-}" ]; then
		_log_path log || :
	fi

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
		    POUDRIERE_BUILD_TYPE=${POUDRIERE_BUILD_TYPE-} \
		    POUDRIERED="${POUDRIERED-}" \
		    POUDRIERE_DATA="${POUDRIERE_DATA-}" \
		    MASTERNAME="${MASTERNAME-}" \
		    MASTERMNT="${MASTERMNT-}" \
		    MY_JOBID="${MY_JOBID-}" \
		    BUILDNAME="${BUILDNAME-}" \
		    JAILNAME="${JAILNAME-}" \
		    PTNAME="${PTNAME-}" \
		    SETNAME="${SETNAME-}" \
		    PACKAGES="${PACKAGES-}" \
		    PACKAGES_ROOT="${PACKAGES_ROOT-}" \
		    /bin/sh "${hookfile}" "${event}" "$@"
	) || err 1 "Hook ${hookfile} for '${hook}:${event}' returned non-zero"
	return 0
}

log_start() {
	[ $# -eq 2 ] || eargs log_start pkgname need_tee
	local pkgname="$1"
	local need_tee="$2"
	local logfile

	_logfile logfile "${pkgname}"

	# Save stdout/stderr for restoration later for bulk/testport -i
	exec 3>&1 4>&2
	export OUTPUT_REDIRECTED=1
	export OUTPUT_REDIRECTED_STDOUT=3
	export OUTPUT_REDIRECTED_STDERR=4
	# Pipe output to tee(1) or timestamp if needed.
	if [ ${need_tee} -eq 1 ] || [ "${TIMESTAMP_LOGS}" = "yes" ]; then
		if [ ! -e ${logfile}.pipe ]; then
			mkfifo ${logfile}.pipe
		fi
		if [ ${need_tee} -eq 1 ]; then
			if [ "${TIMESTAMP_LOGS}" = "yes" ]; then
				# Unbuffered for 'echo -n' support.
				# Otherwise need setbuf -o L here due to
				# stdout not writing to terminal but to tee.
				TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
				    timestamp -u < ${logfile}.pipe | \
				    tee ${logfile} &
			else
				tee ${logfile} < ${logfile}.pipe &
			fi
		elif [ "${TIMESTAMP_LOGS}" = "yes" ]; then
			TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
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

_lookup_portdir() {
	[ $# -eq 2 ] || eargs _lookup_portdir var_return origin
	local _varname="$1"
	local _port="$2"
	local o _ptdir

	for o in ${OVERLAYS}; do
		_ptdir="${OVERLAYSDIR}/${o}/${_port}"
		if [ -r "${MASTERMNTREL}${_ptdir}/Makefile" ]; then
			setvar "${_varname}" "${_ptdir}"
			return
		fi
	done
	_ptdir="${PORTSDIR:?}/${_port}"
	setvar "${_varname}" "${_ptdir}"
	return
}

buildlog_start() {
	[ $# -eq 2 ] || eargs buildlog_start pkgname originspec
	local pkgname="$1"
	local originspec="$2"
	local mnt var portdir
	local make_vars date
	local git_modified git_hash
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
	_lookup_portdir portdir "${port}"

	for var in ${wanted_vars}; do
		local "mk_${var}"
		make_vars="${make_vars:+${make_vars} }${var} mk_${var}"
	done

	port_var_fetch_originspec "${originspec}" \
	    ${PORT_FLAGS} \
	    ${make_vars}

	echo "build started at $(date)"
	if [ "${PKG_REPRODUCIBLE}" != "yes" ]; then
		date=$(env TZ=UTC date "+%Y-%m-%dT%H:%M:%S%z")
		pkg_note_add "${pkgname}" build_timestamp "${date}"
	fi
	echo "port directory: ${portdir}"
	echo "package name: ${pkgname}"
	echo "building for: $(injail uname -a)"
	echo "maintained by: ${mk_MAINTAINER}"
	echo "Makefile datestamp: $(injail ls -l "${portdir}/Makefile")"

	if shash_get ports_metadata top_git_hash git_hash; then
		echo "Ports top last git commit: ${git_hash}"
		pkg_note_add "${pkgname}" ports_top_git_hash "${git_hash}"
		shash_get ports_metadata top_unclean git_modified
		pkg_note_add "${pkgname}" ports_top_checkout_unclean \
		    "${git_modified}"
		echo "Ports top unclean checkout: ${git_modified}"
	fi

	if [ -x "${GIT_CMD}" ] && \
	    ${GIT_CMD} -C "${mnt}/${portdir}" rev-parse \
	    --show-toplevel >/dev/null 2>&1; then
		git_hash=$(${GIT_CMD} -C "${mnt}/${portdir}" log -1 --format=%h .)
		echo "Port dir last git commit: ${git_hash}"
		pkg_note_add "${pkgname}" port_git_hash "${git_hash}"
		git_modified=no
		if git_tree_dirty "${mnt}/${portdir}" 1; then
			git_modified=yes
		fi
		pkg_note_add "${pkgname}" port_checkout_unclean "${git_modified}"
		echo "Port dir unclean checkout: ${git_modified}"
	fi
	echo "Poudriere version: ${POUDRIERE_PKGNAME}"
	if [ "${PKG_REPRODUCIBLE}" != "yes" ]; then
		pkg_note_add "${pkgname}" built_by "${POUDRIERE_PKGNAME}"
	fi
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
	if [ ${build_failed} -gt 0 ]; then
		echo "!!! build failure encountered !!!"
	fi
}

log_stop() {
	if [ ${OUTPUT_REDIRECTED:-0} -eq 1 ]; then
		exec 1>&3 3>&- 2>&4 4>&-
		OUTPUT_REDIRECTED=0
		unset OUTPUT_REDIRECTED_STDOUT
		unset OUTPUT_REDIRECTED_STDERR
	fi
	if [ -n "${tpid-}" ]; then
		# Give tee a moment to flush buffers
		timed_wait_and_kill 5 $tpid 2>/dev/null || :
		unset tpid
	fi
}

attr_set() {
	local type="$1"
	local name="$2"
	local property="$3"
	local dstfile
	shift 3

	dstfile="${POUDRIERED}/${type}/${name}/${property}"
	mkdir -p "${dstfile%/*}"
	{
		write_atomic_cmp "${dstfile}" || \
		    err $? "attr_set failed to write to ${dstfile}"
	} <<-EOF
	$@
	EOF
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
	    "${POUDRIERED}/${type}/${name}/${property}"
}

attr_get() {
	local attr_get_data

	if _attr_get attr_get_data "$@"; then
		if [ -n "${attr_get_data}" ]; then
			echo "${attr_get_data}"
		fi
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
	local -; set +x
	if [ -z "${POUDRIERE_BUILD_TYPE-}" ]; then
		return 1
	fi
	local var_return id property mnt log file READ_FILE_USE_CAT file

	var_return="$1"
	_log_path log
	shift
	if [ $# -eq 2 ]; then
		id="$1"
		shift
	fi
	file=".poudriere.${1}${id:+.${id}}"

	# Use cat(1) to read long list files.
	if [ -z "${1##ports.*}" ]; then
		READ_FILE_USE_CAT=1
	fi

	read_file "${var_return}" "${log}/${file}"
}

bget() {
	local -; set +x
	[ -n "${POUDRIERE_BUILD_TYPE-}" ] || return 0
	local bget_data

	if _bget bget_data "$@"; then
		if [ -n "${bget_data}" ]; then
			echo "${bget_data}"
		fi
		return 0
	fi
	return 1
}

bset() {
	local -; set +x
	was_a_bulk_run || return 0
	[ -n "${POUDRIERE_BUILD_TYPE-}" ] || return 0
	local id property mnt log file

	_log_path log
	# Early error
	[ -d "${log}" ] || return
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	property="$1"
	file=".poudriere.${property}${id:+.${id}}"
	shift
	if [ "${property}" = "status" ]; then
		echo "$@" >> ${log}/${file}.journal% || :
	fi
	write_atomic "${log:?}/${file}" <<-EOF
	$@
	EOF
}

bset_job_status() {
	[ $# -eq 3 ] || eargs bset_job_status status originspec pkgname
	local status="$1"
	local originspec="$2"
	local pkgname="$3"

	bset ${MY_JOBID} status "${status}:${originspec}:${pkgname}:${TIME_START_JOB:-${TIME_START}}:$(clock -monotonic)"
}

badd() {
	local id property mnt log file
	_log_path log
	# Early error
	[ -d "${log}" ] || return
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
	critical_start

	for type in built failed ignored; do
		_bget '' "ports.${type}"
		bset "stats_${type}" ${_read_file_lines_read}
	done

	# Skipped may have duplicates in it
	bset stats_skipped $(bget ports.skipped | awk '{print $1}' | \
		sort -u | wc -l)

	lock_release update_stats
	critical_end
}

update_stats_queued() {
	[ $# -eq 0 ] || eargs update_stats_queued
	local nbq nbi nbs nbp

	nbq=$(pkgqueue_list | wc -l)
	# Need to add in pre-build ignored/skipped
	_bget nbi stats_ignored || nbi=0
	_bget nbs stats_skipped || nbs=0
	_bget nbp stats_fetched || nbp=0
	nbq=$((nbq + nbi + nbs + nbp))

	# Add 1 for the main port to test
	if was_a_testport_run; then
		nbq=$((nbq + 1))
	fi
	bset stats_queued ${nbq##* }
	update_remaining
}

update_remaining() {
	[ $# -eq 0 ] || eargs update_remaining
	local log

	if [ "${HTML_TRACK_REMAINING}" != "yes" ]; then
		return 0
	fi
	_log_path log
	pkgqueue_remaining | write_atomic "${log}/.poudriere.ports.remaining"
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

sighup_handler() {
	EXIT_STATUS="sighup:"
	SIGNAL="SIGHUP"
	sig_handler
}

sigterm_handler() {
	EXIT_STATUS="sigterm:"
	SIGNAL="SIGTERM"
	sig_handler
}

sig_handler() {
	# Reset SIGTERM handler, just exit if another is received.
	trap - TERM
	# Ignore SIGPIPE for messages
	trap '' PIPE
	# Ignore SIGINT while cleaning up
	trap '' INT
	trap '' INFO
	trap '' HUP
	unset IFS
	err 1 "Signal ${SIGNAL} caught, cleaning up and exiting"
}

exit_handler() {
	case "${SHFLAGS}" in
	*x*) ;;
	*) local -; set +x ;;
	esac
	# Ignore errors while cleaning up
	set +e
	ERRORS_ARE_FATAL=0
	trap '' INFO
	# Avoid recursively cleaning up here
	trap - EXIT TERM
	# Ignore SIGPIPE for messages
	trap '' PIPE
	# Ignore SIGINT while cleaning up
	trap '' INT
	SUPPRESS_INT=1
	trap '' HUP
	unset IFS

	if ! type parallel_shutdown >/dev/null 2>&1; then
		parallel_shutdown() { :; }
	fi
	if ! type coprocess_stop >/dev/null 2>&1; then
		coprocess_stop() { :; }
	fi

	# stdin may be redirected if a signal interrupted the read builtin (or
	# any redirection to stdin).  Close it to avoid possibly referencing a
	# file in the jail like builders.pipe on socket 6.
	exec </dev/null

	if was_a_bulk_run; then
		log_stop
		# build_queue may have done cd MASTER_DATADIR/pool,
		# but some of the cleanup here assumes we are
		# PWD=MASTER_DATADIR.  Switch back if possible.
		# It will be changed to / in jail_cleanup
		if [ -n "${MASTER_DATADIR-}" ] &&
		    [ -d "${MASTER_DATADIR}" ]; then
			cd "${MASTER_DATADIR}"
		fi
	fi
	if was_a_jail_run; then
		# Don't use jail for any caching in cleanup
		SHASH_VAR_PATH="${SHASH_VAR_PATH_DEFAULT}"
	fi

	parallel_shutdown

	if was_a_bulk_run; then
		# build_queue socket
		exec 6>&- || :
		coprocess_stop pkg_cacher
		coprocess_stop html_json
	fi

	if [ "${STATUS}" -eq 1 ]; then
		if was_a_bulk_run; then
			update_stats >/dev/null 2>&1 || :
			if [ "${DRY_RUN:-0}" -eq 1 ] &&
			    [ -n "${PACKAGES_ROOT-}" ] &&
			    [ ${PACKAGES_MADE_BUILDING:-0} -eq 1 ] ; then
				rm -rf "${PACKAGES_ROOT}/.building" || :
			fi
		fi

		jail_cleanup
	fi

	if [ -n "${CLEANUP_HOOK-}" ]; then
		${CLEANUP_HOOK}
	fi

	if lock_have "jail_start_${MASTERNAME}"; then
		slock_release "jail_start_${MASTERNAME}" || :
	fi
	slock_release_all || :
	if [ -n "${POUDRIERE_TMPDIR-}" ]; then
		rm -rf "${POUDRIERE_TMPDIR}" >/dev/null 2>&1 || :
	fi
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

	if ! was_a_bulk_run; then
		return 0
	fi
	_log_path log
	msg "Logs: ${log}"
	if build_url build_url; then
		msg "WWW: ${build_url}"
	fi
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
		if [ ${PARALLEL_JOBS} -gt ${tobuild} ]; then
			PARALLEL_JOBS=${tobuild##* }
		fi
		msg "Would build ${tobuild} packages using ${PARALLEL_JOBS} builders"

		if [ "${ALL}" -eq 0 ] || [ "${VERBOSE}" -ge 1 ]; then
			msg_n "Ports to build: "
			{
				if was_a_testport_run; then
					echo "${ORIGINSPEC}"
				fi
				cat "${log}/.poudriere.ports.queued"
			} | while mapfile_read_loop_redir originspec pkgname \
			    _ignored; do
				pkgqueue_contains "${pkgname}" || continue
				# Trim away DEPENDS_ARGS for display
				originspec_decode "${originspec}" origin '' \
				    flavor
				originspec_encode originspec "${origin}" '' \
				    "${flavor}"
				echo "${originspec}"
			done | sort | tr '\n' ' '
			echo
		fi
	else
		msg "No packages would be built"
	fi
	show_log_info
	exit 0
}

show_build_summary() {
	local status nbb nbf nbs nbi nbq nbp ndone nbtobuild buildname
	local log now elapsed buildtime queue_width

	update_stats 2>/dev/null || return 0

	_bget nbq stats_queued || nbq=0
	_bget status status || status=unknown
	_bget nbf stats_failed || nbf=0
	_bget nbi stats_ignored || nbi=0
	_bget nbs stats_skipped || nbs=0
	_bget nbp stats_fetched || nbp=0
	_bget nbb stats_built || nbb=0
	ndone=$((nbb + nbf + nbi + nbs + nbp))
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
	_bget buildname buildname || :
	now=$(clock -epoch)

	calculate_elapsed_from_log "${now}" "${log}" || return 1
	elapsed=${_elapsed_time}
	calculate_duration buildtime "${elapsed}"

	printf "[%s] [%s] [%s] \
Queued: %-${queue_width}d \
${COLOR_SUCCESS}Built: %-${queue_width}d \
${COLOR_FAIL}Failed: %-${queue_width}d \
${COLOR_SKIP}Skipped: %-${queue_width}d \
${COLOR_IGNORE}Ignored: %-${queue_width}d \
${COLOR_FETCHED}Fetched: %-${queue_width}d \
${COLOR_RESET}Tobuild: %-${queue_width}d  Time: %s\n" \
	    "${MASTERNAME}" "${buildname}" "${status}" \
	    "${nbq}" "${nbb}" "${nbf}" "${nbs}" "${nbi}" "${nbp}" \
	    "${nbtobuild}" "${buildtime}"
}

siginfo_handler() {
	local IFS; unset IFS;
	in_siginfo_handler=1
	if [ "${POUDRIERE_BUILD_TYPE}" != "bulk" ]; then
		return 0
	fi
	local status
	local now
	local j elapsed elapsed_phase job_id_color
	local pkgname origin phase buildtime buildtime_phase started
	local started_phase format_origin_phase format_phase
	local -

	set +e

	trap '' INFO

	_bget status status || status=unknown
	if [ "${status}" = "index:" -o "${status#stopped:}" = "crashed:" ]; then
		enable_siginfo_handler
		return 0
	fi

	_bget nbq stats_queued || nbq=0
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
			_bget status ${j} status || :
			# Skip builders not started yet
			if [ -z "${status}" ]; then
				continue
			fi
			# Hide idle workers
			if [ "${status}" = "idle:" ]; then
				continue
			fi
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
				elapsed=$((now - started))
				calculate_duration buildtime "${elapsed}"
				elapsed_phase=$((now - started_phase))
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
	[ $# -eq 1 ] || eargs jail_exists jailname
	local jname=$1
	[ -d "${POUDRIERED}/jails/${jname}" ]
}

jail_runs() {
	[ $# -eq 1 ] || eargs jail_runs jname
	local jname="$1"

	jls -j "$jname" >/dev/null 2>&1
}

porttree_list() {
	local name method p

	[ -d ${POUDRIERED}/ports ] || return 0
	for p in $(find ${POUDRIERED}/ports -type d -maxdepth 1 -mindepth 1 -print); do
		name=${p##*/}
		_pget mnt ${name} mnt || :
		_pget method ${name} method || :
		echo "${name} ${method:--} ${mnt}"
	done
}

porttree_exists() {
	[ $# -eq 1 ] || eargs porttree_exists portstree_name
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
		# Set properties on top dataset and let underlying ones inherit them
		# Explicitly set properties for values diverging from top dataset
		zfs create -p -o atime=off \
			-o compression=on \
			-o mountpoint=${BASEFS} \
			${ZPOOL}${ZROOTFS}
		zfs create ${ZPOOL}${ZROOTFS}/jails
		zfs create ${ZPOOL}${ZROOTFS}/ports
		zfs create -o ${NS}:type=data ${ZPOOL}${ZROOTFS}/data
		zfs create ${ZPOOL}${ZROOTFS}/data/.m
		zfs create -o compression=off ${ZPOOL}${ZROOTFS}/data/cache
		zfs create ${ZPOOL}${ZROOTFS}/data/images
		zfs create ${ZPOOL}${ZROOTFS}/data/logs
		zfs create -o compression=off ${ZPOOL}${ZROOTFS}/data/packages
		zfs create -o compression=off ${ZPOOL}${ZROOTFS}/data/wrkdirs
	else
		mkdir -p "${BASEFS}/data"
	fi
	echo "${BASEFS}/data"
}

fetch_file() {
	[ $# -eq 2 ] || eargs fetch_file destination url
	local destination="$1"
	local url="$2"
	local maxtries=2
	local destfile destdir tries ret

	destdir="${destination%/*}"
	destfile="${destination##*/}"

	tries=0
	msg_verbose "Fetching ${url} to ${destination}"
	while [ "${tries}" -lt "${maxtries}" ]; do
		if (cd "${destdir}" && fetch -p -o "${destfile}" "${url}"); then
			return
		fi
		tries=$((tries + 1))
	done

	err 1 "Failed to fetch from ${url}"
}

# Wrap mktemp to put most tmpfiles in $MNT_DATADIR/tmp rather than system /tmp.
mktemp() {
	local mktemp_tmpfile ret

	ret=0
	_mktemp mktemp_tmpfile "$@" || ret="$?"
	echo "${mktemp_tmpfile}"
	return "${ret}"
}

unlink() {
	command unlink "$@" 2>/dev/null || :
}

common_mtree() {
	[ $# -eq 1 ] || eargs common_mtree mnt
	local mnt="${1}"
	local exclude nullpaths schgpaths dir

	cat <<-EOF
	./.npkg
	./${DATADIR_NAME}
	./.poudriere-snap-*
	.${HOME}/.ccache
	./compat/linux/proc
	./dev
	./distfiles
	.${OVERLAYSDIR}
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
	# Ignore schg files when not testing.
	if schg_immutable_base && [ "${PORTTESTING}" -eq 0 ]; then
		schgpaths="/ /usr /boot"
		for dir in ${schgpaths}; do
			[ -f "${MASTERMNT}${dir}/.cpignore" ] || continue
			sed -e "s,^,.${dir%/}/," "${MASTERMNT}${dir}/.cpignore"
		done
	fi
	for exclude in ${LOCAL_MTREE_EXCLUDES}; do
		echo ".${exclude#.}"
	done
}

markfs() {
	[ $# -eq 2 ] || eargs markfs name mnt
	local name=$1
	local mnt="${2}"
	local fs
	local dozfs=0
	local domtree=0
	local mtreefile
	local snapfile

	fs="$(zfs_getfs ${mnt})"

	msg_n "Recording filesystem state for ${name}..."

	case "${name}" in
	clean)
		if [ -n "${fs}" ]; then
			dozfs=1
		fi
		;;
	prepkg)
		if [ -n "${fs}" ]; then
			dozfs=1
		fi
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
		unlink "${snapfile}" || :
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
	(
		trap - INT
		# cd for 'mtree -p .' but do it early as MASTER_DATADIR is
		# a relative path.
		cd "${mnt}"
		mtreefile="${MASTER_DATADIR}/mtree.${name}exclude${PORTTESTING}"
		if [ ! -f "${mtreefile}" ]; then
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
			} | write_atomic "${mtreefile}"
		fi
		mtree -X "${mtreefile}" -cn -k uid,gid,flags,mode,size -p . \
		    > "${MNT_DATADIR}/mtree.${name}"
	)
	echo " done"
}

rm() {
	local arg

	for arg in "$@"; do
		case "${arg}" in
		/|/COPYRIGHT|/bin)
			err 1 "Tried to rm /"
			;;
		esac
	done

	command rm "$@"
}

_update_relpaths() {
	local -; set +x
	[ $# -eq 2 ] || eargs _update_relpaths oldroot newroot
	local oldroot="$1"
	local newroot="$2"
	local varname

	for varname in ${RELATIVE_PATH_VARS}; do
		make_relative "${varname}" "${oldroot}" "${newroot}"
	done
}

add_relpath_var() {
	[ $# -eq 1 ] || eargs add_relpath_var varname
	local varname="$1"
	local value

	getvar "${varname}" value ||
	    err ${EX_SOFTWARE} "add_relpath_var: \$${varname} path must be set"
	case " ${RELATIVE_PATH_VARS} " in
	*" ${varname} "*) ;;
	*) RELATIVE_PATH_VARS="${RELATIVE_PATH_VARS:+${RELATIVE_PATH_VARS} }${varname}" ;;
	esac
	if ! issetvar "${varname}_ABS"; then
		case "${value}" in
		/*) ;;
		*)
			[ -e "${value}" ] ||
			    err ${EX_SOFTWARE} "add_relpath_var: \$${varname} value '${value}' must exist or be absolute already"
			setvar "${varname}_ABS" "$(realpath "${value}")"
		    ;;
		esac
	fi
	make_relative "${varname}"
}

# Handle relative path change needs
cd() {
	local ret

	ret=0
	command cd "$@" || ret=$?
	# Handle fixing relative paths
	if [ "${OLDPWD}" != "${PWD}" ]; then
		_update_relpaths "${OLDPWD}" "${PWD}" || :
	fi
	return ${ret}
}

do_jail_mounts() {
	[ $# -eq 3 ] || eargs do_jail_mounts from mnt name
	local from="$1"
	local mnt="$2"
	local name="$3"
	local devfspath="null zero random urandom stdin stdout stderr fd fd/* pts pts/*"
	local srcpath nullpaths nullpath p arch

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
		if [ -d "${from}${nullpath}" -a "${from}" != "${mnt}" ]; then
			${NULLMOUNT} -o ro "${from}${nullpath}" "${mnt}${nullpath}"
		fi
	done

	# Mount /usr/src into target if it exists and not overridden
	_jget srcpath ${name} srcpath || srcpath="${from}/usr/src"
	if [ -d "${srcpath}" -a "${from}" != "${mnt}" ]; then
		${NULLMOUNT} -o ro ${srcpath} ${mnt}/usr/src
	fi

	mount -t devfs devfs ${mnt}/dev
	if [ ${JAILED} -eq 0 ]; then
		devfs -m ${mnt}/dev rule apply hide
		for p in ${devfspath} ; do
			devfs -m ${mnt}/dev/ rule apply path "${p}" unhide
		done
	fi

	if [ "${USE_FDESCFS}" = "yes" ] && \
	    [ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ]; then
		    mount -t fdescfs fdesc "${mnt}/dev/fd"
	fi
	if [ "${USE_PROCFS}" = "yes" ]; then
		mount -t procfs proc "${mnt}/proc"
	fi

	if [ -z "${NOLINUX-}" ] && [ -d "${mnt}/compat" ]; then
		_jget arch "${name}" arch || \
		    err 1 "Missing arch metadata for jail"
		if [ "${arch}" = "i386" -o "${arch}" = "amd64" ]; then
			mount -t linprocfs linprocfs "${mnt}/compat/linux/proc"
		fi
	fi

	run_hook jail mount ${mnt}

	return 0
}

# Interactive test mode
enter_interactive() {
	local stopmsg pkgname port originspec dep_args flavor packages
	local portdir one_package _log_path

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
		    /usr/bin/make -C "${PORTSDIR}/${P_PKG_ORIGIN:?}" \
		    PKG_BIN="${PKG_BIN}" install-package
	fi

	# Enable all selected ports and their run-depends
	if ! was_a_testport_run; then
		packages="$(listed_pkgnames)"
	else
		packages="${PKGNAME}"
	fi
	one_package=0
	for pkgname in ${packages}; do
		one_package=$((one_package + 1))
		get_originspec_from_pkgname originspec "${pkgname}"
		originspec_decode "${originspec}" port dep_args flavor
		# Install run-depends since this is an interactive test
		msg "Installing run-depends for ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}"
		_lookup_portdir portdir "${port}"
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    /usr/bin/make -C "${portdir}" ${dep_args} \
		    ${flavor:+FLAVOR=${flavor}} run-depends ||
		    msg_warn "Failed to install ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}${COLOR_RESET} run-depends"
		if [ -z "${POUDRIERE_INTERACTIVE_NO_INSTALL-}" ]; then
			msg "Installing ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}"
			# Only use PKGENV during install as testport will store
			# the package in a different place than dependencies
			injail /usr/bin/env ${PKGENV:+-S "${PKGENV}"} \
			    USE_PACKAGE_DEPENDS_ONLY=1 \
			    /usr/bin/make -C "${portdir}" ${dep_args} \
			    ${flavor:+FLAVOR=${flavor}} install-package ||
			    msg_warn "Failed to install ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}"
		fi
	done
	if [ "${one_package}" -gt 1 ]; then
		unset one_package
	fi

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
	injail pkg update

	msg "Remounting ${PORTSDIR} ${OVERLAYS:+and ${OVERLAYSDIR} }read-write"
	remount_ports -o rw >/dev/null

	_log_path log_path
	msg "Mounting logs from: ${log_path}"
	mkdir -p "${MASTERMNT}/logs"
	${NULLMOUNT} -o ro "${log_path}/logs" "${MASTERMNT}/logs"

	if schg_immutable_base; then
		chflags noschg "${MASTERMNT}/root/.cshrc"
	fi
	cat >> "${MASTERMNT}/root/.cshrc" <<-EOF
	cd "${PORTSDIR}/${one_package:+${port:?}}"
	setenv PORTSDIR "${PORTSDIR}"
	EOF
	cat > "${MASTERMNT}/etc/motd" <<-EOF
	Welcome to Poudriere interactive mode!

	PORTSDIR:		${PORTSDIR}
	Work directories:	/wrkdirs
	Distfiles:		/distfiles
	Packages:		/packages
	Build logs:		/logs
	Lookup port var:	make -V WRKDIR

	EOF
	if [ -n "${one_package-}" ]; then
		local NL=$'\n'
		cat >> "${MASTERMNT}/etc/motd" <<-EOF
		ORIGIN:			${port:?}
		PORTDIR:		${PORTSDIR}/${port:?}
		WRKDIR:			$(injail make -C "${PORTSDIR}/${port:?}" -V WRKDIR)
		EOF
		if [ -n "${flavor-}" ]; then
			cat >> "${MASTERMNT}/etc/motd" <<-EOF
			FLAVOR:			${flavor}
			
			A FLAVOR was used to build but is not in the environment.
			Remember to pass FLAVOR to make:
				make FLAVOR=${flavor}

			EOF
		fi
	fi
	cat >> "${MASTERMNT}/etc/motd" <<-EOF
	Installed packages:	$(echo "${packages}" | sort -V | tr '\n' ' ')

	It is recommended to set these in the environment:
		setenv DEVELOPER 1
		setenv DEVELOPER_MODE yes

	Packages from /packages are loaded into 'pkg' and can be installed
	as needed.

	If building as non-root you will be logged into ${PORTBUILD_USER}.
	su can be used without password to elevate.

	To see this again: cat /etc/motd
	EOF

	if [ "${PORTBUILD_USER}" != "root" ]; then
		chown -R "${PORTBUILD_USER}" "${MASTERMNT}/wrkdirs"
	fi
	if [ ${INTERACTIVE_MODE} -eq 1 ]; then
		msg "Entering interactive test mode. Type 'exit' when done."
		if injail pw groupmod -n wheel -m "${PORTBUILD_USER}"; then
			cat >> "${MASTERMNT}/root/.login" <<-EOF
			if ( -f /tmp/su-to-portbuild ) then
				rm -f /tmp/su-to-portbuild
				exec su -m "${PORTBUILD_USER}" -c csh
			endif
			EOF
			touch "${MASTERMNT}/tmp/su-to-portbuild"
		fi
		JNETNAME="n" injail_tty env -i TERM=${SAVED_TERM} \
		    /usr/bin/login -fp root || :
	elif [ ${INTERACTIVE_MODE} -eq 2 ]; then
		# XXX: Not tested/supported with bulk yet.
		msg "Leaving jail ${MASTERNAME}-n running, mounted at ${MASTERMNT} for interactive run testing"
		msg "To enter jail: jexec ${MASTERNAME}-n env -i TERM=\$TERM /usr/bin/login -fp root"
		stopmsg="-j ${JAILNAME}"
		if [ -n "${SETNAME}" ]; then
			stopmsg="${stopmsg} -z ${SETNAME}"
		fi
		if [ -n "${PTNAME#default}" ]; then
			stopmsg="${stopmsg} -p ${PTNAME}"
		fi
		msg "To stop jail: poudriere jail -k ${stopmsg}"
		CLEANED_UP=1
		return 0
	fi
	print_phase_footer
}

use_options() {
	[ $# -eq 2 ] || eargs use_options mnt optionsdir
	local mnt=$1
	local optionsdir=$2

	if [ "${optionsdir}" = "-" ]; then
		optionsdir="${POUDRIERED}/options"
	else
		optionsdir="${POUDRIERED}/${optionsdir}-options"
	fi
	[ -d "${optionsdir}" ] || return 1
	optionsdir=$(realpath ${optionsdir} 2>/dev/null)
	msg "Copying /var/db/ports from: ${optionsdir}"
	do_clone "${optionsdir}" "${mnt}/var/db/ports" || \
	    err 1 "Failed to copy OPTIONS directory"

	return 0
}

remount_packages() {
	umountfs "${MASTERMNT}/packages"
	mount_packages "$@"
}

mount_packages() {
	local mnt

	_my_path mnt
	${NULLMOUNT} "$@" ${PACKAGES} \
		${mnt}/packages ||
		err 1 "Failed to mount the packages directory "
}

remount_ports() {
	local mnt

	_my_path mnt
	umountfs "${mnt}/${PORTSDIR}"
	umountfs "${mnt}/${OVERLAYSDIR}"
	mount_ports "$@"
}

mount_ports() {
	local mnt o portsdir ptname odir

	_my_path mnt
	ptname="${PTNAME:?}"
	_pget portsdir "${ptname}" mnt || err 1 "Missing mnt metadata for portstree"
	# Some ancient compat
	if [ -d "${portsdir}/ports" ]; then
		portsdir="${portsdir}/ports"
	fi
	msg "Mounting ports from: ${portsdir}"
	${NULLMOUNT} "$@" ${portsdir} ${mnt}${PORTSDIR} ||
	    err 1 "Failed to mount the ports directory "
	for o in ${OVERLAYS}; do
		_pget odir "${o}" mnt || err 1 "Missing mnt metadata for overlay ${o}"
		msg "Mounting ports overlay from: ${odir}"
		${NULLMOUNT} "$@" "${odir}" "${mnt}${OVERLAYSDIR}/${o}"
	done
}

do_portbuild_mounts() {
	[ $# -eq 4 ] || eargs do_portbuild_mounts mnt jname ptname setname
	local mnt="$1"
	local jname="$2"
	local ptname="$3"
	local setname="$4"
	local optionsdir opt o msgmount msgdev

	# Create our data dirs
	MNT_DATADIR="${mnt}/${DATADIR_NAME}"
	mkdir -p "${MNT_DATADIR}"
	add_relpath_var MNT_DATADIR
	if [ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		mnt_tmpfs data "${MNT_DATADIR}"
	fi
	mkdir -p \
	    "${MNT_DATADIR}/tmp" \
	    "${MNT_DATADIR}/var/run"

	# clone will inherit from the ref jail
	if [ ${mnt##*/} = "ref" ]; then
		mkdir -p "${mnt}${PORTSDIR}" \
		    "${mnt}${OVERLAYSDIR}" \
		    "${mnt}/wrkdirs" \
		    "${mnt}/${LOCALBASE:-/usr/local}" \
		    "${mnt}/distfiles" \
		    "${mnt}/packages" \
		    "${mnt}/.npkg" \
		    "${mnt}/var/db/ports" \
		    "${mnt}${HOME}/.ccache" \
		    "${mnt}/usr/home"
		for o in ${OVERLAYS}; do
			mkdir -p "${mnt}${OVERLAYSDIR}/${o}"
		done
		ln -fs "usr/home" "${mnt}/home"
		MASTER_DATADIR="${MNT_DATADIR}"
		add_relpath_var MASTER_DATADIR
	fi
	if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
		${NULLMOUNT} ${CCACHE_DIR} ${mnt}${HOME}/.ccache
	fi
	if [ -n "${MFSSIZE}" ]; then
		mdmfs -t -S -o async -s ${MFSSIZE} md ${mnt}/wrkdirs
	fi
	if [ ${TMPFS_WRKDIR} -eq 1 ]; then
		mnt_tmpfs wrkdir ${mnt}/wrkdirs
	fi
	# Only show mounting messages once, not for every builder
	if [ ${mnt##*/} = "ref" ]; then
		msgmount="msg"
		msgdev="/dev/stdout"
	else
		msgmount=":"
		msgdev="/dev/null"
	fi
	if [ -d "${CCACHE_DIR}" ]; then
		${msgmount} "Mounting ccache from: ${CCACHE_DIR}"
	fi

	mount_ports -o ro > "${msgdev}"
	${msgmount} "Mounting packages from: ${PACKAGES_ROOT}"
	mount_packages -o ro
	${msgmount} "Mounting distfiles from: ${DISTFILES_CACHE}"
	${NULLMOUNT} ${DISTFILES_CACHE} ${mnt}/distfiles ||
		err 1 "Failed to mount the distfiles cache directory"

	# Copy in the options for the ref jail, but just ro nullmount it
	# in builders.
	if [ "${mnt##*/}" = "ref" ]; then
		if [ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
			mnt_tmpfs config "${mnt}/var/db/ports"
		fi
		optionsdir="${MASTERNAME}"
		if [ -n "${setname}" ]; then
			optionsdir="${optionsdir} ${jname}-${setname}"
		fi
		optionsdir="${optionsdir} ${jname}-${ptname}"
		if [ -n "${setname}" ]; then
			optionsdir="${optionsdir} ${ptname}-${setname} ${setname}"
		fi
		optionsdir="${optionsdir} ${ptname} ${jname} -"

		for opt in ${optionsdir}; do
			if use_options ${mnt} ${opt}; then
				break
			fi
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
	PACKAGES_PKG_CACHE="${PACKAGES_ROOT}/.pkg-cache"

	[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] || return 0

	[ -L ${PACKAGES}/.latest ] || convert_repository

	if [ -d ${PACKAGES}/.building ]; then
		# If the .building directory is still around, use it. The
		# previous build may have failed, but all of the successful
		# packages are still worth keeping for this build.
		msg_warn "Using packages from previously failed, or uncommitted, build: ${PACKAGES}/.building"
	else
		msg "Stashing existing package repository"

		# Use a linked shadow directory in the package root, not
		# in the parent directory as the user may have created
		# a separate ZFS dataset or NFS mount for each package
		# set; Must stay on the same device for linking.

		mkdir -p ${PACKAGES}/.building
		PACKAGES_MADE_BUILDING=1
		# hardlink copy all top-level directories
		find ${PACKAGES}/.latest/ -mindepth 1 -maxdepth 1 -type d | \
		    xargs -J % cp -al % ${PACKAGES}/.building

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

	if [ "${COMMIT}" -eq 0 ]; then
		case "${PACKAGES}" in
		${PACKAGES_ROOT}/.building)
			msg_warn "Temporary build directory will not be removed or committed: ${PACKAGES}"
			msg_warn "It will be used to resume the build next time.  Delete it for a fresh build."
			;;
		esac
		return 0
	fi

	# Link the latest-done path now that we're done
	_log_path log
	ln -sfh ${BUILDNAME} ${log%/*}/latest-done

	# Cleanup pkg cache
	if [ -e "${PACKAGES_PKG_CACHE:?}" ]; then
		find -L "${PACKAGES_PKG_CACHE:?}" -links 1 -print0 | \
		    xargs -0 rm -f
	fi

	[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] || return 0
	if [ "${COMMIT_PACKAGES_ON_FAILURE}" = "no" ] &&
	    _bget stats_failed stats_failed && [ ${stats_failed} -gt 0 ]; then
		msg_warn "Not committing packages to repository as failures were encountered"
		return 0
	fi

	pkgdir_new=.real_$(clock -epoch)
	msg "Committing packages to repository: ${PACKAGES_ROOT}/${pkgdir_new} via .latest symlink"
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
			.buildname|.jailversion|\
			meta.${PKG_EXT}|meta.txz|\
			digests.${PKG_EXT}|digests.txz|\
			filesite.${PKG_EXT}|filesite.txz|\
			packagesite.${PKG_EXT}|packagesite.txz|\
			All|Latest)
				# Auto fix pkg-owned files
				unlink "${PACKAGES_ROOT:?}/${name}"
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
		keep_cnt=$((KEEP_OLD_PACKAGES_COUNT + 1))
		find ${PACKAGES_ROOT}/ -type d -mindepth 1 -maxdepth 1 \
		    -name '.real_*' | sort -dr |
		    sed -n "${keep_cnt},\$p" |
		    xargs rm -rf 2>/dev/null || :
	else
		# Remove old and shadow dir
		if [ -n "${pkgdir_old}" ]; then
			rm -rf ${pkgdir_old} 2>/dev/null || :
		fi
	fi
}

show_build_results() {
	local failed built ignored skipped nbbuilt nbfailed nbignored nbskipped
	local nbfetched fetched

	failed=$(bget ports.failed | awk '{print $1 ":" $3 }' | xargs echo)
	failed=$(bget ports.failed | \
	    awk -v color_phase="${COLOR_PHASE}" \
	    -v color_port="${COLOR_PORT}" \
	    '{print $1 ":" color_phase $3 color_port }' | xargs echo)
	built=$(bget ports.built | awk '{print $1}' | xargs echo)
	ignored=$(bget ports.ignored | awk '{print $1}' | xargs echo)
	fetched=$(bget ports.fetched | awk '{print $1}' | xargs echo)
	skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)
	_bget nbbuilt stats_built
	_bget nbfailed stats_failed
	_bget nbignored stats_ignored
	_bget nbskipped stats_skipped
	_bget nbfetched stats_fetched || stats_fetched=0

	if [ $nbbuilt -gt 0 ]; then
		COLOR_ARROW="${COLOR_SUCCESS}" \
		    msg "${COLOR_SUCCESS}Built ports: ${COLOR_PORT}${built}"
	fi
	if [ $nbfailed -gt 0 ]; then
		COLOR_ARROW="${COLOR_FAIL}" \
		    msg "${COLOR_FAIL}Failed ports: ${COLOR_PORT}${failed}"
	fi
	if [ $nbskipped -gt 0 ]; then
		COLOR_ARROW="${COLOR_SKIP}" \
		    msg "${COLOR_SKIP}Skipped ports: ${COLOR_PORT}${skipped}"
	fi
	if [ $nbignored -gt 0 ]; then
		COLOR_ARROW="${COLOR_IGNORE}" \
		    msg "${COLOR_IGNORE}Ignored ports: ${COLOR_PORT}${ignored}"
	fi
	if [ $nbfetched -gt 0 ]; then
		COLOR_ARROW="${COLOR_FETCHED}" \
		    msg "${COLOR_FETCHED}Fetched ports: ${COLOR_PORT}${fetched}"
	fi

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
	local this_command

	if [ $(/usr/bin/id -u) -eq 0 ]; then
		return 0
	fi
	# If poudriered not running then the command cannot be
	# satisfied.
	/usr/sbin/service poudriered onestatus >/dev/null 2>&1 || \
	    err 1 "This command requires root or poudriered running"

	this_command="${SCRIPTNAME}"
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
	if [ "${_arch%.*}" = "${_arch#*.}" ]; then
		_arch="${_arch#*.}"
	fi
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

setup_ccache() {
	[ $# -eq 1 ] || eargs setup_ccache tomnt
	local tomnt="$1"

	if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
		cat >> "${tomnt}/etc/make.conf" <<-EOF
		WITH_CCACHE_BUILD=yes
		CCACHE_DIR=${HOME}/.ccache
		EOF
		chmod 755 "${mnt}${HOME}"
		if [ "${CCACHE_GID}" != "${PORTBUILD_GID}" ]; then
			injail pw groupadd "${CCACHE_GROUP}" \
			    -g "${CCACHE_GID}" || \
			    err 1 "Unable to add group ${CCACHE_GROUP}"
			injail pw groupmod -n "${CCACHE_GROUP}" \
			    -m "${PORTBUILD_USER}" || \
			    err 1 "Unable to add user ${PORTBUILD_USER} to group ${CCACHE_GROUP}"
			if [ "${PORTBUILD_USER}" != "root" ]; then
				injail pw groupmod -n "${CCACHE_GROUP}" \
				    -m "root" || \
				    err 1 "Unable to add user root to group ${CCACHE_GROUP}"
			fi
		fi
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

	# as(1) has been removed in FreeBSD 13.0.  Just check if it's present
	# in the target environment's /nxb-bin and use it if it's there.
	if [ -f "${mnt}/nxb-bin/usr/bin/as" ]; then
		cat >> "${mnt}/etc/make.nxb.conf" <<-EOF
		AS=/nxb-bin/usr/bin/as
		EOF
	fi

	# hardlink these files to capture scripts and tools
	# that explicitly call them instead of using paths.
	HLINK_FILES="usr/bin/env usr/bin/gzip usr/bin/head usr/bin/id usr/bin/limits \
			usr/bin/make usr/bin/dirname usr/bin/diff \
			usr/bin/makewhatis \
			usr/bin/find usr/bin/gzcat usr/bin/awk \
			usr/bin/touch usr/bin/sed usr/bin/patch \
			usr/bin/install usr/bin/gunzip \
			usr/bin/readelf usr/bin/sort \
			usr/bin/tar usr/bin/wc usr/bin/xargs usr/sbin/chown bin/cp \
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
			unlink "${mnt:?}/${file}"
			ln "${mnt}/nxb-bin/${file}" "${mnt:?}/${file}"
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
		} >> "${__MAKE_CONF}.ports_env"
		{
			echo "#### Misc Poudriere ####"
			echo ".include \"${__MAKE_CONF#${mnt}}.ports_env\""
			# This is not set by ports_env as older Poudriere
			# would not handle it right.
			echo "GID=0"
			echo "UID=0"
		} >> "${__MAKE_CONF}"
	fi
}

# Set specified version into login.conf
update_version_env() {
	[ $# -eq 5 ] || \
	    eargs update_version_env mnt host_arch arch version osversion
	local mnt="$1"
	local host_arch="$2"
	local arch="$3"
	local version="$4"
	local osversion="$5"
	local login_env

	login_env=",UNAME_r=${version% *},UNAME_v=FreeBSD ${version},OSVERSION=${osversion}"

	# Tell pkg(8) to not use /bin/sh for the ELF ABI since it is native.
	if [ "${QEMU_EMULATING}" -eq 1 ]; then
		login_env="${login_env},ABI_FILE=\/usr\/lib\/crt1.o"
	fi

	# Check TARGET=i386 not TARGET_ARCH due to pc98/i386
	if need_cross_build "${host_arch}" "${arch}"; then
		login_env="${login_env},UNAME_m=${arch%.*},UNAME_p=${arch#*.}"
	fi

	sed -i "" -e "s/,UNAME_r.*:/:/ ; s/:\(setenv.*\):/:\1${login_env}:/" \
	    "${mnt}/etc/login.conf"
	cap_mkdb "${mnt}/etc/login.conf" || \
	    err 1 "cap_mkdb for the jail failed."
}

export_cross_env() {
	[ $# -eq 2 ] || eargs cross_env arch version
	local arch="$1"
	local version="$2"

	export "UNAME_r=${version% *}"
	export "UNAME_v=FreeBSD ${version}"
	export "UNAME_m=${arch%.*}"
	export "UNAME_p=${arch#*.}"
}

unset_cross_env() {
	unset UNAME_r
	unset UNAME_v
	unset UNAME_m
	unset UNAME_p
}

jail_start() {
	[ $# -ge 2 ] || eargs jail_start name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local arch host_arch version
	local mnt
	local needfs="${NULLFSREF}"
	local needkld kldpair kld kldmodname
	local tomnt fs o
	local portbuild_uid portbuild_gid aarchld
	local portbuild_gids portbuild_add_group _gid

	# Lock the startup. From there jail_runs() works fine.
	if ! slock_acquire "jail_start_${MASTERNAME}" 1; then
		err 1 "jail currently starting: ${MASTERNAME}"
	fi

	if [ -n "${MASTERMNT}" ]; then
		tomnt="${MASTERMNT}"
	else
		_mastermnt tomnt
	fi
	_jget arch ${name} arch || err 1 "Missing arch metadata for jail"
	get_host_arch host_arch
	_jget mnt ${name} mnt || err 1 "Missing mnt metadata for jail"
	_jget version ${name} version || \
	    err 1 "Missing version metadata for jail"

	# Protect ourselves from OOM
	madvise_protect $$ || :

	PORTSDIR="/usr/ports"

	JAIL_OSVERSION=$(awk '/\#define __FreeBSD_version/ { print $3 }' "${mnt}/usr/include/sys/param.h")

	if [ ${JAIL_OSVERSION} -lt 900000 ]; then
		needkld="${needkld} sem"
	fi

	case "${setname}" in
	*-*)
		msg_warn "Using '-' in a SETNAME is not recommended as it causes ambiguities with parsing the build name of ${MASTERNAME}"
		;;
	esac

	if [ "${DISTFILES_CACHE}" != "no" -a ! -d "${DISTFILES_CACHE}" ]; then
		err 1 "DISTFILES_CACHE directory does not exist. (cf.  poudriere.conf)"
	fi
	schg_immutable_base && [ $(sysctl -n kern.securelevel) -ge 1 ] && \
	    err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags for IMMUTABLE_BASE=schg."
	if [ ${TMPFS_ALL} -eq 0 ] && [ ${TMPFS_WRKDIR} -eq 0 ] \
	    && [ $(sysctl -n kern.securelevel) -ge 1 ]; then
		err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags. USE_TMPFS with 'wrkdir' or 'all' values can avoid this."
	fi
	if [ ${TMPFS_ALL} -eq 0 ] && [ ${TMPFS_LOCALBASE} -eq 0 ] \
	    && [ $(sysctl -n kern.securelevel) -ge 1 ]; then
		err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags. USE_TMPFS with 'localbase' or 'all' values can avoid this."
	fi
	[ "${name#*.*}" = "${name}" ] ||
		err 1 "The jail name cannot contain a period (.). See jail(8)"
	[ "${ptname#*.*}" = "${ptname}" ] ||
		err 1 "The ports name cannot contain a period (.). See jail(8)"
	[ "${setname#*.*}" = "${setname}" ] ||
		err 1 "The set name cannot contain a period (.). See jail(8)"
	if [ -n "${HARDLINK_CHECK}" -a ! "${HARDLINK_CHECK}" = "00" ]; then
		case ${BUILD_AS_NON_ROOT} in
			[Yy][Ee][Ss])
				msg_warn "You have BUILD_AS_NON_ROOT set to '${BUILD_AS_NON_ROOT}' (cf. poudriere.conf),"
				msg_warn "    and 'security.bsd.hardlink_check_uid' or 'security.bsd.hardlink_check_gid' are not set to '0'."
				err 1 "Poudriere will not be able to stage some ports. Exiting."
				;;
			*)
				;;
		esac
	fi
	if [ -z "${NOLINUX-}" ]; then
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
		if [ "${USE_TMPFS}" != "no" ] && \
		    [ $(sysctl -n security.jail.mount_tmpfs_allowed) -eq 0 ]; then
			nested_perm="${nested_perm:+${nested_perm} }allow.mount.tmpfs (with USE_TMPFS=${USE_TMPFS})"
		fi
		if [ -n "${nested_perm}" ]; then
			err 1 "Nested jail requires these missing params: ${nested_perm}"
		fi
	fi
	if [ "${USE_TMPFS}" != "no" ]; then
		needfs="${needfs} tmpfs"
	fi
	if [ "${USE_PROCFS}" = "yes" ]; then
		needfs="${needfs} procfs"
	fi
	if [ "${USE_FDESCFS}" = "yes" ] && \
	    [ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ]; then
		needfs="${needfs} fdescfs"
	fi
	for fs in ${needfs}; do
		if ! lsvfs $fs >/dev/null 2>&1; then
			if [ $JAILED -eq 0 ]; then
				kldload -n "$fs" || \
				    err 1 "Required kernel module '${fs}' not found"
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
				kldload -n "${kld}" || \
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

	export HOME=/root
	export USER=root

	# ----- No mounting should be done above this point (STATUS=1) -----

	# Only set STATUS=1 if not turned off
	# jail -s should not do this or jail will stop on EXIT
	if [ ${SET_STATUS_ON_START-1} -eq 1 ]; then
		export STATUS=1
	fi

	# Mount tmpfs at the root to avoid crossing tmpfs-zfs-tmpfs boundary
	# for cloning.
	if [ ${TMPFS_ALL} -eq 1 ]; then
		mnt_tmpfs all "${MASTERMNTROOT}"
	fi

	msg_n "Creating the reference jail..."
	if [ ${USE_CACHED} = "yes" ]; then
		export CACHESOCK=${MASTERMNT%/ref}/cache.sock
		export CACHEPID=${MASTERMNT%/ref}/cache.pid
		cached -s /${MASTERNAME} -p ${CACHEPID} -n ${MASTERNAME}
	fi
	clonefs ${mnt} ${tomnt} clean
	echo " done"

	pwd_mkdb -d "${tomnt}/etc" -p "${tomnt}/etc/master.passwd" || \
	    err 1 "pwd_mkdb for the jail failed."
	update_version_env "${tomnt}" "${host_arch}" "${arch}" \
	    "${version}" "${JAIL_OSVERSION}"

	if [ ${JAIL_OSVERSION} -gt ${HOST_OSVERSION} ]; then
		msg_warn "!!! Jail is newer than host. (Jail: ${JAIL_OSVERSION}, Host: ${HOST_OSVERSION}) !!!"
		msg_warn "This is not supported."
		msg_warn "Host kernel must be same or newer than jail."
		msg_warn "Expect build failures."
		sleep 1
	fi

	msg "Mounting system devices for ${MASTERNAME}"
	do_jail_mounts "${mnt}" "${tomnt}" "${name}"
	# do_portbuild_mounts depends on PACKAGES being set.
	# May already be set for pkgclean
	: ${PACKAGES:=${POUDRIERE_DATA:?}/packages/${MASTERNAME}}
	mkdir -p "${PACKAGES:?}/"
	was_a_bulk_run && stash_packages
	do_portbuild_mounts "${tomnt}" "${name}" "${ptname}" "${setname}"

	if [ "${tomnt##*/}" = "ref" ]; then
		mkdir -p "${MASTER_DATADIR}/var/cache"
		SHASH_VAR_PATH="${MASTER_DATADIR}/var/cache"
		# No prefix needed since we're unique in MASTERMNT.
		SHASH_VAR_PREFIX=
	fi

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
			msg "Copying aarch64-binutils ld from '${aarchld}'"
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
	for o in ${OVERLAYS}; do
		echo "OVERLAYS+=${OVERLAYSDIR}/${o}"
	done >> "${tomnt}/etc/make.conf"
	if [ -z "${NO_FORCE_PACKAGE}" ]; then
		echo "FORCE_PACKAGE=yes" >> "${tomnt}/etc/make.conf"
	fi
	if [ -z "${NO_PACKAGE_BUILDING}" ]; then
		echo "PACKAGE_BUILDING=yes" >> "${tomnt}/etc/make.conf"
		export PACKAGE_BUILDING=yes
		echo "PACKAGE_BUILDING_FLAVORS=yes" >> "${tomnt}/etc/make.conf"
	fi

	setup_makeconf ${tomnt}/etc/make.conf ${name} ${ptname} ${setname}

	if [ -n "${RESOLV_CONF}" ]; then
		cp -v "${RESOLV_CONF}" "${tomnt}/etc/"
	fi
	msg "Starting jail ${MASTERNAME}"
	jstart
	# Safe to release the lock now as jail_runs() will block further bulks.
	slock_release "jail_start_${MASTERNAME}"
	injail id >/dev/null 2>&1 || \
	    err $? "Unable to execute id(1) in jail. Emulation or ABI wrong."

	portbuild_gid=$(injail pw groupshow "${PORTBUILD_GROUP}" 2>/dev/null | cut -d : -f3 || :)
	if [ -z "${portbuild_gid}" ]; then
		msg_n "Creating group ${PORTBUILD_GROUP}"
		injail pw groupadd "${PORTBUILD_GROUP}" -g "${PORTBUILD_GID}" || \
		    err 1 "Unable to create group ${PORTBUILD_GROUP}"
		echo " done"
	else
		PORTBUILD_GID=${portbuild_gid}
	fi
	: ${CCACHE_GID:=${PORTBUILD_GID}}
	portbuild_uid=$(injail id -u "${PORTBUILD_USER}" 2>/dev/null || :)
	if [ -z "${portbuild_uid}" ]; then
		msg_n "Creating user ${PORTBUILD_USER}"
		injail pw useradd "${PORTBUILD_USER}" -u "${PORTBUILD_UID}" \
		    -g "${PORTBUILD_GROUP}" -d /nonexistent -c "Package builder" || \
		    err 1 "Unable to create user ${PORTBUILD_USER}"
		echo " done"
	else
		PORTBUILD_UID=${portbuild_uid}
	fi
	portbuild_gids=$(injail id -G "${PORTBUILD_USER}" 2>/dev/null || :)
	portbuild_add_group=true
	for _gid in ${portbuild_gids}; do
		if [ "${_gid}" = "${PORTBUILD_GID}" ]; then
			portbuild_add_group=false
			break
		fi
	done
	if [ "${portbuild_add_group}" = "true" ]; then
		msg_n "Adding user ${PORTBUILD_USER} to ${PORTBUILD_GROUP}"
		injail pw groupmod "${PORTBUILD_GROUP}" -m "${PORTBUILD_USER}" || \
		    err 1 "Unable to add user ${PORTBUILD_USER} to group ${PORTBUILD_GROUP}"
		echo " done"
	fi
	if was_a_bulk_run; then
		msg "Will build as ${PORTBUILD_USER}:${PORTBUILD_GROUP} (${PORTBUILD_UID}:${PORTBUILD_GID})"
	fi
	injail service ldconfig start >/dev/null || \
	    err 1 "Failed to set ldconfig paths."

	setup_ccache "${tomnt}"

	# We want this hook to run before any make -V executions in case
	# a hook modifies ports or the jail somehow relevant.
	run_hook jail start

	setup_ports_env "${tomnt}" "${tomnt}/etc/make.conf"

	if schg_immutable_base && [ "${tomnt}" = "${MASTERMNT}" ]; then
		msg "Setting schg on jail base paths"
		# The first few directories are allowed for ports to write to.
		find -x "${tomnt}" \
		    -mindepth 1 \
		    \( -depth 1 -name compat -prune \) -o \
		    \( -depth 1 -name etc -prune \) -o \
		    \( -depth 1 -name root -prune \) -o \
		    \( -depth 1 -name var -prune \) -o \
		    \( -depth 1 -name '.poudriere-snap*' -prune \) -o \
		    \( -depth 1 -name .ccache -prune \) -o \
		    \( -depth 1 -name .cpignore -prune \) -o \
		    \( -depth 1 -name .npkg -prune \) -o \
		    \( -depth 1 -name "${DATADIR_NAME}" -prune \) -o \
		    \( -depth 1 -name distfiles -prune \) -o \
		    \( -depth 1 -name packages -prune \) -o \
		    \( -path "${tomnt}/${PORTSDIR}" -prune \) -o \
		    \( -depth 1 -name tmp -prune \) -o \
		    \( -depth 1 -name wrkdirs -prune \) -o \
		    \( -type d -o -type f -o -type l \) \
		    -exec chflags -fh schg {} +
		chflags noschg \
		    "${tomnt}${LOCALBASE:-/usr/local}" \
		    "${tomnt}${PREFIX:-/usr/local}" \
		    "${tomnt}/usr/home" \
		    "${tomnt}/boot/modules" \
		    "${tomnt}/boot/firmware" \
		    "${tomnt}/boot"
		if [ -n "${CCACHE_STATIC_PREFIX}" ] && \
			[ -x "${CCACHE_STATIC_PREFIX}/bin/ccache" ]; then
			# Need to allow ccache-update-links to work.
			chflags noschg \
			    "${tomnt}${CCACHE_JAIL_PREFIX}/libexec/ccache" \
			    "${tomnt}${CCACHE_JAIL_PREFIX}/libexec/ccache/world"
		fi
	fi


	return 0
}

load_blacklist() {
	[ $# -ge 2 ] || eargs load_blacklist name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local bl b bfile

	bl="- ${setname} ${ptname} ${name}"
	if [ -n "${setname}" ]; then
		bl="${bl} ${ptname}-${setname}"
	fi
	bl="${bl} ${name}-${ptname}"
	if [ -n "${setname}" ]; then
		bl="${bl} ${name}-${setname} ${name}-${ptname}-${setname}"
	fi
	# If emulating always load a qemu-blacklist as it has special needs.
	if [ ${QEMU_EMULATING} -eq 1 ]; then
		bl="${bl} qemu"
	fi
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
			BLACKLIST="${BLACKLIST:+${BLACKLIST} }${port}"
		done
	done
}

setup_makeconf() {
	[ $# -ge 3 ] || eargs setup_makeconf dst_makeconf name ptname setname
	local dst_makeconf=$1
	local name=$2
	local ptname=$3
	local setname=$4
	local makeconf opt plugin_dir
	local arch host_arch

	get_host_arch host_arch
	# The jail may be empty for poudriere-options.
	if [ -n "${name}" ]; then
		_jget arch "${name}" arch || \
		    err 1 "Missing arch metadata for jail"
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
	if [ -n "${setname}" ]; then
		makeconf="${makeconf} ${ptname}-${setname}"
	fi
	makeconf="${makeconf} ${name}-${ptname}"
	if [ -n "${setname}" ]; then
		makeconf="${makeconf} ${name}-${setname} \
		    ${name}-${ptname}-${setname}"
	fi
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
	local files file flag debug
	local jail ptname setname
	local OPTIND=1

	# msg_debug is not properly setup this early for VERBOSE to be set
	# so spy on -v and set debug and use it locally instead.
	debug=${VERBOSE:-0}

	# Directly included from tests
	if [ -n "${THISDIR-}" ]; then
		jail="${JAILNAME-}"
		ptname="${PTNAME-}"
		setname="${SETNAME-}"
		debug="${VERBOSE:-0}"
	else
		# We don't know what params take arguments so getopts stops on
		# first non -. We parse it all looking for the flags we want.
		# XXX: May read an intended OPTARG as a flag.
		while [ $# -gt 0 ]; do
			while getopts "j:p:vz:" flag 2>/dev/null; do
				case ${flag} in
				j) jail="${OPTARG}" ;;
				p) ptname="${OPTARG}" ;;
				v)
					case "${SCRIPTNAME}" in
					# These commands have their own
					# -v
					jail.sh|image.sh) ;;
					*)
						debug=$((debug+1))
						;;
					esac
					;;
				z) setname="${OPTARG}" ;;
				*) ;;
				esac
			done
			shift $((OPTIND-1))	# parsed arguments
			if [ $# -ne 0 ]; then
				shift			# the failing argument (no -)
			fi
		done
	fi

	if [ -r "${POUDRIERE_ETC}/poudriere.conf" ]; then
		. "${POUDRIERE_ETC}/poudriere.conf"
		if [ ${debug} -gt 1 ]; then
			msg_debug "Reading ${POUDRIERE_ETC}/poudriere.conf"
		fi
	elif [ -r "${POUDRIERED}/poudriere.conf" ]; then
		. "${POUDRIERED}/poudriere.conf"
		if [ ${debug} -gt 1 ]; then
			msg_debug "Reading ${POUDRIERED}/poudriere.conf"
		fi
	else
		err 1 "Unable to find a readable poudriere.conf in ${POUDRIERE_ETC} or ${POUDRIERED}"
	fi

	files="${setname} ${ptname} ${jail}"
	if [ -n "${ptname}" -a -n "${setname}" ]; then
		files="${files} ${ptname}-${setname}"
	fi
	if [ -n "${jail}" -a -n "${ptname}" ]; then
		files="${files} ${jail}-${ptname}"
	fi
	if [ -n "${jail}" -a -n "${setname}" ]; then
		files="${files} ${jail}-${setname}"
	fi
	if [ -n "${jail}" -a -n "${setname}" -a -n "${ptname}" ]; then
		files="${files} ${jail}-${ptname}-${setname}"
	fi
	for file in ${files}; do
		file="${POUDRIERED}/${file}-poudriere.conf"
		if [ -r "${file}" ]; then
			if [ ${debug} -gt 1 ]; then
				msg_debug "Reading ${file}"
			fi
			. "${file}"
		fi
	done

	return 0
}

jail_stop() {
	[ $# -eq 0 ] || eargs jail_stop
	local last_status

	# Make sure CWD is not inside the jail or MASTER_DATADIR, which may
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
	rm -rfx "${MASTERMNT:?}/../"
	export STATUS=0

	# Don't override if there is a failure to grab the last status.
	_bget last_status status || :
	if [ -n "${last_status}" ]; then
		bset status "stopped:${last_status}" 2>/dev/null || :
	fi
}

jail_cleanup() {
	local wait_pids pid pidfile

	if [ -n "${CLEANED_UP-}" ]; then
		return 0
	fi
	msg "Cleaning up"

	# Only bother with this if using jails as this may be being ran
	# from queue.sh or daemon.sh, etc.
	if [ -n "${MASTERMNT}" -a -n "${MASTERNAME}" ] && was_a_jail_run; then
		if [ -d ${MASTER_DATADIR}/var/run ]; then
			for pidfile in ${MASTER_DATADIR}/var/run/*.pid; do
				# Ensure there is a pidfile to read or break
				[ "${pidfile}" = \
				    "${MASTER_DATADIR}/var/run/*.pid" ] && \
				    break
				read pid < "${pidfile}"
				kill_job 1 "${pid}" || :
				wait_pids="${wait_pids:+${wait_pids} }${pid}"
			done
			_wait ${wait_pids-} || :
		fi

		jail_stop

		rm -rf \
		    ${PACKAGES}/.npkg \
		    ${POUDRIERE_DATA}/packages/${MASTERNAME}/.latest/.npkg \
		    2>/dev/null || :

	fi

	export CLEANED_UP=1
}

_pkg_version_expanded() {
	local -; set -f
	[ $# -eq 1 ] || eargs pkg_ver_expanded version
	local ver="$1"
	local epoch ver_sub IFS

	case "${ver}" in
	*,*)
		epoch="${ver##*,}"
		ver="${ver%,*}"
		;;
	*)
		epoch="0"
		;;
	esac
	_gsub "${ver}" "[_.]" " " ver_sub
	set -- ${ver_sub}

	printf "%02d" "${epoch}"
	while [ $# -gt 0 ]; do
		printf "%02d" "$1"
		shift
	done
	printf "\n"
}

pkg_version() {
	if [ $# -ne 3 ] || [ "$1" != "-t" ]; then
		eargs pkg_version -t version1 version2
	fi
	shift
	local ver1="$1"
	local ver2="$2"
	local ver1_expanded ver2_expanded

	ver1_expanded="$(_pkg_version_expanded "${ver1}")"
	ver2_expanded="$(_pkg_version_expanded "${ver2}")"
	if [ "${ver1_expanded}" -gt "${ver2_expanded}" ]; then
		echo ">"
	elif [ "${ver1_expanded}" -eq "${ver2_expanded}" ]; then
		echo "="
	else
		echo "<"
	fi
}

download_from_repo_check_pkg() {
	[ $# -eq 8 ] || eargs download_from_repo_check_pkg pkgname \
	    abi remote_all_options remote_all_pkgs remote_all_deps \
	    remote_all_annotations remote_all_abi output
	local pkgname="$1"
	local abi="$2"
	local remote_all_options="$3"
	local remote_all_pkgs="$4"
	local remote_all_deps="$5"
	local remote_all_annotations="$6"
	local remote_all_abi="$7"
	local output="$8"
	local pkgbase bpkg selected_options remote_options found
	local run_deps lib_deps raw_deps dep dep_pkgname local_deps remote_deps
	local remote_abi remote_osversion

	# The options checks here are not optimized because we lack goto.
	pkgbase="${pkgname%-*}"

	# Skip blacklisted packages
	for bpkg in ${PACKAGE_FETCH_BLACKLIST-}; do
		case "${pkgbase}" in
		${bpkg})
			msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: blacklisted"
			return
			;;
		esac
	done
	found=$(awk -v pkgname="${pkgname}" -vpkgbase="${pkgbase}" \
	    '$1 == pkgbase {print $2; exit}' "${remote_all_pkgs}")
	if [ -z "${found}" ]; then
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: not found in remote"
		return
	fi
	# Version mismatch
	if [ "${found}" != "${pkgname}" ]; then
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote version mismatch: ${COLOR_PORT}${found}${COLOR_RESET}"
		return
	fi

	# ABI
	remote_abi=$(awk -v pkgname="${pkgname}" -vpkgbase="${pkgbase}" \
	    '$1 == pkgbase {print $2; exit}' "${remote_all_abi}")
	case "${abi}" in
	${remote_abi}) ;;
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote ABI mismatch: ${remote_abi} (want: ${abi})"
		return
		;;
	*)
	esac

	# If package is not NOARCH then we need to check its FreeBSD_version
	if [ "${IGNORE_OSVERSION-}" != "yes" ]; then
		remote_osversion=$(awk -vpkgbase="${pkgbase}" ' \
		    $1 == pkgbase && $2 == "FreeBSD_version" {print $3; exit}' \
		    "${remote_all_annotations}")
		# blank likely means NOARCH
		if [ "${remote_osversion:-0}" -gt "${JAIL_OSVERSION}" ]; then
			msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote osversion too new: ${remote_osversion} (want <=${JAIL_OSVERSION})"
			return
		fi
	fi

	remote_options=$(awk -vpkgbase="${pkgbase}" ' \
	    BEGIN {printed=0}
	    $1 == pkgbase && $3 == "on" {print "+"$2;printed=1}
	    $1 == pkgbase && $3 == "off" {print "-"$2;printed=1}
	    $1 != pkgbase && printed == 1 {exit}
	    ' \
	    "${remote_all_options}" | sort -k1.2 | paste -s -d ' ' -)

	shash_get pkgname-options "${pkgname}" selected_options || \
	    selected_options=

	# Options mismatch
	case "${selected_options}" in
	${remote_options}) ;;
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: options wanted: ${selected_options}"
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: options remote: ${remote_options}"
		return
		;;
	esac

	# Runtime dependency mismatch (for example DEFAULT_VERSIONS=ssl=openssl)
	shash_get pkgname-run_deps "${pkgname}" run_deps || run_deps=
	shash_get pkgname-lib_deps "${pkgname}" lib_deps || lib_deps=
	raw_deps="${run_deps:+${run_deps} }${lib_deps}"
	local_deps=$(for dep in ${raw_deps}; do
		get_pkgname_from_originspec "${dep#*:}" dep_pkgname || continue
		echo "${dep_pkgname}"
	done | sort -u | paste -s -d ' ' -)
	remote_deps=$(awk -vpkgbase="${pkgbase}" ' \
	    BEGIN {printed=0}
	    $1 == pkgbase {print $2;printed=1}
	    $1 != pkgbase && printed == 1 {exit}
	    ' \
	    "${remote_all_deps}" | sort | paste -s -d ' ' -)
	case "${local_deps}" in
	${remote_deps}) ;;
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: deps wanted: ${local_deps}"
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: deps remote: ${remote_deps}"
		return
		;;
	esac

	msg_verbose "Package fetch: Will fetch ${COLOR_PORT}${pkgname}${COLOR_RESET}"
	echo "${pkgname}" >> "${output}"
}

download_from_repo() {
	[ $# -eq 0 ] || eargs download_from_repo
	local pkgname abi originspec listed ignored pkg_bin packagesite
	local packagesite_resolved
	local remote_all_pkgs remote_all_options wantedpkgs remote_all_deps
	local remote_all_annotations remote_all_abi
	local missing_pkgs pkg pkgbase cnt
	local remote_pkg_ver local_pkg_name local_pkg_ver found
	local packages_rel

	if [ -z "${PACKAGE_FETCH_BRANCH-}" ]; then
		return 0
	fi

	if ! have_ports_feature SELECTED_OPTIONS; then
		msg "Package fetch: Not fetching. Ports requires SELECTED_OPTIONS feature"
		return 0
	fi

	bset status "fetching_packages:"

	packagesite="${PACKAGE_FETCH_URL:+${PACKAGE_FETCH_URL}/}${PACKAGE_FETCH_BRANCH}"
	msg "Package fetch: Looking for missing packages to fetch from ${packagesite}"

	# only list packages which do not exists to prevent pkg
	# from overwriting prebuilt packages
	missing_pkgs=$(mktemp -t missing_pkgs)
	while mapfile_read_loop "${MASTER_DATADIR}/all_pkgs" \
	    pkgname originspec listed ignored; do
		# Skip ignored ports
		if [ -n "${ignored}" ]; then
			msg_debug "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: ignored"
			continue
		fi
		# Skip listed packages when testing
		if [ "${PORTTESTING}" -eq 1 ]; then
			if [ "${CLEAN:-0}" -eq 1 ] || \
			    [ "${CLEAN_LISTED:-0}" -eq 1 ]; then
				case "${listed}" in
				listed)
					msg_debug "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: -C will delete"
					continue ;;
				esac
			fi
		fi
		if ! pkgqueue_contains "${pkgname}" ; then
			msg_debug "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: not queued"
			continue
		fi
		# XXX only work when PKG_EXT is the same as the upstream
		if [ -f "${PACKAGES}/All/${pkgname}.${PKG_EXT}" ]; then
			msg_debug "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: have package"
			continue
		fi
		pkgbase="${pkgname%-*}"
		found=0
		for pkg in ${PACKAGE_FETCH_WHITELIST-"*"}; do
			case "${pkgbase}" in
			${pkg})
				found=1
				break
				;;
			esac
		done
		if [ "${found}" -eq 0 ]; then
			msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: not in whitelist" >&2
			continue
		fi
		echo "${pkgname}"
	done > "${missing_pkgs}"
	if [ ! -s "${missing_pkgs}" ]; then
		msg "Package fetch: No eligible missing packages to fetch"
		rm -f "${missing_pkgs}"
		return
	fi

	if ensure_pkg_installed; then
		pkg_bin="${PKG_BIN}"
	else
		# Will bootstrap
		msg "Packge fetch: bootstrapping pkg"
		pkg_bin="pkg"
		# When bootstrapping always fetch a copy of the pkg used
		if ! grep -q "^${P_PKG_PKGNAME:?}\$" "${missing_pkgs}"; then
			echo "${P_PKG_PKGNAME:?}" >> "${missing_pkgs}"
		fi
	fi
	cat >> "${MASTERMNT}/etc/pkg/poudriere.conf" <<-EOF
	FreeBSD: {
	        url: ${packagesite};
	}
	EOF

	# XXX: bootstrap+rquery could be done asynchronously during deps
	# Bootstrapping might occur here.
	# XXX: rquery is supposed to 'update' but it does not on first run.
	JNETNAME="n" injail env ASSUME_ALWAYS_YES=yes \
	    PACKAGESITE="${packagesite}" \
	    ${pkg_bin} update -f

	# Make sure the bootstrapped pkg is not newer.
	if [ "${pkg_bin}" = "pkg" ]; then
		local_pkg_name="${P_PKG_PKGNAME:?}"
		local_pkg_ver="${local_pkg_name##*-}"
		remote_pkg_ver=$(injail ${pkg_bin} rquery -U %v \
		    ${P_PKG_PKGBASE:?})
		if [ "$(pkg_version -t "${remote_pkg_ver}" \
		    "${local_pkg_ver}")" = ">" ]; then
			msg "Package fetch: Not fetching due to remote pkg being newer than local: ${remote_pkg_ver} vs ${local_pkg_ver}"
			rm -f "${missing_pkgs}"
			return 0
		fi
	fi
	# pkg insists on creating a local.sqlite even if we won't use it
	# (like pkg rquery -U), and it uses various locking that isn't needed
	# here. Grab all the options for comparison.
	remote_all_options=$(mktemp -t remote_all_options)
	injail ${pkg_bin} rquery -U '%n %Ok %Ov' > "${remote_all_options}"
	remote_all_pkgs=$(mktemp -t remote_all_pkgs)
	injail ${pkg_bin} rquery -U '%n %n-%v %?O' > "${remote_all_pkgs}"
	remote_all_deps=$(mktemp -t remote_all_deps)
	injail ${pkg_bin} rquery -U '%n %dn-%dv' > "${remote_all_deps}"
	remote_all_annotations=$(mktemp -t remote_all_annotations)
	if [ "${IGNORE_OSVERSION-}" != "yes" ]; then
		injail ${pkg_bin} rquery -U '%n %At %Av' > "${remote_all_annotations}"
	fi
	abi="$(injail "${pkg_bin}" config ABI)"
	remote_all_abi=$(mktemp -t remote_all_abi)
	injail ${pkg_bin} rquery -U '%n %q' > "${remote_all_abi}"

	parallel_start
	wantedpkgs=$(mktemp -t wantedpkgs)
	while mapfile_read_loop "${missing_pkgs}" pkgname; do
		parallel_run download_from_repo_check_pkg \
		    "${pkgname}" "${abi}" \
		    "${remote_all_options}" "${remote_all_pkgs}" \
		    "${remote_all_deps}" "${remote_all_annotations}" \
		    "${remote_all_abi}" "${wantedpkgs}"
	done
	parallel_stop
	rm -f "${missing_pkgs}" \
	    "${remote_all_pkgs}" "${remote_all_options}" "${remote_all_deps}" \
	    "${remote_all_annotations}" "${remote_all_abi}"

	if [ ! -s "${wantedpkgs}" ]; then
		msg "Package fetch: No packages eligible to fetch"
		rm -f "${wantedpkgs}"
		return
	fi

	packagesite_resolved=$(injail ${pkg_bin} -vv | \
	    awk '/[[:space:]]*url[[:space:]]*:[[:space:]]*/ {
		    gsub(/^"|",$|,$/, "", $3)
		    print $3
	    }')
	cnt=$(wc -l ${wantedpkgs} | awk '{print $1}')
	msg "Package fetch: Will fetch ${cnt} packages from remote or local pkg cache"

	echo "${packagesite_resolved}" > "${MASTER_DATADIR}/pkg_fetch_url"

	# Fetch into a cache and link back into the PACKAGES dir.
	mkdir -p "${PACKAGES}/All" \
	    "${PACKAGES_PKG_CACHE:?}" \
	    "${MASTERMNT}/var/cache/pkg"
	${NULLMOUNT} "${PACKAGES_PKG_CACHE}" "${MASTERMNT}/var/cache/pkg" || \
	    err 1 "null mount failed for pkg cache"
	JNETNAME="n" injail xargs \
	    env ASSUME_ALWAYS_YES=yes \
	    ${pkg_bin} fetch -U < "${wantedpkgs}"
	relpath "${PACKAGES}" "${PACKAGES_PKG_CACHE}" packages_rel
	while mapfile_read_loop "${wantedpkgs}" pkgname; do
		if [ ! -e "${PACKAGES_PKG_CACHE}/${pkgname}.${PKG_EXT}" ]; then
			msg_warn "${COLOR_PORT}${pkgname}.${PKG_EXT}${COLOR_RESET} not found. Remote PKG_SUFX likely differs temporarily"
			continue
		fi
		echo "${pkgname}"
	done | tee "${MASTER_DATADIR}/pkg_fetch" | (
		cd "${PACKAGES_PKG_CACHE}"
		sed -e "s,\$,.${PKG_EXT}," |
		    xargs -J % ln -fL % "${packages_rel}/All/"
	)
	umountfs "${MASTERMNT}/var/cache/pkg"
	rm -f "${wantedpkgs}"
	# Bootstrapped.  Need to setup symlinks.
	if [ "${pkg_bin}" = "pkg" ]; then
		pkgname=$(injail ${pkg_bin} query %n-%v ${P_PKG_PKGBASE:?})
		if [ "${pkgname##*-}" != "${remote_pkg_ver}" ]; then
			# XXX: This can happen if remote is updated between
			# bootstrap and fetching.
			err 1 "download_from_repo: Fetched pkg version ${remote_pkg_ver} does not match bootstrapped pkg version ${pkgname##*-}"
		fi
		mkdir -p "${PACKAGES}/Latest"
		# Avoid symlinking if remote PKG_SUFX does not match.
		if [ -f "${PACKAGES}/All/${pkgname}.${PKG_EXT}" ]; then
			ln -fhs "../All/${pkgname}.${PKG_EXT}" \
			    "${PACKAGES}/Latest/pkg.${PKG_EXT}"
			# Backwards compat for bootstrap
			ln -fhs "../All/${pkgname}.${PKG_EXT}" \
			    "${PACKAGES}/Latest/pkg.txz"
			ensure_pkg_installed || \
			    err 1 "download_from_repo: failure to bootstrap pkg"
		fi
	fi
}

download_from_repo_make_log() {
	[ $# -eq 2 ] || eargs download_from_repo_make_log pkgname packagesite
	local pkgname="$1"
	local packagesite="$2"
	local logfile originspec

	get_originspec_from_pkgname originspec "${pkgname}"
	_logfile logfile "${pkgname}"
	{
		buildlog_start "${pkgname}" "${originspec}"
		print_phase_header "poudriere"
		echo "Fetched from ${packagesite}"
		print_phase_footer
		buildlog_stop "${pkgname}" "${originspec}" 0
	} | write_atomic "${logfile}"
	badd ports.fetched "${originspec} ${pkgname}"
}

# Remove from the pkg_fetch list packages that need to rebuild anyway.
download_from_repo_post_delete() {
	[ $# -eq 0 ] || eargs download_from_repo_post_delete
	local log fpkgname packagesite

	if [ -z "${PACKAGE_FETCH_BRANCH-}" ] ||
	    [ ! -f "${MASTER_DATADIR}/pkg_fetch" ]; then
		bset "stats_fetched" 0
		return 0
	fi
	bset status "fetched_package_logs:"
	_log_path log
	msg "Package fetch: Generating logs for fetched packages"
	read_line packagesite "${MASTER_DATADIR}/pkg_fetch_url"
	parallel_start
	while mapfile_read_loop "${MASTER_DATADIR}/pkg_fetch" fpkgname; do
		if [ ! -e "${PACKAGES}/All/${fpkgname}.${PKG_EXT}" ]; then
			msg_debug "download_from_repo_post_delete: We lost ${COLOR_PORT}${fpkgname}.${PKG_EXT}${COLOR_RESET}" >&2
			continue
		fi
		echo "${fpkgname}"
	done | while mapfile_read_loop_redir fpkgname; do
		parallel_run \
		    download_from_repo_make_log "${fpkgname}" "${packagesite}"
	done | write_atomic "${log}/.poudriere.pkg_fetch%"
	parallel_stop
	mv -f "${MASTER_DATADIR}/pkg_fetch_url" \
	    "${log}/.poudriere.pkg_fetch_url%"
	# update_stats
	_bget '' ports.fetched
	bset "stats_fetched" ${_read_file_lines_read}
}

validate_package_branch() {
	[ $# -eq 1 ] || eargs validate_package_branch PACKAGE_FETCH_BRANCH
	local PACKAGE_FETCH_BRANCH="$1"

	case "${PACKAGE_FETCH_BRANCH}" in
	latest|quarterly|release*|"") ;;
	*:*)
		unset PACKAGE_FETCH_URL
		;;
	*)
		err 1 "Invalid branch name for package fetching: ${PACKAGE_FETCH_BRANCH}"
	esac
}

maybe_migrate_packages() {
	local pkg pkgnew pkgdst

	if package_dir_exists_and_has_packages ||
	    ! PKG_EXT=txz package_dir_exists_and_has_packages; then
		return
	fi

	for pkg in ${PACKAGES}/All/*.txz ${PACKAGES}/Latest/*.txz; do
		case "${pkg}" in
		"${PACKAGES}/All/*.txz") return 0 ;;
		"${PACKAGES}/Latest/*.txz") continue ;;
		esac
		pkgnew="${pkg%.txz}.${PKG_EXT}"
		case "${pkg}" in
		${PACKAGES}/Latest/*)
			# Rename Latest/pkg.txz symlink and its dest
			if [ -L "${pkg}" ]; then
				pkgdest="$(readlink "${pkg}")"
				ln -fhs "${pkgdest%.txz}.${PKG_EXT}" "${pkgnew}"
				rm -f "${pkg}"
				continue
			fi
			;;
		esac
		# Don't truncate existing file or mess with pkg compat symlinks.
		if [ -L "${pkg}" ] || [ -e "${pkgnew}" ]; then
			continue
		fi
		rename "${pkg}" "${pkgnew}" || :
	done
	if [ -e "${PACKAGES}/Latest/pkg.txz.pubkeysig" ] &&
	    ! [ -e "${PACKAGES}/Latest/pkg.${PKG_EXT}.pubkeysig" ]; then
		rename "${PACKAGES}/Latest/pkg.txz.pubkeysig" \
		    "${PACKAGES}/Latest/pkg.${PKG_EXT}.pubkeysig"
	fi
}

# return 0 if the package dir exists and has packages, 0 otherwise
package_dir_exists_and_has_packages() {
	if [ ! -d ${PACKAGES}/All ]; then
		return 1
	fi
	if dirempty ${PACKAGES}/All; then
		return 1
	fi
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
	# IGNORED and skipped packages are still deleted here so we don't
	# provide an inconsistent repository.
	pkgbase_is_needed "${pkgname}" || return 0
	pkg_get_dep_origin_pkgnames '' compiled_deps_pkgnames "${pkg}"
	for dep_pkgname in ${compiled_deps_pkgnames}; do
		if [ ! -e "${PACKAGES}/All/${dep_pkgname}.${PKG_EXT}" ]; then
			msg_debug "${COLOR_PORT}${pkg}${COLOR_RESET} needs missing ${COLOR_PORT}${dep_pkgname}${COLOR_RESET}"
			msg "Deleting ${COLOR_PORT}${pkg##*/}${COLOR_RESET}: missing dependency: ${COLOR_PORT}${dep_pkgname}${COLOR_RESET}"
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
	if [ ${ret} -eq 0 ]; then
		return 0	# Nothing deleted
	fi
	if [ ${ret} -eq 65 ]; then
		return 1	# Packages deleted
	fi
	err 1 "Failure during sanity check"
}

check_leftovers() {
	[ $# -eq 1 ] || eargs check_leftovers mnt
	local mnt="${1}"

	( cd "${mnt}" && \
	    mtree -X "${MASTER_DATADIR}/mtree.preinstexclude${PORTTESTING}" \
	    -f "${MNT_DATADIR}/mtree.preinst" -p . ) | \
	    while mapfile_read_loop_redir l; do
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
				if [ -d "${mnt}/${l% *}" ]; then
					find "${mnt}/${l% *}" -exec echo "+ {}" \;
				else
					echo "+ ${mnt}/${l% *}"
				fi
				;;
			*missing)
				l="${l#./}"
				echo "- ${mnt}/${l% *}"
				;;
			*changed)
				changed="M ${mnt}/${l% *}"
				read_again=1
				;;
			extra:*)
				if [ -d "${mnt}/${l#* }" ]; then
					find "${mnt}/${l#* }" -exec echo "+ {}" \;
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
			if [ "${read_again}" -eq 1 ] && read l; then
				continue
			fi
			if [ -n "${changed}" ]; then
				echo "${changed}"
			fi
			break
		done
	done
}

check_fs_violation() {
	[ $# -eq 7 ] || eargs check_fs_violation mnt mtree_target originspec \
	    pkgname status_msg err_msg status_value
	local mnt="$1"
	local mtree_target="$2"
	local originspec="$3"
	local pkgname="$4"
	local status_msg="$5"
	local err_msg="$6"
	local status_value="$7"
	local tmpfile
	local ret=0

	tmpfile=$(mktemp -t check_fs_violation)
	msg_n "${status_msg}..."
	( cd "${mnt}" && \
		mtree -X "${MASTER_DATADIR}/mtree.${mtree_target}exclude${PORTTESTING}" \
		-f "${MNT_DATADIR}/mtree.${mtree_target}" \
		-p . ) >> ${tmpfile}
	echo " done"

	if [ -s ${tmpfile} ]; then
		msg "Error: ${err_msg}"
		cat ${tmpfile}
		bset_job_status "${status_value}" "${originspec}" "${pkgname}"
		job_msg_verbose "Status   ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET}: ${status_value}"
		ret=1
	fi
	unlink ${tmpfile}

	return $ret
}

gather_distfiles() {
	[ $# -eq 6 ] || eargs gather_distfiles originspec_main pkgname_main \
	    originspec pkgname from to
	local originspec_main="$1"
	local pkgname_main="$2"
	local originspec="$3"
	local pkgname="$4"
	local from to
	local sub dists d specials special origin
	local dep_originspec pkgname flavor

	from=$(realpath "$5")
	to=$(realpath "$6")
	port_var_fetch_originspec "${originspec}" \
	    DIST_SUBDIR sub \
	    ALLFILES dists || \
	    err 1 "Failed to lookup distfiles for ${COLOR_PORT}${originspec}${COLOR_RESET}"

	originspec_decode "${originspec}" origin '' flavor
	if [ -z "${pkgname}" ]; then
		# Recursive gather_distfiles()
		shash_get originspec-pkgname "${originspec}" pkgname || \
		    err 1 "gather_distfiles: Could not find PKGNAME for ${COLOR_PORT}${originspec}${COLOR_RESET}"
	fi
	shash_get pkgname-depend_specials "${pkgname}" specials || specials=

	job_msg_dev "${COLOR_PORT}${origin}${flavor:+@${flavor}} | ${pkgname_main}${COLOR_RESET}: distfiles ${from} -> ${to}"
	mkdir -p "${to}/${sub}"
	(
		cd "${to}/${sub}"
		for d in ${dists}; do
			case "${d}" in
			*/*) ;;
			*) continue ;;
			esac
			echo "${d%/*}"
		done | sort -u | xargs mkdir -p
	)
	for d in ${dists}; do
		if [ ! -f "${from}/${sub}/${d}" ]; then
			continue
		fi
		# XXX: A --relative would be nice
		install -pS -m 0644 "${from}/${sub}/${d}" \
		    "${to}/${sub}/${d}" ||
		    return 1
	done

	for special in ${specials}; do
		gather_distfiles "${originspec_main}" "${pkgname_main}" \
		    "${special}" "" \
		    "${from}" "${to}"
	done

	return 0
}

# Build+test port and return 1 on first failure
# Return 2 on test failure if PORTTESTING_FATAL=no
build_port() {
	[ $# -eq 2 ] || eargs build_port originspec pkgname
	local originspec="$1"
	local pkgname="$2"
	local port flavor portdir
	local mnt
	local log
	local network
	local hangstatus
	local pkgenv phaseenv jpkg
	local targets
	local jailuser JUSER
	local testfailure=0
	local max_execution_time allownetworking
	local _need_root NEED_ROOT PREFIX MAX_FILES

	_my_path mnt
	_log_path log

	originspec_decode "${originspec}" port '' flavor
	_lookup_portdir portdir "${port}"

	if [ "${BUILD_AS_NON_ROOT}" = "yes" ]; then
		_need_root="NEED_ROOT NEED_ROOT"
	fi
	port_var_fetch_originspec "${originspec}" \
	    ${PORT_FLAGS} \
	    PREFIX PREFIX \
	    ${_need_root}

	allownetworking=0
	for jpkg in ${ALLOW_NETWORKING_PACKAGES}; do
		case "${pkgname%-*}" in
		${jpkg})
			job_msg_warn "ALLOW_NETWORKING_PACKAGES: Allowing full network access for ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}${COLOR_RESET}"
			msg_warn "ALLOW_NETWORKING_PACKAGES: Allowing full network access for ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}${COLOR_RESET}"
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
	targets="check-sanity pkg-depends fetch-depends fetch checksum \
		  extract-depends extract patch-depends patch build-depends \
		  lib-depends configure build run-depends stage package"
	# Do a install/deinstall cycle for testport/bulk -t.
	if [ "${PORTTESTING}" -eq 1 ]; then
		targets="${targets} install deinstall"
	fi

	# If not testing, then avoid rechecking deps in build/install;
	# When testing, check depends twice to ensure they depend on
	# proper files, otherwise they'll hit 'package already installed'
	# errors.
	if [ "${PORTTESTING}" -eq 0 ]; then
		PORT_FLAGS="${PORT_FLAGS:+${PORT_FLAGS} }NO_DEPENDS=yes"
	else
		PORT_FLAGS="${PORT_FLAGS:+${PORT_FLAGS} }STRICT_DEPENDS=yes"
	fi

	for phase in ${targets}; do
		max_execution_time=${MAX_EXECUTION_TIME}
		phaseenv=
		JUSER=${jailuser}
		bset_job_status "${phase}" "${originspec}" "${pkgname}"
		job_msg_verbose "Status   ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}${COLOR_RESET}: ${COLOR_PHASE}${phase}"
		if [ "${PORTTESTING}" -eq 1 ]; then
			phaseenv="${phaseenv:+${phaseenv} }DEVELOPER_MODE=yes"
		fi
		case ${phase} in
		check-sanity|patch)
			if [ "${PORTTESTING}" -eq 1 ]; then
				phaseenv="${phaseenv:+${phaseenv} }DEVELOPER=1"
			fi
			;;
		fetch)
			mkdir -p ${mnt}/portdistfiles
			if [ "${DISTFILES_CACHE}" != "no" ]; then
				echo "DISTDIR=/portdistfiles" >> ${mnt}/etc/make.conf
				gather_distfiles "${originspec}" "${pkgname}" \
				    "${originspec}" "${pkgname}" \
				    "${DISTFILES_CACHE}" \
				    "${mnt}/portdistfiles" || \
				    return 1
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
		configure)
			if [ "${PORTTESTING}" -eq 1 ]; then
				markfs prebuild ${mnt}
			fi
			;;
		run-depends)
			JUSER=root
			if [ "${PORTTESTING}" -eq 1 ]; then
				check_fs_violation "${mnt}" prebuild \
				    "${originspec}" "${pkgname}" \
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
		stage)
			if [ "${PORTTESTING}" -eq 1 ]; then
				markfs prestage ${mnt}
			fi
			;;
		install)
			max_execution_time=${MAX_EXECUTION_TIME_INSTALL}
			JUSER=root
			if [ "${PORTTESTING}" -eq 1 ]; then
				markfs preinst ${mnt}
			fi
			;;
		package)
			max_execution_time=${MAX_EXECUTION_TIME_PACKAGE}
			if [ "${PORTTESTING}" -eq 1 ]; then
				check_fs_violation "${mnt}" prestage \
				    "${originspec}" "${pkgname}" \
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
			if [ "${pkgname%%*linux*}" != "" ]; then
				msg "Checking shared library dependencies"
				# Not using PKG_BIN to avoid bootstrap issues.
				injail "${LOCALBASE}/sbin/pkg" query '%Fp' "${pkgname}" | \
				    injail xargs readelf -d 2>/dev/null | \
				    grep NEEDED | sort -u
			fi
			;;
		esac

		if [ "${phase}" = "package" ]; then
			echo "PACKAGES=/.npkg" >> ${mnt}/etc/make.conf
			# Create sandboxed staging dir for new package for this build
			rm -rf "${PACKAGES}/.npkg/${pkgname}"
			mkdir -p "${PACKAGES}/.npkg/${pkgname}"
			${NULLMOUNT} \
				"${PACKAGES}/.npkg/${pkgname}" \
				${mnt}/.npkg
			chown -R ${JUSER} ${mnt}/.npkg
			:> "${mnt}/.npkg_mounted"

			# Only set PKGENV during 'package' to prevent
			# testport-built packages from going into the main repo
			pkg_notes_get "${pkgname}" "${PKGENV}" pkgenv
			phaseenv="${phaseenv:+${phaseenv}${pkgenv:+ }}${pkgenv}"
		fi
		if [ "${phase#*-}" = "depends" ]; then
			phaseenv="${phaseenv:+${phaseenv} }USE_PACKAGE_DEPENDS_ONLY=1"
		else
			# No need for nohang or PORT_FLAGS for *-depends
			phaseenv="${phaseenv:+${phaseenv}${PORT_FLAGS:+ }}${PORT_FLAGS}"
		fi

		if [ "${JUSER}" = "root" ]; then
			export UID=0
			export GID=0
		else
			export UID=${PORTBUILD_UID}
			export GID=${PORTBUILD_GID}
		fi
		phaseenv="${phaseenv:+${phaseenv} }USER=${JUSER}"
		phaseenv="${phaseenv:+${phaseenv} }UID=${UID}"
		phaseenv="${phaseenv:+${phaseenv} }GID=${GID}"

		print_phase_header "${phase}" "${phaseenv}"

		if [ "${phase#*-}" = "depends" ]; then
			injail /usr/bin/env ${phaseenv:+-S "${phaseenv}"} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    ${phase} || return 1
		else

			nohang ${max_execution_time} ${NOHANG_TIME} \
				"${log}/logs/${pkgname}.log" \
				"${MASTER_DATADIR}/var/run/${MY_JOBID:-00}_nohang.pid" \
				injail /usr/bin/env ${phaseenv:+-S "${phaseenv}"} \
				/usr/bin/make -C ${portdir} ${MAKE_ARGS} \
				${phase}
			hangstatus=$? # This is done as it may return 1 or 2 or 3
			if [ $hangstatus -ne 0 ]; then
				# 1 = cmd failed, not a timeout
				# 2 = log timed out
				# 3 = cmd timeout
				if [ $hangstatus -eq 2 ]; then
					msg "Killing runaway build after ${NOHANG_TIME} seconds with no output"
					bset_job_status "${phase}/runaway" \
					    "${originspec}" "${pkgname}"
					job_msg_verbose "Status   ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}${COLOR_RESET}: ${COLOR_PHASE}runaway"
				elif [ $hangstatus -eq 3 ]; then
					msg "Killing timed out build after ${max_execution_time} seconds"
					bset_job_status "${phase}/timeout" \
					    "${originspec}" "${pkgname}"
					job_msg_verbose "Status   ${COLOR_PORT}${port}${flavor:+@${flavor}} | ${pkgname}${COLOR_RESET}: ${COLOR_PHASE}timeout"
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
			gather_distfiles "${originspec}" "${pkgname}" \
			    "${originspec}" "${pkgname}" \
			    "${mnt}/portdistfiles" "${DISTFILES_CACHE}" || \
			    return 1
		fi

		if [ "${phase}" = "stage" -a "${PORTTESTING}" -eq 1 ]; then
			local die=0

			bset_job_status "stage-qa" "${originspec}" "${pkgname}"
			if ! injail /usr/bin/env DEVELOPER=1 \
			    ${PORT_FLAGS:=-S "${PORT_FLAGS}"} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    stage-qa; then
				msg "Error: stage-qa failures detected"
				if [ "${PORTTESTING_FATAL}" != "no" ]; then
					return 1
				fi
				die=1
			fi

			bset_job_status "check-plist" "${originspec}" \
			    "${pkgname}"
			if ! injail /usr/bin/env \
			    ${PORT_FLAGS:+-S "${PORT_FLAGS}"} \
			    DEVELOPER=1 \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    check-plist; then
				msg "Error: check-plist failures detected"
				if [ "${PORTTESTING_FATAL}" != "no" ]; then
					return 1
				fi
				die=1
			fi

			if [ ${die} -eq 1 ]; then
				testfailure=2
				die=0
			fi
		fi

		if [ "${phase}" = "deinstall" ]; then
			local add add1 del del1 mod mod1
			local die=0

			add=$(mktemp -t lo.add)
			add1=$(mktemp -t lo.add1)
			del=$(mktemp -t lo.del)
			del1=$(mktemp -t lo.del1)
			mod=$(mktemp -t lo.mod)
			mod1=$(mktemp -t lo.mod1)
			msg "Checking for extra files and directories"
			bset_job_status "leftovers" "${originspec}" \
			    "${pkgname}"

			if [ ! -f "${mnt}${PORTSDIR}/Mk/Scripts/check_leftovers.sh" ]; then
				msg "Obsolete ports tree is missing /usr/ports/Mk/Scripts/check_leftovers.sh"
				testfailure=2
				touch "${add}" "${del}" "${mod}" || :
			else
				check_leftovers ${mnt} | sed -e "s|${mnt}||" |
				    injail /usr/bin/env \
				    ${PORT_FLAGS:+-S "${PORT_FLAGS}"} \
				    PORTSDIR=${PORTSDIR} \
				    UID_FILES="${P_UID_FILES}" \
				    portdir="${portdir}" \
				    /bin/sh \
				    ${PORTSDIR}/Mk/Scripts/check_leftovers.sh \
				    ${port} | while \
				    mapfile_read_loop_redir modtype data; do
					case "${modtype}" in
						+) echo "${data}" >> ${add} ;;
						-) echo "${data}" >> ${del} ;;
						M) echo "${data}" >> ${mod} ;;
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
			if [ ${die} -eq 1 -a "${PREFIX}" != "${LOCALBASE}" ] &&
			    was_a_testport_run; then
				msg "This test was done with PREFIX!=LOCALBASE which \
may show failures if the port does not respect PREFIX."
			fi
			rm -f ${add} ${add1} ${del} ${del1} ${mod} ${mod1}
			[ $die -eq 0 ] || if [ "${PORTTESTING_FATAL}" != "no" ]; then
				return 1
			else
				testfailure=2
			fi
		fi
	done

	if [ -d "${PACKAGES}/.npkg/${pkgname}" ]; then
		# everything was fine we can copy the package to the package
		# directory
		find "${PACKAGES}/.npkg/${pkgname}" \
			-mindepth 1 \( -type f -or -type l \) | \
			while mapfile_read_loop_redir pkg_path; do
			pkg_file="${pkg_path#${PACKAGES}/.npkg/${pkgname}}"
			pkg_base="${pkg_file%/*}"
			mkdir -p "${PACKAGES:?}/${pkg_base}"
			mv "${pkg_path}" "${PACKAGES:?}/${pkg_base}"
		done
	fi

	bset_job_status "build_port_done" "${originspec}" "${pkgname}"
	return ${testfailure}
}

pkg_note_add() {
	[ $# -eq 3 ] || eargs pkg_note_add pkgname key value
	local pkgname="$1"
	local key="$2"
	local value="$3"
	local notes

	hash_set "pkgname-notes-${key}" "${pkgname}"  "${value}"
	hash_get pkgname-notes "${pkgname}" notes || notes=
	notes="${notes:+${notes} }${key}"
	hash_set pkgname-notes "${pkgname}" "${notes}"
}

pkg_notes_get() {
	[ $# -eq 3 ] || eargs pkg_notes_get pkgname PKGENV PKGENV_var
	local pkgname="$1"
	local _pkgenv="$2"
	local _pkgenv_var="$3"
	local notes key value

	hash_remove pkgname-notes "${pkgname}" notes || return 0
	_pkgenv="${_pkgenv:+${_pkgenv} }'PKG_NOTES=${notes}'"
	for key in ${notes}; do
		hash_remove "pkgname-notes-${key}" "${pkgname}" value || value=
		_pkgenv="${_pkgenv} 'PKG_NOTE_${key}=${value}'"
	done
	setvar "${_pkgenv_var}" "${_pkgenv}"
}

# Save wrkdir and return path to file
save_wrkdir() {
	[ $# -eq 4 ] || eargs save_wrkdir mnt originspec pkgname phase
	local mnt="$1"
	local originspec="$2"
	local pkgname="$3"
	local phase="$4"
	local tardir=${POUDRIERE_DATA}/wrkdirs/${MASTERNAME}/${PTNAME}
	local tarname=${tardir}/${pkgname}.${WRKDIR_ARCHIVE_FORMAT}
	local wrkdir

	[ "${SAVE_WRKDIR}" != "no" ] || return 0
	# Don't save pre-extract
	case ${phase} in
	check-sanity|pkg-depends|fetch-depends|fetch|checksum|extract-depends|extract) return 0 ;;
	esac

	job_msg "Saving ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET} wrkdir"
	bset ${MY_JOBID} status "save_wrkdir:"
	mkdir -p ${tardir}

	# Tar up the WRKDIR, and ignore errors
	case ${WRKDIR_ARCHIVE_FORMAT} in
	tar) COMPRESSKEY="" ;;
	tgz) COMPRESSKEY="z" ;;
	tbz) COMPRESSKEY="j" ;;
	txz) COMPRESSKEY="J" ;;
	tzst) COMPRESSKEY="-zstd" ;;
	esac
	unlink ${tarname}

	port_var_fetch_originspec "${originspec}" \
	    WRKDIR wrkdir || \
	    err 1 "Failed to lookup WRKDIR for ${COLOR_PORT}${originspec}${COLOR_RESET}"

	tar -s ",${mnt}${wrkdir%/*},," -cf "${tarname}" ${COMPRESSKEY:+-${COMPRESSKEY}} \
	    "${mnt}${wrkdir}" > /dev/null 2>&1

	job_msg "Saved ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET} wrkdir to: ${tarname}"
}

start_builder() {
	[ $# -eq 4 ] || eargs start_builder MY_JOBID jname ptname setname
	local id="$1"
	local jname="$2"
	local ptname="$3"
	local setname="$4"
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
	do_jail_mounts "${MASTERMNT}" "${mnt}" "${jname}"
	do_portbuild_mounts "${mnt}" "${jname}" "${ptname}" "${setname}"
	jstart
	bset ${id} status "idle:"
	run_hook builder start "${id}" "${mnt}"
}

start_builders() {
	[ $# -eq 3 ] || eargs start_builders jname ptname setname
	local jname="$1"
	local ptname="$2"
	local setname="$3"

	msg "Starting/Cloning builders"
	bset status "starting_jobs:"
	run_hook start_builders start

	bset builders "${JOBS}"
	bset status "starting_builders:"
	parallel_start
	for j in ${JOBS}; do
		parallel_run start_builder "${j}" \
		    "${jname}" "${ptname}" "${setname}"
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
	case ${MASTER_DATADIR}/var/run/*.pid in
	"${MASTER_DATADIR}/var/run/*.pid") ;;
	*) cat ${MASTER_DATADIR}/var/run/*.pid | xargs pwait 2>/dev/null ;;
	esac

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

job_done() {
	[ $# -eq 1 ] || eargs job_done j
	local j="$1"
	local pkgname status

	# Failure to find this indicates the job is already done.
	hash_remove builder_pkgnames "${j}" pkgname || return 1
	hash_unset builder_pids "${j}"
	unlink "${MASTER_DATADIR}/var/run/${j}.pid"
	_bget status ${j} status
	rmdir "${MASTER_DATADIR}/building/${pkgname}"
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
	required_env build_queue PWD "${MASTER_DATADIR_ABS}/pool"
	local j jobid pid pkgname builders_active queue_empty
	local builders_idle idle_only timeout log porttesting

	_log_path log

	run_hook build_queue start

	mkfifo ${MASTER_DATADIR}/builders.pipe
	exec 6<> ${MASTER_DATADIR}/builders.pipe
	unlink ${MASTER_DATADIR}/builders.pipe
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

			pkgqueue_get_next pkgname porttesting || \
			    err 1 "Failed to find a package from the queue."

			if [ -z "${pkgname}" ]; then
				# Check if the ready-to-build pool and need-to-build pools
				# are empty
				pkgqueue_empty && queue_empty=1
				builders_idle=1
				continue
			fi
			builders_active=1
			MY_JOBID="${j}" spawn_job \
			    build_pkg "${pkgname}" "${porttesting}"
			pid=$!
			echo "${pid}" > "${MASTER_DATADIR}/var/run/${j}.pid"
			hash_set builder_pids "${j}" "${pid}"
			hash_set builder_pkgnames "${j}" "${pkgname}"
		done

		if [ ${queue_empty} -eq 1 ]; then
			if [ ${builders_active} -eq 1 ]; then
				# The queue is empty, but builds are still
				# going. Wait on them below.
				:
			else
				# All work is done
				pkgqueue_sanity_check 0
				break
			fi
		fi

		# If builders are idle then there is a problem.
		[ ${builders_active} -eq 1 ] || pkgqueue_sanity_check

		update_remaining

		# Wait for an event from a child. All builders are busy.
		jobid=
		read_blocking -t "${timeout}" jobid <&6 || :
		if [ -n "${jobid}" ]; then
			# A job just finished.
			if job_done "${jobid}"; then
				# Do a quick scan to try dispatching
				# ready-to-build to idle builders.
				idle_only=1
			else
				# The job is already done. It was found to be
				# done by a kill -0 check in a scan.
				:
			fi
		else
			# No event found. The next scan will check for
			# crashed builders and deadlocks by validating
			# every builder is really non-idle.
			idle_only=0
		fi
	done
	exec 6>&-

	run_hook build_queue stop
}

calculate_tobuild() {
	local nbq nbb nbf nbi nbs nbp ndone nremaining

	_bget nbq stats_queued || nbq=0
	_bget nbb stats_built || nbb=0
	_bget nbf stats_failed || nbf=0
	_bget nbi stats_ignored || nbi=0
	_bget nbs stats_skipped || nbs=0
	_bget nbp stats_fetched || nbp=0

	ndone=$((nbb + nbf + nbi + nbs + nbp))
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
	local start_time start_end_time end_time

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
	_elapsed_time=$((end_time - start_time))
	return 0
}

# Build ports in parallel
# Returns when all are built.
parallel_build() {
	local jname="$1"
	local ptname="$2"
	local setname="$3"
	local real_parallel_jobs=${PARALLEL_JOBS}
	local nremaining

	nremaining=$(calculate_tobuild)

	# Subtract the 1 for the main port to test
	was_a_testport_run && \
	    nremaining=$((nremaining - 1))

	# If pool is empty, just return
	[ ${nremaining} -eq 0 ] && return 0

	# Minimize PARALLEL_JOBS to queue size
	[ ${PARALLEL_JOBS} -gt ${nremaining} ] && PARALLEL_JOBS=${nremaining##* }

	msg "Building ${nremaining} packages using ${PARALLEL_JOBS} builders"
	JOBS="$(jot -w %02d ${PARALLEL_JOBS})"

	start_builders "${jname}" "${ptname}" "${setname}"

	# Ensure rollback for builders doesn't copy schg files.
	if schg_immutable_base; then
		chflags noschg \
		    "${MASTERMNT}/boot" \
		    "${MASTERMNT}/usr"
		find -xs "${MASTERMNT}" -mindepth 1 -maxdepth 1 \
		    -flags +schg -print | \
		    sed -e "s,^${MASTERMNT}/,," >> \
		    "${MASTERMNT}/.cpignore"

		# /usr has both schg and noschg paths (LOCALBASE).
		# XXX: This assumes LOCALBASE=/usr/local and does
		# not account for PREFIX either.
		find -xs "${MASTERMNT}/usr" -mindepth 1 -maxdepth 1 \
		    \( -depth 1 -name 'home' -prune \) -o \
		    \( -depth 1 -name 'local' -prune \) -o \
		    -flags +schg -print | \
		    sed -e "s,^${MASTERMNT}/usr/,," >> \
		    "${MASTERMNT}/usr/.cpignore"

		find -xs "${MASTERMNT}/boot" -mindepth 1 -maxdepth 1 \
		    \( -depth 1 -name 'modules' -prune \) -o \
		    \( -depth 1 -name 'firmware' -prune \) -o \
		    -flags +schg -print | \
		    sed -e "s,^${MASTERMNT}/boot/,," >> \
		    "${MASTERMNT}/boot/.cpignore"

		chflags schg \
		    "${MASTERMNT}/usr"
		# /boot purposely left writable but its
		# individual files are read-only.
	fi

	coprocess_start pkg_cacher

	bset status "parallel_build:"

	[ ! -d "${MASTER_DATADIR}/pool" ] && err 1 "Build pool is missing"
	cd "${MASTER_DATADIR}/pool"

	build_queue

	cd "${MASTER_DATADIR}"

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
	local origin originspec logd log log_error

	_log_path logd
	get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" origin '' ''

	echo "Build crashed: ${failed_phase}" >> "${log}/logs/${pkgname}.log"
	log="${logd}/logs/${pkgname}.log"
	log_error="${logd}/logs/errors/${pkgname}.log"

	# If the file already exists then all of this handling was done in
	# build_pkg() already; The port failed already. What crashed
	# came after.
	if ! [ -e "${log_error}" ]; then
		# Symlink the buildlog into errors/
		install -lrs "${log}" "${log_error}"
		badd ports.failed \
		    "${originspec} ${pkgname} ${failed_phase} ${failed_phase}"
		COLOR_ARROW="${COLOR_FAIL}" job_msg \
		    "${COLOR_FAIL}Finished ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_FAIL}: Failed: ${COLOR_PHASE}${failed_phase}"
		run_hook pkgbuild failed "${origin}" "${pkgname}" \
		    "${failed_phase}" \
		    "${log_error}"
	fi
	clean_pool "${pkgname}" "${originspec}" "${failed_phase}"
	stop_build "${pkgname}" "${originspec}" 1 >> "${log}"
}

clean_pool() {
	[ $# -ne 3 ] && eargs clean_pool pkgname originspec clean_rdepends
	local pkgname=$1
	local originspec=$2
	local clean_rdepends="$3"
	local origin skipped_originspec skipped_origin

	[ -n "${MY_JOBID}" ] && bset ${MY_JOBID} status "clean_pool:"

	if [ -z "${originspec}" -a -n "${clean_rdepends}" ]; then
		get_originspec_from_pkgname originspec "${pkgname}"
	fi
	originspec_decode "${originspec}" origin '' ''

	# Cleaning queue (pool is cleaned here)
	pkgqueue_done "${pkgname}" "${clean_rdepends}" | \
	    while mapfile_read_loop_redir skipped_pkgname; do
		# Don't skip listed ports that are also IGNORED. They
		# should be accounted as IGNORED.
		if [ "${clean_rdepends}" = "ignored" ] && \
		    shash_exists pkgname-ignore "${skipped_pkgname}" && \
		    pkgname_is_queued "${skipped_pkgname}"; then
			continue
		fi
		get_originspec_from_pkgname skipped_originspec "${skipped_pkgname}"
		originspec_decode "${skipped_originspec}" skipped_origin '' ''
		badd ports.skipped "${skipped_originspec} ${skipped_pkgname} ${pkgname}"
		COLOR_ARROW="${COLOR_SKIP}" \
		    job_msg "${COLOR_SKIP}Skipping ${COLOR_PORT}${skipped_originspec} | ${skipped_pkgname}${COLOR_SKIP}: Dependent port ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_SKIP} ${clean_rdepends}"
		run_hook pkgbuild skipped "${skipped_origin}" \
		    "${skipped_pkgname}" "${origin}" \
		    >&${OUTPUT_REDIRECTED_STDOUT:-1}
	done

	if [ "${clean_rdepends}" != "ignored" ]; then
		(
			cd "${MASTER_DATADIR}"
			balance_pool || :
		)
	fi
}

print_phase_header() {
	[ $# -le 2 ] || eargs print_phase_header phase [env]
	local phase="$1"
	local env="$2"

	printf "=======================<phase: %-15s>============================\n" "${phase}"
	if [ -n "${env}" ]; then
		printf "===== env: %s\n" "${env}"
	fi
}

print_phase_footer() {
	echo "==========================================================================="
}

build_pkg() {
	[ $# -ne 2 ] && eargs build_pkg pkgname PORTTESTING
	local pkgname="$1"
	PORTTESTING="$2"
	local port portdir
	local build_failed=0
	local name
	local mnt
	local failed_status failed_phase
	local clean_rdepends
	local log
	local errortype
	local ret=0
	local elapsed now pkgname_varname jpkg originspec

	_my_path mnt
	_my_name name
	_log_path log
	clean_rdepends=
	trap '' TSTP
	setproctitle "build_pkg (${pkgname})" || :

	# Don't show timestamps in msg() which goes to logs, only job_msg()
	# which goes to master
	NO_ELAPSED_IN_MSG=1
	TIME_START_JOB=$(clock -monotonic)
	colorize_job_id COLOR_JOBID "${MY_JOBID}"

	get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" port DEPENDS_ARGS FLAVOR
	bset_job_status "starting" "${originspec}" "${pkgname}"
	job_msg "Building ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${pkgname}${COLOR_RESET}"

	MAKE_ARGS="${DEPENDS_ARGS}${FLAVOR:+ FLAVOR=${FLAVOR}}"
	if [ -n "${DEPENDS_ARGS}" ]; then
		pkg_note_add "${pkgname}" depends_args "${DEPENDS_ARGS}"
	fi
	_lookup_portdir portdir "${port}"

	_gsub_var_name "${pkgname%-*}" pkgname_varname
	eval "MAX_FILES=\${MAX_FILES_${pkgname_varname}:-${DEFAULT_MAX_FILES}}"
	if [ -n "${MAX_MEMORY_BYTES}" -o -n "${MAX_FILES}" ]; then
		JEXEC_LIMITS=1
	fi
	MNT_DATADIR="${mnt}/${DATADIR_NAME}"
	add_relpath_var MNT_DATADIR
	cd "${MNT_DATADIR}"

	if [ ${TMPFS_LOCALBASE} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		if [ -f "${mnt}/${LOCALBASE:-/usr/local}/.mounted" ]; then
			umount ${UMOUNT_NONBUSY} ${mnt}/${LOCALBASE:-/usr/local} || \
			    umount -f ${mnt}/${LOCALBASE:-/usr/local}
		fi
		mnt_tmpfs localbase ${mnt}/${LOCALBASE:-/usr/local}
		do_clone -r "${MASTERMNT:?}/${LOCALBASE:-/usr/local}" \
		    "${mnt:?}/${LOCALBASE:-/usr/local}"
		:> "${mnt}/${LOCALBASE:-/usr/local}/.mounted"
	fi

	[ -f ${mnt}/.need_rollback ] && rollbackfs prepkg ${mnt}
	[ -f ${mnt}/.need_rollback ] && \
	    err 1 "Failed to rollback ${mnt} to prepkg"
	:> ${mnt}/.need_rollback

	rm -rfx ${mnt}/wrkdirs/* || :

	log_start "${pkgname}" 0
	msg "Building ${port}"

	for jpkg in ${ALLOW_MAKE_JOBS_PACKAGES}; do
		case "${pkgname%-*}" in
		${jpkg})
			job_msg_verbose "Allowing MAKE_JOBS for ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${pkgname}${COLOR_RESET}"
			sed -i '' '/DISABLE_MAKE_JOBS=poudriere/d' \
			    "${mnt}/etc/make.conf"
			break
			;;
		esac
	done

	buildlog_start "${pkgname}" "${originspec}"

	# Ensure /dev/null exists (kern/139014)
	[ ${JAILED} -eq 0 ] && ! [ -c "${mnt}/dev/null" ] && \
	    devfs -m ${mnt}/dev rule apply path null unhide

	build_port "${originspec}" "${pkgname}" || ret=$?
	if [ ${ret} -ne 0 ]; then
		build_failed=1
		# ret=2 is a test failure
		if [ ${ret} -eq 2 ]; then
			failed_phase=$(awk -f ${AWKPREFIX}/processonelog2.awk \
				"${log}/logs/${pkgname}.log" \
				2> /dev/null)
		else
			_bget failed_status ${MY_JOBID} status
			failed_phase=${failed_status%%:*}
		fi

		save_wrkdir "${mnt}" "${originspec}" "${pkgname}" \
		    "${failed_phase}" || :
	elif [ -f ${mnt}/${portdir}/.keep ]; then
		save_wrkdir "${mnt}" "${originspec}" "${pkgname}" \
		    "noneed" ||:
	fi

	now=$(clock -monotonic)
	elapsed=$((now - TIME_START_JOB))

	if [ ${build_failed} -eq 0 ]; then
		badd ports.built "${originspec} ${pkgname} ${elapsed}"
		COLOR_ARROW="${COLOR_SUCCESS}" job_msg "${COLOR_SUCCESS}Finished ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${pkgname}${COLOR_SUCCESS}: Success"
		run_hook pkgbuild success "${port}" "${pkgname}" \
		    >&${OUTPUT_REDIRECTED_STDOUT:-1}
		# Cache information for next run
		pkg_cacher_queue "${port}" "${pkgname}" \
		    "${DEPENDS_ARGS}" "${FLAVOR}" || :
	else
		# Symlink the buildlog into errors/
		ln -s "../${pkgname}.log" \
		    "${log}/logs/errors/${pkgname}.log"
		errortype=$(/bin/sh ${SCRIPTPREFIX}/processonelog.sh \
			"${log}/logs/errors/${pkgname}.log" \
			2> /dev/null)
		badd ports.failed "${originspec} ${pkgname} ${failed_phase} ${errortype} ${elapsed}"
		COLOR_ARROW="${COLOR_FAIL}" job_msg "${COLOR_FAIL}Finished ${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} | ${pkgname}${COLOR_FAIL}: Failed: ${COLOR_PHASE}${failed_phase}"
		run_hook pkgbuild failed "${port}" "${pkgname}" "${failed_phase}" \
			"${log}/logs/errors/${pkgname}.log" \
			>&${OUTPUT_REDIRECTED_STDOUT:-1}
		# ret=2 is a test failure
		if [ ${ret} -eq 2 ]; then
			clean_rdepends=
		else
			clean_rdepends="failed"
		fi
	fi

	msg "Cleaning up wrkdir"
	injail /usr/bin/make -C "${portdir}" -k \
	    -DNOCLEANDEPENDS clean ${MAKE_ARGS} || :
	rm -rfx ${mnt}/wrkdirs/* || :

	clean_pool "${pkgname}" "${originspec}" "${clean_rdepends}"

	stop_build "${pkgname}" "${originspec}" ${build_failed}

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
		rm -rf "${PACKAGES}/.npkg/${pkgname}"

		if [ "${PORTTESTING}" -eq 1 ]; then
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
	shash_remove origin-flavor-all "${origin}" build_all || build_all=0
	[ "${build_all}" -eq 1 ] && return 0

	# bulk and testport
	return 1
}

# ORIGINSPEC is: ORIGIN@FLAVOR@DEPENDS_ARGS
originspec_decode() {
	local -; set +x -f
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
	__flavor="${2-}"
	__dep_args="${3-}"

	if [ -n "${var_return_origin-}" ]; then
		setvar "${var_return_origin}" "${__origin}"
	fi
	if [ -n "${var_return_dep_args-}" ]; then
		setvar "${var_return_dep_args}" "${__dep_args}"
	fi
	if [ -n "${var_return_flavor-}" ]; then
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
		    err 1 "originspec_encode: Origin ${COLOR_PORT}${origin}${COLOR_RESET} incorrectly trying to use FLAVOR=${_flavor} and DEPENDS_ARGS=${_dep_args}"
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
	[ $# -ne 7 ] && eargs deps_fetch_vars originspec deps_var \
	    pkgname_var dep_args_var flavor_var flavors_var ignore_var
	local originspec="$1"
	local deps_var="$2"
	local pkgname_var="$3"
	local dep_args_var="$4"
	local flavor_var="$5"
	local flavors_var="$6"
	local ignore_var="$7"
	local _pkgname _pkg_deps _lib_depends= _run_depends= _selected_options=
	local _changed_options= _changed_deps= _depends_args= _lookup_flavors=
	local _existing_origin _existing_originspec categories _ignore
	local _forbidden _default_originspec _default_pkgname _no_arch
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
		    err 1 "deps_fetch_vars: Lookup of ${COLOR_PORT}${originspec}${COLOR_RESET} failed to already have ${COLOR_PORT}${_default_originspec}${COLOR_RESET}"
	fi

	if [ "${CHECK_CHANGED_OPTIONS}" != "no" ] && \
	    have_ports_feature SELECTED_OPTIONS; then
		_changed_options=yes
	fi
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		_changed_deps="LIB_DEPENDS _lib_depends RUN_DEPENDS _run_depends"
	fi
	if have_ports_feature FLAVORS; then
		_lookup_flavors="FLAVOR _flavor FLAVORS _flavors"
		[ -n "${_origin_dep_args}" ] && \
		    err 1 "deps_fetch_vars: Using FLAVORS but attempted lookup on ${COLOR_PORT}${originspec}${COLOR_RESET}"
	elif have_ports_feature DEPENDS_ARGS; then
		_depends_args="DEPENDS_ARGS _dep_args"
		[ -n "${_origin_flavor}" ] && \
		    err 1 "deps_fetch_vars: Using DEPENDS_ARGS but attempted lookup on ${COLOR_PORT}${originspec}${COLOR_RESET}"
	fi
	if ! port_var_fetch_originspec "${originspec}" \
	    PKGNAME _pkgname \
	    ${_depends_args} \
	    ${_lookup_flavors} \
	    '${_DEPEND_SPECIALS:C,^${PORTSDIR}/,,}' _depend_specials \
	    CATEGORIES categories \
	    IGNORE _ignore \
	    FORBIDDEN _forbidden \
	    NO_ARCH:Dyes _no_arch \
	    ${_changed_deps} \
	    ${_changed_options:+_PRETTY_OPTS='${SELECTED_OPTIONS:@opt@${opt}+@} ${DESELECTED_OPTIONS:@opt@${opt}-@}'} \
	    ${_changed_options:+'${_PRETTY_OPTS:O:C/(.*)([+-])$/\2\1/}' _selected_options} \
	    _PDEPS='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}' \
	    '${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
	    _pkg_deps; then
		msg_error "Error looking up dependencies for ${COLOR_PORT}${originspec}${COLOR_RESET}"
		return 1
	fi

	[ -n "${_pkgname}" ] || \
	    err 1 "deps_fetch_vars: failed to get PKGNAME for ${COLOR_PORT}${originspec}${COLOR_RESET}"

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
			"PYTHON_VERSION=${P_PYTHON_DEFAULT_VERSION}")
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
				err 1 "deps_fetch_vars: Unknown or invalid DEPENDS_ARGS (${_dep_arg}) for ${COLOR_PORT}${originspec}${COLOR_RESET}"
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
	case " ${BLACKLIST} " in
	*\ ${origin}\ *) : ${_ignore:="Blacklisted"} ;;
	esac
	setvar "${ignore_var}" "${_ignore}"
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
		    err 1 "deps_fetch_vars: ${COLOR_PORT}${originspec}${COLOR_RESET} already known as ${COLOR_PORT}${pkgname}${COLOR_RESET}"
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
				    err 1 "deps_fetch_vars: Lookup of ${COLOR_PORT}${originspec}${COLOR_RESET} failed to already have ${COLOR_PORT}${_default_originspec}${COLOR_RESET}"
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
					    ! shash_exists pkgname-ignore \
					    "${_pkgname}"; then
						err 1 "${COLOR_PORT}${originspec}${COLOR_RESET} is IGNORE but ${COLOR_PORT}${_existing_originspec}${COLOR_RESET} was not for ${COLOR_PORT}${_pkgname}${COLOR_RESET}: ${_ignore}"
					fi
					# Set this for later compute_deps lookups
					shash_set originspec-pkgname \
					    "${originspec}" "${_pkgname}"
				fi
				# This originspec is superfluous, just ignore.
				msg_debug "deps_fetch_vars: originspec ${COLOR_PORT}${originspec}${COLOR_RESET} is superfluous for PKGNAME ${COLOR_PORT}${_pkgname}${COLOR_RESET}"
				[ ${ALL} -eq 0 ] && return 2
				have_ports_feature DEPENDS_ARGS && \
				    [ -n "${_origin_dep_args}" ] && return 2
			fi
		fi
		err 1 "Duplicated origin for ${COLOR_PORT}${_pkgname}${COLOR_RESET}: ${COLOR_PORT}${originspec}${COLOR_RESET} AND ${COLOR_PORT}${_existing_originspec}${COLOR_RESET}. Rerun with -v to see which ports are depending on these."
	fi

	# Discovered a new originspec->pkgname mapping.
	msg_debug "deps_fetch_vars: discovered ${COLOR_PORT}${originspec}${COLOR_RESET} is ${COLOR_PORT}${_pkgname}${COLOR_RESET}"
	shash_set originspec-pkgname "${originspec}" "${_pkgname}"
	[ -n "${_flavor}" ] && \
	    shash_set pkgname-flavor "${_pkgname}" "${_flavor}"
	[ -n "${_flavors}" ] && \
	    shash_set pkgname-flavors "${_pkgname}" "${_flavors}"
	[ -n "${_ignore}" ] && \
	    shash_set pkgname-ignore "${_pkgname}" "${_ignore}"
	[ -n "${_forbidden}" ] && \
	    shash_set pkgname-forbidden "${_pkgname}" "${_forbidden}"
	[ -n "${_no_arch}" ] && \
	    shash_set pkgname-no_arch "${_pkgname}" "${_no_arch}"
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

ensure_pkg_installed() {
	local force="$1"
	local host_ver injail_ver mnt

	_my_path mnt
	[ -n "${PKG_BIN}" ] || err 1 "ensure_pkg_installed: empty PKG_BIN"
	if [ -z "${force}" ] && [ -x "${mnt}${PKG_BIN}" ]; then
		return 0
	fi
	# Hack, speed up QEMU usage on pkg-repo.
	if [ ${QEMU_EMULATING} -eq 1 ] && \
	    [ -x /usr/local/sbin/pkg-static ] &&
	    [ -r "${MASTERMNT}/packages/Latest/pkg.${PKG_EXT}" ]; then
		injail_ver=$(realpath "${MASTERMNT}/packages/Latest/pkg.${PKG_EXT}")
		injail_ver=${injail_ver##*/}
		injail_ver=${injail_ver##*-}
		injail_ver=${injail_ver%.*}
		host_ver=$(/usr/local/sbin/pkg-static -v)
		if [ "${host_ver}" = "${injail_ver}" ]; then
			cp -f /usr/local/sbin/pkg-static "${mnt}/${PKG_BIN}"
			return 0
		fi
	fi
	if [ ! -r "${MASTERMNT}/packages/Latest/pkg.${PKG_EXT}" ]; then
		return 1
	fi
	mkdir -p "${MASTERMNT}/${PKG_BIN%/*}" ||
	    err 1 "ensure_pkg_installed: mkdir ${MASTERMNT}/${PKG_BIN%/*}"
	injail tar xf "/packages/Latest/pkg.${PKG_EXT}" \
	    -C "${PKG_BIN%/*}" -s ",.*/,," "*/pkg-static"
}

# Incremental rebuild checks.
#
# Most checks here operate on PKGNAME which is *unique* for any given
# origin+FLAVOR pair.
# We do not automatically do a "pkgclean" here as we only inspect packages that
# are queued or listed to be built.  If we inspected everything then we would
# cause users who test with a subset of their normal ports to lose packages.
#
# We delete and force a rebuild in these cases:
# - pkg bootstrap is not available
# - FORBIDDEN is set for the port
# - Corrupted package file
# - bulk -a: A package which the tree no longer creates.
#   For example, a package with a removed FLAVOR.
# - Wrong origin cases:
#   o MOVED: origin moved to a new location
#   o MOVED: origin expired
#   o Nonexistent origin
#   o A package with the wrong origin for its PKGNAME
# - Changed PKGNAME
# - PORTVERSION, PORTREVISION, or PORTEPOCH bump.
# - Changed ABI/ARCH/NOARCH
# - FLAVOR for a PKGNAME changed
# - New list of dependencies (not including versions)
#   (requires default-on CHECK_CHANGED_DEPS)
# - Changed options
#   (requires default-on CHECK_CHANGED_OPTIONS)
# - Recursive: rebuild if a dependency was rebuilt due to this.
#
# These are handled by pkg (pkg_jobs_need_upgrade()) but not Poudriere yet:
#
# - changed conflicts		# not used by ports
# - changed provides		# not used by ports
# - changed requires		# not used by ports
# - changed provided shlibs	# effectively by CHECK_CHANGED_DEPS
# - changed required shlibs	# effectively by CHECK_CHANGED_DEPS
#
# Some expensive lookups are delayed until the last possible moment as
# earlier cheaper checks may delete the package.
#
delete_old_pkg() {
	[ $# -eq 2 ] || eargs delete_old_pkg pkgname delete_unqueued
	local pkg="$1"
	local delete_unqueued="$2"
	local mnt pkgfile pkgname new_pkgname
	local origin v v2 compiled_options current_options current_deps
	local td d key dpath dir found raw_deps compiled_deps
	local pkg_origin compiled_deps_pkgnames compiled_deps_pkgbases
	local compiled_deps_pkgname compiled_deps_origin compiled_deps_new
	local pkgbase new_pkgbase flavor pkg_flavor originspec
	local dep_pkgname dep_pkgbase dep_origin dep_flavor dep_dep_args
	local ignore new_origin stale_pkg dep_args pkg_dep_args
	local pkg_arch no_arch arch is_sym

	pkgfile="${pkg##*/}"
	pkgname="${pkgfile%.*}"

	if [ "${DELETE_UNKNOWN_FILES}" = "yes" ]; then
		is_sym=0
		if [ -L "${pkg}" ]; then
			is_sym=1
		fi
		if [ "${is_sym}" -eq 1 ] && [ ! -e "${pkg}" ]; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: dead symlink"
			delete_pkg "${pkg}"
			return 0
		fi
		case "${pkgfile}" in
		*.${PKG_EXT}) ;;
		*.txz)
			# If this is a symlink to a .pkg file then just ignore
			# as the ports framework or pkg sometimes creates them.
			if [ "${is_sym}" -eq 1 ]; then
				case "$(realpath "${pkg}")" in
				*.${PKG_EXT})
					msg_debug "Ignoring symlinked ${COLOR_PORT}${pkgfile}${COLOR_RESET}"
					return 0
					;;
				esac
			fi
		;& # FALTHROUGH
		*)
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: unknown or obsolete file"
			delete_pkg "${pkg}"
			return 0
			;;
		esac
	fi

	# Delete FORBIDDEN packages
	if shash_remove pkgname-forbidden "${pkgname}" ignore; then
		shash_get pkgname-ignore "${pkgname}" ignore || \
		    ignore="is forbidden"
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: ${ignore}"
		delete_pkg "${pkg}"
		return 0
	fi

	pkg_flavor=
	pkg_dep_args=
	originspec=
	if ! pkg_get_origin origin "${pkg}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: corrupted package"
		delete_pkg "${pkg}"
		return 0
	fi

	if ! pkgbase_is_needed_and_not_ignored "${pkgname}"; then
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
		if ! originspec_is_needed_and_not_ignored "${originspec}"; then
			if [ "${delete_unqueued}" -eq 1 ]; then
				msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: no longer needed"
				delete_pkg "${pkg}"
			else
				msg_debug "delete_old_pkg: Skip unqueued ${COLOR_PORT}${pkg} | ${originspec}${COLOR_RESET}"
			fi
			return 0
		fi
		# Apparently we expect this package via its origin and flavor.
	fi

	if shash_get origin-moved "${origin}" new_origin; then
		if [ "${new_origin%% *}" = "EXPIRED" ]; then
			msg "Deleting ${pkgfile}: ${COLOR_PORT}${origin}${COLOR_RESET} ${new_origin#EXPIRED }"
		else
			msg "Deleting ${pkgfile}: ${COLOR_PORT}${origin}${COLOR_RESET} moved to ${COLOR_PORT}${new_origin}${COLOR_RESET}"
		fi
		delete_pkg "${pkg}"
		return 0
	fi

	_my_path mnt

	if ! test_port_origin_exist "${origin}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: stale package: nonexistent origin ${COLOR_PORT}${origin}${COLOR_RESET}"
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
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: stale package: unwanted origin ${COLOR_PORT}${originspec}${COLOR_RESET}"
		delete_pkg "${pkg}"
		return 0
	fi
	pkgbase="${pkgname%-*}"
	new_pkgbase="${new_pkgname%-*}"

	# Check for changed PKGNAME before version as otherwise a new
	# version may show for a stale package that has been renamed.
	# XXX: Check if the pkgname has changed and rename in the repo
	if [ "${pkgbase}" != "${new_pkgbase}" ]; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: package name changed to '${COLOR_PORT}${new_pkgbase}${COLOR_RESET}'"
		delete_pkg "${pkg}"
		return 0
	fi

	v2=${new_pkgname##*-}
	if [ "$v" != "$v2" ]; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: new version: ${v2}"
		delete_pkg "${pkg}"
		return 0
	fi

	# Compare ABI
	if pkg_get_arch pkg_arch "${pkg}"; then
		arch="${P_PKG_ABI:?}"
		if shash_remove pkgname-no_arch "${pkgname}" no_arch; then
			arch="${arch%:*}:*"
		fi
		if [ "${pkg_arch}" != "${arch}" ]; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: ABI changed: '${pkg_arch}' -> '${arch}'"
			delete_pkg "${pkg}"
			return 0
		fi
	fi

	if have_ports_feature FLAVORS; then
		shash_get pkgname-flavor "${pkgname}" flavor || flavor=
		if [ "${pkg_flavor}" != "${flavor}" ]; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: FLAVOR changed to '${flavor}' from '${pkg_flavor}'"
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
			shash_remove pkgname-${td}_deps "${new_pkgname}" raw_deps || raw_deps=
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
						[ -n "${CHANGED_DEPS_LIBLIST}" ] || \
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
					/*)
						if [ -e ${mnt}/${key} ]; then
							found=yes
						fi
						;;
					*)
						if [ -n "$(injail \
						    which ${key})" ]; then
							found=yes
						fi
						;;
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
					    err 1 "Invalid dependency for ${COLOR_PORT}${pkgname}${COLOR_RESET}: ${d}"
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
				[ "${compiled_deps_origin%% *}" = \
				    "EXPIRED" ] && \
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
					    err 1 "delete_old_pkg: Failed to lookup PKGNAME for ${COLOR_PORT}${d}${COLOR_RESET}"
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
				msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: new dependency: ${COLOR_PORT}${d}${COLOR_RESET}"
				delete_pkg "${pkg}"
				return 0
				;;
			esac
		done
	fi

	# Check if the compiled options match the current options from make.conf and /var/db/ports
	if [ "${CHECK_CHANGED_OPTIONS}" != "no" ]; then
		if have_ports_feature SELECTED_OPTIONS; then
			shash_remove pkgname-options "${new_pkgname}" \
			    current_options || current_options=
		else
			# Backwards-compat: Fallback on pretty-print-config.
			current_options=$(injail /usr/bin/make -C \
			    ${PORTSDIR}/${origin} \
			    pretty-print-config | \
			    sed -e 's,[^ ]*( ,,g' -e 's, ),,g' -e 's, $,,' | \
			    tr ' ' '\n' | \
			    sort -k1.2 | \
			    paste -d ' ' -s -)
		fi
		pkg_get_options compiled_options "${pkg}"

		if [ "${compiled_options}" != "${current_options}" ]; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: changed options"
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
	local delete_unqueued

	msg "Checking packages for incremental rebuild needs"
	run_hook delete_old_pkgs start

	# Should unqueued packages be deleted?
	# Care is done because there are multiple use cases for Poudriere.
	# Some users only ever do `bulk -a`, or `bulk -f mostly-static-list`,
	# but some do testing of subsets of their repository.  With subsets if
	# they test a port that has no dependencies then we would otherwise
	# delete everything but that package in the repository here.
	# An override is also provided for cases not thought of ("no") or for
	# users who don't mind subsets deleting everything else ("always").
	case "${DELETE_UNQUEUED_PACKAGES}" in
	always)	delete_unqueued=1 ;;
	yes)
		if [ "${ALL}" -eq 1 ]; then
			# -a owns the repo
			delete_unqueued=1
		elif was_a_testport_run ||
		    [ "${PORTTESTING}" -eq 1 ] ||
		    [ "${CLEAN_LISTED}" -eq 1 ]; then
			# Avoid deleting everything if the user is testing as
			# they likely have queued a small subset of the repo.
			# Testing is considered to be testport, bulk -t, or
			# bulk -C.
			delete_unqueued=0
		elif [ -n "${LISTPKGS}" ]; then
			# -f owns the repo if testing/-C isn't happening
			delete_unqueued=1
		else
			# Some subset of packages was specified on the cmdline.
			delete_unqueued=0
		fi
		;;
	*)	delete_unqueued=0 ;;
	esac
	msg_debug "delete_old_pkgs: delete_unqueued=${delete_unqueued}"

	parallel_start
	for pkg in ${PACKAGES}/All/*; do
		case "${pkg}" in
		"${PACKAGES}/All/*")  break ;;
		esac
		parallel_run delete_old_pkg "${pkg}" "${delete_unqueued}"
	done
	parallel_stop

	run_hook delete_old_pkgs stop
}

_lock_acquire() {
	[ $# -eq 2 -o $# -eq 3 ] || eargs _lock_acquire lockpath lockname \
	    [waittime]
	local lockname="$1"
	local lockpath="$2"
	local waittime="${3:-30}"
	local have_lock mypid lock_pid

	mypid="$(getpid)"
	hash_get have_lock "${lockname}" have_lock || have_lock=0
	# lock_pid is in case a subshell tries to reacquire/relase my lock
	hash_get lock_pid "${lockname}" lock_pid || lock_pid=
	# If the pid is set and does not match I'm a subshell and should wait
	if [ -n "${lock_pid}" -a "${lock_pid}" != "${mypid}" ]; then
		hash_unset have_lock "${lockname}"
		hash_unset lock_pid "${lockname}"
		unset lock_pid
		have_lock=0
	fi
	if [ "${have_lock}" -eq 0 ] &&
		! locked_mkdir "${waittime}" "${lockpath}" "${mypid}"; then
		msg_warn "Failed to acquire ${lockname} lock"
		return 1
	fi
	hash_set have_lock "${lockname}" $((have_lock + 1))
	if [ -z "${lock_pid}" ]; then
		hash_set lock_pid "${lockname}" "${mypid}"
	fi
}

# Acquire local build lock
lock_acquire() {
	[ $# -eq 1 -o $# -eq 2 ] || eargs lock_acquire lockname [waittime]
	local lockname="$1"
	local waittime="$2"
	local lockpath

	lockpath="${POUDRIERE_TMPDIR}/lock-${MASTERNAME}-${lockname}"
	_lock_acquire "${lockname}" "${lockpath}" "${waittime}"
}

# Acquire system wide lock
slock_acquire() {
	[ $# -eq 1 -o $# -eq 2 ] || eargs slock_acquire lockname [waittime]
	local lockname="$1"
	local waittime="$2"
	local lockpath

	mkdir -p "${SHARED_LOCK_DIR}" >/dev/null 2>&1 || :
	lockpath="${SHARED_LOCK_DIR}/lock-poudriere-shared-${lockname}"
	_lock_acquire "${lockname}" "${lockpath}" "${waittime}" || return
	# This assumes SHARED_LOCK_DIR isn't overridden by caller
	SLOCKS="${SLOCKS:+${SLOCKS} }${lockname}"
}

_lock_release() {
	[ $# -eq 2 ] || eargs _lock_release lockname lockpath
	local lockname="$1"
	local lockpath="$2"
	local have_lock lock_pid mypid pid

	hash_get have_lock "${lockname}" have_lock ||
		err 1 "Releasing unheld lock ${lockname}"
	if [ "${have_lock}" -eq 0 ]; then
		err 1 "Release unheld lock (have_lock=0) ${lockname}"
	fi
	hash_get lock_pid "${lockname}" lock_pid ||
		err 1 "Lock had no pid ${lockname}"
	mypid="$(getpid)"
	[ "${mypid}" = "${lock_pid}" ] ||
		err 1 "Releasing lock pid ${lock_pid} owns ${lockname}"
	if [ "${have_lock}" -gt 1 ]; then
		hash_set have_lock "${lockname}" $((have_lock - 1))
	else
		hash_unset have_lock "${lockname}"
		[ -f "${lockpath}.pid" ] ||
			err 1 "No pidfile found for ${lockpath}"
		# Pidfile has no trailing newline so will return 1
		read pid < "${lockpath}.pid" || :
		[ -n "${pid}" ] ||
			err 1 "Pidfile is empty for ${lockpath}"
		[ "${pid}" = "${mypid}" ] ||
			err 1 "Releasing lock pid ${lock_pid} owns ${lockname}"
		rmdir "${lockpath}" ||
			err 1 "Held lock dir not found: ${lockpath}"
	fi
}

# Release local build lock
lock_release() {
	[ $# -eq 1 ] || eargs lock_release lockname
	local lockname="$1"
	local lockpath

	lockpath="${POUDRIERE_TMPDIR}/lock-${MASTERNAME}-${lockname}"
	_lock_release "${lockname}" "${lockpath}"
}

# Release system wide lock
slock_release() {
	[ $# -eq 1 ] || eargs slock_release lockname
	local lockname="$1"
	local lockpath

	lockpath="${SHARED_LOCK_DIR}/lock-poudriere-shared-${lockname}"
	_lock_release "${lockname}" "${lockpath}" || return
	list_remove SLOCKS "${lockname}"
}

slock_release_all() {
	[ $# -eq 0 ] || eargs slock_release_all
	local lockname

	if [ -z "${SLOCKS-}" ]; then
		return 0
	fi
	for lockname in ${SLOCKS}; do
		slock_release "${lockname}"
	done
}

lock_have() {
	[ $# -eq 1 ] || eargs lock_have lockname
	local lockname="$1"
	local mypid lock_pid

	if hash_isset have_lock "${lockname}"; then
		hash_get lock_pid "${lockname}" lock_pid ||
			err 1 "have_lock: Lock had no pid ${lockname}"
		mypid="$(getpid)"
		if [ "${mypid}" = "${lock_pid}" ]; then
			return 0
		fi
	fi
	return 1
}

have_ports_feature() {
	[ -z "${P_PORTS_FEATURES%%*${1}*}" ]
}

# Fetch vars from the Makefile and set them locally.
# port_var_fetch ports-mgmt/pkg PKGNAME pkgname PKGBASE pkgbase ...
# Assignments are supported as well, without a subsequent variable for storage.
port_var_fetch() {
	local -; set +x -f
	[ $# -ge 3 ] || eargs port_var_fetch origin PORTVAR var_set ...
	local origin="$1"
	local _make_origin _makeflags _vars ret
	local _portvar _var _line _errexit shiftcnt varcnt
	# Use a tab rather than space to allow FOO='BLAH BLAH' assignments
	# and lookups like -V'${PKG_DEPENDS} ${BUILD_DEPENDS}'
	local IFS sep=$'\t'
	# Use invalid shell var character '!' to ensure we
	# don't setvar it later.
	local assign_var="!"
	local portdir

	if [ -n "${origin}" ]; then
		_lookup_portdir portdir "${origin}"
		_make_origin="-C${sep}${portdir}"
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
			if [ $# -eq 1 ]; then
				break
			fi
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
	while IFS= read -r _line; do
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
	[ $# -eq 2 ] || eargs get_originspec_from_pkgname var_return pkgname
	local gofp_var_return="$1"
	local gofp_pkgname="$2"
	local gofp_originspec gofp_origin gofp_dep_args gofp_flavor

	setvar "${gofp_var_return}" ""
	shash_get pkgname-originspec "${gofp_pkgname}" gofp_originspec ||
	    err ${EX_SOFTWARE} "get_originspec_from_pkgname: Failed to lookup pkgname-originspec for ${COLOR_PORT}${gofp_pkgname}${COLOR_RESET}"
	# Default originspec won't typically have the flavor in it.
	originspec_decode "${gofp_originspec}" gofp_origin gofp_dep_args \
	    gofp_flavor
	if [ -z "${gofp_flavor}" ] &&
	    shash_get pkgname-flavor "${gofp_pkgname}" gofp_flavor &&
	    [ -n "${gofp_flavor}" ]; then
		originspec_encode gofp_originspec "${gofp_origin}" \
		    "${gofp_dep_args}" \
		    "${gofp_flavor}"
	fi
	setvar "${gofp_var_return}" "${gofp_originspec}"
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
	if [ -z "${_flavor}" ]; then
		return 1
	fi
	# See if the FLAVOR is the default and lookup that PKGNAME if so.
	originspec_encode _originspec "${_origin}" "${_dep_args}" ''
	shash_get originspec-pkgname "${_originspec}" _pkgname || return 1
	# Great, compare the flavors and validate we had the default.
	shash_get pkgname-flavors "${_pkgname}" _flavors || return 1
	if [ -z "${_flavors}" ]; then
		return 1
	fi
	_default_flavor="${_flavors%% *}"
	[ "${_default_flavor}" = "${_flavor}" ] || return 1
	# Yup, this was the default FLAVOR
	setvar "${var_return}" "${_pkgname}"
}

set_dep_fatal_error() {
	if [ -n "${DEP_FATAL_ERROR}" ]; then
		return 0
	fi
	DEP_FATAL_ERROR=1
	# Mark the fatal error flag. Must do it like this as this may be
	# running in a sub-shell.
	: > ${DEP_FATAL_ERROR_FILE}
}

clear_dep_fatal_error() {
	unset DEP_FATAL_ERROR
	unlink ${DEP_FATAL_ERROR_FILE} || :
	export ERRORS_ARE_DEP_FATAL=1
}

check_dep_fatal_error() {
	unset ERRORS_ARE_DEP_FATAL
	[ -n "${DEP_FATAL_ERROR}" ] || [ -f ${DEP_FATAL_ERROR_FILE} ]
}

gather_port_vars() {
	required_env gather_port_vars PWD "${MASTER_DATADIR_ABS}"
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

	if was_a_testport_run; then
		local dep_originspec dep_origin dep_flavor dep_ret

		if [ -z "${ORIGINSPEC}" ]; then
			err 1 "testport+gather_port_vars requires ORIGINSPEC set"
		fi
		if have_ports_feature FLAVORS; then
			# deps_fetch_vars really wants to have the main port
			# cached before being given a FLAVOR.
			originspec_decode "${ORIGINSPEC}" dep_origin \
			    '' dep_flavor
			if [ -n "${dep_flavor}" ]; then
				deps_fetch_vars "${dep_origin}" LISTPORTS \
				    PKGNAME DEPENDS_ARGS FLAVOR FLAVORS \
				    IGNORE
			fi
		fi
		dep_ret=0
		deps_fetch_vars "${ORIGINSPEC}" LISTPORTS PKGNAME \
		    DEPENDS_ARGS FLAVOR FLAVORS IGNORE || dep_ret=$?
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

	:> "${MASTER_DATADIR}/all_pkgs"
	if [ ${ALL} -eq 0 ]; then
		:> "${MASTER_DATADIR}/all_pkgbases"
	fi

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
			if [ -n "${flavor}" ]; then
				err 1 "Flavor ${COLOR_PORT}${originspec}${COLOR_RESET} with ALL=1"
			fi
			parallel_run \
			    prefix_stderr_quick \
			    "(${COLOR_PORT}${originspec}${COLOR_RESET})" \
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
			msg_debug "queueing ${COLOR_PORT}${originspec}${COLOR_RESET} into flavorqueue (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
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
		msg_debug "queueing ${COLOR_PORT}${origin}${COLOR_RESET} into gatherqueue (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
		if [ -n "${rdep}" ]; then
			echo "${rdep}" > "${qorigin}/rdep"
		fi
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
				    err 1 "gather_port_vars: Failed to read rdep for ${COLOR_PORT}${originspec}${COLOR_RESET}"
				parallel_run \
				    prefix_stderr_quick \
				    "(${COLOR_PORT}${originspec}${COLOR_RESET})" \
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
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} incorrectly depends on itself. Please contact maintainer of the port to fix this."
			ret=1
		fi
		# Detect bad cat/origin/ dependency which pkg will not register properly
		if ! [ "${dep_origin}" = "${dep_origin%/}" ]; then
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} depends on bad origin '${COLOR_PORT}${dep_origin}${COLOR_RESET}'; Please contact maintainer of the port to fix this."
			ret=1
		fi
		if ! test_port_origin_exist "${dep_origin}"; then
			# Was it moved? We cannot map it here due to the ports
			# framework not supporting it later on, and the
			# PKGNAME would be wrong, but we can at least
			# advise the user about it.
			shash_get origin-moved "${dep_origin}" \
			    new_origin || new_origin=
			if [ "${new_origin%% *}" = "EXPIRED" ]; then
				moved_reason="port EXPIRED: ${new_origin#EXPIRED }"
			elif [ -n "${new_origin}" ]; then
				moved_reason="moved to ${COLOR_PORT}${new_origin}${COLOR_RESET}"
			else
				unset moved_reason
			fi
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} depends on nonexistent origin '${COLOR_PORT}${dep_origin}${COLOR_RESET}'${moved_reason:+ (${moved_reason})}; Please contact maintainer of the port to fix this."
			ret=1
		fi
		if have_ports_feature FLAVORS && [ -z "${dep_flavor}" ] && \
		    [ "${dep_originspec}" != "${dep_origin}" ]; then
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} has dependency on ${COLOR_PORT}${dep_origin}${COLOR_RESET} with invalid empty FLAVOR; Please contact maintainer of the port to fix this."
			ret=1
		fi
	done
	return ${ret}
}

gather_port_vars_port() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "gather_port_vars_port requires SHASH_VAR_PATH=var/cache"
	required_env gather_port_vars_port PWD "${MASTER_DATADIR_ABS}"
	[ $# -eq 2 ] || eargs gather_port_vars_port originspec rdep
	local originspec="$1"
	local rdep="$2"
	local dep_origin deps pkgname dep_args dep_originspec
	local dep_ret log flavor flavors dep_flavor
	local origin origin_dep_args origin_flavor default_flavor
	local ignore

	msg_debug "gather_port_vars_port (${COLOR_PORT}${originspec}${COLOR_RESET}): LOOKUP"
	originspec_decode "${originspec}" origin origin_dep_args origin_flavor
	if [ -n "${origin_dep_args}" ] && ! have_ports_feature DEPENDS_ARGS; then
		err 1 "gather_port_vars_port: Looking up ${COLOR_PORT}${originspec}${COLOR_RESET} without DEPENDS_ARGS support in ports"
	fi
	if [ -n "${origin_flavor}" ] && ! have_ports_feature FLAVORS; then
		err 1 "gather_port_vars_port: Looking up ${COLOR_PORT}${originspec}${COLOR_RESET} without FLAVORS support in ports"
	fi

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
		    err 1 "gather_port_vars_port: Already had ${COLOR_PORT}${originspec}${COLOR_RESET} (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"

		shash_get pkgname-deps "${pkgname}" deps || deps=
		shash_get pkgname-flavor "${pkgname}" flavor || flavor=
		shash_get pkgname-flavors "${pkgname}" flavors || flavors=
		shash_get pkgname-ignore "${pkgname}" ignore || ignore=
		# DEPENDS_ARGS not fetched since it is not possible to be
		# in this situation with them.  The 'metadata' hack is
		# only used for FLAVOR lookups.
	else
		dep_ret=0
		deps_fetch_vars "${originspec}" deps pkgname dep_args flavor \
		    flavors ignore || dep_ret=$?
		case ${dep_ret} in
		0) ;;
		# Non-fatal duplicate should be ignored
		2)
			# If this a superfluous DEPENDS_ARGS then there's
			# nothing more to do - it's already queued.
			if [ -n "${origin_dep_args}" ]; then
				return 0
			fi
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
			if [ "${origin_flavor}" = "${FLAVOR_DEFAULT}" ]; then
				origin_flavor="${default_flavor}"
			fi
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
			msg_debug "gather_port_vars_port: Fixing up from metadata hack on ${COLOR_PORT}${originspec}${COLOR_RESET}"
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
			msg_debug "SKIPPING ${COLOR_PORT}${originspec}${COLOR_RESET} - no FLAVORS"
			return 0
		fi
		local queued_flavor queuespec

		default_flavor="${flavors%% *}"
		rdep="${rdep#* }"
		queued_flavor="${rdep% *}"
		if [ "${queued_flavor}" = "${FLAVOR_DEFAULT}" ]; then
			queued_flavor="${default_flavor}"
		fi
		# Check if we have the default FLAVOR sitting in the
		# flavorqueue and don't skip if so.
		if [ "${queued_flavor}" != "${default_flavor}" ]; then
			msg_debug "SKIPPING ${COLOR_PORT}${originspec}${COLOR_RESET} - metadata lookup queued=${queued_flavor} default=${default_flavor}"
			return 0
		fi
		# We're keeping this metadata lookup as its original rdep
		# but we need to prevent forcing all FLAVORS to build
		# later, so reset our flavor and originspec.
		rdep="${rdep#* }"
		origin_flavor="${queued_flavor}"
		originspec_encode queuespec "${origin}" "${origin_dep_args}" \
		    "${origin_flavor}"
		msg_debug "gather_port_vars_port: Fixing up ${COLOR_PORT}${originspec}${COLOR_RESET} to be ${COLOR_PORT}${queuespec}${COLOR_RESET}"
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

	msg_debug "WILL BUILD ${COLOR_PORT}${originspec}${COLOR_RESET}"
	echo "${pkgname} ${originspec} ${rdep} ${ignore}" >> "${MASTER_DATADIR}/all_pkgs"
	if [ ${ALL} -eq 0 ]; then
		echo "${pkgname%-*}" >> "${MASTER_DATADIR}/all_pkgbases"
	fi

	# Add all of the discovered FLAVORS into the flavorqueue if
	# this was the default originspec and this originspec was
	# listed to build.
	if [ "${rdep}" = "listed" -a \
	    -z "${origin_flavor}" -a -n "${flavors}" ] && \
	    build_all_flavors "${originspec}"; then
		msg_verbose "Will build all flavors for ${COLOR_PORT}${originspec}${COLOR_RESET}: ${flavors}"
		for dep_flavor in ${flavors}; do
			# Skip default FLAVOR
			if [ "${flavor}" = "${dep_flavor}" ]; then
				continue
			fi
			originspec_encode dep_originspec "${origin}" \
			    "${origin_dep_args}" "${dep_flavor}"
			msg_debug "gather_port_vars_port (${COLOR_PORT}${originspec}${COLOR_RESET}): Adding to flavorqueue FLAVOR=${dep_flavor}${dep_args:+ (DEPENDS_ARGS=${dep_args})}"
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
	if [ -n "${ignore}" ] || [ -z "${deps}" ]; then
		return 0
	fi

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
		msg_debug "gather_port_vars_port (${COLOR_PORT}${originspec}${COLOR_RESET}): Adding to depqueue${dep_args:+ (DEPENDS_ARGS=${dep_args})}"
		mkdir "dqueue/${originspec%/*}!${originspec#*/}" || \
			err 1 "gather_port_vars_port: Failed to add ${COLOR_PORT}${originspec}${COLOR_RESET} to depqueue"
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
	required_env gather_port_vars_process_depqueue_enqueue PWD "${MASTER_DATADIR_ABS}"
	[ $# -eq 4 ] || eargs gather_port_vars_process_depqueue_enqueue \
	    originspec dep_originspec queue rdep
	local originspec="$1"
	local dep_originspec="$2"
	local queue="$3"
	local rdep="$4"
	local origin dep_pkgname

	# Add this origin into the gatherqueue if not already done.
	if shash_get originspec-pkgname "${dep_originspec}" dep_pkgname; then
		if ! is_failed_metadata_lookup "${dep_pkgname}" "${rdep}" || \
		    shash_exists pkgname-ignore "${dep_pkgname}"; then
			msg_debug "gather_port_vars_process_depqueue_enqueue (${COLOR_PORT}${originspec}${COLOR_RESET}): Already had ${COLOR_PORT}${dep_originspec}${COLOR_RESET}, not enqueueing into ${COLOR_PORT}${queue}${COLOR_RESET} (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
			return 0
		fi
		# The package isn't queued but is needed and already known.
		# That means we did a 'metadata' lookup hack on it already.
		# Ensure we process it.
	fi

	msg_debug "gather_port_vars_process_depqueue_enqueue (${COLOR_PORT}${originspec}${COLOR_RESET}): Adding ${COLOR_PORT}${dep_originspec}${COLOR_RESET} into the ${queue} (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
	# Another worker may have created it
	if mkdir "${queue}/${dep_originspec%/*}!${dep_originspec#*/}" \
	    2>&${fd_devnull}; then
		originspec_decode "${originspec}" origin '' ''

		echo "${rdep}" > \
		    "${queue}/${dep_originspec%/*}!${dep_originspec#*/}/rdep"
	fi
}

gather_port_vars_process_depqueue() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "gather_port_vars_process_depqueue requires SHASH_VAR_PATH=var/cache"
	required_env gather_port_vars_process_depqueue PWD "${MASTER_DATADIR_ABS}"
	[ $# -eq 1 ] || eargs gather_port_vars_process_depqueue originspec
	local originspec="$1"
	local origin pkgname deps dep_origin
	local dep_args dep_originspec dep_flavor queue rdep
	local fd_devnull

	msg_debug "gather_port_vars_process_depqueue (${COLOR_PORT}${originspec}${COLOR_RESET})"

	# Add all of this origin's deps into the gatherqueue to reprocess
	shash_get originspec-pkgname "${originspec}" pkgname || \
	    err 1 "gather_port_vars_process_depqueue failed to find pkgname for origin ${COLOR_PORT}${originspec}${COLOR_RESET}"
	shash_get pkgname-deps "${pkgname}" deps || \
	    err 1 "gather_port_vars_process_depqueue failed to find deps for pkg ${COLOR_PORT}${pkgname}${COLOR_RESET}"

	# Open /dev/null in case gather_port_vars_process_depqueue_enqueue
	# uses it, to avoid opening for every dependency.
	if [ -n "${deps}" ]; then
		exec 5>/dev/null
		fd_devnull=5
	fi

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

			msg_debug "Want to enqueue default ${COLOR_PORT}${dep_origin}${COLOR_RESET} rdep=${COLOR_PORT}${rdep}${COLOR_RESET} into ${queue}"
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
			msg_debug "Want to enqueue ${COLOR_PORT}${dep_originspec}${COLOR_RESET} rdep=${COLOR_PORT}${origin}${COLOR_RESET} into ${queue}"
			gather_port_vars_process_depqueue_enqueue \
			    "${originspec}" "${dep_originspec}" "${queue}" \
			    "${originspec}"
		fi
	done

	if [ -n "${deps}" ]; then
		exec 5>&-
		unset fd_devnull
	fi
}


compute_deps() {
	local pkgname originspec dep_pkgname _ignored

	msg "Calculating ports order and dependencies"
	bset status "computingdeps:"
	run_hook compute_deps start

	:> "${MASTER_DATADIR}/pkg_deps.unsorted"

	clear_dep_fatal_error
	parallel_start
	while mapfile_read_loop "${MASTER_DATADIR}/all_pkgs" \
	    pkgname originspec _ignored; do
		parallel_run compute_deps_pkg "${pkgname}" "${originspec}" \
		    "${MASTER_DATADIR}/pkg_deps.unsorted" || set_dep_fatal_error
	done
	if ! parallel_stop || check_dep_fatal_error; then
		err 1 "Fatal errors encountered calculating dependencies"
	fi

	sort -u "${MASTER_DATADIR}/pkg_deps.unsorted" \
	    > "${MASTER_DATADIR}/pkg_deps"
	unlink "${MASTER_DATADIR}/pkg_deps.unsorted"

	bset status "computingrdeps:"
	pkgqueue_compute_rdeps
	find deps rdeps > "pkg_pool"

	run_hook compute_deps stop
	return 0
}

compute_deps_pkg() {
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err 1 "compute_deps_pkg requires SHASH_VAR_PATH=var/cache"
	[ $# -eq 3 ] || eargs compute_deps_pkg pkgname originspec pkg_deps
	local pkgname="$1"
	local originspec="$2"
	local pkg_deps="$3"
	local deps dep_pkgname dep_originspec dep_origin dep_flavor
	local raw_deps d key dpath dep_real_pkgname err_type

	# Safe to remove pkgname-deps now, it won't be needed later.
	shash_remove pkgname-deps "${pkgname}" deps || \
	    err 1 "compute_deps_pkg failed to find deps for ${COLOR_PORT}${pkgname}${COLOR_RESET}"

	if shash_exists pkgname-ignore "${pkgname}"; then
		msg_debug "compute_deps_pkg: Will not build IGNORED ${COLOR_PORT}${pkgname}${COLOR_RESET} nor queue its deps"
		return
	fi
	msg_debug "compute_deps_pkg: Will build ${COLOR_PORT}${pkgname}${COLOR_RESET}"
	pkgqueue_add "${pkgname}" || \
	    err 1 "compute_deps_pkg: Error creating queue entry for ${COLOR_PORT}${pkgname}${COLOR_RESET}: There may be a duplicate origin in a category Makefile"

	for dep_originspec in ${deps}; do
		if ! get_pkgname_from_originspec "${dep_originspec}" \
		    dep_pkgname; then
			originspec_decode "${dep_originspec}" dep_origin '' \
			    dep_flavor
			if [ ${ALL} -eq 0 ]; then
				msg_error "compute_deps_pkg failed to lookup pkgname for ${COLOR_PORT}${dep_originspec}${COLOR_RESET} processing package ${COLOR_PORT}${pkgname}${COLOR_RESET} from ${COLOR_PORT}${originspec}${COLOR_RESET} -- Does ${COLOR_PORT}${dep_origin}${COLOR_RESET} provide the '${dep_flavor}' FLAVOR?"
			else
				msg_error "compute_deps_pkg failed to lookup pkgname for ${COLOR_PORT}${dep_originspec}${COLOR_RESET} processing package ${COLOR_PORT}${pkgname}${COLOR_RESET} from ${COLOR_PORT}${originspec}${COLOR_RESET} -- Is SUBDIR+=${COLOR_PORT}${dep_originspec#*/}${COLOR_RESET} missing in ${COLOR_PORT}${dep_originspec%/*}${COLOR_RESET}/Makefile and does the port provide the '${dep_flavor}' FLAVOR?"
			fi
			set_dep_fatal_error
			continue
		fi
		msg_debug "compute_deps_pkg: Will build ${COLOR_PORT}${dep_originspec}${COLOR_RESET} for ${COLOR_PORT}${pkgname}${COLOR_RESET}"
		pkgqueue_add_dep "${pkgname}" "${dep_pkgname}"
		echo "${pkgname} ${dep_pkgname}"
		if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
			# Cache for call later in this func
			hash_set compute_deps_originspec-pkgname \
			    "${dep_originspec}" "${dep_pkgname}"
		fi
	done >> "${pkg_deps}"

	# Check for invalid PKGNAME dependencies which break later incremental
	# 'new dependency' detection.  This is done here rather than
	# delete_old_pkgs since that only covers existing packages, but we
	# need to detect the problem for all new package builds.
	if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
		if [ "${BAD_PKGNAME_DEPS_ARE_FATAL}" = "yes" ]; then
			err_type="msg_error"
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
				if [ -z "${dpath}" ]; then
					msg_error "Invalid dependency line for ${COLOR_PORT}${pkgname}${COLOR_RESET}: ${d}"
					set_dep_fatal_error
					continue
				fi
				if ! hash_get \
				    compute_deps_originspec-pkgname \
				    "${dpath}" dep_real_pkgname; then
					msg_error "compute_deps_pkg failed to lookup PKGNAME for ${COLOR_PORT}${dpath}${COLOR_RESET} processing package ${COLOR_PORT}${pkgname}${COLOR_RESET}"
					set_dep_fatal_error
					continue
				fi
				case "${dep_real_pkgname%-*}" in
				"${dep_pkgname}") ;;
				*)
					${err_type} "${COLOR_PORT}${originspec}${COLOR_WARN} dependency on ${COLOR_PORT}${dpath}${COLOR_WARN} has wrong PKGNAME of '${dep_pkgname}' but should be '${dep_real_pkgname%-*}'"
					if [ \
					    "${BAD_PKGNAME_DEPS_ARE_FATAL}" = \
					    "yes" ]; then
						set_dep_fatal_error
						continue
					fi
					;;
				esac
				;;
			*) ;;
			esac
		done
	fi

	return 0
}

test_port_origin_exist() {
	[ $# -eq 1 ] || eargs test_port_origin_exist origin
	local _origin="$1"
	local o

	for o in ${OVERLAYS}; do
		if [ -d "${MASTERMNTREL}${OVERLAYSDIR:?}/${o}/${_origin}" ]; then
			return 0
		fi
	done
	if [ -d "${MASTERMNTREL}/${PORTSDIR:?}/${_origin}" ]; then
		return 0
	fi
	return 1
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
	local pymaster_prefix

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
	mapped_origin="${origin%%${pyreg}*}/${pymaster_prefix}${origin#*${pyreg}}"
	# Verify the port even exists or else we need a special case above.
	test_port_origin_exist "${mapped_origin}" || \
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
		_listed_ports "$@" | \
		    while mapfile_read_loop_redir originspec; do
			map_py_slave_port "${originspec}" originspec || :
			echo "${originspec}"
		done
		return
	fi
	_listed_ports "$@"
}

_list_ports_dir() {
	[ $# -eq 2 ] || eargs _list_ports_dir ptdir overlay
	local ptdir="$1"
	local overlay="$2"
	local cat

	# skip overlays with no categories listed
	if [ ! -f "${ptdir}/Makefile" ]; then
		return 0
	fi
	(
		cd "${ptdir}"
		ptdir="."
		for cat in $(awk -F= '$1 ~ /^[[:space:]]*SUBDIR[[:space:]]*\+/ {gsub(/[[:space:]]/, "", $2); print $2}' "${ptdir}/Makefile"); do
			# skip overlays with no ports hooked to the build
			[ -f "${ptdir}/${cat}/Makefile" ] || continue
			awk -F= -v cat=${cat} '$1 ~ /^[[:space:]]*SUBDIR[[:space:]]*\+/ {gsub(/[[:space:]]/, "", $2); print cat"/"$2}' "${ptdir}/${cat}/Makefile"
		done | while mapfile_read_loop_redir origin; do
			if ! [ -d "${ptdir:?}/${origin}" ]; then
				msg_warn "Nonexistent origin listed in category Makefiles in \"${overlay}\": ${COLOR_PORT}${origin}${COLOR_RESET} (skipping)"
				continue
			fi
			echo "${origin}"
		done
	)
}

_listed_ports() {
	local tell_moved="${1}"
	local portsdir origin file o mnt

	if [ ${ALL} -eq 1 ]; then
		_pget portsdir ${PTNAME:?} mnt || \
		    err 1 "Missing mnt metadata for portstree"
		if [ -d "${portsdir}/ports" ]; then
			portsdir="${portsdir}/ports"
		fi
		{
			_list_ports_dir "${portsdir}" "${PTNAME:?}"
			for o in ${OVERLAYS}; do
				_pget portsdir "${o}" mnt
				_list_ports_dir "${portsdir}" "${o}"
			done
		} | {
			# Sort but only if there's OVERLAYS to avoid
			# needless slowdown for pipelining otherwise.
			if [ -n "${OVERLAYS}" ]; then
				sort -ud
			else
				cat -u
			fi
		}
		return 0
	fi

	{
		# -f specified
		if [ -n "${LISTPKGS-}" ]; then
			local _ignore_comments

			for file in ${LISTPKGS}; do
				while mapfile_read_loop "${file}" origin \
				    _ignore_comments; do
					# Skip blank lines and comments
					if [ -z "${origin%%#*}" ]; then
						continue
					fi
					# Remove excess slashes for mistakes
					origin="${origin#/}"
					echo "${origin%/}"
				done
			done
		elif [ -n "${LISTPORTS-}" ]; then
			# Ports specified on cmdline
			for origin in ${LISTPORTS}; do
				# Remove excess slashes for mistakes
				origin="${origin#/}"
				echo "${origin%/}"
			done
		fi
	} | sort -u | while mapfile_read_loop_redir originspec; do
		originspec_decode "${originspec}" origin '' flavor
		if [ -n "${flavor}" ] && ! have_ports_feature FLAVORS; then
			msg_error "Trying to build FLAVOR-specific ${originspec} but ports tree has no FLAVORS support."
			set_dep_fatal_error
			continue
		fi
		origin_listed="${origin}"
		if shash_get origin-moved "${origin}" new_origin; then
			if [ "${new_origin%% *}" = "EXPIRED" ]; then
				msg_error "MOVED: ${origin} ${new_origin}"
				set_dep_fatal_error
				continue
			fi
			originspec="${new_origin}"
			originspec_decode "${originspec}" origin '' flavor
		else
			unset new_origin
		fi
		if ! test_port_origin_exist "${origin}"; then
			msg_error "Nonexistent origin listed: ${COLOR_PORT}${origin_listed}${new_origin:+${COLOR_RESET} (moved to nonexistent ${COLOR_PORT}${new_origin}${COLOR_RESET})}"
			set_dep_fatal_error
			continue
		fi
		if [ -n "${tell_moved}" ] && [ -n "${new_origin}" ]; then
			msg_warn \
			    "MOVED: ${COLOR_PORT}${origin_listed}${COLOR_RESET} renamed to ${COLOR_PORT}${new_origin}${COLOR_RESET}"
		fi
		echo "${originspec}"
	done
}

listed_pkgnames() {
	awk '$3 == "listed" { print $1 }' "${MASTER_DATADIR}/all_pkgs"
}

# Pkgname was in queue
pkgname_is_queued() {
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
	    }' "${MASTER_DATADIR}/all_pkgs"
}

# Pkgname was listed to be built
pkgname_is_listed() {
	[ $# -eq 1 ] || eargs pkgname_is_listed pkgname
	local pkgname="$1"

	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi

	awk -vpkgname="${pkgname}" '
	    $3 == "listed" && $1 == pkgname {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTER_DATADIR}/all_pkgs"
}

# PKGBASE was requested to be built, or is needed by a port requested to be built
pkgbase_is_needed() {
	[ $# -eq 1 ] || eargs pkgbase_is_needed pkgname
	local pkgname="$1"
	local pkgbase

	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi

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
	    }' "${MASTER_DATADIR}/all_pkgbases"
}

pkgbase_is_needed_and_not_ignored() {
	[ $# -eq 1 ] || eargs pkgbase_is_needed_and_not_ignored pkgname
	local pkgname="$1"
	local pkgbase

	# We check on PKGBASE rather than PKGNAME from pkg_deps
	# since the caller may be passing in a different version
	# compared to what is in the queue to build for.
	pkgbase="${pkgname%-*}"

	awk -vpkgbase="${pkgbase}" '
	    {sub(/-[^-]*$/, "", $1)}
	    $1 == pkgbase {
               if (NF < 4)
                   found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTER_DATADIR}/all_pkgs"
}


ignored_packages() {
	[ $# -eq 0 ] || eargs ignored_packages

	awk 'NF >= 4' "${MASTER_DATADIR}/all_pkgs"
}

# Port was requested to be built, or is needed by a port requested to be built
originspec_is_needed_and_not_ignored() {
       [ $# -eq 1 ] || eargs originspec_is_needed_and_not_ignored originspec
       local originspec="$1"

       awk -voriginspec="${originspec}" '
           $2 == originspec {
               if (NF < 4)
                   found=1
               exit 0
           }
           END {
               if (found != 1)
                       exit 1
           }' "${MASTER_DATADIR}/all_pkgs"
}

get_porttesting() {
	[ $# -eq 1 ] || eargs get_porttesting pkgname
	local pkgname="$1"
	local porttesting

	porttesting=0
	if [ "${PORTTESTING}" -eq 1 ]; then
		if [ ${ALL} -eq 1 -o ${PORTTESTING_RECURSIVE} -eq 1 ]; then
			porttesting=1
		elif pkgname_is_listed "${pkgname}"; then
			porttesting=1
		fi
	fi
	echo "${porttesting}"
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
	if [ "${SCRIPTNAME}" != "distclean.sh" ]; then
		[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
		    err 1 "load_moved requires SHASH_VAR_PATH=var/cache"
	fi
	[ -f ${MASTERMNT}${PORTSDIR}/MOVED ] || return 0
	msg "Loading MOVED for ${MASTERMNT}${PORTSDIR}"
	bset status "loading_moved:"
	local movedfiles o

	{
		echo "${MASTERMNT}${PORTSDIR}/MOVED"
		for o in ${OVERLAYS}; do
			test -f "${MASTERMNT}${OVERLAYSDIR}/${o}/MOVED" || continue
			echo "${MASTERMNT}${OVERLAYSDIR}/${o}/MOVED"
		done
	} | \
	xargs cat | \
	awk -f ${AWKPREFIX}/parse_MOVED.awk | \
	while mapfile_read_loop_redir old_origin new_origin; do
		# new_origin may be EXPIRED followed by the reason
		# or only a new origin.
		shash_set origin-moved "${old_origin}" "${new_origin}"
	done
}

fetch_global_port_vars() {
	local git_hash git_modified git_dirty

	was_a_testport_run && [ -n "${P_PORTS_FEATURES}" ] && return 0
	# Before we start, determine the default PYTHON version to
	# deal with any use of DEPENDS_ARGS involving it.  DEPENDS_ARGS
	# was a hack only actually used for python ports.
	port_var_fetch '' \
	    'USES=python' \
	    PORTS_FEATURES P_PORTS_FEATURES \
	    PKG_NOCOMPRESS:Dyes P_PKG_NOCOMPRESS \
	    PKG_ORIGIN P_PKG_ORIGIN \
	    PKG_SUFX P_PKG_SUFX \
	    UID_FILES P_UID_FILES \
	    PYTHON_MAJOR_VER P_PYTHON_MAJOR_VER \
	    PYTHON_DEFAULT_VERSION P_PYTHON_DEFAULT_VERSION \
	    PYTHON3_DEFAULT P_PYTHON3_DEFAULT || \
	    err 1 "Error looking up pre-build ports vars"
	port_var_fetch "${P_PKG_ORIGIN}" \
	    PKGNAME P_PKG_PKGNAME \
	    PKGBASE P_PKG_PKGBASE \
	# Ensure not blank so -z checks work properly
	if [ -z "${P_PORTS_FEATURES}" ]; then
		P_PORTS_FEATURES="none"
	fi
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
	if [ "${P_PORTS_FEATURES}" != "none" ]; then
		msg "Ports supports: ${P_PORTS_FEATURES}"
	fi
	export P_PORTS_FEATURES P_PYTHON_MAJOR_VER P_PYTHON_DEFAULT_VERSION \
	    P_PYTHON3_DEFAULT

	if was_a_bulk_run && [ -x "${GIT_CMD}" ] &&
	    ${GIT_CMD} -C "${MASTERMNT}/${PORTSDIR}" rev-parse \
	    --show-toplevel >/dev/null 2>&1; then
		git_hash=$(${GIT_CMD} -C "${MASTERMNT}/${PORTSDIR}" log -1 \
		    --format=%h .)
		shash_set ports_metadata top_git_hash "${git_hash}"
		git_modified=no
		msg_n "Inspecting ports tree for modifications to git checkout..."
		if git_tree_dirty "${MASTERMNT}/${PORTSDIR}" 0; then
			git_modified=yes
			git_dirty="(dirty)"
		fi
		echo " ${git_modified}"
		shash_set ports_metadata top_unclean "${git_modified}"
		msg "Ports top-level git hash: ${git_hash} ${git_dirty}"
	fi
}

git_tree_dirty() {
	[ $# -eq 2 ] || eargs git_tree_dirty git_dir inport
	local git_dir="$1"
	local inport="$2"
	local file

	if ! ${GIT_CMD} -C "${git_dir}" \
	    -c core.checkStat=minimal \
	    -c core.fileMode=off \
	    diff --quiet .; then
		return 0
	fi

	${GIT_CMD} -C "${git_dir}" ls-files --directory --others . | (
	# Look for patches and .local files
		while read file; do
			if [ "${inport}" -eq 0 ]; then
				case "${file}" in
				Makefile.local|\
				*/Makefile.local|\
				*/*/Makefile.local)
					return 0
					;;
				*/*/files/*)
					case "${file}" in
					# Mk/Scripts/do-patch.sh
					*.orig|*.rej|*~|*,v) ;;
					*) return 0 ;;
					esac
					;;
				esac
			else
				case "${file}" in
				Makefile.local)
					return 0
					;;
				files/*)
					case "${file}" in
					# Mk/Scripts/do-patch.sh
					*.orig|*.rej|*~|*,v) ;;
					*) return 0 ;;
					esac
					;;
				esac
			fi
		done
		return 1
	)
}

trim_ignored() {
	[ $# -eq 0 ] || eargs trim_ignored
	local pkgname originspec _rdep ignore

	bset status "trimming_ignore:"
	msg "Trimming IGNORED and blacklisted ports"

	ignored_packages | while mapfile_read_loop_redir pkgname originspec \
	    _rdep ignore; do
		trim_ignored_pkg "${pkgname}" "${originspec}" "${ignore}"
	done
	# Update ignored/skipped stats
	update_stats 2>/dev/null || :
	update_stats_queued
}

trim_ignored_pkg() {
	[ $# -eq 3 ] || eargs trim_ignored_pkg pkgname originspec ignore
	local pkgname="$1"
	local originspec="$2"
	local ignore="$3"
	local origin flavor logfile

	originspec_decode "${originspec}" origin '' flavor
	COLOR_ARROW="${COLOR_IGNORE}" \
	    msg "${COLOR_IGNORE}Ignoring ${COLOR_PORT}${origin}${flavor:+@${flavor}} | ${pkgname}${COLOR_IGNORE}: ${ignore}"
	_logfile logfile "${pkgname}"
	{
		buildlog_start "${pkgname}" "${originspec}"
		print_phase_header "check-sanity"
		echo "Ignoring: ${ignore}"
		print_phase_footer
		buildlog_stop "${pkgname}" "${originspec}" 0
	} | write_atomic "${logfile}"
	badd ports.ignored "${originspec} ${pkgname} ${ignore}"
	run_hook pkgbuild ignored "${origin}" "${pkgname}" "${ignore}"
	clean_pool "${pkgname}" "${originspec}" "ignored"
}

# PWD will be MASTER_DATADIR after this
prepare_ports() {
	local pkg
	local log log_top
	local n resuming_build
	local cache_dir sflag delete_pkg_list shash_bucket

	pkgqueue_init

	cd "${MASTER_DATADIR}"
	[ "${SHASH_VAR_PATH}" = "var/cache" ] || \
	    err ${EX_SOFTWARE} "SHASH_VAR_PATH failed to be relpath updated"
	# Allow caching values now
	USE_CACHE_CALL=1

	if was_a_bulk_run; then
		_log_path log
		_log_path_top log_top

		if [ -e "${log}/.poudriere.ports.built" ]; then
			resuming_build=1
		else
			resuming_build=0
		fi

		# Fetch library list for later comparisons
		if [ "${CHECK_CHANGED_DEPS}" != "no" ]; then
			CHANGED_DEPS_LIBLIST=$(injail \
			    ldconfig -r | \
			    awk '$1 ~ /:-l/ { gsub(/.*-l/, "", $1); printf("%s ",$1) } END { printf("\n") }')
		fi

		if [ ${resuming_build} -eq 0 ] || ! [ -d "${log}" ]; then
			get_cache_dir cache_dir
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
			if [ -d ${MASTERMNT}${PORTSDIR}/.svn ]; then
				bset svn_url $(
				${SVN_CMD} info ${MASTERMNT}${PORTSDIR} | awk '
					/^URL: / {URL=substr($0, 6)}
					/Revision: / {REVISION=substr($0, 11)}
					END { print URL "@" REVISION }
				')
			fi

			bset mastername "${MASTERNAME}"
			bset jailname "${JAILNAME}"
			bset setname "${SETNAME}"
			bset ptname "${PTNAME}"
			bset buildname "${BUILDNAME}"
			bset started "${EPOCH_START}"
		fi

		show_log_info
		if [ ${HTML_JSON_UPDATE_INTERVAL} -ne 0 ]; then
			coprocess_start html_json
		else
			msg "HTML UI updates are disabled by HTML_JSON_UPDATE_INTERVAL being 0"
		fi
	fi

	load_moved
	load_blacklist "${MASTERNAME}" "${PTNAME}" "${SETNAME}"

	fetch_global_port_vars || \
	    err 1 "Failed to lookup global ports metadata"

	PKG_EXT="${P_PKG_SUFX#.}"
	PKG_BIN="/${DATADIR_NAME}/pkg-static"
	PKG_ADD="${PKG_BIN} add"
	PKG_DELETE="${PKG_BIN} delete -y -f"
	PKG_VERSION="${PKG_BIN} version"

	if [ -n "${PKG_REPO_SIGNING_KEY}" ] &&
	    ! [ -f "${PKG_REPO_SIGNING_KEY}" ]; then
		err 1 "PKG_REPO_SIGNING_KEY defined but the file is missing."
	fi

	gather_port_vars

	compute_deps

	bset status "sanity:"

	if was_a_bulk_run; then
		# Migrate packages to new sufx
		maybe_migrate_packages
		# Stash dependency graph
		cp -f "${MASTER_DATADIR}/pkg_deps" "${log}/.poudriere.pkg_deps%"
		cp -f "${MASTER_DATADIR}/pkg_pool" \
		    "${log}/.poudriere.pkg_pool%"
		cp -f "${MASTER_DATADIR}/all_pkgs" "${log}/.poudriere.all_pkgs%"

		if [ -f "${PACKAGES}/.jailversion" ] &&
		    [ "$(cat ${PACKAGES}/.jailversion)" != \
		    "$(jget ${JAILNAME} version)" ]; then
			delete_all_pkgs "newer version of jail"
		fi
		if [ ${CLEAN} -eq 1 ]; then
			if [ "${ATOMIC_PACKAGE_REPOSITORY}" != "yes" ] && \
			    package_dir_exists_and_has_packages; then
				confirm_if_tty "Are you sure you want to clean all packages?" || \
				    err 1 "Not cleaning all packages"
			fi
			delete_all_pkgs "-c specified"
		fi
		if [ ${CLEAN_LISTED} -eq 1 ]; then
			msg "-C specified, cleaning listed packages"
			delete_pkg_list=$(mktemp -t poudriere.cleanC)
			clear_dep_fatal_error
			listed_pkgnames | while mapfile_read_loop_redir \
			    pkgname; do
				pkg="${PACKAGES}/All/${pkgname}.${PKG_EXT}"
				if [ -f "${pkg}" ]; then
					if shash_exists pkgname-ignore \
					    "${pkgname}"; then
						continue
					fi
					msg "(-C) Will delete existing package: ${pkg##*/}"
					delete_pkg_xargs "${delete_pkg_list}" \
					    "${pkg}"
					if [ -L "${pkg%.*}.txz" ]; then
						delete_pkg_xargs \
						    "${delete_pkg_list}" \
						    "${pkg%.*}.txz"
					fi
				fi
			done
			check_dep_fatal_error && \
			    err 1 "Error processing -C packages"
			if [ "${ATOMIC_PACKAGE_REPOSITORY}" != "yes" ] && \
			    [ -s "${delete_pkg_list}" ]; then
				confirm_if_tty "Are you sure you want to delete the listed packages?" || \
				    err 1 "Not cleaning packages"
			fi
			msg "(-C) Flushing package deletions"
			cat "${delete_pkg_list}" | tr '\n' '\000' | \
			    xargs -0 rm -rf
			unlink "${delete_pkg_list}" || :
		fi
		if ! ensure_pkg_installed; then
			delete_all_pkgs "pkg package missing"
		fi

		# If the build is being resumed then packages already
		# built/failed/skipped/ignored should not be rebuilt.
		if [ ${resuming_build} -eq 1 ]; then
			awk '{print $2}' \
			    ${log}/.poudriere.ports.built \
			    ${log}/.poudriere.ports.failed \
			    ${log}/.poudriere.ports.ignored \
			    ${log}/.poudriere.ports.fetched \
			    ${log}/.poudriere.ports.skipped | \
			    pkgqueue_remove_many_pipe
		else
			# New build
			bset stats_queued 0
			bset stats_built 0
			bset stats_failed 0
			bset stats_ignored 0
			bset stats_skipped 0
			bset stats_fetched 0
			:> ${log}/.data.json
			:> ${log}/.data.mini.json
			:> ${log}/.poudriere.ports.built
			:> ${log}/.poudriere.ports.failed
			:> ${log}/.poudriere.ports.ignored
			:> ${log}/.poudriere.ports.skipped
			:> ${log}/.poudriere.ports.fetched
			trim_ignored
		fi
		download_from_repo
		bset status "sanity:"
	fi

	msg "Sanity checking the repository"

	for n in \
	    meta.${PKG_EXT} meta.txz \
	    digests.${PKG_EXT} digests.txz \
	    filesite.${PKG_EXT} filesite.txz \
	    packagesite.${PKG_EXT} packagesite.txz; do
		pkg="${PACKAGES}/All/${n}"
		if [ -f "${pkg}" ]; then
			msg "Removing invalid pkg repo file: ${pkg}"
			unlink "${pkg}"
		fi

	done

	delete_stale_pkg_cache

	# Skip incremental build for pkgclean
	if was_a_bulk_run; then
		install -lsr "${log}" "${PACKAGES}/logs"

		if ensure_pkg_installed; then
			P_PKG_ABI="$(injail ${PKG_BIN} config ABI)" || \
			    err 1 "Failure looking up pkg ABI"
		fi
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
		download_from_repo_post_delete
		bset status "sanity:"

		# Cleanup cached data that is no longer needed.
		(
			cd "${SHASH_VAR_PATH}"
			for shash_bucket in \
			    origin-moved \
			    pkgname-ignore \
			    pkgname-options \
			    pkgname-run_deps \
			    pkgname-lib_deps \
			    pkgname-flavors; do
				shash_remove_var "${shash_bucket}" || :
			done
		)
	fi

	export LOCALBASE=${LOCALBASE:-/usr/local}

	pkgqueue_unqueue_existing_packages
	pkgqueue_trim_orphaned_build_deps

	if was_a_bulk_run && [ "${resuming_build}" -eq 0 ]; then
		# Update again after trimming the build queue
		update_stats_queued
	fi

	# Call the deadlock code as non-fatal which will check for cycles
	msg "Sanity checking build queue"
	bset status "pkgqueue_sanity_check:"
	pkgqueue_sanity_check 0

	if was_a_bulk_run; then
		if [ "${resuming_build}" -eq 0 ]; then
			# Generate ports.queued list after the queue was
			# trimmed.
			local _originspec _pkgname _rdep _ignore

			while mapfile_read_loop "${MASTER_DATADIR}/all_pkgs" \
			    _pkgname _originspec _rdep _ignore; do
				if [ "${_rdep}" = "listed" ] || \
				    pkgqueue_contains "${_pkgname}"; then
					echo "${_originspec} ${_pkgname} ${_rdep}"
				fi
			done | sort | \
			    write_atomic "${log}/.poudriere.ports.queued"
		fi

		load_priorities

		# Avoid messing with the queue for DRY_RUN or it confuses
		# the dry run summary output as it doesn't know about
		# the ready-to-build pool dir.
		if [ "${DRY_RUN}" -eq 0 ]; then
			pkgqueue_move_ready_to_pool
			msg "Balancing pool"
			balance_pool
		fi

		if [ "${ALLOW_MAKE_JOBS-}" != "yes" ]; then
			echo "DISABLE_MAKE_JOBS=poudriere" \
			    >> ${MASTERMNT}/etc/make.conf
		fi
		# Don't leak ports-env UID as it conflicts with BUILD_AS_NON_ROOT
		if [ "${BUILD_AS_NON_ROOT}" = "yes" ]; then
			sed -i '' '/^UID=0$/d' "${MASTERMNT}/etc/make.conf"
			sed -i '' '/^GID=0$/d' "${MASTERMNT}/etc/make.conf"
			# Will handle manually for now on until build_port.
			export UID=0
			export GID=0
		fi

		jget ${JAILNAME} version > "${PACKAGES}/.jailversion" || \
		    err 1 "Missing version metadata for jail"
		echo "${BUILDNAME}" > "${PACKAGES}/.buildname"

	fi
	unset P_PYTHON_MAJOR_VER P_PYTHON_DEFAULT_VERSION P_PYTHON3_DEFAULT

	return 0
}

load_priorities_ptsort() {
	local priority pkgname originspec pkg_boost origin flavor _ignored
	local - # Keep set -f local

	set -f # for PRIORITY_BOOST

	awk '{print $2 " " $1}' "${MASTER_DATADIR}/pkg_deps" \
	    > "${MASTER_DATADIR}/pkg_deps.ptsort"

	# Add in boosts before running ptsort
	while mapfile_read_loop "${MASTER_DATADIR}/all_pkgs" \
	    pkgname originspec _ignored; do
		# Does this pkg have an override?
		for pkg_boost in ${PRIORITY_BOOST}; do
			case ${pkgname%-*} in
			${pkg_boost})
				pkgqueue_contains "${pkgname}" || \
				    continue
				originspec_decode "${originspec}" \
				    origin '' ''
				msg "Boosting priority: ${COLOR_PORT}${origin}${flavor:+@${flavor}} | ${pkgname}"
				echo "${pkgname} ${PRIORITY_BOOST_VALUE}" >> \
				    "${MASTER_DATADIR}/pkg_deps.ptsort"
				break
				;;
			esac
		done
	done

	ptsort -p "${MASTER_DATADIR}/pkg_deps.ptsort" > \
	    "${MASTER_DATADIR}/pkg_deps.priority"
	unlink "${MASTER_DATADIR}/pkg_deps.ptsort"

	# Read all priorities into the "priority" hash
	while mapfile_read_loop "${MASTER_DATADIR}/pkg_deps.priority" \
	    priority pkgname; do
		hash_set "priority" "${pkgname}" ${priority}
	done

	return 0
}

load_priorities() {
	msg "Processing PRIORITY_BOOST"
	bset status "load_priorities:"

	load_priorities_ptsort

	# Create buckets to satisfy the dependency chain priorities.
	POOL_BUCKET_DIRS=$(awk '{print $1}' \
	    "${MASTER_DATADIR}/pkg_deps.priority"|sort -run)

	# If there are no buckets then everything to build will fall
	# into 0 as they depend on nothing and nothing depends on them.
	# I.e., pkg-devel in -ac or testport on something with no deps
	# needed.
	if [ -z "${POOL_BUCKET_DIRS}" ]; then
		POOL_BUCKET_DIRS="0"
	fi

	# Create buckets after loading priorities in case of boosts.
	( cd "${MASTER_DATADIR}/pool" && mkdir ${POOL_BUCKET_DIRS} )

	# unbalanced is where everything starts at.  Items are moved in
	# balance_pool based on their priority in the "priority" hash.
	POOL_BUCKET_DIRS="${POOL_BUCKET_DIRS} unbalanced"

	return 0
}

balance_pool() {
	required_env balance_pool PWD "${MASTER_DATADIR_ABS}"

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

	bset ${MY_JOBID} status "balancing_pool:"

	# For everything ready-to-build...
	for pkg_dir in pool/unbalanced/*; do
		# May be empty due to racing with pkgqueue_get_next()
		case "${pkg_dir}" in
			"pool/unbalanced/*") break ;;
		esac
		pkgname=${pkg_dir##*/}
		hash_remove "priority" "${pkgname}" dep_count || dep_count=0
		# This races with pkgqueue_get_next(), just ignore failure
		# to move it.
		rename "${pkg_dir}" \
		    "pool/${dep_count}/${pkgname}" || :
	done 2>/dev/null
	# New files may have been added in unbalanced/ via pkgqueue_done() due
	# to not being locked. These will be picked up in the next run.

	rmdir ${lock}
}

append_make() {
	[ $# -eq 3 ] || eargs append_make srcdir src_makeconf dst_makeconf
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
	if grep -q "# ${src_makeconf} #" ${dst_makeconf}; then
		return 0
	fi
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
				[ -r "${listpkg_name}" ] ||
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
	local o

	msg "Cleaning restricted packages"
	bset status "clean_restricted:"
	remount_packages -o rw
	injail /usr/bin/make -s -C ${PORTSDIR} -j ${PARALLEL_JOBS} \
	    RM="/bin/rm -fv" ECHO_MSG="true" clean-restricted
	for o in ${OVERLAYS}; do
		injail /usr/bin/make -s -C "${OVERLAYSDIR}/${o}" \
		    -j ${PARALLEL_JOBS} \
		    RM="/bin/rm -fv" ECHO_MSG="true" clean-restricted
	done
	remount_packages -o ro
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
	local origin pkg_repo_list_files

	msg "Creating pkg repository"
	if [ ${DRY_RUN} -eq 1 ]; then
		return 0
	fi
	bset status "pkgrepo:"
	ensure_pkg_installed force_extract || \
	    err 1 "Unable to extract pkg."
	if [ "${PKG_REPO_LIST_FILES}" = "yes" ]; then
		pkg_repo_list_files="--list-files"
	fi
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
		injail ${PKG_BIN} repo \
			${pkg_repo_list_files} \
			-o /tmp/packages \
			${PKG_META} \
			/packages /tmp/repo.key
		unlink ${MASTERMNT}/tmp/repo.key
	elif [ "${PKG_REPO_FROM_HOST:-no}" = "yes" ]; then
		# Sometimes building repo from host is needed if
		# using SSH with DNSSEC as older hosts don't support
		# it.
		${MASTERMNT}${PKG_BIN} repo \
		    ${pkg_repo_list_files} \
		    -o ${MASTERMNT}/tmp/packages ${PKG_META_MASTERMNT} \
		    ${MASTERMNT}/packages \
		    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
	else
		JNETNAME="n" injail ${PKG_BIN} repo \
		    ${pkg_repo_list_files} \
		    -o /tmp/packages ${PKG_META} /packages \
		    ${SIGNING_COMMAND:+signing_command: ${SIGNING_COMMAND}}
	fi
	cp ${MASTERMNT}/tmp/packages/* ${PACKAGES}/

	# Sign the ports-mgmt/pkg package for bootstrap
	if [ -e "${PACKAGES}/Latest/pkg.${PKG_EXT}" ]; then
		if [ -n "${SIGNING_COMMAND}" ]; then
			sign_pkg fingerprint "${PACKAGES}/Latest/pkg.${PKG_EXT}"
		elif [ -n "${PKG_REPO_SIGNING_KEY}" ]; then
			sign_pkg pubkey "${PACKAGES}/Latest/pkg.${PKG_EXT}"
		fi
	fi
}

calculate_size_in_mb() {
	local calc_var="$1"
	local calc_size

	getvar "$calc_var" calc_size

	case ${calc_size} in
	*p)
		calc_size=${calc_size%p}
		calc_size=$(( calc_size << 10 ))
		;&
	*t)
		calc_size=${calc_size%t}
		calc_size=$(( calc_size << 10 ))
		;&
	*g)
		calc_size=${calc_size%g}
		calc_size=$(( calc_size << 10 ))
		;&
	*m)
		calc_size=${calc_size%m}
	esac

	setvar "$calc_var" "$calc_size"
}

calculate_ospart_size() {
	# How many partitions do we need
	local NUM_PART="$1"
	# size of the image in MB
	local FULL_SIZE="$2"
	# size of the /cfg partition
	local CFG_SIZE="$3"
	# size of the Data partition
	local DATA_SIZE="$4"
	# size of the swap partition
	local SWAP_SIZE="$5"

	if [ -n "${CFG_SIZE}" ]; then
		calculate_size_in_mb CFG_SIZE
	else
		CFG_SIZE=0
	fi
	if [ -n "${DATA_SIZE}" ]; then
		calculate_size_in_mb DATA_SIZE
	else
		DATA_SIZE=0
	fi
	if [ -n "${SWAP_SIZE}" ]; then
		calculate_size_in_mb SWAP_SIZE
	else
		SWAP_SIZE=0
	fi
	
	OS_SIZE=$(( ( FULL_SIZE - CFG_SIZE - DATA_SIZE - SWAP_SIZE ) / NUM_PART ))
	msg "OS Partiton size: ${OS_SIZE}m"
}

svn_git_checkout_method() {
	[ $# -eq 7 ] || eargs svn_git_checkout_method SOURCES_URL METHOD \
	   SVN_URL_DEFAULT GIT_URL_DEFAULT \
           METHOD_var SVN_FULLURL_var GIT_FULLURL_var
	local SOURCES_URL="$1"
	local _METHOD="$2"
	local SVN_URL_DEFAULT="$3"
	local GIT_URL_DEFAULT="$4"
	local METHOD_var="$5"
	local SVN_FULLURL_var="$6"
	local GIT_FULLURL_var="$7"
	local _SVN_FULLURL _GIT_FULLURL
	local proto url_prefix=

	if [ -n "${SOURCES_URL}" ]; then
		case "${_METHOD}" in
		svn*)
			case "${SOURCES_URL}" in
			http://*) _METHOD="svn+http" ;;
			https://*) _METHOD="svn+https" ;;
			file://*) _METHOD="svn+file" ;;
			svn+ssh://*) _METHOD="svn+ssh" ;;
			svn://*) _METHOD="svn" ;;
			*)
				msg_error "Invalid svn url"
				return 1
				;;
			esac
			;;
		git*)
			case "${SOURCES_URL}" in
			ssh://*) _METHOD="git+ssh" ;;
			http://*) _METHOD="git+http" ;;
			https://*) _METHOD="git+https" ;;
			file://*) _METHOD="git+file" ;;
			git://*) _METHOD="git" ;;
			/*) _METHOD="git+file" ;;
			*://*) err 1 "Invalid git protocol" ;;
			*:*) _METHOD="git+ssh" ;;
			*)
				msg_error "Invalid git url"
				return 1
				;;
			esac
			;;
		*)
			msg_error "-U only valid with git and svn methods"
			return 1
			;;
		esac
		_SVN_FULLURL="${SOURCES_URL}"
		_GIT_FULLURL="${SOURCES_URL}"
	else
		# Compat hacks for FreeBSD's special git server
		case "${GIT_URL_DEFAULT}" in
		${FREEBSD_GIT_BASEURL}|${FREEBSD_GIT_PORTSURL})
			case "${_METHOD}" in
			git+ssh) url_prefix="${FREEBSD_GIT_SSH_USER}@" ;;
			git) msg_warn "As of 2021-04-08 FreeBSD's git server does not support the git protocol.  Remove -m or try git+https or git+ssh." ;;
			esac
			;;
		*) ;;
		esac
		case "${_METHOD}" in
		svn+http) proto="http" ;;
		svn+https) proto="https" ;;
		svn+ssh) proto="svn+ssh" ;;
		svn+file) proto="file" ;;
		svn) proto="svn" ;;
		git+ssh) proto="ssh" ;;
		git+http) proto="http" ;;
		git+https) proto="https" ;;
		git+file) proto="file" ;;
		git) proto="git" ;;
		*)
			return 1
			;;
		esac
		_SVN_FULLURL="${proto}://${SVN_URL_DEFAULT}"
		_GIT_FULLURL="${proto}://${url_prefix}${GIT_URL_DEFAULT}"
	fi
	setvar "${METHOD_var}" "${_METHOD}"
	setvar "${SVN_FULLURL_var}" "${_SVN_FULLURL}"
	setvar "${GIT_FULLURL_var}" "${_GIT_FULLURL}"
}

# Builtin-only functions
_BUILTIN_ONLY=""
for _var in ${_BUILTIN_ONLY}; do
	if ! [ "$(type ${_var} 2>/dev/null)" = \
		"${_var} is a shell builtin" ]; then
		eval "${_var}() { return 0; }"
	fi
done
unset _BUILTIN_ONLY
if [ "$(type setproctitle 2>/dev/null)" = "setproctitle is a shell builtin" ]; then
	setproctitle() {
		PROC_TITLE="$@"
		command setproctitle "poudriere${MASTERNAME:+[${MASTERNAME}]}${MY_JOBID:+[${MY_JOBID}]}: $*"
	}
else
	setproctitle() { :; }
fi

STATUS=0 # out of jail #
if [ ${IN_TEST:-0} -eq 0 ]; then
	# cd into / to avoid foot-shooting if running from deleted dirs or
	# NFS dir which root has no access to.
	SAVED_PWD="${PWD}"
	cd /tmp
fi

. ${SCRIPTPREFIX}/include/colors.pre.sh
if [ -z "${POUDRIERE_ETC}" ]; then
	POUDRIERE_ETC=$(realpath ${SCRIPTPREFIX}/../../etc)
fi
# If this is a relative path, add in ${PWD} as a cd / is done.
if [ "${POUDRIERE_ETC#/}" = "${POUDRIERE_ETC}" ]; then
	POUDRIERE_ETC="${SAVED_PWD:?}/${POUDRIERE_ETC}"
fi
POUDRIERED=${POUDRIERE_ETC}/poudriere.d
include_poudriere_confs "$@"

AWKPREFIX=${SCRIPTPREFIX}/awk
HTMLPREFIX=${SCRIPTPREFIX}/html
HOOKDIR=${POUDRIERED}/hooks

# If the zfs module is not loaded it means we can't have zfs
[ -z "${NO_ZFS}" ] && lsvfs zfs >/dev/null 2>&1 || NO_ZFS=yes
# Short circuit to prevent running zpool(1) and loading zfs.ko
[ -z "${NO_ZFS}" ] && [ -z "$(zpool list -H -o name 2>/dev/null)" ] && NO_ZFS=yes

[ -z "${NO_ZFS}" -a -z "${ZPOOL}" ] && err 1 "ZPOOL variable is not set"
[ -z "${BASEFS}" ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"

trap sigpipe_handler PIPE
trap sigint_handler INT
trap sighup_handler HUP
trap sigterm_handler TERM
trap exit_handler EXIT
enable_siginfo_handler() {
	was_a_bulk_run && trap siginfo_handler INFO
	in_siginfo_handler=0
	return 0
}
enable_siginfo_handler

# Test if zpool exists
if [ -z "${NO_ZFS}" ]; then
	zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
fi

: ${FREEBSD_SVN_HOST:="svn.FreeBSD.org"}
: ${FREEBSD_GIT_HOST:="git.FreeBSD.org"}
: ${FREEBSD_GIT_BASEURL:="${FREEBSD_GIT_HOST}/src.git"}
: ${FREEBSD_GIT_PORTSURL:="${FREEBSD_GIT_HOST}/ports.git"}
: ${FREEBSD_HOST:="https://download.FreeBSD.org"}
: ${FREEBSD_GIT_SSH_USER="anongit"}

: ${SVN_HOST:="${FREEBSD_SVN_HOST}"}
: ${GIT_HOST:="${FREEBSD_GIT_HOST}"}
: ${GIT_BASEURL:=${FREEBSD_GIT_BASEURL}}
# GIT_URL is old compat
: ${GIT_PORTSURL:=${GIT_URL:-${FREEBSD_GIT_PORTSURL}}}

if [ -z "${NO_ZFS}" ]; then
	: ${ZROOTFS="/poudriere"}
	case ${ZROOTFS} in
	[!/]*) err 1 "ZROOTFS should start with a /" ;;
	esac
fi

HOST_OSVERSION="$(sysctl -n kern.osreldate 2>/dev/null || echo 0)"
if [ -z "${NO_ZFS}" -a -z "${ZFS_DEADLOCK_IGNORED}" ]; then
	[ ${HOST_OSVERSION} -gt 900000 -a \
	    ${HOST_OSVERSION} -le 901502 ] && err 1 \
	    "FreeBSD 9.1 ZFS is not safe. It is known to deadlock and cause system hang. Either upgrade the host or set ZFS_DEADLOCK_IGNORED=yes in poudriere.conf"
fi

: ${USE_TMPFS:=no}
if [ -n "${MFSSIZE}" -a "${USE_TMPFS}" != "no" ]; then
	err 1 "You can't use both tmpfs and mdmfs"
fi

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
unset val

# Backwards compat for renamed IMMUTABLE_BASE
if [ -n "${MUTABLE_BASE-}" ] && [ -z "${IMMUTABLE_BASE-}" ]; then
	for val in ${MUTABLE_BASE}; do
		case ${val} in
			schg|nullfs)	IMMUTABLE_BASE="${val}" ;;
			yes)		IMMUTABLE_BASE="no" ;;
			no)		IMMUTABLE_BASE="yes" ;;
			*) err 1 "Unknown value for MUTABLE_BASE" ;;
		esac
		msg_warn "MUTABLE_BASE=${val} is deprecated. Change to IMMUTABLE_BASE=${IMMUTABLE_BASE}"
	done
fi

for val in ${IMMUTABLE_BASE-}; do
	case ${val} in
		schg|no|nullfs) ;;
		yes) IMMUTABLE_BASE="schg" ;;
		*) err 1 "Unknown value for IMMUTABLE_BASE" ;;
	esac
done

case ${TMPFS_WRKDIR}${TMPFS_DATA}${TMPFS_LOCALBASE}${TMPFS_ALL} in
1**1|*1*1|**11)
	TMPFS_WRKDIR=0
	TMPFS_DATA=0
	TMPFS_LOCALBASE=0
	;;
esac

if [ -e "${BASEFS}" ]; then
	BASEFS=$(realpath "${BASEFS}")
fi
POUDRIERE_DATA="$(get_data_dir)"
if [ -e "${POUDRIERE_DATA}" ]; then
	POUDRIERE_DATA=$(realpath "${POUDRIERE_DATA}")
fi
: ${WRKDIR_ARCHIVE_FORMAT="tbz"}
case "${WRKDIR_ARCHIVE_FORMAT}" in
	tar|tgz|tbz|txz|tzst);;
	*) err 1 "invalid format for WRKDIR_ARCHIVE_FORMAT: ${WRKDIR_ARCHIVE_FORMAT}" ;;
esac

#Converting portstree if any
if [ ! -d ${POUDRIERED}/ports ]; then
	mkdir -p ${POUDRIERED}/ports
	if [ -z "${NO_ZFS}" ]; then
		zfs list -t filesystem -H \
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
	fi
	if [ -f ${POUDRIERED}/portstrees ]; then
		while read name method mnt; do
			if [ -z "${name###*}" ]; then
				continue # Skip comments
			fi
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
	if [ -z "${NO_ZFS}" ]; then
		zfs list -t filesystem -H \
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
fi

: ${LOIP6:=::1}
: ${LOIP4:=127.0.0.1}
# If in a nested jail we may not even have a loopback to use.
if [ "${JAILED:-0}" -eq 1 ]; then
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
: ${PORTBUILD_GROUP:=${PORTBUILD_USER}}
# CCACHE_GID defaults to PORTBUILD_GID in jail_start()
: ${CCACHE_GROUP:=${PORTBUILD_GROUP}}
: ${CCACHE_DIR_NON_ROOT_SAFE:=no}
if [ -n "${CCACHE_DIR}" ] && [ "${CCACHE_DIR_NON_ROOT_SAFE}" = "no" ]; then
	if [ "${BUILD_AS_NON_ROOT}" = "yes" ]; then
		msg_warn "BUILD_AS_NON_ROOT and CCACHE_DIR are potentially incompatible.  Disabling BUILD_AS_NON_ROOT"
		msg_warn "Either disable one or, set CCACHE_DIR_NON_ROOT_SAFE=yes and do the following procedure _on the host_."
		cat >&2 <<-EOF

		## Summary of https://ccache.dev/manual/3.7.11.html#_sharing_a_cache
	        	# pw groupadd portbuild -g 65532
	        	# pw useradd portbuild -u 65532 -g portbuild -d /nonexistent -s /usr/sbin/nologin
	        	# pw groupmod -n portbuild -m root
	        	# echo "umask = 0002" >> ${CCACHE_DIR}/ccache.conf
	        	# find ${CCACHE_DIR}/ -type d -exec chmod 2775 {} +
	        	# find ${CCACHE_DIR}/ -type f -exec chmod 0664 {} +
	        	# chown -R :portbuild ${CCACHE_DIR}/
	        	# chmod 1777 ${CCACHE_DIR}/tmp

		## If a separate group is wanted:
	        	# pw groupadd ccache -g 65531
	        	# pw groupmod -n cacche -m root
	        	# chown -R :ccache ${CCACHE_DIR}/

		## poudriere.conf
	        	CCACHE_DIR_NON_ROOT_SAFE=yes
	        	CCACHE_GROUP=ccache
	        	CCACHE_GID=65531
		EOF
		err ${EX_DATAERR} "BUILD_AS_NON_ROOT + CCACHE_DIR manual action required."
	fi
	# Default off with CCACHE_DIR.
	: ${BUILD_AS_NON_ROOT:=no}
fi
: ${CCACHE_JAIL_PREFIX:=/ccache}
# Default on otherwise.
: ${BUILD_AS_NON_ROOT:=yes}
: ${DISTFILES_CACHE:=/nonexistent}
: ${SVN_CMD:=$(which svn 2>/dev/null || which svnlite 2>/dev/null)}
: ${GIT_CMD:=$(which git 2>/dev/null)}
: ${BINMISC:=/usr/sbin/binmiscctl}
: ${PATCHED_FS_KERNEL:=no}
: ${ALL:=0}
: ${CLEAN:=0}
: ${CLEAN_LISTED:=0}
: ${VERBOSE:=0}
: ${QEMU_EMULATING:=0}
: ${PORTTESTING:=0}
: ${PORTTESTING_FATAL:=yes}
: ${PORTTESTING_RECURSIVE:=0}
: ${PRIORITY_BOOST_VALUE:=99}
: ${RESTRICT_NETWORKING:=yes}
: ${DISALLOW_NETWORKING:=no}
: ${TRIM_ORPHANED_BUILD_DEPS:=yes}
: ${USE_JEXECD:=no}
: ${USE_PROCFS:=yes}
: ${USE_FDESCFS:=yes}
: ${IMMUTABLE_BASE:=no}
: ${PKG_REPO_LIST_FILES:=no}
: ${PKG_REPRODUCIBLE:=no}
: ${HTML_JSON_UPDATE_INTERVAL:=2}
: ${HTML_TRACK_REMAINING:=no}
: ${FORCE_MOUNT_HASH:=no}
: ${DELETE_UNQUEUED_PACKAGES:=no}
: ${DELETE_UNKNOWN_FILES:=yes}
DRY_RUN=0
INTERACTIVE_MODE=0

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
: ${NULLFS_PATHS:="/rescue /usr/share /usr/tests /usr/lib32"}
: ${PACKAGE_FETCH_URL:="pkg+http://pkg.FreeBSD.org/\${ABI}"}

: ${POUDRIERE_TMPDIR:=$(command mktemp -dt poudriere)}
: ${SHASH_VAR_PATH_DEFAULT:=${POUDRIERE_TMPDIR}}
: ${SHASH_VAR_PATH:=${SHASH_VAR_PATH_DEFAULT}}
: ${SHASH_VAR_PREFIX:=sh-}
: ${DATADIR_NAME:=".p"}

: ${USE_CACHED:=no}

: ${BUILDNAME_FORMAT:="%Y-%m-%d_%Hh%Mm%Ss"}
: ${BUILDNAME:=$(date +${BUILDNAME_FORMAT})}

: ${HTML_TYPE:=inline}
: ${LC_COLLATE:=C}
export LC_COLLATE

if [ -n "${MAX_MEMORY}" ]; then
	MAX_MEMORY_BYTES="$((MAX_MEMORY * 1024 * 1024 * 1024))"
fi
: ${MAX_FILES:=1024}
: ${DEFAULT_MAX_FILES:=${MAX_FILES}}
: ${DEP_FATAL_ERROR_FILE:=dep_fatal_error}
HAVE_FDESCFS=0
if [ "$(mount -t fdescfs | awk '$3 == "/dev/fd" {print $3}')" = "/dev/fd" ]; then
	HAVE_FDESCFS=1
fi

: ${OVERLAYSDIR:=/overlays}

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
. ${SCRIPTPREFIX}/include/pkg.sh
. ${SCRIPTPREFIX}/include/pkgqueue.sh

if [ -z "${LOIP6}" -a -z "${LOIP4}" ]; then
	msg_warn "No loopback address defined, consider setting LOIP6/LOIP4 or assigning a loopback address to the jail."
fi

if [ -e /nonexistent ]; then
	err 1 "You may not have a /nonexistent.  Please remove it."
fi

if [ "${USE_CACHED}" = "yes" ]; then
	err 1 "USE_CACHED=yes is not supported."
fi
