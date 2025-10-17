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

EX_USAGE=64
EX_DATAERR=65
EX_SOFTWARE=70
EX_IOERR=74

alias redirect_to_real_stdout='>&${OUTPUT_REDIRECTED_STDOUT:-1} '
alias redirect_to_real_stderr='2>&${OUTPUT_REDIRECTED_STDERR:-2} '
alias redirect_to_real_tty='redirect_to_real_stdout redirect_to_real_stderr '
alias redirect_to_bulk='redirect_to_real_tty '
MSG_FUNCS="
msg_verbose
msg_dev
msg_debug
job_msg_verbose
job_msg_status_verbose
job_msg_status_debug
job_msg_status_dev
job_msg_dev
job_msg_debug
"
# Alias the functions such that they can be disabled at runtime.
for msg_func in ${MSG_FUNCS}; do
	# Keep msg_assert_dev alias up-to-date too.
	alias "${msg_func}"="\${MSG_FUNC_${msg_func}-} _${msg_func}"
done
unset msg_func

case "$%$+${FUNCNAME-}" in
'$%$+') ;;
# Customization.
# $% = getpid()
# $+ = funcnest+loopnest
# $FUNCNAME is the current function
*) PS4='$%<$+>${FUNCNAME:+<${FUNCNAME}>}+ ' ;;
esac

. "${SCRIPTPREFIX:?}/include/asserts.sh"
if ! type err >/dev/null 2>&1; then
	# This function may be called in "$@" contexts that do not use eval.
	# eval is used here to avoid existing alias parsing issues.
	eval 'err() { _err "" "$@"; }'
	alias err="_err \"${_LINEINFO_DATA:?}\" ";
fi
BSDPLATFORM=`uname -s | tr '[:upper:]' '[:lower:]'`
. "${SCRIPTPREFIX:?}/include/common.sh.${BSDPLATFORM}"
. "${SCRIPTPREFIX:?}/include/hash.sh"
. "${SCRIPTPREFIX:?}/include/util.sh"
SHFLAGS="$-"

# Use builtin if possible.
cat() {
	# no flags are compat
	case "${1-}" in
	-*) ;;
	*)
		if have_builtin mapfile_cat_file; then
			mapfile_cat_file "$@" || return
			return 0
		fi
		;;
	esac
	command cat "$@"
}

# Return true if ran from bulk/testport, ie not daemon/status/jail
was_a_bulk_run() {
	case "${SCRIPTNAME:?}" in
	"bulk.sh") return 0;
	esac
	was_a_testport_run || return 1
}
was_a_testport_run() {
	case "${SCRIPTNAME:?}" in
	"testport.sh") return 0 ;;
	esac
	return 1
}
# Return true if in a bulk or other jail run that needs to shutdown the jail
was_a_jail_run() {
	if was_a_bulk_run; then
		return 0
	fi
	case "${SCRIPTNAME:?}" in
	foreachport.sh|\
	pkgclean.sh|\
	repo.sh|\
	:) return 0 ;;
	esac
	return 1
}
schg_immutable_base() {
	case "${IMMUTABLE_BASE}" in
	"schg") ;;
	*) return 1 ;;
	esac
	if [ ${TMPFS_ALL} -eq 0 ] && [ -z "${NO_ZFS}" ]; then
		return 1
	fi
	return 0
}
# Return true if output via msg() should show elapsed time
should_show_elapsed() {
	if [ "${IN_TEST:-0}" -eq 1 ]; then
		return 1
	fi
	case "${TIME_START-}" in
	"") return 1 ;;
	esac
	if [ "${NO_ELAPSED_IN_MSG:-0}" -ge 1 ]; then
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
	case "${os}" in
	"${BSDPLATFORM}")
		err 1 "This is not supported on ${BSDPLATFORM}: $*"
		;;
	esac
}

_err() {
	local -; set +e +u
	local lineinfo="${1-}"
	local exit_status="${2-}"
	local msg="${3-}"

	if [ -n "${CRASHED:-}" ]; then
		case "$#" in
		[012]) ;;
		*)
			shift 2
			msg="$*"
			;;
		esac
		echo "err: Recursive error detected: ${msg}" >&2 || :
		exit "${exit_status}"
	fi
	case "${SHFLAGS}" in
	*x*) ;;
	*) local -; set +x ;;
	esac
	trap '' INFO
	export CRASHED=1
	case "$#" in
	[012])
		msg_error "err expects 3 arguments: exit_number \"message\": actual: '$#': $*"
		exit ${EX_SOFTWARE}
		;;
	*)
		shift 2
		msg="$*"
		;;
	esac
	# Try to set status so other processes know this crashed
	# Don't set it from children failures though, only master
	case "${PARALLEL_CHILD:-0}" in
	0)
		bset ${MY_BUILDER_ID:+"${MY_BUILDER_ID}"} status \
		    "crashed:err:${msg}" || :
		;;
	esac
	case "${exit_status}" in
	0) msg "${msg}" ;;
	*)
		if use_debug; then
			lineinfo="${COLOR_ERROR}[$(getpid)${PROC_TITLE:+:${PROC_TITLE}}]${lineinfo:+ ${lineinfo}}${COLOR_RESET}"
		fi
		# hack for tests using SH=/bin/sh. See critical_retry().
		local msg_type
		case "${_CRITICAL_RETRY:-0}.${exit_status}" in
		1.143|1.130) msg_type=":" ;;
		*) msg_type="msg_error" ;;
		esac
		"${msg_type}" "${lineinfo:+${lineinfo}:}${msg}"
		;;
	esac || :
	case "${ERRORS_ARE_PIPE_FATAL:+set}${PARALLEL_CHILD:+set}" in
	*set*) set_pipe_fatal_error ;;
	esac
	# Avoid recursive err()->exit_handler()->err()... Just let
	# exit_handler() cleanup.
	case "${IN_EXIT_HANDLER:-0}" in
	1)
		case "${exit_status}" in
		1) EXIT_STATUS="${exit_status}" ;;
		esac
		return 0
		;;
	esac
	case "${ERRORS_ARE_FATAL:-1}" in
	1)
		if was_a_bulk_run &&
		    [ -n "${POUDRIERE_BUILD_TYPE-}" ] &&
		    [ "${PARALLEL_CHILD:-0}" -eq 0 ] &&
		    [ "$(getpid)" = "$$" ]; then
		{
			show_build_summary
			show_log_info
		} >&2
		fi
		exit "${exit_status}"
		;;
	esac
	CAUGHT_ERR_STATUS="${exit_status}"
	CAUGHT_ERR_MSG="${msg}"
	return "${exit_status}"
}

dev_err() {
	DEV_ERROR=1 err "$@"
}
if ! use_debug; then
	# This function may be called in "$@" contexts that do not use eval.
	dev_err() { :; }
	alias dev_err='# '
fi

# Message functions that depend on VERBOSE are stubbed out in post_getopts.

_msg_fmt_n() {
	local -; set +x
	local now elapsed
	local fmt="${1}"
	local nl="${2}"
	local arrow arrow2 DRY_MODE
	local fmt_prefix fmt_prefix2 fmt_prefix_nocol fmt_sufx
	shift 2

	if [ "${MSG_NESTED:-0}" -eq 1 ]; then
		unset elapsed arrow arrow2 DRY_MODE
	elif should_show_elapsed; then
		now=$(clock -monotonic)
		calculate_duration elapsed "$((now - ${TIME_START:-0}))"
		elapsed="[${elapsed}] "
		unset arrow
		arrow2="=>>>"
	else
		unset elapsed
		arrow="=>>"
		arrow2="=>>>"
	fi
	case "${COLOR_ARROW-}${1}" in
	*$'\033'"["*)
		# Need to insert a COLOR_RESET before the newline
		# for timestamp(1) or otherwise the timestamp gets
		# colored before the reset starts the next line.
		fmt_prefix="${elapsed:+${COLOR_ARROW-}${elapsed}${COLOR_RESET}}${DRY_MODE:+${COLOR_ARROW-}${DRY_MODE-}${COLOR_RESET}}${arrow:+${COLOR_ARROW-}${arrow} ${COLOR_RESET}}"
		fmt_prefix_nocol="${elapsed-}${DRY_MODE-}${arrow:+${arrow} }"
		#fmt_prefix2="${arrow2:+${COLOR_ARROW-}${arrow2} ${COLOR_RESET}}"
		fmt_prefix2=align
		fmt_sufx="${COLOR_RESET}"
		;;
	*)
		fmt_prefix="${elapsed-}${DRY_MODE-}${arrow:+${arrow} }"
		fmt_prefix_nocol=
		#fmt_prefix2="${arrow2:+${arrow2} }"
		fmt_prefix2=align
		fmt_sufx=
		;;
	esac
	# Add in prefix/sufx for subsequent lines if needed.
	case "${fmt_prefix2:+set}.${fmt_sufx:+set}" in
	".") ;;
	*)
		case "${fmt}" in
		*"\n"*)
			case "${fmt_prefix2}" in
			"align")
				# Fill in the 2nd line with blanks to align
				# with the first line.
				local fmt_prefix_blank

				_gsub "${fmt_prefix_nocol:-${fmt_prefix}}" \
				    "*" " " fmt_prefix_blank
				_gsub "${fmt}" "\n" \
				    "${fmt_sufx}\n${fmt_prefix_blank}" \
				    fmt
				;;
			*)
				# Use fmt_prefix2 as the prefix for
				# subsequent lines.
				_gsub "${fmt}" "\n" \
				    "${fmt_sufx}\n${fmt_prefix2}" \
				    fmt
				;;
			esac
			;;
		esac
		;;
	esac
	printf "${fmt_prefix}${fmt}${fmt_sufx}${nl}" "$@"
}

msg_fmt() {
	local -; set +x
	local fmt="$1"
	shift
	local nl

	# Need to split out the end newline for color handling in
	# _msg_fmt_n.
	case "${fmt}" in
	*"\n")
		fmt="${fmt%"\n"}"
		nl="\n"
		;;
	*)
		nl=
		;;
	esac
	_msg_fmt_n "${fmt}" "${nl}" "$@"
}

msg_n() {
	_msg_fmt_n "%s" '' "$*"
}

msg() {
	_msg_fmt_n "%s" "\n" "$*"
}

_msg_verbose() {
	msg "$*"
}

msg_error() {
	local -; set +x
	local MSG_NESTED
	local prefix

	prefix="${DEV_ERROR:+Dev }Error:"
	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	case "${MY_BUILDER_ID:+set}" in
	set)
		# Send colored msg to bulk log...
		COLOR_ARROW="${COLOR_ERROR}" \
		    redirect_to_bulk \
		    job_msg "${COLOR_ERROR}${prefix}${COLOR_RESET}" "$@" >&2
		# Needed hack for test output ordering
		if [ "${IN_TEST:-0}" -eq 1 -a -n "${TEE_SLEEP_TIME-}" ]; then
			sleep "${TEE_SLEEP_TIME}"
		fi
		# And non-colored to buld log
		msg "${prefix}" "$@" >&2
		;;
	*)
		# Send to true stderr
		COLOR_ARROW="${COLOR_ERROR}" \
		    redirect_to_bulk \
		    msg "${COLOR_ERROR}${prefix}${COLOR_RESET}" "$@" >&2
		;;
	esac
	return 0
}

_msg_dev() {
	local -; set +x
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_DEV}" \
	    msg "${COLOR_DEV}[$(getpid)] Dev:${COLOR_RESET} $*" >&2
}

_msg_debug() {
	local -; set +x
	local MSG_NESTED

	MSG_NESTED="${MSG_NESTED_STDERR:-0}"
	COLOR_ARROW="${COLOR_DEBUG}" \
	    msg "${COLOR_DEBUG}Debug:${COLOR_RESET} $*" >&2
}

msg_warn() {
	local -; set +x
	local MSG_NESTED MSG_NESTED_STDERR prefix

	: "${MSG_NESTED_STDERR:=0}"
	MSG_NESTED="${MSG_NESTED_STDERR}"
	if [ "${MSG_NESTED_STDERR}" -eq 0 ]; then
		prefix="Warning:"
	else
		unset prefix
	fi
	COLOR_ARROW="${COLOR_WARN}" \
	    msg "${prefix:+${COLOR_WARN}${prefix}${COLOR_RESET} }$*" >&2
}

job_msg() {
	local -; set +x
	local now elapsed NO_ELAPSED_IN_MSG output

	case "${MY_BUILDER_ID:+set}" in
	set)
		elapsed=
		if [ "${IN_TEST:-0}" -eq 0 ]; then
			NO_ELAPSED_IN_MSG="$((NO_ELAPSED_IN_MSG - 1))"
			now=$(clock -monotonic)
			calculate_duration elapsed "$((now - ${TIME_START_JOB:-${TIME_START:-0}}))"
		fi
		output="[${COLOR_JOBID-}${MY_BUILDER_ID}${COLOR_RESET}]${elapsed:+ [${elapsed}]}"
		;;
	*)
		unset output
		;;
	esac
	redirect_to_bulk msg "${output:+${output} }$*"
}

# Stubbed until post_getopts
_job_msg_verbose() {
	job_msg "$@"
}

: "${JOB_STATUS_TITLE_WIDTH:=10}"
job_msg_status() {
	[ "$#" -ge 3 ] ||
	    eargs job_msg_status msgfunc title originspec pkgname '[msg]...'
	local title="$1"
	local originspec="$2"
	local pkgname="$3"
	shift 3
	local msg="$*"
	local title_msg job_name msg_colored

	title_msg="${COLOR_ARROW-}$(printf "%-${JOB_STATUS_TITLE_WIDTH}s" "${title}")${COLOR_ARROW:+${COLOR_RESET}}"
	job_name="${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET}"
	msg_colored="${msg:+${COLOR_ARROW-}: ${msg}${COLOR_ARROW:+${COLOR_RESET}}}"
	job_msg "${title_msg} ${job_name}${msg_colored-}"
}

_job_msg_status_verbose() {
	job_msg_status "$@"
}

_job_msg_status_debug() {
	job_msg_status "$@"
}

_job_msg_status_dev() {
	job_msg_status "$@"
}

# These are aligned for 'Building msg'
_job_msg_dev() {
	COLOR_ARROW="${COLOR_DEV}" \
	    job_msg "${COLOR_DEV}Dev:     " "$@"
}

_job_msg_debug() {
	COLOR_ARROW="${COLOR_DEBUG}" \
	    job_msg "${COLOR_DEBUG}Debug: " "$@"
}

job_msg_warn() {
	COLOR_ARROW="${COLOR_WARN}" \
	    job_msg "${COLOR_WARN}Warning:" "$@"
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
nop() { :; }
post_getopts() {
	local msg_func level disable

	for msg_func in ${MSG_FUNCS}; do
		level="${msg_func##*_}"
		unset disable
		if ! msg_level "${level}"; then
			# Using ":" directly would be nice but it then
			# breaks "FOO=value msg..." as it becomes
			# "FOO-value : msg..." resulting in FOO being set
			# after still.
			disable="nop"
		fi
		setvar "MSG_FUNC_${msg_func}" ${disable:+"${disable}"}
	done
	return 0
}

msg_level() {
	[ $# -eq 1 ] || eargs msg_level level
	local level="$1"

	case "${level}" in
	*dev)		level=3 ;;
	*debug)		level=2 ;;
	*verbose)	level=1 ;;
	*)		level=0 ;;
	esac
	if [ "${VERBOSE:-0}" -ge "${level}" ]; then
		return 0
	fi
	return 1
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
	mnt="${POUDRIERE_DATA:?}/.m/${mastername}/ref"
	case "${NOLINUX:+set}" in
	"") testpath="/compat/linux/proc" ;;
	set) testpath="/var/db/ports" ;;
	esac
	mnttest="${mnt:?}${testpath}"

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
	setvar "$1" "${mnt:?}"
	MASTERMNTREL="${mnt:?}"
	add_relpath_var MASTERMNTREL
	# MASTERMNTROOT=
	setvar "${1}ROOT" "${mnt%/ref}"
}

_my_path() {
	local -; set -u +x

	case "${MY_BUILDER_ID:+set}" in
	"") setvar "$1" "${MASTERMNT:?}" ;;
	set)
		case "${MASTERMNTROOT:+set}" in
		set)
			setvar "$1" "${MASTERMNTROOT:?}/${MY_BUILDER_ID}"
			;;
		"")
			setvar "$1" "${MASTERMNT:?}/../${MY_BUILDER_ID}"
			;;
		esac
		;;
	esac
}

_my_name() {
	local -; set -u +x

	setvar "$1" "${MASTERNAME}${MY_BUILDER_ID:+-job-${MY_BUILDER_ID}}"
}

_logfile() {
	local -; set -u +x
	[ $# -eq 2 ] || eargs _logfile var_return pkgname
	local var_return="$1"
	local pkgname="$2"
	local _log _log_top _log_jail _latest_log _logfile

	_log_path _log
	_logfile="${_log:?}/logs/${pkgname:?}.log"
	if [ ! -r "${_logfile}" ]; then
		_log_path_top _log_top
		_log_path_jail _log_jail

		_latest_log="${_log_top:?}/latest-per-pkg/${pkgname%-*}/${pkgname##*-}"

		# These 4 operations can race with logclean which mitigates
		# the issue by looking for files older than 1 minute.

		# Make sure directory exists
		mkdir -p "${_log:?}/logs" \
		    "${_latest_log:?}" \
		    "${_log_jail:?}/latest-per-pkg"

		:> "${_logfile:?}"

		# Link to BUILD_TYPE/latest-per-pkg/PORTNAME/PKGVERSION/MASTERNAME.log
		ln -f "${_logfile}" "${_latest_log:?}/${MASTERNAME:?}.log"

		if slock_acquire -q "logs_latest-per-pkg" 60; then
			# Link to JAIL/latest-per-pkg/PKGNAME.log
			ln -f "${_logfile}" \
			    "${_log_jail:?}/latest-per-pkg/${pkgname:?}.log"
			slock_release "logs_latest-per-pkg"
		fi
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

	setvar "$1" "${POUDRIERE_DATA:?}/logs/${POUDRIERE_BUILD_TYPE:?}"
}

_log_path_jail() {
	local -; set -u +x
	local log_path_top

	_log_path_top log_path_top
	setvar "$1" "${log_path_top:?}/${MASTERNAME:?}"
}

_log_path() {
	local -; set -u +x
	local log_path_jail

	_log_path_jail log_path_jail
	setvar "$1" "${log_path_jail:?}/${BUILDNAME:?}"
}

_tmpfs_blacklist_tmpdir() {
	local -; set -u +x

	setvar "$1" "${TMPFS_BLACKLIST_TMPDIR:?}/wrkdirs/${MASTERNAME:?}/${BUILDNAME:?}"
}

# Call function with vars set:
# log MASTERNAME BUILDNAME jailname ptname setname
for_each_build() {
	required_env for_each_build \
	    BUILDNAME_GLOB! '' \
	    SHOW_FINISHED! ''
	[ $# -eq 1 ] || eargs for_each_build action
	local action="$1"
	local MASTERNAME BUILDNAME buildname jailname ptname setname
	local log_top ret

	POUDRIERE_BUILD_TYPE="bulk" _log_path_top log_top
	[ -d "${log_top:?}" ] || err 1 "Log path ${log_top} does not exist."
	cd "${log_top:?}"

	found_jobs=0
	ret=0
	for mastername in *; do
		# Check empty dir
		case "${mastername}" in
			"*") break ;;
		esac
		[ -L "${mastername:?}/latest" ] || continue
		MASTERNAME="${mastername:?}"
		case "${MASTERNAME}" in
		"latest-per-pkg") continue ;;
		esac
		if [ ${SHOW_FINISHED} -eq 0 ] && \
		    ! jail_runs "${MASTERNAME}"; then
			continue
		fi

		# Look for all wanted buildnames (will be 1 or Many(-a)))
		for buildname in "${mastername:?}/"${BUILDNAME_GLOB}; do
			case "${buildname}" in
			"${mastername}/${BUILDNAME_GLOB}")
				# No results ; but maybe an oddly named build?
				[ -e "${buildname:?}" ] || break
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
			buildname="${buildname#"${mastername}"/}"
			BUILDNAME="${buildname}"
			# Unset so later they can be checked for NULL (don't
			# want to lookup again if value looked up is empty
			unset jailname ptname setname
			# Try matching on any given JAILNAME/PTNAME/SETNAME,
			# and if any don't match skip this MASTERNAME entirely.
			# If the file is missing it's a legacy build, skip it
			# but not the entire mastername if it has a match.
			case "${JAILNAME:+set}" in
			set)
				if _bget jailname jailname; then
					case "${jailname:?}" in
					"${JAILNAME}") ;;
					*) continue 2 ;;
					esac
				else
					case "${MASTERNAME:?}" in
					"${JAILNAME}"-*) ;;
					*) continue 2 ;;
					esac
					continue
				fi
				;;
			esac
			case "${PTNAME:+set}" in
			set)
				if _bget ptname ptname; then
					case "${ptname}" in
					"${PTNAME}") ;;
					*) continue 2 ;;
					esac
				else
					case "${MASTERNAME}" in
					*"-${PTNAME}") ;;
					*) continue 2 ;;
					esac
					continue
				fi
				;;
			esac
			case "${SETNAME:+set}" in
			set)
				if _bget setname setname; then
					case "${setname}" in
					"${SETNAME%0}") ;;
					*) continue 2 ;;
					esac
				else
					case "${MASTERNAME}" in
					*"-${SETNAME%0}") ;;
					*) continue 2 ;;
					esac
					continue
				fi
				;;
			esac
			# Dereference latest into actual buildname
			case "${buildname}" in
			"latest-done")
				_bget BUILDNAME buildname
				;;
			"latest")
				_bget BUILDNAME buildname
				;;
			esac
			# May be blank if build is still starting up
			case "${BUILDNAME}" in
			"") continue 2 ;;
			esac

			found_jobs=$((found_jobs + 1))

			# Lookup jailname/setname/ptname if needed. Delayed
			# from earlier for performance for -a
			case "${jailname+null}" in
			"") _bget jailname jailname || : ;;
			esac
			case "${setname+null}" in
			"") _bget setname setname || : ;;
			esac
			case "${ptname+null}" in
			"") _bget ptname ptname || : ;;
			esac
			log="${mastername:?}/${BUILDNAME:?}"

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
	cd "${OLDPWD}"
	return "${ret}"
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

	count_lines "${filelist:?}" file_cnt
	if [ "${file_cnt}" -eq 0 ]; then
		msg "No ${reason} to cleanup"
		return 2
	fi

	msg_n "Calculating size for found files..."
	hsize=$(cat "${filelist:?}" | \
	    tr '\n' '\000' | \
	    xargs -0 -J % find % -print0 | \
	    stat_humanize)
	echo " done"

	msg "These ${reason} will be deleted:"
	cat "${filelist:?}"
	count_lines "${filelist:?}" count
	msg "Removing these ${count} ${reason} will free: ${hsize}"

	if [ ${DRY_RUN} -eq 1 ];  then
		msg "Dry run: not cleaning anything."
		return 3
	fi

	case "${answer}" in
	"")
		if prompt "Proceed?"; then
			answer="yes"
		fi
		;;
	esac

	ret=0
	case "${answer}" in
	"yes")
		msg_n "Removing files..."
		remove_many_file "${filelist:?}" rm -rf ||
		    err 1 "Failed to delete files"
		echo " done"
		ret=1
		;;
	esac
	return ${ret}
}

setup_jexec_limits()  {
	[ $# -eq 1 ] || eargs setup_jexec_limits pkgbase
	local pkgbase="$1"
	local pkgbase_varname limit_var

	_gsub_var_name "${pkgbase:?}" pkgbase_varname
	for limit_var in EXECUTION_TIME FILES MEMORY; do
		if isset "MAX_${limit_var:?}_${pkgbase_varname:?}"; then
			getvar "MAX_${limit_var:?}_${pkgbase_varname:?}" \
			    MAX_${limit_var:?}
		fi
	done
	# Subtle but the `+set` rather than `:+set` allows
	# `MAX_type_pkgbase=` to override the global value.
	case "${MAX_MEMORY+set}${MAX_FILES+set}" in
	*set*)
		JEXEC_LIMITS=1
		;;
	esac
}

injail() {
	local -; set +x
	case "${DISALLOW_NETWORKING}" in
	"yes") local JNETNAME= ;;
	esac

	case "${INJAIL_HOST:-0}" in
	1)
		# For test/
		"$@" || return
		return
		;;
	esac
	injail_direct "$@"
}

injail_direct() {
	local name
	local MAX_MEMORY_BYTES MAX_FILES
	case "${DISALLOW_NETWORKING}" in
	"yes") local JNETNAME= ;;
	esac

	_my_name name
	case "${name}" in
	"") err 1 "No jail setup" ;;
	esac
	unset MAX_MEMORY_BYTES
	case "${JEXEC_LIMITS:-0}" in
	1)
		case "${MAX_MEMORY:+set}" in
		set)
			MAX_MEMORY_BYTES="$((MAX_MEMORY * 1024 * 1024 * 1024))"
			;;
		esac
		;;
	0)
		unset MAX_FILES
		;;
	esac
	${JEXEC_SETSID-} /usr/sbin/jexec \
		-U "${JUSER:-root}" \
		"${name:?}${JNETNAME:+-${JNETNAME}}" \
		${JEXEC_LIMITS+/usr/bin/limits} \
		${MAX_MEMORY_BYTES:+-v "${MAX_MEMORY_BYTES}"} \
		${MAX_FILES:+-n "${MAX_FILES}"} \
		"$@"
}

injail_tty() {
	redirect_to_real_tty injail_direct "$@"
}

jstart() {
	local mpath name network
	network="${LOCALIPARGS:?}"

	case "${RESTRICT_NETWORKING-}" in
	"yes") ;;
	*)
		network="${IPARGS:?} ${JAIL_NET_PARAMS-}"
		;;
	esac

	_my_name name

	mpath="${MASTERMNT:?}${MY_BUILDER_ID:+/../${MY_BUILDER_ID}}"
	echo "::1 ${name:?}" >> "${mpath:?}/etc/hosts"
	echo "127.0.0.1 ${name:?}" >> "${mpath:?}/etc/hosts"

	# Restrict to no networking (if RESTRICT_NETWORKING==yes)
	jail -c persist "name=${name:?}" \
		"path=${mpath:?}" \
		"host.hostname=${BUILDER_HOSTNAME-${name}}" \
		${network} ${JAIL_PARAMS-} ||
	    err 1 "jstart: Failed to start jail ${name:?}" \
		"${network:+network="'${network}'"}" \
		"${JAIL_PARAMS:+JAIL_PARAMS="'${JAIL_PARAMS}'"}"
	# Allow networking in -n jail
	jail -c persist "name=${name}-n" \
		"path=${mpath:?}" \
		"host.hostname=${BUILDER_HOSTNAME-${name}}" \
		${IPARGS:?} ${JAIL_PARAMS-} ${JAIL_NET_PARAMS-} ||
	    err 1 "jstart: Failed to start networking jail ${name:?}-n" \
		"${JAIL_PARAMS:+JAIL_PARAMS="'${JAIL_PARAMS}'"}" \
		"${IPARGS:+IPARGS='${IPARGS}'}" \
		"${JAIL_NET_PARAMS:+JAIL_NET_PARAMS="'${JAIL_NET_PARAMS}'"}"
	return 0
}

jail_has_processes() {
	case "${PROFILING:-no}" in
	yes)
		return 1
		;;
	esac
	local pscnt

	# 2 = HEADER+ps itself
	pscnt=2
	# Cannot use ps -J here as not all versions support it.
	if [ $(injail ps aux | wc -l) -ne ${pscnt} ]; then
		return 0
	fi
	return 1
}

jkill_wait() {
	case "${INJAIL_HOST:-0}" in
	1) err "${EX_SOFTWARE}" "jkill_wait: kill -9 -1 with INJAIL_HOST=${INJAIL_HOST}" ;;
	esac
	injail kill -9 -1 2>/dev/null || return 0
	while jail_has_processes; do
		sleep 1
		injail kill -9 -1 2>/dev/null || return 0
	done
}

# Kill everything in the jail and ensure it is free of any processes
# before returning.
jkill() {
	jkill_wait
	JNETNAME="n" jkill_wait
}

jstop() {
	local name

	_my_name name
	jail -r "${name:?}" 2>/dev/null || :
	jail -r "${name:?}-n" 2>/dev/null || :
}

eargs() {
	[ "$#" -ge 1 ] ||
		err 1 "Usage: eargs funcname named_var1 '[named_var...]' EARGS: \"\$@\""
	local fname="$1"
	# First set of args are the named vars expected.
	# Optionally then EARGS: values to assign for those vars.
	# Be sure to pass in $@ to match up vars properly.
	shift
	local var vars vars2 pre least max maxn cnt range gotargs val vals
	local namedvals var_sep
	local gotcnt got

	var_sep="@"
	gotargs=0
	least=0
	cnt=0
	unset max
	while [ "$#" -gt 0 ]; do
		case "$1" in
		"EARGS:")
			gotargs=1
			shift
			# "$*" is now caller's "$*"
			break
			;;
		*...*)
			max=inf
			maxn=999
			;;
		'['*) # Optional argument
			:
			;;
		*)
			least="$((least + 1))"
			;;
		esac
		vars="${vars:+${vars} }$1"
		vars2="${vars2:+${vars2}${var_sep:?}}$1"
		cnt="$((cnt + 1))"
		shift
	done
	: "${max:="${cnt}"}"
	: "${maxn:="${max}"}"
	case "${max}" in
	"${least}")
		range="${max}"
		;;
	*)
		range="${least}-${max}"
		;;
	esac
	# Match up named vars with values for display. This would be simpler
	# using any helper function but eargs should be independent.
	# Special care here to convey how $@ was grouped.
	# Match <named args> up with actual positional arguments in $@.
	gotcnt=0
	for val in "$@"; do
		gotcnt="$((gotcnt + 1))"
		case "${vars2}" in
		"")
			if [ "${gotcnt}" -gt "${maxn}" ]; then
				namedvals="${namedvals:+${namedvals}}\" ??=\"${val}"
			else
				# Last var to add in.
				namedvals="${namedvals:+${namedvals} }\"${val}"
			fi
			;;
		*)
			# Pop off first name
			var="${vars2%%"${var_sep:?}"*}"
			vars2="${vars2#"${var}${var_sep:?}"}"
			case "${var}" in
			"${vars2}") vars2= ;;
			esac
			# on new var need to open a quote
			namedvals="${namedvals:+${namedvals}\" }\"${val}"
			# XXX: clever but does not handle [] or -flags right
			# namedvals="${namedvals:+${namedvals}\" }${var}=\"${val}"
			;;
		esac
	done
	# Close last double quote.
	namedvals="${namedvals:+${namedvals}\"}"
	case "${gotargs}" in
	0)
		gotargs=
		got=
		;;
	1)
		got=", got $#"
		gotargs="${namedvals:+"$'\n'$'\t'"Received: ${fname} ${namedvals}}"
		# Missing vars
		case "${vars2}" in
		"") ;;
		*)
			# Need to reconvert vars2 from var_sep to spaces.
			local IFS -

			IFS="${var_sep:?}"
			set -o noglob
			# shellcheck disable=SC2086
			set -- ${vars2}
			set +o noglob
			unset IFS
			vars2="$*"
			gotargs="${gotargs:+${gotargs}}"$'\n'$'\t'"Missing:  ${vars2}"
			;;
		esac
		;;
	esac
	vars=$'\n'$'\t'"Expected: ${fname} ${vars}"
	case "${cnt}" in
	0)
		err ${EX_SOFTWARE} "${fname}: No arguments expected${got}:${vars}${gotargs}"
		;;
	1)
		err ${EX_SOFTWARE} "${fname}: 1 argument expected${got}:${vars}${gotargs}"
		;;
	*)
		err ${EX_SOFTWARE} "${fname}: ${range} arguments expected${got}:${vars}${gotargs}"
		;;
	esac
}

pkgbuild_done() {
	[ $# -eq 1 ] || eargs pkgbuild_done pkgname
	local pkgname="$1"
	local shash_bucket

	for shash_bucket in \
	    pkgname-check_shlibs \
	    pkgname-need_root \
	    pkgname-prefix \
	    pkgname-shlibs_required \
	    ; do
		shash_unset "${shash_bucket}" "${pkgname}" || :
	done
}

run_hook() {
	local -; set +x
	[ $# -ge 2 ] || eargs run_hook '[-v]' hook event args
	local flag OPTIND=1 vflag

	vflag=
	while getopts "v" flag; do
		case "${flag}" in
		v) vflag=1 ;;
		*) err "${EX_USAGE:-64}" "run_hook: Invalid flag" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -ge 2 ] || eargs run_hook '[-v]' hook event args
	local hook="$1"
	local event="$2"
	local build_url log log_url plugin_dir

	shift 2

	build_url build_url || :
	log_url log_url || :
	case "${POUDRIERE_BUILD_TYPE:+set}" in
	set)
		_log_path log || :
		;;
	esac

	run_hook_file ${vflag:+-v} \
	    "${HOOKDIR:?}/${hook}.sh" "${hook}" "${event}" \
	    "${build_url}" "${log_url}" "${log}" "$@"

	if [ -d "${HOOKDIR}/plugins" ]; then
		for plugin_dir in ${HOOKDIR}/plugins/*; do
			# Check empty dir
			case "${plugin_dir}" in
			"${HOOKDIR}/plugins/*") break ;;
			esac
			run_hook_file ${vflag:+-v} \
			    "${plugin_dir:?}/${hook}.sh" "${hook}" \
			    "${event}" "${build_url}" "${log_url}" "${log}" \
			    "$@"
		done
	fi
}

have_hook() {
	[ $# -eq 1 ] || eargs have_hook hookname
	local hook="$1"
	local plugin_dir

	if [ -r "${HOOKDIR:?}/${hook:?}.sh" ]; then
		return 0
	fi
	if [ -d "${HOOKDIR:?}/plugins" ]; then
		for plugin_dir in ${HOOKDIR:?}/plugins/*; do
			# Check empty dir
			case "${plugin_dir:?}" in
			"${HOOKDIR:?}/plugins/*") break ;;
			esac
			if [ -r "${plugin_dir:?}/${hook:?}.sh" ]; then
				return 0
			fi
		done
	fi
	return 1
}

run_hook_file() {
	[ $# -ge 6 ] ||
	    eargs run_hook_file '[-v]' hookfile hook event build_url \
	    log_url log args
	local flag OPTIND=1 vflag

	vflag=
	while getopts "v" flag; do
		case "${flag}" in
		v) vflag=1 ;;
		*) err "${EX_USAGE:-64}" "run_hook_file: Invalid flag" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -ge 6 ] ||
	    eargs run_hook_file '[-v]' hookfile hook event build_url \
	    log_url log args
	local hookfile="$1"
	local hook="$2"
	local event="$3"
	local build_url="$4"
	local log_url="$5"
	local log="$6"
	[ -f "${hookfile}" ] || return 0

	shift 6

	case "${vflag}" in
	1)
		msg "Running hook ${hookfile} for event '${hook}:${event}'"
		;;
	esac

	job_msg_dev "Running ${hookfile} for event '${hook}:${event}' args:" \
	    "$@"

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
		    MY_JOBID="${MY_BUILDER_ID-}" \
		    MY_BUILDER_ID="${MY_BUILDER_ID-}" \
		    BUILDNAME="${BUILDNAME-}" \
		    JAILNAME="${JAILNAME-}" \
		    PTNAME="${PTNAME-}" \
		    SETNAME="${SETNAME-}" \
		    PACKAGES="${PACKAGES-}" \
		    PACKAGES_ROOT="${PACKAGES_ROOT-}" \
		    VERBOSE="${VERBOSE:-0}" \
		    /bin/sh "${hookfile:?}" "${event}" "$@"
	) || err 1 "Hook ${hookfile} for '${hook}:${event}' returned non-zero"
	return 0
}

log_start() {
	[ $# -eq 2 ] || eargs log_start pkgname need_tee
	local pkgname="$1"
	local need_tee="$2"
	local logfile
	local -

	_logfile logfile "${pkgname}"

	critical_start
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
		set -m
		if [ ${need_tee} -eq 1 ]; then
			if [ "${TIMESTAMP_LOGS}" = "yes" ]; then
				# Unbuffered for 'echo -n' support.
				# Otherwise need setbuf -o L here due to
				# stdout not writing to terminal but to tee.
				TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
				    _spawn_wrapper \
				    timestamp -u ${TIMESTAMP_FLAGS-} \
				    < ${logfile}.pipe |
				    tee ${logfile} &
			else
				_spawn_wrapper \
				    tee ${logfile} < ${logfile}.pipe &
			fi
		elif [ "${TIMESTAMP_LOGS}" = "yes" ]; then
			TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
			    _spawn_wrapper \
			    timestamp ${TIMESTAMP_FLAGS-} \
			    > ${logfile} < ${logfile}.pipe &
		fi
		set +m
		madvise_protect "-$!" ||
		    err "1" "log_start: madvise_protect"
		get_job_id "$!" log_start_job
		msg_dev "log_start: spawned job %${log_start_job} pid=$!"
		exec > ${logfile}.pipe 2>&1

		# Remove fifo pipe file right away to avoid orphaning it.
		# The pipe will continue to work as long as we keep
		# the FD open to it.
		unlink ${logfile}.pipe
	else
		# Send output directly to file.
		unset log_start_job
		exec > ${logfile} 2>&1
	fi
	critical_end
}

_lookup_portdir() {
	[ $# -eq 2 ] || eargs _lookup_portdir var_return origin
	local _varname="$1"
	local _port="$2"
	local o _ptdir

	for o in ${OVERLAYS}; do
		_ptdir="${OVERLAYSDIR:?}/${o:?}/${_port:?}"
		if [ -r "${MASTERMNTREL?}${_ptdir:?}/Makefile" ]; then
			setvar "${_varname}" "${_ptdir}"
			return
		fi
	done
	_ptdir="${PORTSDIR:?}/${_port:?}"
	setvar "${_varname}" "${_ptdir}"
	return
}

get_times() {
	[ $# -eq 2 ] || eargs get_times reason elapsed
	local reason="$1"
	local elapsed="$2"
	local times
	local duration

	calculate_duration_times duration "${elapsed}"

	# times | read does not grab the proper info.
	{
		local n line which
		n=0
		while read -r line; do
			case "${n}" in
			0) which="shell" ;;
			1) which="child" ;;
			esac
			echo "times ${reason} [${which}]" \
			    "(user/sys/real): ${line} ${duration}"
			n="$((n + 1))"
		done
	} <<-EOF
	$(times)
	EOF
}

buildlog_start() {
	[ $# -eq 2 ] || eargs buildlog_start pkgname originspec
	local pkgname="$1"
	local originspec="$2"
	local mnt var portdir
	local make_vars date
	local git_modified git_hash
	local jname
	local wanted_vars="
	    MAINTAINER
	    PORTVERSION
	    PORTREVISION
	    CONFIGURE_ARGS
	    CONFIGURE_ENV
	    MAKE_ENV
	    PLIST_SUB
	    SUB_LIST
	    "

	_my_name jname
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

	echo "build started at $(date -Iseconds 2>/dev/null || date)"
	case "${PKG_REPRODUCIBLE}" in
	"yes") ;;
	*)
		date="$(date -u -Iseconds 2>/dev/null || date -u)"
		pkg_note_add "${pkgname}" build_timestamp "${date}"
		;;
	esac
	echo "port directory: ${portdir}"
	echo "package name: ${pkgname}"
	echo "building for: $(injail uname -a)"
	echo "maintained by: ${mk_MAINTAINER}"
	echo "port version: ${mk_PORTVERSION}"
	echo "port revision: ${mk_PORTREVISION}"
	echo "Makefile datestamp: $(stat -f %Sm "${mnt:?}/${portdir}/Makefile")"

	case "${NO_GIT:+set}" in
	"")
		if shash_get ports_metadata top_git_hash git_hash; then
			echo "Ports top last git commit: ${git_hash}"
			pkg_note_add "${pkgname}" ports_top_git_hash "${git_hash}"
			shash_get ports_metadata top_unclean git_modified
			pkg_note_add "${pkgname}" ports_top_checkout_unclean \
			    "${git_modified}"
			echo "Ports top unclean checkout: ${git_modified}"
		fi
		if git_get_hash_and_dirty "${MASTERMNT:?}/${portdir:?}" 1 \
		    "" git_modified; then
			pkg_note_add "${pkgname}" port_checkout_unclean "${git_modified}"
			echo "Port dir unclean checkout: ${git_modified}"
		fi
		;;
	esac
	echo "Poudriere version: ${POUDRIERE_PKGNAME}"
	case "${PKG_REPRODUCIBLE}" in
	"yes") ;;
	*)
		pkg_note_add "${pkgname}" built_by "${POUDRIERE_PKGNAME}"
		;;
	esac
	echo "Host OSVERSION: ${HOST_OSVERSION}"
	echo "Jail OSVERSION: ${JAIL_OSVERSION}"
	echo "Builder Id: ${MY_BUILDER_ID}"
	echo "Job Idx: ${MY_JOB_IDX}"
	echo "Jail Id (no networking)  : $(jls -j ${jname} jid || :)"
	echo "Jail Name (no networking): ${jname}"
	echo "Jail Id (networking)     : $(jls -j ${jname}-n jid || :)"
	echo "Jail Name (networking)   : ${jname}-n"
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
	cleanenv injail /usr/bin/env
	echo "---End Environment---"
	echo ""
	echo "---Begin Poudriere Port Flags/Env---"
	echo "PORT_FLAGS=${PORT_FLAGS}"
	echo "PKGENV=${PKGENV}"
	echo "FLAVOR=${FLAVOR}"
	echo "MAKE_ARGS=${MAKE_ARGS}"
	echo "---End Poudriere Port Flags/Env---"
	echo ""
	echo "---Begin OPTIONS List---"
	cleanenv injail /usr/bin/make -C "${portdir:?}" ${MAKE_ARGS} showconfig || :
	echo "---End OPTIONS List---"
	echo ""
	for var in ${wanted_vars}; do
		echo "--${var}--"
		eval "echo \"\${mk_${var}}\""
		echo "--End ${var}--"
		echo ""
	done
	echo "---Begin make.conf---"
	cat "${mnt:?}/etc/make.conf"
	echo "---End make.conf---"
	if [ -f "${mnt:?}/etc/make.nxb.conf" ]; then
		echo "---Begin make.nxb.conf---"
		cat "${mnt:?}/etc/make.nxb.conf"
		echo "---End make.nxb.conf---"
	fi

	echo "--Resource limits--"
	cleanenv injail /bin/sh -c "ulimit -a" || :
	echo "--End resource limits--"
	get_times "start" "$(($(clock -monotonic) - TIME_START))"
}

buildlog_stop() {
	[ $# -eq 3 ] || eargs buildlog_stop pkgname originspec build_failed
	local pkgname="$1"
	local originspec=$2
	local build_failed="$3"
	local log
	local now elapsed buildtime

	_log_path log

	echo "build of ${originspec} | ${pkgname} ended at" \
	    "$(date -Iseconds 2>/dev/null || date)"
	case "${TIME_START_JOB:+set}" in
	set)
		now=$(clock -monotonic)
		elapsed=$((now - TIME_START_JOB))
		calculate_duration buildtime "${elapsed}"
		echo "build time: ${buildtime}"
		get_times "end" "${elapsed}"
		;;
	esac
	if [ ${build_failed} -gt 0 ]; then
		echo "!!! build failure encountered !!!"
	fi
}

log_stop() {
	critical_start
	if [ ${OUTPUT_REDIRECTED:-0} -eq 1 ]; then
		dev_assert 3 "${OUTPUT_REDIRECTED_STDOUT}"
		dev_assert 4 "${OUTPUT_REDIRECTED_STDERR}"
		exec 1>&3 3>&- 2>&4 4>&-
		OUTPUT_REDIRECTED=0
		unset OUTPUT_REDIRECTED_STDOUT
		unset OUTPUT_REDIRECTED_STDERR
	fi
	case "${log_start_job:+set}" in
	set)
		timed_wait_and_kill_job 5 "%${log_start_job}"
		unset log_start_job
		;;
	esac
	critical_end
}

attr_set() {
	local type="$1"
	local name="$2"
	local property="$3"
	local dstfile
	shift 3

	dstfile="${POUDRIERED}/${type}/${name}/${property}"
	mkdir -p "${dstfile%/*}"
	write_atomic_cmp "${dstfile}" "$@" ||
	    err $? "attr_set failed to write to ${dstfile}"
}

jset() { attr_set jails "$@" ; }
pset() { attr_set ports "$@" ; }

_attr_get() {
	[ $# -eq 4 ] || eargs _attr_get var_return type name property
	local _ag_outvar="$1"
	local type="$2"
	local name="$3"
	local property="$4"

	read_file "${_ag_outvar}" \
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
	local _jg_outvar="$1"

	shift
	_attr_get "${_jg_outvar}" jails "$@"
}
pget() { attr_get ports "$@" ; }
_pget() {
	[ $# -eq 3 ] || eargs _pget var_return ptname property
	local _pg_outvar="$1"

	shift
	_attr_get "${_pg_outvar}" ports "$@"
}

#build getter/setter
_bget() {
	local -; set +x
	case "${POUDRIERE_BUILD_TYPE-}" in
	"") return 1 ;;
	esac
	local _bg_outvar id property mnt log file READ_FILE_USE_CAT file

	_bg_outvar="$1"
	_log_path log
	shift
	if [ $# -eq 2 ]; then
		id="$1"
		shift
	fi
	file=".poudriere.${1}${id:+.${id}}"

	# Use cat(1) to read long list files.
	case "${1}" in
	"ports."*)
		READ_FILE_USE_CAT=1
		;;
	esac

	read_file "${_bg_outvar}" "${log:?}/${file:?}"
}

bget() {
	local -; set +x
	case "${POUDRIERE_BUILD_TYPE-}" in
	"") return 1 ;;
	esac
	local bget_data
	if _bget bget_data "$@"; then
		case "${bget_data:+set}" in
		set) echo "${bget_data}" ;;
		esac
		return 0
	fi
	return 1
}

bset() {
	local -; set +x
	was_a_bulk_run || return 0
	case "${POUDRIERE_BUILD_TYPE-}" in
	"") return 1 ;;
	esac
	local id property mnt log file

	_log_path log
	# Early error
	[ -d "${log:?}" ] || return
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	property="$1"
	file=".poudriere.${property}${id:+.${id}}"
	shift
	case "${property}" in
	"status")
		echo "$(clock -epoch):$*" >> "${log:?}/${file:?}.journal%" || :
		;;
	esac
	write_atomic "${log:?}/${file:?}" "$@"
}

job_build_status() {
	[ "$#" -eq 3 ] || eargs job_build_status phase origingspec pkgname
	local phase="$1"
	local originspec="$2"
	local pkgname="$3"

	bset_job_status "${phase}" "${originspec}" "${pkgname}"
	job_msg_status_verbose "Status" "${originspec}" "${pkgname}" \
	    "${COLOR_PHASE}${phase}${COLOR_RESET}"
}

bset_job_status() {
	[ $# -eq 3 ] || eargs bset_job_status status originspec pkgname
	local status="$1"
	local originspec="$2"
	local pkgname="$3"

	# testport may call this without MY_BUILDER_ID set.
	bset ${MY_BUILDER_ID:+"${MY_BUILDER_ID}"} status \
	    "${status}:${originspec}:${pkgname}:${TIME_START_JOB:-${TIME_START}}:$(clock -monotonic)"
}

badd() {
	local id property mnt log file
	_log_path log
	# Early error
	[ -d "${log:?}" ] || return
	if [ $# -eq 3 ]; then
		id=$1
		shift
	fi
	file=.poudriere.${1}${id:+.${id}}
	shift
	echo "$@" >> "${log:?}/${file:?}" || :
}

update_stats() {
	local type unused scnt
	local -

	set +e

	lock_acquire update_stats || return 1
	critical_start

	for type in built failed inspected ignored; do
		critical_retry _bget '' "ports.${type}"
		critical_retry bset "stats_${type}" "${_read_file_lines_read:?}"
	done

	# Skipped may have duplicates in it
	critical_retry_cmdsubst scnt \
	    "\$(bget ports.skipped | awk '{print \$1}' | sort -u | wc -l)"
	scnt="${scnt##* }"
	critical_retry bset stats_skipped "${scnt}"

	lock_release update_stats
	critical_end
}

update_stats_queued() {
	[ "$#" -eq 0 ] || eargs update_stats_queued
	local _originspec _pkgname _rdep _ignore nbq
	local log

	_log_path log
	sort "${log:?}/.poudriere.ports.tobuild" \
	    "${log:?}/.poudriere.ports.ignored" \
	    "${log:?}/.poudriere.ports.inspected" \
	    "${log:?}/.poudriere.ports.skipped" \
	    "${log:?}/.poudriere.ports.fetched" \
	    | write_atomic "${log:?}/.poudriere.ports.queued"
	count_lines "${log:?}/.poudriere.ports.queued" nbq
	bset stats_queued "${nbq}"
}

update_tobuild() {
	[ "$#" -eq 0 ] || eargs update_tobuild
	local pkgname originspec rdep

	while mapfile_read_loop "${MASTER_DATADIR:?}/all_pkgs_not_ignored" \
	    pkgname originspec rdep; do
		if ! pkgqueue_contains "build" "${pkgname}"; then
			continue
		fi
		echo "${pkgname} ${originspec} ${rdep}"
	done > "${MASTER_DATADIR:?}/tobuild_pkgs"

	update_stats_tobuild
}

update_stats_tobuild() {
	[ "$#" -eq 0 ] || eargs update_stats_tobuild
	local nbtb log

	_log_path log
	awk '{print $2,$1,$3 }' "${MASTER_DATADIR:?}/tobuild_pkgs" > \
	    "${log:?}/.poudriere.ports.tobuild"
	count_lines "${log:?}/.poudriere.ports.tobuild" nbtb
	bset stats_tobuild "${nbtb}"
}

update_remaining() {
	[ $# -eq 0 ] || eargs update_remaining
	local log

	case "${HTML_TRACK_REMAINING-}" in
	"yes") ;;
	*) return 0 ;;
	esac
	_log_path log
	pkgqueue_remaining |
	    write_atomic "${log:?}/.poudriere.ports.remaining"
}

exit_handler() {
	: ${EXIT_STATUS:="$?"}
	# SIGPIPE is blocked while in here from setup_traps() as we want
	# to ensure we cleanup jails before giving up.

	post_getopts

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
		# MY_BUILDER_ID may incorrectly be set if we got here
		# via crashed_build() in main process.
		case "$$" in
		"$(getpid)") unset MY_BUILDER_ID ;;
		esac
		# build_queue may have done cd MASTER_DATADIR/pool,
		# but some of the cleanup here assumes we are
		# PWD=MASTER_DATADIR.  Switch back if possible.
		# It will be changed to / in jail_cleanup
		if [ -n "${MASTER_DATADIR-}" ] &&
		    [ -d "${MASTER_DATADIR}" ]; then
			cd "${MASTER_DATADIR:?}"

			# Save the .p dir.
			# Super cautious to avoid any errors here.
			case "${BUILDNAME:+set}.${MASTERNAME:+set}" in
			set.set)
				local log

				if _log_path log && [ -d "${log}" ]; then
					find -x . -ls > \
					    "${log:?}/.poudriere.datadir%"
				fi
				;;
			esac
		fi
	fi

	case "${EXIT_STATUS}" in
	0|130|"${EX_USAGE}")
		: ${ERROR_VERBOSE:=0} ;;
	*)	: ${ERROR_VERBOSE:=1} ;;
	esac
	if [ "${ERROR_VERBOSE}" -eq 1 ] && [ "${CRASHED:-0}" -eq 0 ]; then
		echo "[ERROR] Unhandled error!" >&2
	fi
	# Try to set status so other processes know this crashed
	# Don't set it from children failures though, only master
	case "${EXIT_BSTATUS:+set}${PARALLEL_CHILD:-0}" in
	set.0)
		bset ${MY_BUILDER_ID:+"${MY_BUILDER_ID}"} status \
		    "${EXIT_BSTATUS}" || :
		;;
	esac

	if was_a_jail_run; then
		# Don't use jail for any caching in cleanup
		SHASH_VAR_PATH="${SHASH_VAR_PATH_DEFAULT:?}"
	fi

	parallel_shutdown

	if was_a_bulk_run; then
		# build_queue socket
		exec 6>&- || :
		coprocess_stop pkg_cacher ||
		{
			msg_warn "pkg_cacher exited with status $?"
			EXIT_STATUS=$((EXIT_STATUS + 1))
		}
		coprocess_stop html_json ||
		{
			msg_warn "html_json exited with $?"
			EXIT_STATUS=$((EXIT_STATUS + 1))
		}
	fi

	if [ "${STATUS}" -eq 1 ]; then
		if was_a_bulk_run; then
			update_stats >/dev/null 2>&1 || :
			if [ "${DRY_RUN:-0}" -eq 1 ] &&
			    [ -n "${PACKAGES_ROOT-}" ] &&
			    [ ${PACKAGES_MADE_BUILDING:-0} -eq 1 ] ; then
				rm -rf "${PACKAGES_ROOT:?}/.building" || :
			fi
		fi

		jail_cleanup
	fi

	if was_a_bulk_run; then
		log_stop
	fi

	case "${CLEANUP_HOOK:+set}" in
	set)
		set -f
		${CLEANUP_HOOK}
		set +f
		;;
	esac

	# Kill jobs started with spawn_job()
	ret=0
	kill_all_jobs || ret="$?"
	case "${ret}" in
	0|143|130) ;;
	*)
		msg_error "Job failures detected ret=${ret}"
		EXIT_STATUS=$((EXIT_STATUS + 1))
		;;
	esac
	case "${EXIT_STATUS}" in
	0)
		if check_pipe_fatal_error; then
			msg_error "Unhandled child process error"
			EXIT_STATUS=$((EXIT_STATUS + 1))
		fi
		;;
	*)
		clear_pipe_fatal_error
		;;
	esac

	slock_release_all || :
	case "${POUDRIERE_TMPDIR:+set}" in
	set)
		rm -rf "${POUDRIERE_TMPDIR:?}" 2>/dev/null || :
		;;
	esac
	case "${ERROR_VERBOSE}.${USE_DEBUG:-no}" in
	1.*|0.yes)
		echo "Exiting with status ${EXIT_STATUS}" >&2 || :
		;;
	esac
	# return rather than exit as this function is called by exit_return().
	return "${EXIT_STATUS}"
}

build_url() {
	local buildname

	case "${URL_BASE-}" in
	"")
		setvar "$1" ""
		return 1
		;;
	esac

	# URL encode '+' which may come in for tz.
	_gsub "${BUILDNAME}" "+" "%2b" buildname
	setvar "$1" "${URL_BASE}/build.html?mastername=${MASTERNAME}&build=${buildname}"
}

log_url() {
	case "${URL_BASE-}" in
	"")
		setvar "$1" ""
		return 1
		;;
	esac
	setvar "$1" "${URL_BASE}/data/${MASTERNAME}/${BUILDNAME}/logs"
}

show_log_info() {
	local log build_url

	if ! was_a_bulk_run; then
		case "${SCRIPTNAME:?}" in
		"status.sh") ;;
		*) return 0 ;;
		esac
	fi
	_log_path log
	[ -d "${log:?}" ] || return 0
	msg "Logs: ${log}"
	if build_url build_url; then
		msg "WWW: ${build_url}"
	fi
	return 0
}

show_dry_run_summary() {
	local tobuild
	[ ${DRY_RUN} -eq 1 ] || return 0

	bset status "done:"
	msg "Dry run mode, cleaning up and exiting"
	_bget tobuild stats_tobuild ||
	    err "${EX_SOFTWARE}" "Failed to lookup stats_tobuild"
	if [ ${tobuild} -gt 0 ]; then
		if [ ${PARALLEL_JOBS} -gt ${tobuild} ]; then
			PARALLEL_JOBS=${tobuild##* }
		fi
		msg "Would build ${tobuild} packages using ${PARALLEL_JOBS} builders"

		if [ "${ALL}" -eq 0 ] || [ "${VERBOSE}" -ge 1 ]; then
			msg_n "Ports to build: "
			cut -d ' ' -f2 "${MASTER_DATADIR:?}/tobuild_pkgs" |
			    paste -s -d ' ' -
		fi
	else
		msg "No packages would be built"
	fi
	show_build_summary
	show_log_info
	exit 0
}

show_build_summary() {
	local status nbb nbf nbs nbi nbin nbq nbp ndone nbremaining buildname
	local log now elapsed buildtime nbtb dev_msg

	_bget status status || status=unknown
	_log_path log
	[ -d "${log:?}" ] || return 0
	_bget buildname buildname || buildname=
	now=$(clock -epoch)

	calculate_elapsed_from_log "${now}" "${log}" || return 0
	elapsed=${_elapsed_time}
	calculate_duration buildtime "${elapsed}"

	if ! _bget nbq stats_queued || [ "${nbq}" -eq 0 ]; then
		# The queue is not ready to display stats for.
		printf "[%s] [%s] [%s] Time: %s\n" \
		    "${MASTERNAME}" "${buildname}" "${status%%:*}" \
		    "${buildtime}"
		return 0
	fi
	update_stats 2>/dev/null || return 0
	update_remaining || :
	_bget nbf stats_failed || nbf=0
	_bget nbi stats_ignored || nbi=0
	_bget nbin stats_inspected || nbin=0
	_bget nbs stats_skipped || nbs=0
	_bget nbp stats_fetched || nbp=0
	_bget nbb stats_built || nbb=0
	_bget nbtb stats_tobuild || nbtb=0
	ndone=$((nbb + nbf + nbi + nbin + nbs + nbp))
	nbremaining=$((nbq - ndone))

	msg_fmt "[%s] [%s] [%s] Time: %s\n\
Queued: %d \
${COLOR_IGNORE}Inspected: %d \
${COLOR_IGNORE}Ignored: %d \
${COLOR_SUCCESS}Built: %d \
${COLOR_FAIL}Failed: %d \
${COLOR_SKIP}Skipped: %d \
${COLOR_FETCHED}Fetched: %d \
${COLOR_RESET}Remaining: %d\n" \
	    "${MASTERNAME}" "${buildname}" "${status%%:*}" "${buildtime}" \
	    "${nbq}" "${nbin}" "${nbi}" "${nbb}" "${nbf}" "${nbs}" "${nbp}" \
	    "${nbremaining}"
	case "${CRASHED:-0}" in
	0) dev_msg="dev_err ${EX_SOFTWARE}" ;;
	1) dev_msg="msg_warn" ;;
	esac
	case "${nbremaining}" in
	-*) ${dev_msg} "show_build_summary: negative remaining count" ;;
	esac
	case "${status}" in
	idle:)
		case "${nbremaining}" in
		0) ;;
		*)
			${dev_msg} "show_build_summary: remaining count >0 after build"
		esac
	esac
}

_siginfo_handler() {
	local IFS
	local status
	local now
	local j elapsed elapsed_phase job_id_color
	local pkgname origin phase buildtime buildtime_phase started
	local started_phase format_origin_phase format_phase sep
	local tmpfs cpu mem nbq
	local -

	_bget status status || status=unknown
	case "${status}" in
	"index:"|"crashed:"*|"stopped:crashed:"*)
			return 0
			;;
	esac

	case "${POUDRIERE_BUILD_TYPE-}" in
	"") return 0 ;;
	esac

	show_build_summary

	if ! _bget nbq stats_queued || [ "${nbq}" -eq 0 ]; then
		# Not ready to display stats
		show_log_info
		return 0
	fi

	now=$(clock -monotonic)

	# Skip if stopping or starting jobs or stopped.
	if [ -n "${BUILDERS:+set}" -a "${status#starting_jobs:}" = "${status}" \
	    -a "${status}" != "stopping_jobs:" -a -n "${MASTERMNT}" ] && \
	    ! status_is_stopped "${status}"; then
		# Some of the \b and empty field hacks here are for adding [] in
		# the output but not the header for historical and consistency
		# reasons.
		format_origin_phase="%%c \b%%s \b%%-%ds${COLOR_RESET} \b%%c %%-%ds ${COLOR_PORT}%%%ds %%c %%-%ds${COLOR_RESET} ${COLOR_PHASE}%%%ds${COLOR_RESET} %%-%ds %%-%ds %%%ds %%%ds"
		display_setup "${format_origin_phase}"
		display_add " " "" "ID" " " "TOTAL" "ORIGIN" " " "PKGNAME" "PHASE" \
			    "TIME" "TMPFS" "CPU%" "MEM%"

		while mapfile_read_loop_redir j cpu mem; do
			j="${j#*-job-}"
			hash_set siginfo_cpu "${j}" "${cpu}"
			hash_set siginfo_mem "${j}" "${mem}"
		done <<-EOF
		$(ps -ax -o jail,%cpu,%mem |
		    awk -v MASTERNAME="${MASTERNAME}" '\
			$1 ~ "^" MASTERNAME "(-job-[0-9]+)?(-n)?$" \
			{ \
				gsub(/-n$/, "", $1); \
				cpu[$1] += $2; \
				mem[$1] += $3; \
			} \
			END { \
				for (jail in cpu) { \
					print jail, cpu[jail], mem[jail]; \
				} \
			} \
		    ')
		EOF
		while mapfile_read_loop_redir j tmpfs; do
			hash_set siginfo_tmpfs "${j}" "${tmpfs}"
		done <<-EOF
		$(BLOCKSIZE=512 df -t tmpfs 2>/dev/null | \
		  awk -v MASTERMNTROOT="${MASTERMNTROOT}" ' \
		    function humanize(number) { \
			hum[1024**4]="TiB"; \
			hum[1024**3]="GiB"; \
			hum[1024**2]="MiB"; \
			hum[1024]="KiB"; \
			hum[0]="B"; \
			for (x=1024**4; x>=1024; x/=1024) { \
				if (number >= x) { \
					printf "%.2f %s", number/x, hum[x]; \
					return; \
				} \
			} \
		    } \
		    $6 ~ "^" MASTERMNTROOT "/" { \
			sub(MASTERMNTROOT "/", "", $6); \
			slash = match($6, "/"); \
			if (RLENGTH == -1) \
				id = substr($6, 0); \
			else \
				id = substr($6, 0, slash-1); \
			totals[id] += $3; \
		    } \
		    END { \
			for (id in totals) { \
				print id, humanize(totals[id]*512); \
			} \
		    }')
		EOF
		for j in ${BUILDERS}; do
			# Ignore error here as the zfs dataset may not be cloned yet.
			_bget status ${j} status || status=
			# Skip builders not started yet
			case "${status}" in
			"") continue ;;
			esac
			set -f
			IFS=:
			set -- ${status}
			unset IFS
			set +f
			phase="${1}"

			# Hide idle workers
			case "${phase}" in
			idle|done) continue ;;
			esac

			origin="${2-}"
			pkgname="${3-}"
			started="${4-}"
			started_phase="${5-}"

			case "${pkgname:+set}" in
			set)
				case "${started}" in
				[0-9]*)
					elapsed=$((now - started))
					calculate_duration buildtime "${elapsed}"
					elapsed_phase=$((now - started_phase))
					calculate_duration buildtime_phase \
					    "${elapsed_phase}"
					;;
				*)
					elapsed=
					elapsed_phase=
					;;
				esac
				sep="|"
				hash_remove siginfo_cpu "${j}" cpu || cpu=
				hash_remove siginfo_mem "${j}" mem || mem=
				hash_remove siginfo_tmpfs "${j}" tmpfs || tmpfs=
				;;
			"")
				buildtime=
				buildtime_phase=
				sep=
				tmpfs=
				cpu=
				mem=
				;;
			esac
			colorize_job_id job_id_color "${j}"
			display_add \
			    "[" "${job_id_color}" "${j}" "]" \
			    "${buildtime-}" \
			    "${origin-}" "${sep:- }" "${pkgname-}" "${phase-}" \
			    "${buildtime_phase-}" \
			    "${tmpfs}" \
			    "${cpu:+${cpu}%}" \
			    "${mem:+${mem}%}"
		done
		display_output
	fi
	show_log_info
}

siginfo_handler() {
	local -; set +x

	# Reset state that this trap doesn't expect.
	unset IFS
	set +e +u

	trap '' INFO
	if ! was_a_bulk_run; then
		case "${SCRIPTNAME:?}" in
		"status.sh") ;;
		*)
			err "${EX_SOFTWARE}" "siginfo_handler for non-bulk run?"
			;;
		esac
	fi
	# Send all output to the real stderr.
	redirect_to_real_tty _siginfo_handler >&2
	enable_siginfo_handler
}

enable_siginfo_handler() {
	if was_a_bulk_run; then
		trap siginfo_handler INFO
	fi
	return 0
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
	local name method p trees

	[ -d "${POUDRIERED:?}/ports" ] ||
	    [ -L "${POUDRIERED:?}/ports" ] ||
	    return 0
	trees="$(find "${POUDRIERED:?}/ports/" -type d \
	    -maxdepth 1 -mindepth 1 -print)" ||
	    err "${EX_SOFTWARE}" "porttree_list: Failed to find port trees"
	for p in ${trees}; do
		name=${p##*/}
		_pget mnt ${name} mnt || :
		_pget method ${name} method || :
		echo "${name} ${method:--} ${mnt}"
	done
}

porttree_exists() {
	[ $# -eq 1 ] || eargs porttree_exists portstree_name
	local ptname="$1"

	if [ -d "${POUDRIERED:?}/ports/${ptname:?}" ]; then
		return 0
	fi
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
		zfs create -o atime=off \
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

# Make sure 'mktemp foo' wasn't passed in without a prefix.
_validate_mktemp() {
	local -; set +x
	local OPTIND flag

	OPTIND=1
	while getopts "dp:qt:u" flag; do
		case "${flag}" in
		d|p|q|u) ;;
		t) return 0 ;;
		esac
	done
	shift $((OPTIND-1))
	case "${1-}" in
	""|*X*) return 0 ;;
	esac
	echo "mktemp: argument missing prefix: $*" >&2
	return 1
}

# Wrap mktemp to put most tmpfiles in $MNT_DATADIR/tmp rather than system /tmp.
mktemp() {
	local mktemp_tmpfile ret

	_validate_mktemp "$@" || return
	ret=0
	_mktemp mktemp_tmpfile "$@" || ret="$?"
	echo "${mktemp_tmpfile}"
	return "${ret}"
}

case "$(type unlink 2>/dev/null)" in
"unlink is a shell builtin") ;;
*)
	unlink() {
		command unlink "$@" 2>/dev/null || :
	}
;;
esac

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
	.${OVERLAYSDIR:?}
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
		{ mtree -X "${mtreefile}" -cn -k uid,gid,flags,mode,size -p .; } \
		    > "${MNT_DATADIR}/mtree.${name}"
	)
	echo " done"
}

rm() {
	local -; set +x
	local arg

	for arg in "$@"; do
		case "${arg}" in
		/) err "${EX_SOFTWARE}" "Tried to rm /" ;;
		/|/COPYRIGHT|/bin) err "${EX_SOFTWARE}" "Tried to rm /*" ;;
		esac
	done

	command rm "$@"
}

do_jail_mounts() {
	[ $# -eq 3 ] || eargs do_jail_mounts from mnt name
	local from="$1"
	local mnt="$2"
	local name="$3"
	local srcpath nullpaths nullpath p arch

	# from==mnt is via jail -u

	# clone will inherit from the ref jail
	case "${mnt}" in
	*/ref)
		mkdir -p ${mnt:?}/proc \
		    ${mnt:?}/dev \
		    ${mnt:?}/compat/linux/proc \
		    ${mnt:?}/usr/src
		;;
	esac

	# Mount some paths read-only from the ref-jail if possible.
	nullpaths="$(nullfs_paths "${mnt}")"
	if have_builtin mkdir; then
		for nullpath in ${nullpaths}; do
			mkdir -p "${mnt:?}${nullpath:?}"
		done
	else
		echo ${nullpaths} |
		    tr ' ' '\n' |
		    sed -e "s,^/,${mnt}/," |
		    xargs mkdir -p
	fi
	for nullpath in ${nullpaths}; do
		if [ -d "${from}${nullpath}" ]; then
			case "${from}" in
			"${mnt}") ;;
			*)
				${NULLMOUNT} -o ro "${from:?}${nullpath}" \
				    "${mnt:?}${nullpath}"
				;;
			esac
		fi
	done

	# Mount /usr/src into target if it exists and not overridden
	_jget srcpath ${name} srcpath || srcpath="${from}/usr/src"
	if [ -d "${srcpath}" ]; then
		case "${from}" in
		"${mnt}") ;;
		*)
			${NULLMOUNT} -o ro "${srcpath:?}" "${mnt:?}/usr/src"
			;;
		esac
	fi

	mount -t devfs devfs ${mnt:?}/dev
	if [ ${JAILED} -eq 0 ]; then
		devfs -m ${mnt:?}/dev ruleset ${DEVFS_RULESET}
		devfs -m ${mnt:?}/dev rule applyset
	fi

	if [ "${USE_FDESCFS}" = "yes" ] && \
	    [ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ]; then
		    mount -t fdescfs fdesc "${mnt:?}/dev/fd"
	fi
	case "${USE_PROCFS}" in
	"yes")
		mount -t procfs proc "${mnt:?}/proc"
		;;
	esac

	case "${NOLINUX-}" in
	"")
		if [ -d "${mnt:?}/compat" ]; then
			_jget arch "${name}" arch || \
			    err 1 "Missing arch metadata for jail"
			case "${arch}" in
			i386|amd64)
				mount -t linprocfs linprocfs "${mnt:?}/compat/linux/proc"
				;;
			esac
		fi
		;;
	esac

	run_hook jail mount ${mnt}

	return 0
}

# Interactive test mode
enter_interactive() {
	local stopmsg pkgname port originspec flavor subpkg packages
	local portdir one_package _log_path _install_target

	if [ ${ALL} -ne 0 ]; then
		msg "(-a) Not entering interactive mode."
		return 0
	fi

	print_phase_header "Interactive"
	bset status "interactive:"

	msg "Installing packages"
	echo "PACKAGES=/packages" >> "${MASTERMNT:?}/etc/make.conf"
	echo "127.0.0.1 ${MASTERNAME}" >> "${MASTERMNT:?}/etc/hosts"

	# Skip for testport as it has already installed pkg in the ref jail.
	if ! was_a_testport_run; then
		# Install pkg-static so full pkg package can install
		ensure_pkg_installed force_extract || \
		    err 1 "Unable to extract pkg."
		# Install the selected pkg package
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    /usr/bin/make -C "${PORTSDIR:?}/${P_PKG_ORIGIN:?}" \
		    PKG_BIN="${PKG_BIN:?}" install-package
	fi

	# Enable all selected ports and their run-depends
	one_package=0
	packages="$(listed_pkgnames)" ||
	    err "${EX_SOFTWARE}" "enter_interactive: Failed to list packages"
	for pkgname in ${packages}; do
		one_package=$((one_package + 1))
		get_originspec_from_pkgname originspec "${pkgname}"
		originspec_decode "${originspec}" port flavor subpkg
		# Install run-depends since this is an interactive test
		msg "Installing run-depends for ${COLOR_PORT}${port}${flavor:+@${flavor}}${subpkg:+~${subpkg}} | ${pkgname}"
		_lookup_portdir portdir "${port}"
		injail env USE_PACKAGE_DEPENDS_ONLY=1 \
		    /usr/bin/make -C "${portdir:?}" \
		    ${flavor:+FLAVOR=${flavor}} run-depends ||
		    msg_warn "Failed to install ${COLOR_PORT}${port}${flavor:+@${flavor}}${subpkg:+~${subpkg}} | ${pkgname}${COLOR_RESET} run-depends"
		case "${POUDRIERE_INTERACTIVE_NO_INSTALL-}" in
		"")
			msg "Installing ${COLOR_PORT}${port}${flavor:+@${flavor}}${subpkg:+~${subpkg}} | ${pkgname}"
			_install_target="install-package${subpkg:+.${subpkg}}"
			# Only use PKGENV during install as testport will store
			# the package in a different place than dependencies
			injail /usr/bin/env ${PKGENV:+-S "${PKGENV}"} \
			    USE_PACKAGE_DEPENDS_ONLY=1 \
			    /usr/bin/make -C "${portdir:?}" \
			    ${flavor:+FLAVOR=${flavor}} "${_install_target}" ||
			    msg_warn "Failed to install ${COLOR_PORT}${port}${flavor:+@${flavor}}${subpkg:+~${subpkg}} | ${pkgname}"
			;;
		esac
	done
	if [ "${one_package}" -gt 1 ]; then
		unset one_package
		portdir="${PORTSDIR}"
	fi

	# Create a pkg repo configuration, and disable FreeBSD
	msg "Installing local Pkg repository to ${LOCALBASE}/etc/pkg/repos"
	mkdir -p ${MASTERMNT:?}${LOCALBASE:?}/etc/pkg/repos
	cat > ${MASTERMNT:?}${LOCALBASE:?}/etc/pkg/repos/local.conf <<-EOF
	FreeBSD: { enabled: no }
	FreeBSD-kmods: { enabled: no }
	FreeBSD-ports: { enabled: no }
	FreeBSD-ports-kmods: { enabled: no }
	FreeBSD-base: { enabled: no }

	local: {
		url: "file:///packages",
		enabled: yes
	}
	EOF
	# XXX: build_repo ?
	#injail pkg update || :

	msg "Remounting ${PORTSDIR} ${OVERLAYS:+and ${OVERLAYSDIR} }read-write"
	remount_ports -o rw >/dev/null

	_log_path log_path
	msg "Mounting logs from: ${log_path}"
	mkdir -p "${MASTERMNT:?}/logs"
	${NULLMOUNT} -o ro "${log_path:?}/logs" "${MASTERMNT:?}/logs"

	if schg_immutable_base; then
		chflags noschg \
		    "${MASTERMNT:?}/root/.cshrc" \
		    "${MASTERMNT:?}/root/.login" \
		    "${MASTERMNT:?}/root/.shrc" \
		    "${MASTERMNT:?}/root/.profile"
	fi
	cat >> "${MASTERMNT:?}/root/.cshrc" <<-EOF
	cd "${portdir:?}"
	setenv PORTSDIR "${PORTSDIR}"
	EOF
	cat >> "${MASTERMNT:?}/root/.shrc" <<-EOF
	cd "${portdir:?}"
	export PORTSDIR="${PORTSDIR}"
	EOF
	ln -fs /etc/motd "${MASTERMNT:?}/var/run/motd"
	cat > "${MASTERMNT}/etc/motd" <<-EOF
	Welcome to Poudriere interactive mode!

	PORTSDIR:		${PORTSDIR}
	Work directories:	/wrkdirs
	Distfiles:		/distfiles
	Packages:		/packages
	Build logs:		/logs
	Lookup port var:	make -V WRKDIR

	EOF
	case "${one_package:+set}" in
	set)
		cat >> "${MASTERMNT:?}/etc/motd" <<-EOF
		ORIGIN:			${port:?}
		PORTDIR:		${portdir:?}
		WRKDIR:			$(injail make -C "${portdir:?}" -V WRKDIR)
		EOF
		case "${flavor:+set}" in
		set)
			cat >> "${MASTERMNT:?}/etc/motd" <<-EOF
			FLAVOR:			${flavor}

			A FLAVOR was used to build but is not in the environment.
			Remember to pass FLAVOR to make:
				make FLAVOR=${flavor}

			EOF
			;;
		esac
		;;
	esac
	cat >> "${MASTERMNT:?}/etc/motd" <<-EOF
	Installed packages:	$(echo "${packages}" | sort -V | tr '\n' ' ')

	It is recommended to set these in the environment:
	EOF
	case "${INTERACTIVE_SHELL}" in
	csh)
		cat >> "${MASTERMNT:?}/etc/motd" <<-EOF
			setenv DEVELOPER 1
			setenv DEVELOPER_MODE yes
		EOF
		;;
	*sh)
		cat >> "${MASTERMNT:?}/etc/motd" <<-EOF
			export DEVELOPER=1
			export DEVELOPER_MODE=yes
		EOF
		;;
	esac
	cat >> "${MASTERMNT:?}/etc/motd" <<-EOF

	Packages from /packages can be installed with 'pkg add' as needed.

	If building as non-root you will be logged into ${PORTBUILD_USER}.
	su can be used without password to elevate.

	To see this again: cat /etc/motd
	EOF

	case "${PORTBUILD_USER}" in
	"root") ;;
	*)
		chown -R "${PORTBUILD_USER}" "${MASTERMNT:?}/wrkdirs"
		;;
	esac
	case "${EMULATOR:+set}" in
	set)
		# Needed for su(1) to work.
		chmod u+s "${MASTERMNT:?}${EMULATOR}"
		;;
	esac

	if [ ${INTERACTIVE_MODE} -eq 1 ]; then
		if [ -n "${INTERACTIVE_SHELL}" ]; then
			injail pw usermod -n root -s "${INTERACTIVE_SHELL}" ||
			    err "${EX_USAGE}" "Failed to set interactive shell to ${INTERACTIVE_SHELL}"
		fi
		msg "Entering interactive test mode. Type 'exit' when done."
		if injail pw groupmod -n wheel -m "${PORTBUILD_USER}"; then
			cat >> "${MASTERMNT:?}/root/.login" <<-EOF
			if ( -f /tmp/su-to-portbuild ) then
				rm -f /tmp/su-to-portbuild
				cd /
				exec su -m "${PORTBUILD_USER}" -c ${INTERACTIVE_SHELL}
			endif
			EOF
			cat >> "${MASTERMNT:?}/root/.profile" <<-EOF
			if [ -f /tmp/su-to-portbuild ]; then
				rm -f /tmp/su-to-portbuild
				cd /
				exec su -m "${PORTBUILD_USER}" -c ${INTERACTIVE_SHELL}
			fi
			EOF
			touch "${MASTERMNT:?}/tmp/su-to-portbuild"
		fi
		JNETNAME="n" injail_tty env -i TERM=${SAVED_TERM} \
		    /usr/bin/login -fp root || :
		case "${EMULATOR:+set}" in
		set)
			chmod u-s "${MASTERMNT:?}${EMULATOR}"
			;;
		esac
	elif [ ${INTERACTIVE_MODE} -eq 2 ]; then
		# XXX: Not tested/supported with bulk yet.
		msg "Leaving jail ${MASTERNAME}-n running, mounted at ${MASTERMNT} for interactive run testing"
		msg "To enter jail: jexec ${MASTERNAME}-n env -i TERM=\$TERM /usr/bin/login -fp root"
		stopmsg="-j ${JAILNAME}"
		case "${SETNAME:+set}" in
		set)
			stopmsg="${stopmsg} -z ${SETNAME}"
			;;
		esac
		case "${PTNAME}" in
		"default") ;;
		*) stopmsg="${stopmsg} -p ${PTNAME}" ;;
		esac
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

	case "${optionsdir:?}" in
	"-") optionsdir="${POUDRIERED:?}/options" ;;
	*) optionsdir="${POUDRIERED:?}/${optionsdir:?}-options" ;;
	esac
	[ -d "${optionsdir:?}" ] || return 1
	optionsdir="$(realpath "${optionsdir:?}")"
	msg "Copying /var/db/ports from: ${optionsdir}"
	do_clone "${optionsdir:?}" "${mnt:?}/var/db/ports" || \
	    err 1 "Failed to copy OPTIONS directory"

	return 0
}

remount_packages() {
	umountfs "${MASTERMNT:?}/packages"
	mount_packages "$@"
}

mount_packages() {
	local mnt

	_my_path mnt
	${NULLMOUNT} "$@" "${PACKAGES:?}" \
		"${mnt:?}/packages" ||
		err 1 "Failed to mount the packages directory "
}

remount_ports() {
	local mnt

	_my_path mnt
	umountfs "${mnt:?}/${PORTSDIR:?}"
	umountfs "${mnt:?}/${OVERLAYSDIR:?}"
	mount_ports "$@"
}

mount_ports() {
	local mnt o portsdir ptname odir

	_my_path mnt
	ptname="${PTNAME:?}"
	_pget portsdir "${ptname}" mnt || err 1 "Missing mnt metadata for portstree"
	# Some ancient compat
	if [ -d "${portsdir}/ports" ]; then
		portsdir="${portsdir:?}/ports"
	fi
	msg "Mounting ports from: ${portsdir:?}"
	${NULLMOUNT} "$@" ${portsdir:?} ${mnt:?}${PORTSDIR:?} ||
	    err 1 "Failed to mount the ports directory "
	for o in ${OVERLAYS}; do
		_pget odir "${o}" mnt || err 1 "Missing mnt metadata for overlay ${o}"
		msg "Mounting ports overlay from: ${odir}"
		${NULLMOUNT} "$@" "${odir:?}" "${mnt:?}${OVERLAYSDIR:?}/${o:?}"
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
	MNT_DATADIR="${mnt:?}/${DATADIR_NAME:?}"
	mkdir -p "${MNT_DATADIR:?}"
	add_relpath_var MNT_DATADIR
	if [ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		mnt_tmpfs data "${MNT_DATADIR:?}"
	fi
	mkdir -p \
	    "${MNT_DATADIR:?}/tmp" \
	    "${MNT_DATADIR:?}/var/run"

	# clone will inherit from the ref jail
	case "${mnt}" in
	*/ref)
		mkdir -p "${mnt:?}${PORTSDIR:?}" \
		    "${mnt:?}${OVERLAYSDIR:?}" \
		    "${mnt:?}/wrkdirs" \
		    "${mnt:?}/${LOCALBASE:-/usr/local}" \
		    "${mnt:?}/distfiles" \
		    "${mnt:?}/packages" \
		    "${mnt:?}/.npkg" \
		    "${mnt:?}/var/db/ports" \
		    "${mnt:?}${HOME:?}/.ccache" \
		    "${mnt:?}/usr/home"
		for o in ${OVERLAYS}; do
			mkdir -p "${mnt:?}${OVERLAYSDIR:?}/${o:?}"
		done
		ln -fs "usr/home" "${mnt:?}/home"
		MASTER_DATADIR="${MNT_DATADIR:?}"
		add_relpath_var MASTER_DATADIR
		;;
	esac
	if [ -d "${CCACHE_DIR:-/nonexistent}" ]; then
		${NULLMOUNT} "${CCACHE_DIR:?}" "${mnt:?}${HOME:?}/.ccache"
	fi
	case "${MFSSIZE:+set}" in
	set)
		mdmfs -t -S -o async -s ${MFSSIZE} md "${mnt:?}/wrkdirs"
		;;
	esac
	if [ ${TMPFS_WRKDIR} -eq 1 ]; then
		mnt_tmpfs wrkdir "${mnt:?}/wrkdirs"
	fi
	# Only show mounting messages once, not for every builder
	case "${mnt}" in
	*/ref)
		msgmount="msg"
		msgdev="/dev/stdout"
		;;
	*)
		msgmount=":"
		msgdev="/dev/null"
		;;
	esac
	if [ -d "${CCACHE_DIR}" ]; then
		${msgmount} "Mounting ccache from: ${CCACHE_DIR}"
	fi

	mount_ports -o ro > "${msgdev:?}"
	${msgmount} "Mounting packages from: ${PACKAGES_ROOT-${PACKAGES}}"
	mount_packages -o ro
	case "${DISTFILES_CACHE}" in
	no) ;;
	*)
		${msgmount} "Mounting distfiles from: ${DISTFILES_CACHE:?}"
		${NULLMOUNT} -o ro \
		    "${DISTFILES_CACHE:?}" "${mnt:?}/distfiles" ||
		    err 1 "Failed to mount the distfiles cache directory"
		;;
	esac

	# Copy in the options for the ref jail, but just ro nullmount it
	# in builders.
	case "${mnt}" in
	*/ref)
		if [ ${TMPFS_DATA} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
			mnt_tmpfs config "${mnt}/var/db/ports"
		fi
		optionsdir="${MASTERNAME}"
		case "${setname:+set}" in
		set)
			optionsdir="${optionsdir} ${jname}-${setname}"
			;;
		esac
		optionsdir="${optionsdir} ${jname}-${ptname}"
		case "${setname:+set}" in
		set)
			optionsdir="${optionsdir} ${ptname}-${setname} ${setname}"
			;;
		esac
		optionsdir="${optionsdir} ${ptname} ${jname} -"

		for opt in ${optionsdir}; do
			if use_options ${mnt} ${opt}; then
				break
			fi
		done
		;;
	*)
		${NULLMOUNT} -o ro "${MASTERMNT:?}/var/db/ports" \
		    "${mnt:?}/var/db/ports" ||
		    err 1 "Failed to mount the options directory"
		;;
	esac

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
	mkdir "${PACKAGES:?}/${pkgdir:?}"

	# Move all top-level dirs into .real
	find "${PACKAGES:?}/" -mindepth 1 -maxdepth 1 -type d \
	    ! -name "${pkgdir:?}" |
	    xargs -J % mv % "${PACKAGES:?}/${pkgdir:?}"
	# Symlink them over through .latest
	find "${PACKAGES:?}/${pkgdir:?}" -mindepth 1 -maxdepth 1 -type d \
	    ! -name ${pkgdir:?} | while read directory; do
		dirname=${directory##*/}
		ln -s ".latest/${dirname:?}" "${PACKAGES:?}/${dirname:?}"
	done

	# Now move+symlink any files in the top-level
	find "${PACKAGES:?}/" -mindepth 1 -maxdepth 1 -type f |
	    xargs -J % mv % "${PACKAGES:?}/${pkgdir:?}"
	find "${PACKAGES:?}/${pkgdir:?}" -mindepth 1 -maxdepth 1 -type f |
	    while read file; do
		fname=${file##*/}
		ln -s ".latest/${fname:?}" "${PACKAGES:?}/${fname:?}"
	done

	# Setup current symlink which is how the build will atomically finish
	ln -s "${pkgdir:?}" "${PACKAGES:?}/.latest"
}

_stash_packages_clone() {
	[ $# -eq 2 ] || eargs _stash_packages_clone src dst
	local src="$1"
	local dst="$2"

	mkdir -p "${dst:?}"
	PACKAGES_MADE_BUILDING=1
	# hardlink copy all top-level directories
	find "${src:?}/" -mindepth 1 -maxdepth 1 -type d |
	    xargs -J % cp -al % "${dst:?}"

	# Copy all top-level files to avoid appending
	# to real copy in pkg-repo, etc.
	find "${src:?}/" -mindepth 1 -maxdepth 1 -type f |
	    xargs -J % cp -a % "${dst:?}"
}

stash_packages() {

	PACKAGES_ROOT="${PACKAGES:?}"
	PACKAGES_PKG_CACHE="${PACKAGES_ROOT}/.pkg-cache"

	case "${ATOMIC_PACKAGE_REPOSITORY-}" in
	yes) ;;
	*) return 0 ;;
	esac

	[ -L "${PACKAGES:?}/.latest" ] || convert_repository

	case "${CLEAN-}" in
	1)
		if [ -d "${PACKAGES:?}/.building" ]; then
			rm -rf "${PACKAGES:?}/.building"
		fi
		;;
	esac
	if [ -d "${PACKAGES:?}/.building" ]; then
		# If the .building directory is still around, use it. The
		# previous build may have failed, but all of the successful
		# packages are still worth keeping for this build.
		msg_warn "Using packages from previously failed, or uncommitted, build: ${PACKAGES:?}/.building"
	else
		msg "Stashing existing package repository"

		# Use a linked shadow directory in the package root, not
		# in the parent directory as the user may have created
		# a separate ZFS dataset or NFS mount for each package
		# set; Must stay on the same device for linking.

		critical_start
		critical_retry _stash_packages_clone \
		    "${PACKAGES:?}/.latest" \
		    "${PACKAGES:?}/.building" ||
		    err 1 "stash_packages: failed to clone repo"
		critical_end
	fi

	# From this point forward, only work in the shadow
	# package dir
	PACKAGES="${PACKAGES:?}/.building"
}

commit_packages() {
	local pkgdir_old pkgdir_new stats_failed log log_jail

	if [ "${COMMIT}" -eq 0 ]; then
		case "${PACKAGES:?}" in
		"${PACKAGES_ROOT:?}/.building")
			msg_warn "Temporary build directory will not be removed or committed: ${PACKAGES}"
			msg_warn "It will be used to resume the build next time.  Delete it for a fresh build."
			;;
		esac
		return 0
	fi

	# Link the latest-done path now that we're done
	_log_path log
	_log_path_jail log_jail
	ln -sfh "${BUILDNAME:?}" "${log_jail:?}/latest-done"

	# Cleanup pkg cache
	if [ -e "${PACKAGES_PKG_CACHE:?}" ]; then
		find -L "${PACKAGES_PKG_CACHE:?}" -links 1 -print0 |
		    unlink_many_pipe
	fi

	case "${COMMIT_PACKAGES_ON_FAILURE-}" in
	no)
		if _bget stats_failed stats_failed &&
		    [ "${stats_failed}" -gt 0 ]; then
			case "${ATOMIC_PACKAGE_REPOSITORY-}" in
			yes)
				msg_warn "Not committing, or publishing," \
				    "packages to repository as failures" \
				    "were encountered"
				;;
			*)
				if have_hook pkgrepo; then
					msg_warn "Not publishing packages" \
					    "as failures were encountered"
				fi
				;;
			esac
			install -lsr "${PACKAGES:?}/" "${log:?}/packages"
			return 0
		fi
	esac
	case "${ATOMIC_PACKAGE_REPOSITORY-}" in
	yes) ;;
	*)
		run_hook -v pkgrepo publish "${PACKAGES:?}"
		install -lsr "${PACKAGES:?}/" "${log:?}/packages"
		return 0
		;;
	esac

	pkgdir_new=.real_$(clock -epoch)
	msg "Committing packages to repository: ${PACKAGES_ROOT}/${pkgdir_new} via .latest symlink"
	bset status "committing:"

	# Find any new top-level files not symlinked yet. This is
	# mostly incase pkg adds a new top-level repo or the ports framework
	# starts creating a new directory
	find "${PACKAGES:?}/" -mindepth 1 -maxdepth 1 \
	    \( ! -name '.*' -o -name '.jailversion' -o -name '.buildname' \) |
	    while mapfile_read_loop_redir path; do
		name=${path##*/}
		[ ! -L "${PACKAGES_ROOT:?}/${name:?}" ] || continue
		if [ -e "${PACKAGES_ROOT:?}/${name:?}" ]; then
			case "${name}" in
			.buildname|.jailversion|\
			"data.${PKG_EXT}"|data.txz|\
			"meta.${PKG_EXT}"|meta.txz|\
			"digests.${PKG_EXT}"|digests.txz|\
			"filesite.${PKG_EXT}"|filesite.txz|\
			"packagesite.${PKG_EXT}"|packagesite.txz|\
			All|Latest)
				# Auto fix pkg-owned files
				unlink "${PACKAGES_ROOT:?}/${name:?}"
				;;
			*)
				msg_error "${PACKAGES_ROOT}/${name}
shadows repository file in .latest/${name}. Remove the top-level one and
symlink to .latest/${name}"
				continue
				;;
			esac
		fi
		ln -s ".latest/${name:?}" "${PACKAGES_ROOT:?}/${name:?}"
	done

	pkgdir_old="$(realpath -q "${PACKAGES_ROOT:?}/.latest" || :)"

	# Rename shadow dir to a production name
	mv "${PACKAGES_ROOT:?}/.building" "${PACKAGES_ROOT:?}/${pkgdir_new:?}"

	# XXX: Copy in packages that failed to build

	# Switch latest symlink to new build
	PACKAGES="${PACKAGES_ROOT:?}/.latest"
	ln -s "${pkgdir_new:?}" "${PACKAGES_ROOT:?}/.latest_new"
	rename "${PACKAGES_ROOT:?}/.latest_new" "${PACKAGES:?}"

	# Look for broken top-level links and remove them, if they reference
	# the old directory
	find -L "${PACKAGES_ROOT:?}/" -mindepth 1 -maxdepth 1 \
	    \( ! -name '.*' -o -name '.jailversion' -o -name '.buildname' \) \
	    -type l |
	    while mapfile_read_loop_redir path; do
		link="$(readlink "${path:?}")"
		# Skip if link does not reference inside latest
		case "${link}" in
		.latest/*) continue ;;
		esac
		unlink "${path:?}"
	done

	install -lsr "${PACKAGES:?}/" "${log:?}/packages"

	msg "Removing old packages"

	case "${KEEP_OLD_PACKAGES-}" in
	yes)
		keep_cnt=$((KEEP_OLD_PACKAGES_COUNT + 1))
		find "${PACKAGES_ROOT:?}/" -type d -mindepth 1 -maxdepth 1 \
		    -name '.real_*' | sort -dr |
		    sed -n "${keep_cnt},\$p" |
		    rmrf_many_pipe ||
		    err 1 "commit_packages: rm"
		;;
	*)
		# Remove old and shadow dir
		case "${pkgdir_old:+set}" in
		set)
			rm -rf "${pkgdir_old:?}" ||
			    err 1 "commit_packages: rm"
			;;
		esac
		;;
	esac
	run_hook -v pkgrepo publish "${PACKAGES:?}"
}

show_build_results() {
	local failed built ignored skipped nbbuilt nbfailed nbignored nbskipped
	local inspected nbinspected
	local nbfetched fetched

	failed=$(bget ports.failed | awk '{print $1 ":" $3 }' | xargs echo)
	failed=$(bget ports.failed | \
	    awk -v color_phase="${COLOR_PHASE}" \
	    -v color_port="${COLOR_PORT}" \
	    '{print $1 ":" color_phase $3 color_port }' | xargs echo)
	built=$(bget ports.built | awk '{print $1}' | xargs echo)
	ignored=$(bget ports.ignored | awk '{print $1}' | xargs echo)
	inspected=$(bget ports.inspected | awk '{print $1}' | xargs echo)
	fetched=$(bget ports.fetched | awk '{print $1}' | xargs echo)
	skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)
	_bget nbbuilt stats_built
	_bget nbfailed stats_failed
	_bget nbignored stats_ignored
	_bget nbinspected stats_inspected
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
	if [ $nbinspected -gt 0 ]; then
		COLOR_ARROW="${COLOR_IGNORE}" \
		    msg "${COLOR_IGNORE}Inspected ports: ${COLOR_PORT}${inspected}"
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
	[ "$#" -eq 1 ] || eargs maybe_run_queued encoded_args
	local encoded_args="$1"
	local this_command

	if [ "$(/usr/bin/id -u)" -eq 0 ]; then
		return 0
	fi
	# If poudriered not running then the command cannot be
	# satisfied.
	/usr/sbin/service poudriered onestatus >/dev/null 2>&1 || \
	    err 1 "This command requires root or poudriered running"

	this_command="${SCRIPTNAME}"
	this_command="${this_command%.sh}"

	eval "$(decode_args encoded_args)"
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
		    err 1 "You need to install the qemu-user-static package" \
		    "and run \`service qemu_user_static onestart\` to enable" \
		    "the binary image activators for QEMU via binmiscctl(8)," \
		    "or setup another emulator with binmiscctl(8)" \
		    "for ${wanted_arch#*.}"
		export QEMU_EMULATING=1
	fi
}

need_emulation() {
	[ $# -eq 1 ] || eargs need_emulation wanted_arch
	local wanted_arch="$1"
	local target_arch

	# kern.supported_archs is a list of TARGET_ARCHs.
	target_arch="${wanted_arch#*.}"

	# armv6 binaries can natively execute on armv7, no emulation needed
	case "${target_arch}" in
	"armv6")
		target_arch="armv[67]"
		;;
	esac

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
		cat >> "${tomnt:?}/etc/make.conf" <<-EOF
		WITH_CCACHE_BUILD=yes
		CCACHE_DIR=${HOME}/.ccache
		EOF
		chmod 755 "${tomnt:?}${HOME:?}"
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
		mkdir -p "${tomnt:?}${CCACHE_JAIL_PREFIX}/libexec/ccache/world" \
		    "${tomnt:?}${CCACHE_JAIL_PREFIX}/bin"
		msg "Copying host static ccache from ${CCACHE_STATIC_PREFIX}/bin/ccache"
		cp -f "${CCACHE_STATIC_PREFIX}/bin/ccache" \
		    "${CCACHE_STATIC_PREFIX}/bin/ccache-update-links" \
		    "${tomnt:?}${CCACHE_JAIL_PREFIX}/bin/"
		cp -f "${CCACHE_STATIC_PREFIX}/libexec/ccache/world/ccache" \
		    "${tomnt:?}${CCACHE_JAIL_PREFIX}/libexec/ccache/world/ccache"
		# Tell the ports framework that we don't need it to add
		# a BUILD_DEPENDS on everything for ccache.
		# Also set it up to look in our ccacheprefix location for the
		# wrappers.
		cat >> "${tomnt:?}/etc/make.conf" <<-EOF
		NO_CCACHE_DEPEND=1
		CCACHE_WRAPPER_PATH=	${CCACHE_JAIL_PREFIX}/libexec/ccache
		EOF
		# Link the wrapper update script to /sbin so that
		# any package trying to update the links will find it
		# rather than an actual ccache package in the jail.
		ln -fs "../${CCACHE_JAIL_PREFIX}/bin/ccache-update-links" \
		    "${tomnt:?}/sbin/ccache-update-links"
		# Fix the wrapper update script to always make the links
		# in the new prefix.
		sed -i '' -e "s,^\(PREFIX\)=.*,\1=\"${CCACHE_JAIL_PREFIX}\"," \
		    "${tomnt:?}${CCACHE_JAIL_PREFIX}/bin/ccache-update-links"
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
	mkdir -p "${mnt:?}${EMULATOR%/*}"
	cp -f "${EMULATOR:?}" "${mnt:?}${EMULATOR}"
}

setup_xdev() {
	[ $# -eq 2 ] || eargs setup_xdev mnt target
	local mnt="$1"
	local target="$2"
	local HLINK_FILES file

	[ -d "${mnt:?}/nxb-bin" ] || return 0

	msg_n "Setting up native-xtools environment in jail..."
	cat > "${mnt:?}/etc/make.nxb.conf" <<-EOF
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
	if [ -f "${mnt:?}/nxb-bin/usr/bin/as" ]; then
		cat >> "${mnt:?}/etc/make.nxb.conf" <<-EOF
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
		if [ -f "${mnt:?}/nxb-bin/${file}" ]; then
			unlink "${mnt:?}/${file}"
			ln "${mnt:?}/nxb-bin/${file}" "${mnt:?}/${file}"
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
			    MAKE_OBJDIR_CHECK_WRITABLE=0 \
			    /bin/sh ${PORTSDIR}/Mk/Scripts/ports_env.sh | \
			    grep '^export [^;&]*' | \
			    sed -e 's,^export ,,' -e 's,=",=,' -e 's,"$,,'
		} >> "${__MAKE_CONF}.ports_env"
		{
			echo "#### Misc Poudriere ####"
			echo ".include \"${__MAKE_CONF#"${mnt}"}.ports_env\""
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
	    "${mnt:?}/etc/login.conf"
	cap_mkdb "${mnt:?}/etc/login.conf" || \
	    err 1 "cap_mkdb for the jail failed."
}

export_cross_env() {
	[ $# -eq 3 ] || eargs jailname cross_env arch version
	local jailname="$1"
	local arch="$2"
	local version="$3"
	local mnt osversion

	export "UNAME_r=${version% *}"
	export "UNAME_v=FreeBSD ${version}"
	export "UNAME_m=${arch%.*}"
	export "UNAME_p=${arch#*.}"
	if _jget mnt ${JAILNAME} mnt; then
		osversion=$(awk '/\#define __FreeBSD_version/ { print $3 }' \
		    "${mnt:?}/usr/include/sys/param.h")
		export "OSVERSION=${osversion}"
	fi
}

unset_cross_env() {
	unset UNAME_r
	unset UNAME_v
	unset UNAME_m
	unset UNAME_p
	unset OSVERSION
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

	case "${MASTERMNT:+set}" in
	set)
		tomnt="${MASTERMNT}"
		;;
	*)
		_mastermnt tomnt
		;;
	esac
	_jget arch ${name} arch || err 1 "Missing arch metadata for jail"
	get_host_arch host_arch
	_jget mnt ${name} mnt || err 1 "Missing mnt metadata for jail"
	_jget version ${name} version || \
	    err 1 "Missing version metadata for jail"

	# Protect ourselves from OOM
	madvise_protect $$ || :

	PORTSDIR="/usr/ports"

	JAIL_OSVERSION=$(awk '/\#define __FreeBSD_version/ { print $3 }' "${mnt:?}/usr/include/sys/param.h")

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
	if schg_immutable_base && [ $(sysctl -n kern.securelevel) -ge 1 ]; then
		err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags for IMMUTABLE_BASE=schg."
	fi
	if [ ${TMPFS_ALL} -eq 0 ] && [ ${TMPFS_WRKDIR} -eq 0 ] \
	    && [ $(sysctl -n kern.securelevel) -ge 1 ]; then
		err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags. USE_TMPFS with 'wrkdir' or 'all' values can avoid this."
	fi
	if [ ${TMPFS_ALL} -eq 0 ] && [ ${TMPFS_LOCALBASE} -eq 0 ] \
	    && [ $(sysctl -n kern.securelevel) -ge 1 ]; then
		err 1 "kern.securelevel >= 1. Poudriere requires no securelevel to be able to handle schg flags. USE_TMPFS with 'localbase' or 'all' values can avoid this."
	fi
	case "${name}" in
	*.*)
		err 1 "The jail name cannot contain a period (.). See jail(8)"
		;;
	esac
	case "${ptname}" in
	*.*)
		err 1 "The ports name cannot contain a period (.). See jail(8)"
		;;
	esac
	case "${setname}" in
	*.*)
		err 1 "The set name cannot contain a period (.). See jail(8)"
		;;
	esac
	case "${HARDLINK_CHECK-}" in
	""|"00") ;;
	*)
		case ${BUILD_AS_NON_ROOT} in
			[Yy][Ee][Ss])
				msg_warn "You have BUILD_AS_NON_ROOT set to '${BUILD_AS_NON_ROOT}' (cf. poudriere.conf),"
				msg_warn "    and 'security.bsd.hardlink_check_uid' or 'security.bsd.hardlink_check_gid' are not set to '0'."
				err 1 "Poudriere will not be able to stage some ports. Exiting."
				;;
			*)
				;;
		esac
		;;
	esac
	case "${NOLINUX-}" in
	"")
		case "${arch}" in
		i386|amd64)
			needfs="${needfs} linprocfs"
			needkld="${needkld} linuxelf:linux"
			case "${arch}" in
			amd64)
				if  [ ${HOST_OSVERSION} -ge 1002507 ]; then
					needkld="${needkld} linux64elf:linux64"
				fi
				;;
			esac
			;;
		esac
		;;
	esac

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
	case "${USE_TMPFS}" in
	"no") ;;
	*)
		needfs="${needfs} tmpfs"
		;;
	esac
	case "${USE_PROCFS}" in
	"yes")
		needfs="${needfs} procfs"
		;;
	esac
	case "${USE_FDESCFS}" in
	"yes")
		if  [ ${JAILED} -eq 0 -o "${PATCHED_FS_KERNEL}" = "yes" ]; then
			needfs="${needfs} fdescfs"
		fi
		;;
	esac
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
	if jail_runs ${MASTERNAME}; then
		err 1 "jail already running: ${MASTERNAME}"
	fi
	check_emulation "${host_arch}" "${arch}"

	# Block the build dir from being traversed by non-root to avoid
	# system blowup due to all of the extra mounts
	mkdir -p ${MASTERMNTROOT:?}
	chmod 0755 ${POUDRIERE_DATA:?}/.m
	chmod 0711 ${MASTERMNTROOT:?}

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
		mnt_tmpfs all "${MASTERMNTROOT:?}"
	fi

	msg_n "Creating the reference jail..."
	clonefs ${mnt:?} ${tomnt:?} clean
	echo " done"

	pwd_mkdb -d "${tomnt:?}/etc" -p "${tomnt:?}/etc/master.passwd" || \
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
	do_jail_mounts "${mnt:?}" "${tomnt:?}" "${name}"
	# do_portbuild_mounts depends on PACKAGES being set.
	# May already be set for pkgclean
	: ${PACKAGES:=${POUDRIERE_DATA:?}/packages/${MASTERNAME}}
	mkdir -p "${PACKAGES:?}/"
	if was_a_bulk_run; then
		stash_packages
	fi
	do_portbuild_mounts "${tomnt:?}" "${name}" "${ptname}" "${setname}"

	case "${tomnt}" in
	*/ref)
		mkdir -p "${MASTER_DATADIR:?}/var/cache"
		SHASH_VAR_PATH="${MASTER_DATADIR:?}/var/cache"
		# No prefix needed since we're unique in MASTERMNT.
		SHASH_VAR_PREFIX=
		;;
	esac

	# Handle special QEMU needs.
	if [ ${QEMU_EMULATING} -eq 1 ]; then
		setup_xdev "${tomnt:?}" "${arch%.*}"

		# QEMU is really slow. Extend the time significantly.
		msg "Raising MAX_EXECUTION_TIME and NOHANG_TIME for QEMU from QEMU_ values"
		MAX_EXECUTION_TIME=${QEMU_MAX_EXECUTION_TIME}
		NOHANG_TIME=${QEMU_NOHANG_TIME}
		# Setup native-xtools overrides.
		cat >> "${tomnt:?}/etc/make.conf" <<-EOF
		.sinclude "/etc/make.nxb.conf"
		EOF
		qemu_install "${tomnt:?}"
	fi
	# Handle special ARM64 needs
	case "${arch}" in
	*.aarch64)
		if ! [ -f "${tomnt}/usr/bin/ld" ]; then
			for aarchld in /usr/local/aarch64-*freebsd*/bin/ld; do
				case "${aarchld}" in
				"/usr/local/aarch64-*freebsd*/bin/ld")
					# empty dir
					err 1 "Arm64 requires aarch64-binutils to be installed."
					;;
				esac
				msg "Copying aarch64-binutils ld from '${aarchld}'"
				cp -f "${aarchld:?}" \
				    "${tomnt:?}/usr/bin/ld"
				if [ -d "${tomnt:?}/nxb-bin/usr/bin" ]; then
					# Create a symlink to satisfy the LD in
					# make.nxb.conf and because running
					# /nxb-bin/usr/bin/cc defaults to looking for
					# /nxb-bin/usr/bin/ld.
					ln -f "${tomnt:?}/usr/bin/ld" \
					    "${tomnt:?}/nxb-bin/usr/bin/ld"
				fi
			done
		fi
		;;
	esac

	{
		cat <<-EOF
		USE_PACKAGE_DEPENDS=yes
		BATCH=yes
		WRKDIRPREFIX=/wrkdirs
		PORTSDIR=${PORTSDIR:?}
		PACKAGES=/packages
		DISTDIR=/distfiles
		EOF
		for o in ${OVERLAYS}; do
			echo "OVERLAYS+=${OVERLAYSDIR:?}/${o:?}"
		done
		case "${NO_FORCE_PACKAGE}" in
		"")
			echo "FORCE_PACKAGE=yes"
			;;
		esac
		case "${NO_PACKAGE_BUILDING}" in
		"")
			echo "PACKAGE_BUILDING=yes"
			export PACKAGE_BUILDING=yes
			echo "PACKAGE_BUILDING_FLAVORS=yes"
			;;
		esac
	} >> "${tomnt:?}/etc/make.conf"

	setup_makeconf "${tomnt:?}/etc/make.conf" "${name}" "${ptname}" \
	    "${setname}"

	case "${RESOLV_CONF:+set}" in
	set)
		cp -v "${RESOLV_CONF}" "${tomnt:?}/etc/"
		;;
	esac
	msg "Starting jail ${MASTERNAME}"
	jstart
	# Safe to release the lock now as jail_runs() will block further bulks.
	slock_release "jail_start_${MASTERNAME}"
	injail service ldconfig start >/dev/null || \
	    err $? "Unable to regenerate runtime linker cache in jail. Emulation or ABI wrong."
	injail id >/dev/null 2>&1 || \
	    err $? "Unable to execute id(1) in jail. Emulation or ABI wrong."

	# Generate /var/run/os-release
	injail service os-release start || :

	case "${BUILD_AS_NON_ROOT-}" in
	no)
		PORTBUILD_USER="root"
		PORTBUILD_GROUP="wheel"
		;;
	esac
	portbuild_gid=$(injail pw groupshow "${PORTBUILD_GROUP}" 2>/dev/null | cut -d : -f3 || :)
	case "${portbuild_gid}" in
	"")
		msg_n "Creating group ${PORTBUILD_GROUP}"
		injail pw groupadd "${PORTBUILD_GROUP}" -g "${PORTBUILD_GID}" || \
		    err 1 "Unable to create group ${PORTBUILD_GROUP}"
		echo " done"
		;;
	*)
		PORTBUILD_GID=${portbuild_gid}
		;;
	esac
	: ${CCACHE_GID:=${PORTBUILD_GID}}
	portbuild_uid=$(injail id -u "${PORTBUILD_USER}" 2>/dev/null || :)
	case "${portbuild_uid}" in
	"")
		msg_n "Creating user ${PORTBUILD_USER}"
		injail pw useradd "${PORTBUILD_USER}" -u "${PORTBUILD_UID}" \
		    -g "${PORTBUILD_GROUP}" -d /nonexistent -c "Package builder" || \
		    err 1 "Unable to create user ${PORTBUILD_USER}"
		echo " done"
		;;
	*)
		PORTBUILD_UID=${portbuild_uid}
		;;
	esac
	portbuild_gids=$(injail id -G "${PORTBUILD_USER}" 2>/dev/null || :)
	portbuild_add_group=true
	for _gid in ${portbuild_gids}; do
		case "${_gid}" in
		"${PORTBUILD_GID}")
			portbuild_add_group=false
			break
			;;
		esac
	done
	case "${portbuild_add_group}" in
	"true")
		msg_n "Adding user ${PORTBUILD_USER} to ${PORTBUILD_GROUP}"
		injail pw groupmod "${PORTBUILD_GROUP}" -m "${PORTBUILD_USER}" || \
		    err 1 "Unable to add user ${PORTBUILD_USER} to group ${PORTBUILD_GROUP}"
		echo " done"
		;;
	esac
	if was_a_bulk_run; then
		msg "Will build as ${PORTBUILD_USER}:${PORTBUILD_GROUP} (${PORTBUILD_UID}:${PORTBUILD_GID})"
	fi

	setup_ccache "${tomnt}"

	# We want this hook to run before any make -V executions in case
	# a hook modifies ports or the jail somehow relevant.
	run_hook jail start

	setup_ports_env "${tomnt:?}" "${tomnt:?}/etc/make.conf"

	if schg_immutable_base && [ "${tomnt}" = "${MASTERMNT}" ]; then
		msg "Setting schg on jail base paths"
		# The first few directories are allowed for ports to write to.
		find -x "${tomnt:?}" \
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
		if [ -d "${tomnt:?}/boot/modules" ]; then
		    chflags -R noschg "${tomnt:?}/boot/modules"
		fi
		if [ -d "${tomnt:?}/boot/firmware" ]; then
		    chflags -R noschg "${tomnt:?}/boot/firmware"
		fi
		chflags -R noschg \
		    "${tomnt:?}${LOCALBASE:-/usr/local}" \
		    "${tomnt:?}${PREFIX:-/usr/local}" \
		    "${tomnt:?}/usr/home" \
		    "${tomnt:?}/boot"
		if [ -n "${CCACHE_STATIC_PREFIX-}" ] && \
			[ -x "${CCACHE_STATIC_PREFIX}/bin/ccache" ]; then
			# Need to allow ccache-update-links to work.
			chflags noschg \
			    "${tomnt:?}${CCACHE_JAIL_PREFIX:?}/libexec/ccache" \
			    "${tomnt:?}${CCACHE_JAIL_PREFIX:?}/libexec/ccache/world"
		fi
	fi


	return 0
}

load_blacklist() {
	[ $# -ge 2 ] || eargs load_blacklist name ptname setname
	local name=$1
	local ptname=$2
	local setname=$3
	local bl b bfile ports

	bl="- ${setname} ${ptname} ${name}"
	case "${setname:+set}" in
	set) bl="${bl} ${ptname}-${setname}" ;;
	esac
	bl="${bl} ${name}-${ptname}"
	case "${setname:+set}" in
	set) bl="${bl} ${name}-${setname} ${name}-${ptname}-${setname}" ;;
	esac
	# If emulating always load a qemu-blacklist as it has special needs.
	if [ ${QEMU_EMULATING} -eq 1 ]; then
		bl="${bl} qemu"
	fi
	for b in ${bl} ; do
		case "${b}" in
		"-") unset b ;;
		esac
		bfile="${b:+${b}-}blacklist"
		[ -f "${POUDRIERED:?}/${bfile:?}" ] || continue
		msg "Loading blacklist from ${POUDRIERED:?}/${bfile:?}"
		ports="$(grep -h -v -E '(^[[:space:]]*#|^[[:space:]]*$)' \
		    "${POUDRIERED:?}/${bfile:?}" | sed -e 's|[[:space:]]*#.*||')" ||
		    ports=
		for port in ${ports}; do
			case " ${BLACKLIST-} " in
			*" ${port} "*) continue;;
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
	if [ -n "${ARCH}" ]; then
		arch="${ARCH}"
	elif [ -n "${name}" ]; then
		_jget arch "${name}" arch || \
		    err 1 "Missing arch metadata for jail"
	fi

	case "${arch:+set}" in
	set)
		if need_cross_build "${host_arch}" "${arch}"; then
			cat >> "${dst_makeconf}" <<-EOF
			MACHINE=${arch%.*}
			MACHINE_ARCH=${arch#*.}
			ARCH=\${MACHINE_ARCH}
			EOF
			case "${name:+set}" in
			set)
				if _jget version ${name} version; then
					export_cross_env "${JAILNAME}" \
					    "${arch}" \
					    "${version}"
				fi
				;;
			esac
		fi
		;;
	esac

	makeconf="- ${setname} ${ptname} ${name}"
	case "${setname:+set}" in
	set) makeconf="${makeconf} ${ptname}-${setname}" ;;
	esac
	makeconf="${makeconf} ${name}-${ptname}"
	case "${setname:+set}" in
	set)
		makeconf="${makeconf} ${name}-${setname} \
		    ${name}-${ptname}-${setname}"
		;;
	esac
	for opt in ${makeconf}; do
		append_make "${POUDRIERED:?}" "${opt}" "${dst_makeconf}"
	done

	# Check for and load plugin make.conf files
	if [ -d "${HOOKDIR:?}/plugins" ]; then
		for plugin_dir in ${HOOKDIR:?}/plugins/*; do
			# Check empty dir
			case "${plugin_dir}" in
			"${HOOKDIR:?}/plugins/*") break ;;
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
	local jail ptname setname loaded_conf
	local OPTIND=1

	# msg_debug is not properly setup this early for VERBOSE to be set
	# so spy on -v and set debug and use it locally instead.
	debug=${VERBOSE:-0}

	# Directly included from tests
	case "${IN_TEST:-0}" in
	1)
		jail="${JAILNAME-}"
		ptname="${PTNAME-}"
		setname="${SETNAME-}"
		debug="${VERBOSE:-0}"
		;;
	*)
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
		;;
	esac

	loaded_conf=0
	if [ -r "${POUDRIERE_ETC:?}/poudriere.conf" ]; then
		if [ "${debug}" -gt 1 ]; then
			msg "Reading ${POUDRIERE_ETC}/poudriere.conf"
		fi
		. "${POUDRIERE_ETC:?}/poudriere.conf"
		loaded_conf=1
	fi
	if [ -r "${POUDRIERED:?}/poudriere.conf" ]; then
		case "$(realpath -q "${POUDRIERED:?}/poudriere.conf")" in
		$(realpath -q "${POUDRIERE_ETC:?}/poudriere.conf")) ;;
		*)
			if [ "${debug}" -gt 1 ]; then
				msg "Reading ${POUDRIERED}/poudriere.conf"
			fi
			. "${POUDRIERED:?}/poudriere.conf"
			loaded_conf=1
			;;
		esac
	fi
	case "${loaded_conf}" in
	0)
		err 1 "Unable to find a readable poudriere.conf in ${POUDRIERE_ETC} or ${POUDRIERED}"
		;;
	esac

	files="${setname} ${ptname} ${jail}"
	case "${ptname:+set}.${setname:+set}" in
	set.set) files="${files} ${ptname}-${setname}" ;;
	esac
	case "${jail:+set}.${ptname:+set}" in
	set.set) files="${files} ${jail}-${ptname}" ;;
	esac
	case "${jail:+set}.${setname:+set}" in
	set.set) files="${files} ${jail}-${setname}";;
	esac
	case "${jail:+set}.${setname:+set}.${ptname:+set}" in
	set.set.set)
		files="${files} ${jail}-${ptname}-${setname}"
		;;
	esac
	for file in ${files}; do
		file="${POUDRIERED:?}/${file}-poudriere.conf"
		if [ -r "${file}" ]; then
			if [ "${debug}" -gt 1 ]; then
				msg "Reading ${file}"
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

	stop_builders || :
	run_hook jail stop
	jstop || :
	msg "Unmounting file systems"
	destroyfs ${MASTERMNT:?} jail || :
	umountfs "${MASTERMNTROOT:?}"
	rm -rfx "${MASTERMNTROOT:?}"
	export STATUS=0

	# Don't override if there is a failure to grab the last status.
	_bget last_status status || :
	case "${last_status:+set}" in
	set)
		bset status "stopped:${last_status}" 2>/dev/null || :
		;;
	esac
}

jail_cleanup() {
	case "${CLEANED_UP:+set}" in
	set) return 0 ;;
	esac
	msg "Cleaning up"

	# Only bother with this if using jails as this may be being ran
	# from queue.sh or daemon.sh, etc.
	case "${MASTERMNT:+set}.${MASTERNAME:+set}" in
	set.set)
		if was_a_jail_run; then
			jail_stop

			case "${PACKAGES:+set}" in
			set) rm -rfx "${PACKAGES:?}/.npkg" ;;
			esac
			rm -rf \
			    "${POUDRIERE_DATA:?}/packages/${MASTERNAME:?}/.latest/.npkg" \
			    2>/dev/null || :
		fi
	esac

	export CLEANED_UP=1
}

download_from_repo_check_pkg() {
	[ $# -eq 10 ] || eargs download_from_repo_check_pkg pkgname \
	    abi remote_all_options remote_all_pkgs remote_all_deps \
	    remote_all_annotations remote_all_abi remote_all_prefix \
	    remote_all_cats output
	local pkgname="$1"
	local abi="$2"
	local remote_all_options="$3"
	local remote_all_pkgs="$4"
	local remote_all_deps="$5"
	local remote_all_annotations="$6"
	local remote_all_abi="$7"
	local remote_all_prefix="$8"
	local remote_all_cats="$9"
	local output="${10}"
	local pkgbase selected_options remote_options found
	local run_deps lib_deps raw_deps dep dep_pkgname
	local local_deps local_deps_vers remote_deps
	local remote_abi remote_osversion remote_prefix prefix no_arch
	local -

	# The options checks here are not optimized because we lack goto.
	pkgbase="${pkgname%-*}"

	# Skip blacklisted packages
	# pkg is always blacklisted so it is built locally
	if patternlist_match "${PACKAGE_FETCH_BLACKLIST-} ${P_PKG_PKGBASE:?}" \
	    "${pkgbase:?}"; then
		msg_verbose "Package fetch: Skipping" \
		    "${COLOR_PORT}${pkgname}${COLOR_RESET}: blacklisted"
		return
	fi

	found=$(awk -v pkgname="${pkgname}" -vpkgbase="${pkgbase}" \
	    '$1 == pkgbase {print $2; exit}' "${remote_all_pkgs}")
	case "${found}" in
	"")
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: not found in remote"
		return
		;;
	"${pkgname}") ;;
	# Version mismatch
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote version mismatch: ${COLOR_PORT}${found}${COLOR_RESET}"
		return
		;;
	esac

	# ABI
	remote_abi=$(awk -v pkgname="${pkgname}" -vpkgbase="${pkgbase}" \
	    '$1 == pkgbase {print $2; exit}' "${remote_all_abi}")
	if shash_get pkgname-no_arch "${pkgname}" no_arch; then
		abi="${abi%:*}:*"
	fi
	case "${abi}" in
	"${remote_abi}") ;;
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote ABI mismatch: ${remote_abi} (want: ${abi})"
		return
		;;
	esac

	case "${IGNORE_OSVERSION-}" in
	"yes") ;;
	*)
		# If package is not NOARCH then we need to check its FreeBSD_version
		remote_osversion=$(awk -vpkgbase="${pkgbase}" ' \
		    $1 == pkgbase && $2 == "FreeBSD_version" {print $3; exit}' \
		    "${remote_all_annotations}")
		# blank likely means NOARCH
		if [ "${remote_osversion:-0}" -gt "${JAIL_OSVERSION}" ]; then
			msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote osversion too new: ${remote_osversion} (want <=${JAIL_OSVERSION})"
			return
		fi

		# If package has a kld then we need to check its FreeBSD_version
		if awk -vpkgbase="${pkgbase}" ' \
			$1 == pkgbase && $2 == "kld" {
				found = 1
				exit
			}
			END {
				exit !found
			}' "${remote_all_cats}"; then
			if [ "${remote_osversion:-0}" -ne "${JAIL_OSVERSION}" ]; then
				msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote has kld and mismatched osversion: ${remote_osversion} (want ==${JAIL_OSVERSION})"
			fi
		fi
		;;
	esac

	# PREFIX
	remote_prefix=$(awk -v pkgname="${pkgname}" -vpkgbase="${pkgbase}" \
	    '$1 == pkgbase {print $2; exit}' "${remote_all_prefix}")
	shash_get pkgname-prefix "${pkgname}" prefix ||
	    prefix="${LOCALBASE:-/usr/local}"
	case "${prefix}" in
	"${remote_prefix}") ;;
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: remote PREFIX mismatch: ${remote_prefix} (want: ${prefix})"
		return
		;;
	esac

	# Options mismatch
	remote_options=$(awk -vpkgbase="${pkgbase}" ' \
	    BEGIN {printed=0}
	    $1 == pkgbase && $3 == "on" {print "+"$2;printed=1}
	    $1 == pkgbase && $3 == "off" {print "-"$2;printed=1}
	    $1 != pkgbase && printed == 1 {exit}
	    ' \
	    "${remote_all_options}" | sort -k1.2 -u | paste -s -d ' ' -)

	shash_get pkgname-options "${pkgname}" selected_options || \
	    selected_options=
	case "${selected_options}" in
	"${remote_options}") ;;
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
		case "${PKG_NO_VERSION_FOR_DEPS:?}" in
		"no") echo "${dep_pkgname}" ;;
		*) echo "${dep_pkgname%-*}" ;;
		esac
	done | sort -u | paste -s -d ' ' -)
	local_deps_vers=$(for dep in ${raw_deps}; do
		get_pkgname_from_originspec "${dep#*:}" dep_pkgname || continue
		echo "${dep_pkgname}"
	done | sort -u | paste -s -d ' ' -)
	remote_deps=$(awk -vpkgbase="${pkgbase}" ' \
	    BEGIN {printed=0}
	    $1 == pkgbase {
		    # Trim out PKG_NO_VERSION_FOR_DEPS missing version
		    sub(/-\(null\)$/, "", $2)
		    print $2
		    printed=1
	    }
	    $1 != pkgbase && printed == 1 {exit}
	    ' \
	    "${remote_all_deps}" | sort -u | paste -s -d ' ' -)
	case "${remote_deps}" in
	# All the deps are unversioned and match local
	"${local_deps}") ;;
	# The deps are versioned but match local.
	# XXX: Can take this out once PKG_NO_VERSION_FOR_DEPS is default
	# enabled in official packages; We may delete this fetched package
	# if a deep dependency is deleted by delete_old_pkg().  See
	# download_from_repo_post_delete() for other side of this.
	"${local_deps_vers}") ;;
	*)
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: deps wanted: ${local_deps}"
		# XXX: Can take this out once PKG_NO_VERSION_FOR_DEPS is default enabled in official packages
		msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: deps wanted: ${local_deps_vers}"
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
	local remote_all_annotations remote_all_abi remote_all_prefix
	local remote_all_cats missing_pkgs pkgbase cnt
	local remote_pkg_ver local_pkg_name local_pkg_ver
	local packages_rel
	local -

	case "${PACKAGE_FETCH_BRANCH-}" in
	"") return 0 ;;
	esac

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
	while mapfile_read_loop "${MASTER_DATADIR:?}/all_pkgs_not_ignored" \
	    pkgname originspec listed ignored; do
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
		if was_a_testport_run; then
			# Skip testport package
			case "${pkgname}" in
			"${PKGNAME:?}") continue ;;
			esac
		fi
		if ! pkgqueue_contains "build" "${pkgname}" ; then
			msg_debug "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: not queued"
			continue
		fi
		# XXX only work when PKG_EXT is the same as the upstream
		if [ -f "${PACKAGES:?}/All/${pkgname:?}.${PKG_EXT}" ]; then
			msg_debug "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: have package"
			continue
		fi
		pkgbase="${pkgname%-*}"
		if ! patternlist_match "${PACKAGE_FETCH_WHITELIST-}" \
		    "${pkgbase}"; then
			msg_verbose "Package fetch: Skipping ${COLOR_PORT}${pkgname}${COLOR_RESET}: not in whitelist" >&2
			continue
		fi
		echo "${pkgname:?}"
	done > "${missing_pkgs:?}"
	if [ ! -s "${missing_pkgs}" ]; then
		msg "Package fetch: No eligible missing packages to fetch"
		rm -f "${missing_pkgs}"
		return
	fi

	if ensure_pkg_installed; then
		pkg_bin="${PKG_BIN:?}"
	else
		# Will bootstrap
		msg "Package fetch: bootstrapping pkg"
		pkg_bin="pkg"
	fi
	cat >> "${MASTERMNT:?}/etc/pkg/poudriere.conf" <<-EOF
	FreeBSD: { enabled: no }
	FreeBSD-kmods: { enabled: no }
	FreeBSD-ports: { enabled: no }
	FreeBSD-ports-kmods: { enabled: no }
	FreeBSD-base: { enabled: no }

	Poudriere: {
	        url: ${packagesite};
	        mirror_type: $(if [ "${packagesite#pkg+}" = "${packagesite}" ]; then echo "none"; else echo "srv"; fi);
	}
	EOF

	# XXX: bootstrap+rquery could be done asynchronously during deps
	# Bootstrapping might occur here.
	# XXX: rquery is supposed to 'update' but it does not on first run.
	if ! JNETNAME="n" injail env ASSUME_ALWAYS_YES=yes \
	    PACKAGESITE="${packagesite:?}" \
	    ${pkg_bin} update -f; then
		msg "Package fetch: Not fetching as remote repository is unavailable."
		rm -f "${missing_pkgs}"
		return 0
	fi
	# Don't trust pkg-update to return its error
	if ! injail ${pkg_bin} rquery -U %n pkg >/dev/null; then
		msg "Package fetch: Failed to fetch package repository."
		rm -f "${missing_pkgs}"
		return 0
	fi

	remote_pkg_ver="$(injail ${pkg_bin} rquery -U %v "${P_PKG_PKGBASE:?}")"
	local_pkg_name="${P_PKG_PKGNAME:?}"
	local_pkg_ver="${local_pkg_name##*-}"
	case "$(pkg_version -t "${remote_pkg_ver}" "${local_pkg_ver}")" in
	">")
		msg "Package fetch: Not fetching due to remote pkg being newer than local: ${remote_pkg_ver} vs ${local_pkg_ver}"
		rm -f "${missing_pkgs}"
		return 0
		;;
	esac

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
	remote_all_cats=$(mktemp -t remote_all_cats)
	case "${IGNORE_OSVERSION-}" in
	"yes") ;;
	*)
		injail ${pkg_bin} rquery -U '%n %At %Av' > "${remote_all_annotations}"
		injail ${pkg_bin} rquery -U '%n %C' > "${remote_all_cats}"
		;;
	esac
	abi="$(injail "${pkg_bin}" config ABI)"
	remote_all_abi=$(mktemp -t remote_all_abi)
	injail ${pkg_bin} rquery -U '%n %q' > "${remote_all_abi}"
	remote_all_prefix=$(mktemp -t remote_all_prefix)
	injail ${pkg_bin} rquery -U '%n %p' > "${remote_all_prefix}"

	parallel_start || err 1 "parallel_start"
	wantedpkgs=$(mktemp -t wantedpkgs)
	while mapfile_read_loop "${missing_pkgs}" pkgname; do
		parallel_run download_from_repo_check_pkg \
		    "${pkgname}" "${abi}" \
		    "${remote_all_options}" "${remote_all_pkgs}" \
		    "${remote_all_deps}" "${remote_all_annotations}" \
		    "${remote_all_abi}" "${remote_all_prefix}" \
		    "${remote_all_cats}" "${wantedpkgs}"
	done
	if ! parallel_stop; then
		err 1 "Package fetch: Errors detected downloading packages"
	fi
	rm -f "${missing_pkgs}" \
	    "${remote_all_pkgs}" "${remote_all_options}" "${remote_all_deps}" \
	    "${remote_all_annotations}" "${remote_all_abi}" \
	    "${remote_all_prefix}" "${remote_all_cats}"

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
	count_lines "${wantedpkgs}" cnt
	msg "Package fetch: Will fetch ${cnt} packages from remote or local pkg cache"

	echo "${packagesite_resolved}" > "${MASTER_DATADIR:?}/pkg_fetch_url"

	# Fetch into a cache and link back into the PACKAGES dir.
	mkdir -p "${PACKAGES:?}/All" \
	    "${PACKAGES_PKG_CACHE:?}" \
	    "${MASTERMNT:?}/var/cache/pkg"
	${NULLMOUNT} "${PACKAGES_PKG_CACHE:?}" "${MASTERMNT:?}/var/cache/pkg" || \
	    err 1 "null mount failed for pkg cache"
	if ! JNETNAME="n" injail xargs \
	    env ASSUME_ALWAYS_YES=yes \
	    ${pkg_bin} fetch -U < "${wantedpkgs}"; then
		msg "Package fetch: Error fetching packages"
		umountfs "${MASTERMNT:?}/var/cache/pkg"
		rm -f "${wantedpkgs}"
		return 0
	fi
	relpath "${PACKAGES:?}" "${PACKAGES_PKG_CACHE:?}" packages_rel ||
	    err 1 "download_from_repo: relpath ${PACKAGES:?}" \
		"${PACKAGES_PKG_CACHE:?}"
	while mapfile_read_loop "${wantedpkgs}" pkgname; do
		if [ ! -e "${PACKAGES_PKG_CACHE:?}/${pkgname}.${PKG_EXT}" ]; then
			msg_warn "${COLOR_PORT}${pkgname}.${PKG_EXT}${COLOR_RESET} not found. Remote PKG_SUFX likely differs temporarily"
			continue
		fi
		echo "${pkgname}"
	done | sort | tee "${MASTER_DATADIR:?}/pkg_fetch" | (
		cd "${PACKAGES_PKG_CACHE:?}" ||
		    err 1 "cd ${PACKAGES_PKG_CACHE:?}"
		sed -e "s,\$,.${PKG_EXT}," |
		    xargs -J % ln -fL % "${packages_rel:?}/All/"
	)
	while mapfile_read_loop "${MASTER_DATADIR:?}/pkg_fetch" pkgname; do
		msg "Package fetch: Using cached copy of ${COLOR_PORT}${pkgname}${COLOR_RESET}"
	done
	umountfs "${MASTERMNT:?}/var/cache/pkg"
	rm -f "${wantedpkgs}"
	# Bootstrapped.  Need to setup symlinks.
	case "${pkg_bin}" in
	"pkg")
		# Save the bootstrapped pkg for package sanity/version checking
		cp -f "${MASTERMNT:?}${LOCALBASE:-/usr/local}/sbin/pkg-static" \
		    "${MASTERMNT:?}${PKG_BIN:?}"
		;;
	esac
	ensure_pkg_installed || \
	    err 1 "download_from_repo: failure to bootstrap pkg"
}

download_from_repo_make_log() {
	[ $# -eq 2 ] || eargs download_from_repo_make_log pkgname packagesite
	local pkgname="$1"
	local packagesite="$2"
	local logfile originspec

	get_originspec_from_pkgname originspec "${pkgname}"
	if [ "${DRY_RUN:-0}" -eq 0 ]; then
		local log

		_log_path log
		_logfile logfile "${pkgname}"
		{
			local NO_GIT

			NO_GIT=1 buildlog_start "${pkgname}" "${originspec}"
			print_phase_header "poudriere"
			echo "Fetched from ${packagesite}"
			print_phase_footer
			buildlog_stop "${pkgname}" "${originspec}" 0
		} | write_atomic "${logfile}"
		ln -fs "../${pkgname:?}.log" \
		    "${log:?}/logs/fetched/${pkgname:?}.log"
	fi
	badd ports.fetched "${originspec} ${pkgname}"
}

# Remove from the pkg_fetch list packages that need to rebuild anyway.
download_from_repo_post_delete() {
	[ $# -eq 0 ] || eargs download_from_repo_post_delete
	local log fpkgname packagesite

	if [ -z "${PACKAGE_FETCH_BRANCH-}" ] ||
	    [ ! -f "${MASTER_DATADIR:?}/pkg_fetch" ]; then
		bset "stats_fetched" 0
		return 0
	fi
	bset status "fetched_package_logs:"
	_log_path log
	msg "Package fetch: Generating logs for fetched packages"
	read_line packagesite "${MASTER_DATADIR:?}/pkg_fetch_url"
	parallel_start || err 1 "parallel_start"
	while mapfile_read_loop "${MASTER_DATADIR:?}/pkg_fetch" fpkgname; do
		if [ ! -e "${PACKAGES}/All/${fpkgname}.${PKG_EXT}" ]; then
			case "${PKG_NO_VERSION_FOR_DEPS:?}" in
			"no")
				# Due to not recursively validating a package
				# will be used, we still may fetch a package
				# and then later delete it.
				# The PKG_NO_VERSION_FOR_DEPS=yes feature is
				# not prone to this error since we do not
				# recursively delete.
				# Package fetch: Using cached copy of python311-3.11.9_1
				# Package fetch: Using cached copy of py311-setuptools-63.1.0_1
				# Deleting python311-3.11.9_1.pkg: missing dependency: readline-8.2.10
				# Deleting py311-setuptools-63.1.0_1.pkg: missing dependency: python311-3.11.9_1
				msg_debug "download_from_repo_post_delete: We lost fetched ${COLOR_PORT}${fpkgname}.${PKG_EXT}${COLOR_RESET}"
				continue
				;;
			*)
				# We should not be fetching packages and then
				# deleting them.  Let's get the user to report
				# to us to not waste bandwidth.
				err ${EX_SOFTWARE} "download_from_repo_post_delete: We lost fetched unversioned ${COLOR_PORT}${fpkgname}.${PKG_EXT}${COLOR_RESET}"
				;;
			esac
		fi
		echo "${fpkgname}"
	done | while mapfile_read_loop_redir fpkgname; do
		parallel_run \
		    download_from_repo_make_log "${fpkgname}" "${packagesite}"
	done | write_atomic "${log:?}/.poudriere.pkg_fetch%"
	if ! parallel_stop; then
		err 1 "Errors creating fetched package logs"
	fi
	mv -f "${MASTER_DATADIR:?}/pkg_fetch_url" \
	    "${log:?}/.poudriere.pkg_fetch_url%"
	# update_stats
	_bget '' ports.fetched
	bset "stats_fetched" "${_read_file_lines_read:?}"
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

	for pkg in "${PACKAGES:?}"/All/*.txz "${PACKAGES:?}"/Latest/*.txz; do
		case "${pkg}" in
		"${PACKAGES:?}/All/*.txz") return 0 ;;
		"${PACKAGES:?}/Latest/*.txz") continue ;;
		esac
		pkgnew="${pkg%.txz}.${PKG_EXT}"
		case "${pkg}" in
		"${PACKAGES:?}"/Latest/*)
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
	if [ -e "${PACKAGES:?}/Latest/pkg.txz.pubkeysig" ] &&
	    ! [ -e "${PACKAGES:?}/Latest/pkg.${PKG_EXT}.pubkeysig" ]; then
		rename "${PACKAGES:?}/Latest/pkg.txz.pubkeysig" \
		    "${PACKAGES:?}/Latest/pkg.${PKG_EXT}.pubkeysig"
	fi
}

# return 0 if the package dir exists and has packages, 0 otherwise
package_dir_exists_and_has_packages() {
	if [ ! -d "${PACKAGES:?}/All" ]; then
		return 1
	fi
	if dirempty "${PACKAGES:?}/All"; then
		return 1
	fi
	# Check for non-empty directory with no packages in it
	for pkg in "${PACKAGES:?}"/All/*.${PKG_EXT}; do
		case "${pkg}" in
		"${PACKAGES:?}/All/*.${PKG_EXT}") return 1 ;;
		esac
		# Stop on first match
		break
	done
	return 0
}

sanity_check_pkg() {
	[ $# -eq 1 ] || eargs sanity_check_pkg pkg
	local pkg="$1"
	local compiled_deps_pkgnames pkgname dep_pkgname
	local pkgfile reason displayed_warning

	pkgfile="${pkg##*/}"
	pkgname="${pkgfile%.*}"
	# IGNORED and skipped packages are still deleted here so we don't
	# provide an inconsistent repository.
	pkgbase_is_needed "${pkgname}" || return 0
	compiled_deps_pkgnames=
	if ! pkg_get_dep_origin_pkgnames '' compiled_deps_pkgnames "${pkg}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: corrupted package (deps)"
		delete_pkg "${pkg}"
		return 65	# Package deleted, need another pass
	fi
	displayed_warning=0
	for dep_pkgname in ${compiled_deps_pkgnames}; do
		case "${dep_pkgname}" in
		*"-(null)")
			# Dependency generated with PKG_NO_VERSION_FOR_DEPS
			# which means this package doesn't care about any
			# specific dependency's version.
			case "${displayed_warning}" in
			0)
				msg_debug "${COLOR_PORT}${pkgname}${COLOR_RESET} has unversioned dependencies: ${COLOR_PORT}${compiled_deps_pkgnames}${COLOR_RESET}"
				displayed_warning=1
				;;
			esac
			case "${PKG_NO_VERSION_FOR_DEPS:?}" in
			"no")
				# This package format is no longer acceptable
				msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: unwanted unversioned dependency: ${COLOR_PORT}${dep_pkgname}${COLOR_RESET}"
				delete_pkg "${pkg}"
				return 65	# Package deleted, need another pass
				;;
			esac
			# Nothing more to do if it is already in
			# PKG_NO_VERSION_FOR_DEPS format.
			return 0
			;;
		esac
		if [ -e "${PACKAGES:?}/All/${dep_pkgname}.${PKG_EXT}" ]; then
			continue
		fi
		case "${PKG_NO_VERSION_FOR_DEPS:?}" in
		"no")
			reason="missing dependency"
			;;
		*)
			if ! pkgqueue_contains build "${dep_pkgname}"; then
				reason="missing versioned dependency"
			else
				# The dependency is queued with the
				# same needed version so this is not a
				# violation.
				continue
			fi
			;;
		esac
		msg_debug "${COLOR_PORT}${pkg}${COLOR_RESET} needs ${reason} ${COLOR_PORT}${dep_pkgname}${COLOR_RESET}"
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: ${reason}: ${COLOR_PORT}${dep_pkgname}${COLOR_RESET}"
		delete_pkg "${pkg}"
		return 65	# Package deleted, need another pass
	done

	return 0
}

sanity_check_pkgs() {
	local ret=0

	package_dir_exists_and_has_packages || return 0
	ensure_pkg_installed ||
	    err ${EX_SOFTWARE} "sanity_check_pkg: Missing bootstrap pkg"

	parallel_start || err 1 "parallel_start"
	for pkg in "${PACKAGES:?}"/All/*.${PKG_EXT}; do
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

	( cd "${mnt:?}" && \
	    mtree -X "${MASTER_DATADIR:?}/mtree.preinstexclude${PORTTESTING}" \
	    -f "${MNT_DATADIR:?}/mtree.preinst" -p . ) | \
	    while mapfile_read_loop_redir l; do
		local changed read_again

		changed=
		while :; do
			read_again=0

			# Handle leftover read from changed paths
			case ${l} in
			*extra|*missing|extra:*|*changed|*:*)
				case "${changed:+set}" in
				set)
					echo "${changed}"
					changed=
					;;
				esac
				;;
			esac
			case ${l} in
			*extra)
				if [ -d "${mnt:?}/${l% *}" ]; then
					find "${mnt:?}/${l% *}" -exec echo "+ {}" \;
				else
					echo "+ ${mnt:?}/${l% *}"
				fi
				;;
			*missing)
				l="${l#./}"
				echo "- ${mnt:?}/${l% *}"
				;;
			*changed)
				changed="M ${mnt:?}/${l% *}"
				read_again=1
				;;
			extra:*)
				if [ -d "${mnt:?}/${l#* }" ]; then
					find "${mnt:?}/${l#* }" -exec echo "+ {}" \;
				else
					echo "+ ${mnt:?}/${l#* }"
				fi
				;;
			*:*)
				changed="M ${mnt:?}/${l%:*} ${l#*:}"
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
			case "${changed:+set}" in
			set) echo "${changed}" ;;
			esac
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
	( cd "${mnt:?}" && \
		mtree -X "${MASTER_DATADIR:?}/mtree.${mtree_target}exclude${PORTTESTING}" \
		-f "${MNT_DATADIR:?}/mtree.${mtree_target}" \
		-p . ) >> "${tmpfile:?}"
	echo " done"

	if [ -s "${tmpfile:?}" ]; then
		msg "Error: ${err_msg}"
		cat "${tmpfile:?}"
		job_build_status "${status_value}" "${originspec}" "${pkgname}"
		ret=1
	fi
	unlink "${tmpfile:?}"

	return $ret
}

gather_distfiles() {
	[ $# -eq 7 ] || [ $# -eq 6 ] ||
	    eargs gather_distfiles '[-l]' originspec_main pkgname_main \
	    originspec pkgname from to
	local OPTIND flag lflag

	OPTIND=1
	lflag=0
	while getopts "l" flag; do
		case "${flag}" in
		l) lflag=1 ;;
		*) err 1 "gather_distfiles: invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -eq 6 ] ||
	    eargs gather_distfiles '[-l]' originspec_main pkgname_main \
	    originspec pkgname from to
	local originspec_main="$1"
	local pkgname_main="$2"
	local originspec="$3"
	local pkgname="$4"
	local from to
	local sub dists d specials special origin
	local dep_originspec pkgname flavor subpkg
	local srcsize dstsize doinstall

	from="$(realpath "$5")"
	to="$(realpath "$6")"
	# Can't remove the values as other ports may have us as a special.
	shash_get originspec-dist_subdir "${originspec}" sub || sub=
	shash_get originspec-dist_allfiles "${originspec}" dists || dists=
	originspec_decode "${originspec}" origin flavor subpkg
	case "${pkgname}" in
	"")
		# Recursive gather_distfiles()
		shash_get originspec-pkgname "${originspec}" pkgname || \
		    err 1 "gather_distfiles: Could not find PKGNAME for ${COLOR_PORT}${originspec}${COLOR_RESET}"
		;;
	esac
	shash_get pkgname-depend_specials "${pkgname}" specials || specials=

	job_msg_dev "${COLOR_PORT}${origin}${flavor:+@${flavor}}${subpkg:+~${subpkg}} | ${pkgname_main}${COLOR_RESET}: distfiles ${from} -> ${to}"
	mkdir -p "${to}/${sub}"
	(
		cd "${to}/${sub}"
		if have_builtin mkdir; then
			for d in ${dists}; do
				case "${d}" in
				*/*) ;;
				*) continue ;;
				esac
				mkdir -p "${d%/*}"
			done
		else
			for d in ${dists}; do
				case "${d}" in
				*/*) ;;
				*) continue ;;
				esac
				echo "${d%/*}"
			done | sort -u | xargs mkdir -p
		fi
	)
	for d in ${dists}; do
		if [ ! -f "${from}/${sub}/${d}" ]; then
			continue
		fi
		case "${lflag}" in
		0)	# We want to do a hard copy of the files.
			local linkpath

			# If the file is a symlink then it may be pointing
			# back to the null-mounted distdir, or it is some
			# distfile symlink like go.mod or user-made.
			if linkpath="$(readlink "${from}/${sub}/${d}")"; then
				case "${linkpath}" in
				..*/distfiles/*)
					msg_debug "gather_distfiles:" \
					    "skipping untouched" \
					    "'${from}/${sub}/${d}'"
					continue
					;;
				esac
				# We need to copy the symlink.
			fi
			if [ ! -f "${to}/${sub}/${d}" ]; then
				msg_debug "gather_distfiles: missing" \
				    "'${to}/${sub}/${d}'"
				doinstall=1
			else
				dstsize="$(stat -f %z "${to}/${sub}/${d}")"
				srcsize="$(stat -f %z "${from}/${sub}/${d}")"
				case "${srcsize}" in
				"${dstsize}")
					msg_debug "gather_distfiles:" \
					    "skipping copy" \
					    "'${from}/${sub}/${d}'"
					doinstall=0
					;;
				*)
					msg_debug "gather_distfiles:" \
					    "size mismatch" \
					    "($srcsize != $dstsize)," \
					    "overwriting '${to}/${sub}/${d}'"
					doinstall=1
					;;
				esac
			fi
			if [ "${doinstall}" -eq 1 ]; then
				msg_debug "gather_distfiles:" \
				    "copying" \
				    "'${from}/${sub}/${d}'" \
				    "->" \
				    "'${to}/${sub}/${d}'"
				install -pS -m 0644 \
				    "${from}/${sub}/${d}" \
				    "${to}/${sub}/${d}" ||
				    return 1
			fi
			;;
		1)	# We want to symlink all the needed files in.
			msg_debug "gather_distfiles:" \
			    "symlinking (relative)" \
			    "'${to}/${sub}/${d}'" \
			    "->" \
			    "${from}/${sub}/${d}"
			install -p -m 0644 -lrs \
			    "${from}/${sub}/${d}" \
			    "${to}/${sub}/${d}" ||
			    return 1
			;;
		esac
	done

	for special in ${specials}; do
		gather_distfiles "${originspec_main}" "${pkgname_main}" \
		    "${special}" "" \
		    "${from}" "${to}"
	done

	return 0
}

# Avoid some of our global env leaking out.
cleanenv() {
	[ "$#" -gt 0 ] || eargs cleanenv cmd ...
	local save

	# unexport these but keep them set for internal use
	local LIBEXECPREFIX; save="${LIBEXECPREFIX}"; unset LIBEXECPREFIX; LIBEXECPREFIX="${save}";
	local SCRIPTNAME; save="${SCRIPTNAME}"; unset SCRIPTNAME; SCRIPTNAME="${save}";
	local SCRIPTPATH; save="${SCRIPTPATH}"; unset SCRIPTPATH; SCRIPTPATH="${save}";
	local SCRIPTPREFIX; save="${SCRIPTPREFIX}"; unset SCRIPTPREFIX; SCRIPTPREFIX="${save}";
	local USE_DEBUG; save="${USE_DEBUG}"; unset USE_DEBUG; USE_DEBUG="${save}";
	"$@"
}

# Build+test port and return 1 on first failure
# Return 2 on test failure if PORTTESTING_FATAL=no
build_port() {
	[ $# -eq 2 ] || eargs build_port originspec pkgname
	local originspec="$1"
	local pkgname="$2"
	local port flavor portdir subpkg pkgbase
	local mnt
	local log
	local network
	local hangstatus
	local pkgenv phaseenv
	local targets
	local jailuser JUSER
	local testfailure=0
	local max_execution_time allownetworking
	local NEED_ROOT PREFIX MAX_FILES
	local JEXEC_SETSID
	local -

	_my_path mnt
	_log_path log

	originspec_decode "${originspec}" port flavor subpkg
	_lookup_portdir portdir "${port}"
	pkgbase="${pkgname%-*}"

	if ! was_a_testport_run; then
		exec </dev/null
	fi

	NEED_ROOT=
	case "${BUILD_AS_NON_ROOT}" in
	"yes") shash_remove pkgname-need_root "${pkgname}" NEED_ROOT || : ;;
	esac
	if was_a_testport_run; then
		# PREFIX will already be set
		dev_assert_not "" "${PREFIX-}"
		shash_unset pkgname-prefix "${pkgname}"
	else
		shash_remove pkgname-prefix "${pkgname}" PREFIX ||
		    err 1 "build_port: shash_get PREFIX for pkgname=${pkgname}"
	fi

	allownetworking=0

	if patternlist_match "${ALLOW_NETWORKING_PACKAGES-}" \
	    "${pkgbase:?}"; then
		job_msg_warn "ALLOW_NETWORKING_PACKAGES: Allowing" \
		    "full network access for" \
		    "${COLOR_PORT}${port}${flavor:+@${flavor}} |" \
		    "${pkgname}${COLOR_RESET}"
		msg_warn "ALLOW_NETWORKING_PACKAGES: Allowing full network" \
		    "access for ${COLOR_PORT}${port}${flavor:+@${flavor}} |" \
		    "${pkgname}${COLOR_RESET}"
		allownetworking=1
		JNETNAME="n"
	fi

	# Must install run-depends as 'actual-package-depends' and autodeps
	# only consider installed packages as dependencies
	jailuser=root
	case "${BUILD_AS_NON_ROOT}.${NEED_ROOT-}" in
	yes."")
		jailuser=${PORTBUILD_USER}
		;;
	esac
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
		case "${phase}" in
		configure|build|test) JEXEC_SETSID="setsid -w" ;;
		*) JEXEC_SETSID= ;;
		esac
		max_execution_time=${MAX_EXECUTION_TIME}
		phaseenv=
		JUSER=${jailuser}
		job_build_status "${phase}" "${originspec}" "${pkgname}"
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
			case "${DISTFILES_CACHE}" in
			"no") ;;
			*)
				mkdir -p "${mnt:?}/portdistfiles"
				echo "DISTDIR=/portdistfiles" >> \
				    "${mnt:?}/etc/make.conf"
				# Symlink in existing distfiles from the
				# read-only mount at /distfiles to
				# /portdistfiles.
				gather_distfiles -l \
				    "${originspec}" "${pkgname}" \
				    "${originspec}" "${pkgname}" \
				    "${mnt:?}/distfiles" \
				    "${mnt:?}/portdistfiles" || \
				    return 1
				;;
			esac
			JNETNAME="n"
			JUSER=root
			;;
		extract)
			max_execution_time=${MAX_EXECUTION_TIME_EXTRACT}
			case "${JUSER}" in
			"root") ;;
			*)
				chown -R ${JUSER} "${mnt:?}/wrkdirs"
				;;
			esac
			;;
		configure)
			if [ "${PORTTESTING}" -eq 1 ]; then
				markfs prebuild "${mnt:?}"
			fi
			;;
		run-depends)
			JUSER=root
			if [ "${PORTTESTING}" -eq 1 ]; then
				check_fs_violation "${mnt:?}" prebuild \
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
				markfs prestage "${mnt:?}"
			fi
			;;
		install)
			max_execution_time=${MAX_EXECUTION_TIME_INSTALL}
			JUSER=root
			if [ "${PORTTESTING}" -eq 1 ]; then
				markfs preinst "${mnt:?}"
			fi
			;;
		package)
			max_execution_time=${MAX_EXECUTION_TIME_PACKAGE}
			if [ "${PORTTESTING}" -eq 1 ]; then
				check_fs_violation "${mnt:?}" prestage \
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
			case "${pkgname}" in
			# Skip for all linux ports, they are not safe
			*"linux"*) ;;
			*)
				msg "Checking shared library dependencies"
				cleanenv injail "${PKG_BIN}" query '%Fp' "${pkgname}" | \
				    cleanenv injail xargs readelf -d 2>/dev/null | \
				    grep NEEDED | sort -u
				;;
			esac
			;;
		esac

		case "${phase}" in
		"package")
			echo "PACKAGES=/.npkg" >> "${mnt:?}/etc/make.conf"
			# Create sandboxed staging dir for new package for this build
			rm -rf "${PACKAGES:?}/.npkg/${pkgname:?}"
			mkdir -p "${PACKAGES:?}/.npkg/${pkgname:?}"
			${NULLMOUNT} \
				"${PACKAGES:?}/.npkg/${pkgname:?}" \
				"${mnt:?}/.npkg"
			chown -R ${JUSER} "${mnt:?}/.npkg"
			:> "${mnt:?}/.npkg_mounted"

			pkgenv="${PKGENV}"
			# Only set PKGENV during 'package' to prevent
			# testport-built packages from going into the main repo
			pkg_notes_get "${pkgname}" pkgenv
			case "${PKG_NO_VERSION_FOR_DEPS:?}" in
			"no") ;;
			*)
				pkgenv="${pkgenv:+${pkgenv} }PKG_NO_VERSION_FOR_DEPS=1"
				;;
			esac
			phaseenv="${phaseenv:+${phaseenv}${pkgenv:+ }}${pkgenv}"
			;;
		esac
		case "${phase}" in
		*"-depends")
			# No need for nohang or PORT_FLAGS for *-depends
			phaseenv="${phaseenv:+${phaseenv} }USE_PACKAGE_DEPENDS_ONLY=1"
			;;
		*)
			phaseenv="${phaseenv:+${phaseenv}${PORT_FLAGS:+ }}${PORT_FLAGS}"
			;;
		esac

		case "${JUSER}" in
		"root")
			export UID=0
			export GID=0
			;;
		*)
			export UID=${PORTBUILD_UID}
			export GID=${PORTBUILD_GID}
			;;
		esac
		phaseenv="${phaseenv:+${phaseenv} }USER=${JUSER}"
		phaseenv="${phaseenv:+${phaseenv} }UID=${UID}"
		phaseenv="${phaseenv:+${phaseenv} }GID=${GID}"

		print_phase_header "${phase}" "${phaseenv}"

		case "${phase}" in
		*"-depends")
			cleanenv injail /usr/bin/env ${phaseenv:+-S "${phaseenv}"} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    ${phase} || return 1
			;;
		*)
			nohang ${max_execution_time} ${NOHANG_TIME} \
				"${log:?}/logs/${pkgname:?}.log" \
				"${MASTER_DATADIR:?}/var/run/${MY_BUILDER_ID:-00}_nohang.pid" \
				cleanenv injail /usr/bin/env ${phaseenv:+-S "${phaseenv}"} \
				/usr/bin/make -C ${portdir} ${MAKE_ARGS} \
				${phase}
			hangstatus=$? # This is done as it may return 1 or 2 or 3
			if [ $hangstatus -ne 0 ]; then
				# 1 = cmd failed, not a timeout
				# 2 = log timed out
				# 3 = cmd timeout
				if [ $hangstatus -eq 2 ]; then
					msg "Killing runaway build after ${NOHANG_TIME} seconds with no output"
					job_build_status "${phase}/runaway" \
					    "${originspec}" "${pkgname}"
				elif [ $hangstatus -eq 3 ]; then
					msg "Killing timed out build after ${max_execution_time} seconds"
					job_build_status "${phase}/timeout" \
					    "${originspec}" "${pkgname}"
				fi
				return 1
			fi
			;;
		esac

		case "${phase}" in
		"checksum")
			if [ "${allownetworking}" -eq 0 ]; then
				JNETNAME=""
			fi
			case "${DISTFILES_CACHE}" in
			"no") ;;
			*)
				gather_distfiles "${originspec}" "${pkgname}" \
				    "${originspec}" "${pkgname}" \
				    "${mnt:?}/portdistfiles" \
				    "${DISTFILES_CACHE:?}" ||
				    return 1
				;;
			esac
			;;
		esac

		print_phase_footer

		case "${PORTTESTING}${phase}" in
		"1""stage")
			local die=0

			job_build_status "stage-qa" "${originspec}" "${pkgname}"
			if ! cleanenv injail /usr/bin/env DEVELOPER=1 \
			    ${PORT_FLAGS:=-S "${PORT_FLAGS}"} \
			    /usr/bin/make -C ${portdir} ${MAKE_ARGS} \
			    stage-qa; then
				msg "Error: stage-qa failures detected"
				if [ "${PORTTESTING_FATAL}" != "no" ]; then
					return 1
				fi
				die=1
			fi

			job_build_status "check-plist" "${originspec}" \
			    "${pkgname}"
			if ! cleanenv injail /usr/bin/env \
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
			;;
		esac

		case "${phase}" in
		"deinstall")
			local add add1 del del1 mod mod1
			local m_add m_del m_mod
			local die=0

			add="$(mktemp -t lo.add)"
			add1="$(mktemp -t lo.add1)"
			del="$(mktemp -t lo.del)"
			del1="$(mktemp -t lo.del1)"
			mod="$(mktemp -t lo.mod)"
			mod1="$(mktemp -t lo.mod1)"
			msg "Checking for extra files and directories"
			bset_job_status "leftovers" "${originspec}" \
			    "${pkgname}"

			check_leftovers "${mnt:?}" |
			    sed -e "s|${mnt:?}||" |
			    cleanenv injail /usr/bin/env \
			    ${PORT_FLAGS:+-S "${PORT_FLAGS}"} \
			    PORTSDIR=${PORTSDIR} \
			    FLAVOR="${flavor}" \
			    UID_FILES="${P_UID_FILES}" \
			    portdir="${portdir}" \
			    /bin/sh \
			    "${PORTSDIR:?}/Mk/Scripts/check_leftovers.sh" \
			    "${port:?}" |
			{
				mapfile m_add "${add:?}" "we" ||
				    err 1 "mapfile m_add"
				mapfile m_del "${del:?}" "we" ||
				    err 1 "mapfile m_del"
				mapfile m_mod "${mod:?}" "we" ||
				    err 1 "mapfile m_mod"
				while mapfile_read_loop_redir modtype data; do
					case "${modtype}" in
					+)
						mapfile_write \
						    "${m_add:?}" \
						    "${data}"
						;;
					-)
						mapfile_write \
						    "${m_del:?}" \
						    "${data}"
						;;
					M)
						mapfile_write \
						    "${m_mod:?}" \
						    "${data}"
						;;
					*)
						err 1 "check_leftovers" \
						    "unsupported" \
						    "modtype=${modtype}"
						;;
					esac
				done
				mapfile_close "${m_add:?}"
				mapfile_close "${m_del:?}"
				mapfile_close "${m_mod:?}"
			}
			if [ -s "${add:?}" ]; then
				sort "${add:?}" -o "${add1:?}"
			else
				:> "${add1:?}"
			fi
			if [ -s "${del:?}" ]; then
				sort "${del:?}" -o "${del1:?}"
			else
				:> "${del1:?}"
			fi
			if [ -s "${mod:?}" ]; then
				sort "${mod:?}" -o "${mod1:?}"
			else
				:> "${mod1:?}"
			fi
			{ comm -12 "${add1:?}" "${del1:?}"; } >> "${mod1:?}"
			{ comm -23 "${add1:?}" "${del1:?}"; } > "${add:?}"
			{ comm -13 "${add1:?}" "${del1:?}"; } > "${del:?}"
			if [ -s "${add:?}" ]; then
				msg "Error: Files or directories left over:"
				die=1
				grep -v "^@dirrm" "${add:?}"
				grep "^@dirrm" "${add:?}" | sort -r
			fi
			if [ -s "${del:?}" ]; then
				msg "Error: Files or directories removed:"
				die=1
				cat "${del:?}"
			fi
			if [ -s "${mod:?}" ]; then
				msg "Error: Files or directories modified:"
				die=1
				cat "${mod1:?}"
			fi
			if [ "${die:?}" -eq 1 ] &&
			    [ "${PREFIX}" != "${LOCALBASE}" ] &&
			    was_a_testport_run; then
				msg "This test was done with" \
				    "PREFIX!=LOCALBASE which may show" \
				    "failures if the port does not respect" \
				    "PREFIX."
			fi
			rm -f "${add}" "${add1}" "${del}" \
			    "${del1}" "${mod}" "${mod1}"
			[ "${die}" -eq 0 ] ||
			    if [ "${PORTTESTING_FATAL}" != "no" ]; then
				return 1
			else
				testfailure=2
			fi
			;;
		esac
	done

	if [ -d "${PACKAGES}/.npkg/${pkgname}" ]; then
		# everything was fine we can copy the package to the package
		# directory
		find "${PACKAGES:?}/.npkg/${pkgname}" \
		    -mindepth 1 \( -type f -or -type l \) |
		    while mapfile_read_loop_redir pkg_path; do
			pkg_file="${pkg_path#"${PACKAGES}/.npkg/${pkgname:?}"}"
			pkg_base="${pkg_file%/*}"
			mkdir -p "${PACKAGES:?}/${pkg_base:?}"
			# rename as this is expected to be on the same
			# filesystem.
			rename "${pkg_path}" \
			    "${PACKAGES:?}/${pkg_base:?}/${pkg_path##*/}" ||
			    err 1 "build_port: rename"
		done
	fi

	bset_job_status "build_port_done" "${originspec}" "${pkgname}"
	return ${testfailure}
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
	local wrkdir status

	case "${SAVE_WRKDIR}" in
	"no") return 0 ;;
	esac
	# Don't save pre-extract
	case ${phase} in
	check-sanity|pkg-depends|fetch-depends|fetch|checksum|extract-depends|extract) return 0 ;;
	esac

	job_msg "Saving ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET} wrkdir"
	_bget status ${MY_BUILDER_ID:+"${MY_BUILDER_ID}"} status
	bset_job_status "save_wrkdir" "${originspec}" "${pkgname}"
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

	tar -s ",${mnt:?}${wrkdir%/*},," -cf "${tarname}" ${COMPRESSKEY:+-${COMPRESSKEY}} \
	    "${mnt:?}${wrkdir:?}" > /dev/null 2>&1

	job_msg "Saved ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_RESET} wrkdir to: ${tarname}"
	bset_job_status "${status%%:*}" "${originspec}" "${pkgname}"
}

start_builder() {
	[ $# -eq 4 ] || eargs start_builder MY_BUILDER_ID jname ptname setname
	local id="$1"
	local jname="$2"
	local ptname="$3"
	local setname="$4"
	local mnt MY_BUILDER_ID NO_ELAPSED_IN_MSG TIME_START_JOB COLOR_JOBID

	MY_BUILDER_ID="${id}"
	_my_path mnt

	NO_ELAPSED_IN_MSG="$((NO_ELAPSED_IN_MSG + 1))"
	TIME_START_JOB=$(clock -monotonic)
	colorize_job_id COLOR_JOBID "${MY_BUILDER_ID:?}"
	job_msg "Builder starting"

	# Jail might be lingering from previous build. Already recursively
	# destroyed all the builder datasets, so just try stopping the jail
	# and ignore any errors
	stop_builder "${id}"
	mkdir -p "${mnt:?}"
	clonefs "${MASTERMNT:?}" "${mnt:?}" prepkg
	markfs prepkg "${mnt:?}" >/dev/null
	do_jail_mounts "${MASTERMNT:?}" "${mnt:?}" "${jname:?}"
	do_portbuild_mounts "${mnt:?}" "${jname:?}" "${ptname}" "${setname}"
	jstart
	bset ${id} status "idle:"
	shash_set builder_active "${id}" 1
	run_hook builder start "${id}" "${mnt:?}"

	job_msg "Builder started"
}

maybe_start_builder() {
	[ $# -ge 5 ] || eargs maybe_start_builder MY_BUILDER_ID jname ptname \
	    setname cmd [args]
	local builder_id="$1"
	local jname="$2"
	local ptname="$3"
	local setname="$4"
	shift 4

	if ! shash_exists builder_active "${builder_id}"; then
		start_builder "${builder_id}" "${jname}" "${ptname}" \
		    "${setname}" || return "$?"
	fi
	"$@"
}

start_builders() {
	[ $# -eq 3 ] || eargs start_builders jname ptname setname
	local jname="$1"
	local ptname="$2"
	local setname="$3"
	local builder_id

	msg "Starting/Cloning builders"
	bset status "starting_jobs:"
	run_hook start_builders start

	bset builders "${BUILDERS:?}"
	bset status "starting_builders:"
	parallel_start || err 1 "parallel_start"
	for builder_id in ${BUILDERS:?}; do
		parallel_run start_builder "${builder_id}" \
		    "${jname}" "${ptname}" "${setname}"
	done
	if ! parallel_stop; then
		err 1 "Errors starting builders"
	fi

	run_hook start_builders stop
}

stop_builder() {
	[ $# -eq 1 ] || eargs stop_builder builder_id
	local builder_id="$1"
	local mnt MY_BUILDER_ID

	MY_BUILDER_ID="${builder_id}"
	_my_path mnt
	run_hook builder stop "${builder_id}" "${mnt:?}"
	jstop
	destroyfs "${mnt:?}" jail
	shash_unset builder_active "${builder_id}"
}

stop_builders() {
	local PARALLEL_JOBS real_parallel_jobs pid
	local - ret

	case "${BUILDER_JOBS:+set}" in
	set)
		# Same as parallel_shutdown(), BUILDER_JOBS may be inconsistent
		# and kill_jobs() asserts only known jobs.
		local job builder_jobs

		unset builder_jobs
		for job in ${BUILDER_JOBS}; do
			if ! jobid "${job:?}"; then
				continue
			fi
			builder_jobs="${builder_jobs:+${builder_jobs} }${job:?}"
		done >/dev/null 2>&1
		set -o noglob
		ret=0
		# shellcheck disable=SC2086
		kill_jobs 10 ${builder_jobs} || ret="$?"
		set +o noglob
		case "${ret}" in
		0|143|130) ;;
		*)
			msg_warn "Build jobs did not exit cleanly: ${ret}"
			EXIT_STATUS=$((${EXIT_STATUS:-0} + 1))
			;;
		esac
		set +f
		;;
	esac

	if [ ${PARALLEL_JOBS} -ne 0 ]; then
		msg "Stopping up to ${PARALLEL_JOBS} builders"

		real_parallel_jobs=${PARALLEL_JOBS}
		parallel_start || err 1 "parallel_start"
		for j in ${BUILDERS-$(jot -w %02d ${real_parallel_jobs})}; do
			parallel_run stop_builder "${j}" ||
			    msg_error "stop_builder ret=$?"
		done
		if ! parallel_stop; then
			err 1 "Errors stopping builders"
		fi

		case "${TMPFS_BLACKLIST_TMPDIR:+set}" in
		set)
			local tmpfs_blacklist_tmpdir

			_tmpfs_blacklist_tmpdir tmpfs_blacklist_tmpdir
			if [ -d "${tmpfs_blacklist_tmpdir:?}" ] &&
			    ! rm -rfx "${tmpfs_blacklist_tmpdir:?}/"*; then
				chflags -R 0 \
				    "${tmpfs_blacklist_tmpdir:?}"/* || :
				rm -rfx "${tmpfs_blacklist_tmpdir:?}"/* || :
			fi
			;;
		esac
	fi

	# No builders running, unset BUILDERS
	BUILDERS=""
}

job_done() {
	[ $# -eq 1 ] || eargs job_done job_idx
	local job_idx="$1"
	local job_name job_type status builder_id ret MY_BUILDER_ID job
	local job_job_idx

	# Failure to find this indicates the job is already done.
	hash_remove job_idx_job "${job_idx:?}" job || return 2
	dev_assert_true kill -0 "${job}"
	hash_remove job_job_idx "${job:?}" job_job_idx || return 3
	dev_assert "${job_idx:?}" "${job_job_idx:?}"
	hash_remove job_idx_job_type "${job_idx:?}" job_type || return 4
	hash_remove job_idx_job_name "${job_idx:?}" job_name || return 5
	hash_remove job_idx_builder_id "${job_idx:?}" builder_id || return 6
	list_remove BUILDER_JOBS "${job:?}" || return 7
	dev_assert_true hash_isset builder_busy "${builder_id:?}"
	hash_unset builder_busy "${builder_id:?}"
	_bget status "${builder_id:?}" status ||
	    err 1 "job_done: Failed to grab status for builder_id=${builder_id}"
	pkgqueue_job_done "${job_type}" "${job_name}"
	ret=0
	_wait "${job}" || ret="$?"
	case "${status}:" in
	"done:"*)
		dev_assert 0 "${ret}"
		bset "${builder_id:?}" status "idle:"
		;;
	*)
		# Try to cleanup and mark build crashed
		MY_BUILDER_ID="${builder_id:?}" crashed_build "${job_type}" \
		    "${job_name}" "${status%%:*}"
		;;
	esac
	return "${ret}"
}

_build_queue_runner_exit() {
	local ret="$?"

	echo "${MY_JOB_IDX:?}" >&6
	fp_sleep FP_BUILD_QUEUE_RUNNER_EXIT_SLEEP
	return "${ret}"
}

build_queue_runner() {
	[ $# -ge 1 ] || eargs build_queue_runner cmd '[args...]'

	setup_traps _build_queue_runner_exit
	fp_sleep FP_BUILD_QUEUE_RUNNER_ENTER_SLEEP
	"$@"
}

_build_queue_check_orphans() {
	[ $# -eq 0 ] || eargs _build_queue_check_orphans
	local jobs_it job job_status job_idx jret

	case "${FP_BUILD_QUEUE_NO_CRASHED_COLLECTION:-}" in
	1) return 0 ;;
	esac
	case "${BUILDER_JOBS:+set}" in
	set) ;;
	*) return 0 ;;
	esac
	unset jobs_it
	while jobs_with_statuses jobs_it job job_status -- \
	    ${BUILDER_JOBS}; do
		case "${job_status:?}" in
		"Running") continue ;;
		esac
		# The job is Done or Terminated.
		hash_get job_job_idx "${job:?}" job_idx ||
		    err "${EX_SOFTWARE:-70}" "_build_queue_check_orphans:" \
			"failed to find job_idx" \
			"job=${job}"
		if msg_level dev; then
			msg_dev "_build_queue_check_orphans: discovered" \
			    "job=${job}" \
			    "job_idx=${job_idx:?}" \
			    "was Done/Terminated: $(jobs -l)"
		fi
		jret=0
		job_done "${job_idx:?}" || jret="$?"
		case "${jret}" in
		0) ;;
		*)
			err 1 "_build_queue_check_orphans: job_done failed" \
			    "job_idx=${job_idx}" \
			    "ret=${jret}"
			;;
		esac
	done
}

build_queue() {
	[ $# -eq 3 ] || eargs build_queue jname ptname setname
	required_env build_queue PWD "${MASTER_DATADIR_ABS:?}/pool"
	local jname="$1"
	local ptname="$2"
	local setname="$3"
	# builder_id is analgous to MY_BUILDER_ID: builder number 0..$BUILDERS
	# job is from $(jobs)
	# job_idx is a unique id for the job
	local builder_id job job_name builders_active queue_empty
	local next_job_idx job_idx job_type job_status check_orphans timeout

	run_hook build_queue start

	mkfifo ${MASTER_DATADIR:?}/builders.pipe
	exec 6<> ${MASTER_DATADIR:?}/builders.pipe
	unlink ${MASTER_DATADIR:?}/builders.pipe
	queue_empty=0

	msg "Hit CTRL+t at any time to see build progress and stats"
	msg_dev "build_queue: BUILDERS=${BUILDERS}"

	check_orphans=0
	next_job_idx=0
	BUILDER_JOBS=
	# Mark all builders idle
	for builder_id in ${BUILDERS:?}; do
		hash_unset builder_busy "${builder_id}" || :
	done
	# Timeout indicates how often we check for dead jobs or
	# a stuck queue.
	timeout="${BUILD_QUEUE_TIMEOUT:-30}"
	while :; do
		local -
		case "${check_orphans}" in
		1)
			# First check for crashed jobs. We may pick up
			# successful jobs here too.
			_build_queue_check_orphans
			check_orphans=0
			;;
		esac
		# Then check for idle builders to dispatch jobs to.
		for builder_id in ${BUILDERS:?}; do
			# If the queue is empty, there is nothing to do here.
			case "${queue_empty:?}" in
			1) break ;;
			esac
			if hash_isset builder_busy "${builder_id}"; then
				continue
			fi
			# This builder is idle and needs work.
			# Get the next item from the queue.
			pkgqueue_get_next job_type job_name ||
			    err 1 "Failed to find a package from the queue."
			msg_dev "build_queue: pkgqueue_get_next got" \
			    "job=${job_type-}${job_name:+:${job_name}}"
			case "${job_name}" in
			"")
				# Check if the ready-to-run pool and
				# need-to-run pools are empty.
				if pkgqueue_empty; then
					queue_empty=1
					msg_dev "build_queue: queue empty"
				else
					# The queue is blocked until we finish
					# some work.
					msg_dev "build_queue: queue idle"
				fi
				continue
				;;
			esac
			case "${job_type}" in
			"build") ;;
			*)
				err ${EX_SOFTWARE} "Found job '${job_name}'" \
				    "with unsupported type '${job_type}'."
				;;
			esac
			dev_assert_false hash_isset builder_busy \
			    "${builder_id:?}"
			next_job_idx="$((next_job_idx + 1))"
			job_idx="${next_job_idx:?}"
			# Opportunistically start the builder in a subproc
			MY_BUILDER_ID="${builder_id:?}" \
			    MY_JOB_IDX="${job_idx:?}" \
			    spawn_job_protected \
			    maybe_start_builder "${builder_id}" "${jname}" \
			        "${ptname}" "${setname}" \
			    build_queue_runner \
			    build_pkg "${job_name}"
			job="${spawn_job:?}"
			hash_set job_idx_job "${job_idx:?}" "${job:?}"
			hash_set job_job_idx "${job:?}" "${job_idx:?}"
			hash_set job_idx_job_type "${job_idx:?}" "${job_type}"
			hash_set job_idx_job_name "${job_idx:?}" "${job_name}"
			hash_set job_idx_builder_id "${job_idx:?}" \
			    "${builder_id:?}"
			list_add BUILDER_JOBS "${job:?}"
			hash_set builder_busy "${builder_id:?}" 1
			msg_dev "build_queue: launched job=${job}" \
			    "job_idx=${job_idx}" \
			    "builder_id=${builder_id}" \
			    "runjob=${job_type}:${job_name}"
		done

		case "${BUILDER_JOBS:+set}" in
		set) builders_active=1 ;;
		*)   builders_active=0 ;;
		esac

		case "${queue_empty:?}" in
		1)
			case "${builders_active:?}" in
			1)
				# The queue is empty, but builds are still
				# going. Wait on them below.
				:
				;;
			*)
				# All work is done
				pkgqueue_sanity_check 0
				break
				;;
			esac
			;;
		esac

		# If builders are idle then there is a problem.
		case "${builders_active:?}" in
		0) pkgqueue_sanity_check 1 ;;
		esac

		update_remaining

		# Wait for an event from a child. All builders are busy.
		job_idx=
		read_blocking -t "${timeout:?}" job_idx <&6 || :
		fp_sleep FP_BUILD_QUEUE_POST_READ
		case "${job_idx:+set}" in
		set)
			msg_dev "build_queue: jobpipe read job_idx=${job_idx}"
			# A job just finished.
			if job_done "${job_idx:?}"; then
				msg_dev "build_queue:" \
				    "builder_id=${builder_id}" \
				    "job_idx=${job_idx}" \
				    "job_done success"
			else
				# The job is already done. It was found to be
				# done by a kill -0 check in a scan.
				:
				msg_dev "build_queue:" \
				    "builder_id=${builder_id}" \
				    "job_idx=${job_idx}" \
				    "was already done"
			fi
			;;
		"")
			msg_dev "build_queue: jobpipe read timeout"
			# No event found. The next scan will check for
			# crashed builders and deadlocks by validating
			# every builder is really non-idle.
			check_orphans=1
			;;
		esac
	done
	exec 6>&-

	run_hook build_queue stop
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

	[ -f "${log:?}/.poudriere.status" ] || return 1
	start_end_time=$(stat -f '%B %m' \
	    "${log:?}/.poudriere.status.journal%" 2>/dev/null || \
	    stat -f '%B %m' "${log:?}/.poudriere.status")
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
	local nremaining log

	if [ "${DRY_RUN}" -eq 1 ]; then
		err "${EX_SOFTWARE}" "parallel_build: In DRY_RUN?"
	fi

	_bget nremaining stats_tobuild ||
	    err "${EX_SOFTWARE}" "Failed to lookup stats_tobuild"

	# Cleanup cached data that is no longer needed.
	(
		cd "${SHASH_VAR_PATH:?}"
		for shash_bucket in \
		    origin-flavors \
		    originspec-moved \
		    ; do
			shash_remove_var "${shash_bucket}" || :
		done
	)

	# The port-to-test is "queued" but won't build in here. Avoid
	# starting a builder for it.
	if was_a_testport_run && [ -z "${IGNORE:+set}" ]; then
		dev_assert_not 0 "${nremaining}"
		nremaining="$((nremaining - 1))"
	fi

	# If pool is empty, just return
	if [ "${nremaining:?}" -eq 0 ]; then
		return 0
	fi

	# Minimize PARALLEL_JOBS to queue size
	if [ "${PARALLEL_JOBS:?}" -gt "${nremaining:?}" ]; then
		PARALLEL_JOBS=${nremaining##* }
	fi

	load_priorities

	pkgqueue_move_ready_to_pool
	_log_path log
	( cd "${MASTER_DATADIR:?}"; find pool ) > \
	    "${log:?}/.poudriere.pkg_pool_trimmed%" || :

	msg "Building ${nremaining} packages using up to ${PARALLEL_JOBS} builders"
	BUILDERS="$(jot -w %02d ${PARALLEL_JOBS})"

	# Ensure rollback for builders doesn't copy schg files.
	if schg_immutable_base; then
		chflags noschg \
		    "${MASTERMNT:?}/boot" \
		    "${MASTERMNT:?}/usr"
		find -xs "${MASTERMNT:?}" -mindepth 1 -maxdepth 1 \
		    -flags +schg -print | \
		    sed -e "s,^${MASTERMNT}/,," >> \
		    "${MASTERMNT:?}/.cpignore"

		# /usr has both schg and noschg paths (LOCALBASE).
		# XXX: This assumes LOCALBASE=/usr/local and does
		# not account for PREFIX either.
		find -xs "${MASTERMNT:?}/usr" -mindepth 1 -maxdepth 1 \
		    \( -depth 1 -name 'home' -prune \) -o \
		    \( -depth 1 -name 'local' -prune \) -o \
		    -flags +schg -print | \
		    sed -e "s,^${MASTERMNT}/usr/,," >> \
		    "${MASTERMNT:?}/usr/.cpignore"

		find -xs "${MASTERMNT:?}/boot" -mindepth 1 -maxdepth 1 \
		    \( -depth 1 -name 'modules' -prune \) -o \
		    \( -depth 1 -name 'firmware' -prune \) -o \
		    -flags +schg -print | \
		    sed -e "s,^${MASTERMNT}/boot/,," >> \
		    "${MASTERMNT:?}/boot/.cpignore"

		chflags schg \
		    "${MASTERMNT:?}/usr"
		# /boot purposely left writable but its
		# individual files are read-only.
	fi

	coprocess_start pkg_cacher

	bset builders "${BUILDERS:?}"
	bset status "parallel_build:"

	case "${PROFILING:-no}" in
	yes)
		start_builders "${jname}" "${ptname}" "${setname}"
		;;
	esac

	if [ ! -d "${MASTER_DATADIR:?}/pool" ]; then
		err 1 "Build pool is missing"
	fi
	cd "${MASTER_DATADIR:?}/pool"

	build_queue "${jname}" "${ptname}" "${setname}"

	cd "${MASTER_DATADIR:?}"

	bset status "stopping_jobs:"
	stop_builders
	coprocess_stop pkg_cacher ||
	{
		msg_warn "pkg_cacher exited with status $?"
		EXIT_STATUS=$((${EXIT_STATUS:-0} + 1))
	}

	bset status "updating_stats:"
	update_stats || msg_warn "Error updating build stats"

	bset status "idle:"

	# Restore PARALLEL_JOBS
	PARALLEL_JOBS=${real_parallel_jobs}

	return 0
}

crashed_build() {
	[ $# -eq 3 ] || eargs crashed_build job_type pkgname failed_phase
	local job_type="$1"
	local pkgname="$2"
	local failed_phase="$3"
	local origin originspec logd log log_error

	_log_path logd
	get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" origin '' ''

	log="${logd:?}/logs/${pkgname:?}.log"
	log_error="${logd:?}/logs/errors/${pkgname:?}.log"
	echo "${job_type} crashed: ${failed_phase}" >> "${log:?}"

	# If the file already exists then all of this handling was done in
	# build_pkg() already; The port failed already. What crashed
	# came after.
	COLOR_ARROW="${COLOR_FAIL}" job_msg_status \
	    "Crashed" "${originspec}" "${pkgname}" \
	    "Failed: ${COLOR_PHASE}${failed_phase}"
	if ! [ -e "${log_error}" ]; then
		# Symlink the buildlog into errors/
		install -lrs "${log:?}" "${log_error:?}"
		badd ports.failed \
		    "${originspec} ${pkgname} ${failed_phase} ${failed_phase}"
		pkgbuild_done "${pkgname}"
		run_hook pkgbuild failed "${origin}" "${pkgname}" \
		    "${failed_phase}" \
		    "${log_error}"
	fi
	if ! was_a_testport_run; then
		COLOR_ARROW="${COLOR_FAIL}" \
		    job_msg_verbose "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
		    "log: ${log_error:?}"
	fi
	clean_pool "${job_type}" "${pkgname}" "${originspec}" "${failed_phase}"
	stop_build "${pkgname}" "${originspec}" 1 >> "${log:?}"
	case "${MY_BUILDER_ID-}" in
	"") ;;
	*)
		bset_job_status "crashed" "${originspec}" "${pkgname}"
		;;
	esac
}

clean_pool() {
	[ $# -eq 4 ] || eargs clean_pool job_type pkgname originspec clean_rdepends
	local job_type="$1"
	local pkgname="$2"
	local originspec="$3"
	local clean_rdepends="$4"
	local origin skipped_originspec skipped_origin skipped_flavor
	local skipped_pkgname skipped_originspec skipped_origin
	local skipped_job_type skipped_pkgqueue_job

	case "${MY_BUILDER_ID:+set}" in
	set)
		bset ${MY_BUILDER_ID} status "clean_pool:"
		;;
	esac

	case "${originspec}.${clean_rdepends:+set}" in
	"".set)
		get_originspec_from_pkgname originspec "${pkgname}"
		;;
	esac
	originspec_decode "${originspec}" origin '' ''

	# Cleaning queue (pool is cleaned here)
	pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends}" |
	    while mapfile_read_loop_redir skipped_pkgqueue_job; do
		pkgqueue_job_decode "${skipped_pkgqueue_job}" \
		    skipped_job_type skipped_pkgname
		case "${skipped_job_type}" in
		"run") continue ;;
		esac
		get_originspec_from_pkgname skipped_originspec "${skipped_pkgname}"
		originspec_decode "${skipped_originspec}" skipped_origin \
		    skipped_flavor ''
		# If this package was listed as @all then we do not
		# mark it as 'skipped' unless it was the default FLAVOR.
		# This prevents bulk's exit status being a failure when a
		# secondary FLAVOR must be skipped.
		# Mark it ignored instead.
		if [ "${clean_rdepends}" == "ignored" ] &&
		    build_all_flavors "${skipped_originspec}" &&
		    ! originspec_is_default_flavor "${skipped_originspec}" &&
		    pkgname_is_listed "${skipped_pkgname}"; then
			trim_ignored_pkg "${skipped_pkgname}" "${skipped_originspec}" "Dependent port ${originspec} | ${pkgname} ${clean_rdepends}"
		else
			if ! noclobber \
			    shash_set pkgname-skipped \
			    "${skipped_pkgname}" 1 2>/dev/null; then
				msg_debug "clean_pool: Skipping duplicate ${skipped_pkgname}"
				continue
			fi
			# Normal skip handling.
			badd ports.skipped "${skipped_originspec} ${skipped_pkgname} ${pkgname}"
			COLOR_ARROW="${COLOR_SKIP}" \
			    job_msg_status "Skipping" \
			    "${skipped_originspec}" "${skipped_pkgname}" \
			    "Dependent port ${COLOR_PORT}${originspec} | ${pkgname}${COLOR_SKIP} ${clean_rdepends}"
			pkgbuild_done "${skipped_pkgname}"
			if [ "${DRY_RUN:-0}" -eq 0 ]; then
				redirect_to_bulk \
				    run_hook pkgbuild skipped \
				    "${skipped_origin}" \
				    "${skipped_pkgname}" "${origin}"
			fi
		fi
	done
}

print_phase_header() {
	[ $# -le 2 ] || eargs print_phase_header phase [env]
	local phase="$1"
	local env="$2"

	printf "=======================<phase: %-15s>============================\n" "${phase}"
	case "${env:+set}" in
	set)
		printf "===== env: %s\n" "${env}"
		;;
	esac
}

print_phase_footer() {
	echo "==========================================================================="
}

fp_pkgname() {
	[ $# -eq 2 ] || eargs fp_pkgname fp_var pkgname
	local fp_fp_var="$1"
	local fp_pkgname="$2"
	local fp_value fp_pkgbase
	local -

	if ! getvar "${fp_fp_var}" fp_value; then
		return 1
	fi
	fp_pkgbase="${fp_pkgname%-*}"
	if ! patternlist_match "${fp_value}" "${fp_pkgbase:?}"; then
		return 1
	fi
	msg_error "${fp_fp_var:?} failpoint match pkgname='${fp_pkgname}'"
	return 0
}

_build_pkg_fp() {
	[ $# -eq 1 ] || eargs _build_pkg_fp pkgname
	local _bpf_pkgname="$1"

	if fp_pkgname FP_BUILD_PKG_SETE_PKGNAMES "${_bpf_pkgname:?}"; then
		false
		# If set -e was not respected then pretend like no crash
		# happened to cause the test to fail.
		msg_error "set -e failure not respected"
	fi
	if fp_pkgname FP_BUILD_PKG_TRAP_PKGNAMES "${_bpf_pkgname:?}"; then
		raise SIGTERM
		msg_error "trap SIGTERM not respected"
	fi
	if fp_pkgname FP_BUILD_PKG_ERR_PKGNAMES "${_bpf_pkgname:?}"; then
		err 1 "build_pkg: FP_BUILD_PKG_ERR_PKGNAME match on" \
		    "${_bpf_pkgname:?}"
	fi
}

build_pkg() {
	[ "$#" -eq 1 ] || eargs build_pkg pkgname
	local pkgname="$1"
	local pkgfile port portdir subpkg
	local build_failed=0
	local name pkgbase
	local mnt
	local failed_status failed_phase
	local clean_rdepends
	local log
	local errortype="???"
	local ret=0
	local tmpfs_blacklist_dir JEXEC_LIMITS
	local elapsed now originspec status
	local PORTTESTING build_reason
	local -

	_my_path mnt
	_my_name name
	_log_path log
	clean_rdepends=
	trap '' TSTP
	setproctitle "build_pkg (${pkgname})" || :

	# Don't show timestamps in msg() which goes to logs, only job_msg()
	# which goes to master
	NO_ELAPSED_IN_MSG="$((NO_ELAPSED_IN_MSG + 1))"
	TIME_START_JOB=$(clock -monotonic)
	colorize_job_id COLOR_JOBID "${MY_BUILDER_ID}"

	get_originspec_from_pkgname originspec "${pkgname}"
	originspec_decode "${originspec}" port FLAVOR subpkg

	ensure_pkg_installed || :

	bset_job_status "starting" "${originspec}" "${pkgname}"
	_build_pkg_fp "${pkgname:?}"
	pkgfile="${PACKAGES:?}/All/${pkgname:?}.${PKG_EXT:?}"
	if [ -f "${pkgfile:?}" ]; then
		dev_assert_not "no" "${PKG_NO_VERSION_FOR_DEPS:?}"
		job_msg_status "Inspecting" "${port}${FLAVOR:+@${FLAVOR}}" \
		    "${pkgname}" "determining shlib requirements"
		if ! shash_exists pkgname-check_shlibs "${pkgname}"; then
			err ${EX_SOFTWARE} "build_pkg: Trying to build ${COLOR_PORT}${pkgname}${COLOR_RESET} when the package is already present"
		fi
		bset_job_status "inspecting" "${originspec}" "${pkgname}"
		unset build_reason
		if package_libdeps_satisfied "${pkgname}" build_reason; then
			local ignore

			ignore="no rebuild needed for shlib chase"
			badd ports.inspected "${originspec} ${pkgname} ${ignore}"
			COLOR_ARROW="${COLOR_IGNORE}" \
			    job_msg_status "Finished" \
			    "${port}${FLAVOR:+@${FLAVOR}}" "${pkgname}" \
			    "Nothing to do"
			pkgbuild_done "${pkgname}"
			clean_pool "run" "${pkgname}" "${originspec}" \
			    "${clean_rdepends}"
			clean_pool "build" "${pkgname}" "${originspec}" \
			    "${clean_rdepends}"
			bset "${MY_BUILDER_ID:?}" status "done:"
			return 0
		fi
		delete_pkg "${pkgfile:?}"
	else
		unset build_reason
	fi
	bset_job_status "building" "${originspec}" "${pkgname}"
	job_msg_status "Building" \
	    "${port}${FLAVOR:+@${FLAVOR}}${subpkg:+~${subpkg}}" \
	    "${pkgname}" \
	    ${build_reason:+"${build_reason}"}

	get_porttesting "${pkgname}" PORTTESTING
	MAKE_ARGS="${FLAVOR:+ FLAVOR=${FLAVOR}}"
	_lookup_portdir portdir "${port}"

	pkgbase="${pkgname%-*}"
	setup_jexec_limits "${pkgbase:?}"
	MNT_DATADIR="${mnt:?}/${DATADIR_NAME:?}"
	add_relpath_var MNT_DATADIR
	cd "${MNT_DATADIR:?}"

	if [ ${TMPFS_LOCALBASE} -eq 1 -o ${TMPFS_ALL} -eq 1 ]; then
		if [ -f "${mnt:?}/${LOCALBASE:-/usr/local}/.mounted" ]; then
			umount -n "${mnt:?}/${LOCALBASE:-/usr/local}" || \
			    umount -f "${mnt:?}/${LOCALBASE:-/usr/local}"
		fi
		mnt_tmpfs localbase "${mnt:?}/${LOCALBASE:-/usr/local}"
		do_clone -r "${MASTERMNT:?}/${LOCALBASE:-/usr/local}" \
		    "${mnt:?}/${LOCALBASE:-/usr/local}"
		:> "${mnt:?}/${LOCALBASE:-/usr/local}/.mounted"
	fi

	if [ -f "${mnt:?}/.tmpfs_blacklist_dir" ]; then
		local tmpfs_blacklist_dir

		umount -n "${mnt:?}/wrkdirs" ||
		    umount -f "${mnt:?}/wrkdirs"
		read_line tmpfs_blacklist_dir \
		    "${mnt:?}/.tmpfs_blacklist_dir" ||
		    err 1 "Failed to read tmpfs blacklist dir"
		rm -rfx "${tmpfs_blacklist_dir:?}"
	fi
	if [ -f "${mnt:?}/.need_rollback" ]; then
		rollbackfs prepkg "${mnt:?}" || :
		if [ -f "${mnt:?}/.need_rollback" ]; then
			err 1 "Failed to rollback ${mnt} to prepkg"
		fi
	fi
	:> "${mnt:?}/.need_rollback"

	if patternlist_match "${TMPFS_BLACKLIST-}" "${pkgbase:?}"; then
		local tmpfs_blacklist_tmpdir

		_tmpfs_blacklist_tmpdir tmpfs_blacklist_tmpdir
		mkdir -p "${tmpfs_blacklist_tmpdir:?}"
		tmpfs_blacklist_dir="$(\
			TMPDIR="${tmpfs_blacklist_tmpdir:?}" \
			mktemp -dt "${pkgname:?}")"
		${NULLMOUNT} "${tmpfs_blacklist_dir:?}" "${mnt:?}/wrkdirs"
		echo "${tmpfs_blacklist_dir:?}" \
		    > "${mnt:?}/.tmpfs_blacklist_dir"
	fi

	rm -rfx "${mnt:?}"/wrkdirs/* || :

	log_start "${pkgname}" 0
	msg "Building ${port}"

	if patternlist_match "${ALLOW_MAKE_JOBS_PACKAGES-}" \
	    "${pkgbase:?}"; then
		job_msg_verbose "Allowing MAKE_JOBS for" \
		    "${COLOR_PORT}${port}${FLAVOR:+@${FLAVOR}} |" \
		    "${pkgname}${COLOR_RESET}"
		sed -i '' '/DISABLE_MAKE_JOBS=poudriere/d' \
		    "${mnt:?}/etc/make.conf"
	fi

	buildlog_start "${pkgname}" "${originspec}"

	# Ensure /dev/null exists (kern/139014)
	if [ ${JAILED} -eq 0 ] && ! [ -c "${mnt:?}/dev/null" ]; then
		devfs -m "${mnt:?}/dev" rule apply path null unhide
	fi

	build_port "${originspec}" "${pkgname}" || ret=$?
	if [ ${ret} -ne 0 ]; then
		build_failed=1
		# ret=2 is a test failure
		if [ ${ret} -eq 2 ]; then
			failed_phase=$(awk -f ${AWKPREFIX:?}/processonelog2.awk \
				"${log:?}/logs/${pkgname:?}.log" \
				2> /dev/null)
		else
			_bget failed_status "${MY_BUILDER_ID:?}" status
			failed_phase=${failed_status%%:*}
		fi

		save_wrkdir "${mnt:?}" "${originspec}" "${pkgname}" \
		    "${failed_phase}" || :
	elif [ -f "${mnt:?}/${portdir:?}/.keep" ]; then
		save_wrkdir "${mnt:?}" "${originspec}" "${pkgname}" \
		    "noneed" ||:
	fi

	now=$(clock -monotonic)
	elapsed=$((now - TIME_START_JOB))

	if [ ${build_failed} -eq 0 ]; then
		ln -s "../${pkgname:?}.log" \
		    "${log:?}/logs/built/${pkgname:?}.log"
		badd ports.built "${originspec} ${pkgname} ${elapsed}"
		COLOR_ARROW="${COLOR_SUCCESS}" \
		    job_msg_status "Finished" \
		    "${port}${FLAVOR:+@${FLAVOR}}" "${pkgname}" \
		    "Success"
		pkgbuild_done "${pkgname}"
		redirect_to_bulk \
		    run_hook pkgbuild success "${port}" "${pkgname}"
		# Cache information for next run
		pkg_cacher_queue "${port}" "${pkgname}" "${FLAVOR}" || :
	else
		# Symlink the buildlog into errors/
		ln -s "../${pkgname:?}.log" \
		    "${log:?}/logs/errors/${pkgname:?}.log"
		case "${DETERMINE_BUILD_FAILURE_REASON-}" in
		"yes")
			_bget status "${MY_BUILDER_ID:?}" status
			bset_job_status "processlog" "${originspec}" "${pkgname}"
			errortype="$(awk -f ${AWKPREFIX:?}/processonelog.awk \
				"${log:?}/logs/errors/${pkgname:?}.log" \
				2> /dev/null)" || :
			bset_job_status "${status%%:*}" "${originspec}" "${pkgname}"
			;;
		*)
			errortype=
			;;
		esac
		badd ports.failed "${originspec} ${pkgname} ${failed_phase} ${errortype} ${elapsed}"
		COLOR_ARROW="${COLOR_FAIL}" \
		    job_msg_status "Finished" \
		    "${port}${FLAVOR:+@${FLAVOR}}" "${pkgname}" \
		    "Failed: ${COLOR_PHASE}${failed_phase}"
		if ! was_a_testport_run; then
			COLOR_ARROW="${COLOR_FAIL}" \
			    job_msg_verbose "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
			    "log: ${log:?}/logs/errors/${pkgname:?}.log"
		fi
		pkgbuild_done "${pkgname}"
		redirect_to_bulk \
		    run_hook pkgbuild failed "${port}" "${pkgname}" \
		    "${failed_phase}" \
		    "${log:?}/logs/errors/${pkgname:?}.log"
		# ret=2 is a test failure
		if [ ${ret} -eq 2 ]; then
			clean_rdepends=
		else
			clean_rdepends="failed"
		fi
	fi

	msg "Cleaning up wrkdir"
	cleanenv injail /usr/bin/make -C "${portdir:?}" -k \
	    -DNOCLEANDEPENDS clean ${MAKE_ARGS} || :
	rm -rfx ${mnt:?}/wrkdirs/* || :

	case "${tmpfs_blacklist_dir:+set}" in
	set)
		umount -n "${mnt:?}/wrkdirs" ||
		    umount -f "${mnt:?}/wrkdirs"
		rm -f "${mnt:?}/.tmpfs_blacklist_dir"
		rm -rf "${tmpfs_blacklist_dir:?}"
		;;
	esac

	if fp_pkgname FP_BUILD_PKG_EXIT_PKGNAMES "${pkgname}"; then
		# exit immediately rather than go through err() cleanup.
		exit 1
	fi

	clean_pool "build" "${pkgname}" "${originspec}" "${clean_rdepends}"

	stop_build "${pkgname}" "${originspec}" ${build_failed}

	log_stop

	bset "${MY_BUILDER_ID:?}" status "done:"
}

stop_build() {
	[ $# -eq 3 ] || eargs stop_build pkgname originspec build_failed
	local pkgname="$1"
	local originspec="$2"
	local build_failed="$3"
	local mnt

	case "${MY_BUILDER_ID:+set}" in
	set)
		_my_path mnt

		if [ -f "${mnt:?}/.npkg_mounted" ]; then
			umount -n "${mnt:?}/.npkg" || \
			    umount -f "${mnt:?}/.npkg"
			unlink "${mnt:?}/.npkg_mounted"
		fi
		rm -rfx "${PACKAGES:?}/.npkg/${pkgname:?}"

		if [ "${PORTTESTING}" -eq 1 ]; then
			if jail_has_processes; then
				msg_warn "Leftover processes:"
				injail ps auxwwd | egrep -v 'ps auxwwd'
				jkill_wait
			fi
			if JNETNAME="n" jail_has_processes; then
				msg_warn "Leftover processes (network jail):"
				JNETNAME="n" injail ps auxwwd | egrep -v 'ps auxwwd'
				JNETNAME="n" jkill_wait
			fi
		else
			jkill
		fi
		;;
	esac

	buildlog_stop "${pkgname}" "${originspec}" ${build_failed}
}

: ${ORIGINSPEC_FL_SEP:="@"}
: ${ORIGINSPEC_SP_SEP:="~"}
: ${FLAVOR_DEFAULT:="-"}
: ${FLAVOR_ALL:="all"}

build_all_flavors() {
	[ $# -eq 1 ] || eargs build_all_flavors originspec
	local originspec="$1"
	local origin build_all

	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi
	case "${FLAVOR_DEFAULT_ALL}" in
	"yes") return 0 ;;
	esac
	originspec_decode "${originspec}" origin '' ''
	shash_get origin-flavor-all "${origin}" build_all || build_all=0
	if [ "${build_all}" -eq 1 ]; then
		return 0
	fi

	# bulk and testport
	return 1
}

# ORIGINSPEC is: ORIGIN@FLAVOR~SUBPKG
originspec_decode() {
	local -; set +x -f
	[ $# -eq 4 ] || eargs originspec_decode originspec \
	    var_return_origin var_return_flavor var_return_subpkg
	local _originspec="$1"
	local var_return_origin="$2"
	local var_return_flavor="$3"
	local var_return_subpkg="$4"
	local __origin __flavor __subpkg IFS

	IFS="${ORIGINSPEC_SP_SEP}"
	set -- ${_originspec}
	__origin="$1"
	__subpkg="${2-}"

	IFS="${ORIGINSPEC_FL_SEP}"
	set -- ${__origin}
	__origin="$1"
	__flavor="${2-}"

	case "${var_return_origin:+set}" in
	set) setvar "${var_return_origin}" "${__origin}" ;;
	esac
	case "${var_return_flavor:+set}" in
	set) setvar "${var_return_flavor}" "${__flavor}" ;;
	esac
	case "${var_return_subpkg:+set}" in
	set) setvar "${var_return_subpkg}" "${__subpkg}" ;;
	esac
}

# !!! NOTE that the encoded originspec may not match the parameter ordering.
originspec_encode() {
	local -; set +x
	[ $# -eq 4 ] || eargs originspec_encode var_return origin flavor subpkg
	local _var_return="$1"
	local _origin_in="$2"
	local _flavor="$3"
	local _subpkg="$4"
	local output

	output="${_origin_in}"
	# Only add in FLAVOR if needed.  If not needed then don't add
	# ORIGINSPEC_FL_SEP either.
	case "${_flavor:+set}" in
	set) output="${output}${ORIGINSPEC_FL_SEP}${_flavor}" ;;
	esac
	# Only add in SUBPACKAGE if needed.  If not needed then don't add
	# ORIGINSPEC_SP_SEP either.
	case "${_subpkg:+set}" in
	set) output="${output}${ORIGINSPEC_SP_SEP}${_subpkg}" ;;
	esac
	setvar "${_var_return}" "${output}"
}

deps_fetch_vars() {
	[ $# -eq 6 ] || eargs deps_fetch_vars originspec deps_var \
	    pkgname_var flavor_var flavors_var ignore_var
	local originspec="$1"
	local deps_var="$2"
	local pkgname_var="$3"
	local flavor_var="$4"
	local flavors_var="$5"
	local ignore_var="$6"
	local _pkgname _pkg_deps= _lib_depends= _run_depends= _selected_options=
	local _build_deps= _run_deps=
	local _changed_options= _changed_deps= _lookup_flavors=
	local _existing_origin _existing_originspec pkgcategory _ignore
	local _forbidden _default_originspec _default_pkgname _no_arch
	local origin _dep _new_pkg_deps
	local _origin_flavor _flavor _flavors _default_flavor
	local _origin_subpkg
	local _prefix _pkgname_var _pdeps_var _bdeps_var _rdeps_var
	local _depend_specials= _build_as_non_root= _need_root=
	local dist_subdir dist_allfiles
	local port_flags

	originspec_decode "${originspec}" origin _origin_flavor _origin_subpkg
	# If we were passed in a FLAVOR then we better have already looked up
	# the default for this port.  This is to avoid making the default port
	# become superfluous.  Bulk -a would have already visited from the
	# category Makefiles.  The main port would have been looked up
	# potentially by the 'metadata' hack.
	case "${ALL:-0}.${_origin_flavor:+set}" in
	0.set)
		originspec_encode _default_originspec "${origin}" '' \
		    "${_origin_subpkg}"
		shash_get originspec-pkgname "${_default_originspec}" \
		    _default_pkgname || \
		    err 1 "deps_fetch_vars: Lookup of ${COLOR_PORT}${originspec}${COLOR_RESET} failed to already have ${COLOR_PORT}${_default_originspec}${COLOR_RESET}"
		;;
	esac

	case "${CHECK_CHANGED_OPTIONS}" in
	no) ;;
	*)
		if have_ports_feature SELECTED_OPTIONS; then
			_changed_options=yes
		fi
		;;
	esac
	case "${CHECK_CHANGED_DEPS}" in
	no) ;;
	*)
		if have_ports_feature SUBPACKAGES; then
			_changed_deps="LIB_DEPENDS_ALL _lib_depends RUN_DEPENDS_ALL _run_depends"
		else
			_changed_deps="LIB_DEPENDS _lib_depends RUN_DEPENDS _run_depends"
		fi
		;;
	esac
	if have_ports_feature FLAVORS; then
		_lookup_flavors="FLAVOR _flavor FLAVORS _flavors"
	fi
	if have_ports_feature SUBPACKAGES; then
		_pkgname_var="PKGNAME${_origin_subpkg:+.${_origin_subpkg}}"
		_pdeps_var='${PKG_DEPENDS_ALL} ${EXTRACT_DEPENDS_ALL} ${PATCH_DEPENDS_ALL} ${FETCH_DEPENDS_ALL} ${BUILD_DEPENDS_ALL} ${LIB_DEPENDS_ALL} ${RUN_DEPENDS_ALL}'
		_bdeps_var='${PKG_DEPENDS_ALL} ${EXTRACT_DEPENDS_ALL} ${PATCH_DEPENDS_ALL} ${FETCH_DEPENDS_ALL} ${BUILD_DEPENDS_ALL} ${LIB_DEPENDS_ALL}'
		_rdeps_var='${LIB_DEPENDS_ALL} ${RUN_DEPENDS_ALL}'
	else
		_pkgname_var="PKGNAME"
		_pdeps_var='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}'
		_bdeps_var='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS}'
		_rdeps_var='${LIB_DEPENDS} ${RUN_DEPENDS}'
	fi
	case "${BUILD_AS_NON_ROOT}" in
	yes) _build_as_non_root="NEED_ROOT _need_root" ;;
	esac
	# This is for testport.
	shash_remove originspec-port_flags "${originspec}" port_flags ||
	    port_flags=
	if ! port_var_fetch_originspec "${originspec}" \
		${port_flags-} \
		${_pkgname_var} _pkgname \
		${_lookup_flavors} \
		'${_DEPEND_SPECIALS:C,^${PORTSDIR}/,,}' _depend_specials \
		PKGCATEGORY pkgcategory \
		IGNORE _ignore \
		FORBIDDEN _forbidden \
		NO_ARCH:Dyes _no_arch \
		PREFIX _prefix \
		DIST_SUBDIR dist_subdir \
		ALLFILES dist_allfiles \
		${_build_as_non_root} \
		${_changed_deps} \
		${_changed_options:+_PRETTY_OPTS='${SELECTED_OPTIONS:@opt@${opt}+@} ${DESELECTED_OPTIONS:@opt@${opt}-@}'} \
		${_changed_options:+'${_PRETTY_OPTS:O:C/(.*)([+-])$/\2\1/}' _selected_options} \
		_BDEPS="${_bdeps_var}" \
		'${_BDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
		_build_deps \
		_RDEPS="${_rdeps_var}" \
		'${_RDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
		_run_deps \
		_PDEPS="${_pdeps_var}" \
		'${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
		_pkg_deps; then
		msg_error "Error looking up dependencies for ${COLOR_PORT}${originspec}${COLOR_RESET}"
		return 1
	fi

	case "${_pkgname}" in
	"")
		err 1 "deps_fetch_vars: failed to get PKGNAME for ${COLOR_PORT}${originspec}${COLOR_RESET}"
		;;
	esac

	# Validate PKGCATEGORY is proper to avoid:
	# - Pkg not registering the dependency
	# - Having delete_old_pkg later remove it due to the origin fetched
	#   from pkg-query not existing.
	case "${pkgcategory}" in
	"${origin%%/*}") ;;
	*)
		msg_error "${COLOR_PORT}${origin}${COLOR_RESET} has incorrect CATEGORIES, first should be '${origin%%/*}'.  Please contact maintainer of the port to fix this."
		return 1
	esac

	setvar "${pkgname_var}" "${_pkgname}"
	setvar "${deps_var}" "${_pkg_deps}"
	setvar "${flavor_var}" "${_flavor}"
	setvar "${flavors_var}" "${_flavors}"
	# Handle BLACKLIST
	case "${_flavors:+set}" in
	set)
		_default_flavor="${_flavors%% *}"
		case "${_flavor}" in
		"${_default_flavor}")
			case " ${BLACKLIST-} " in
			*" ${origin}@${FLAVOR_DEFAULT} "*|\
			*" ${origin}@${_flavor} "*|\
			*" ${origin}@${FLAVOR_ALL} "*|\
			*" ${origin} "*)
				: ${_ignore:="Blacklisted"}
				;;
			esac
			;;
		*)
			case " ${BLACKLIST-} " in
			*" ${origin}@${_flavor} "*|\
			*" ${origin}@${FLAVOR_ALL} "*|\
			*" ${origin} "*)
				: ${_ignore:="Blacklisted"}
				;;
			esac
			;;
		esac
		;;
	*)	# Port has NO flavors
		case " ${BLACKLIST-} " in
		*" ${origin} "*)
			: ${_ignore:="Blacklisted"}
			;;
		esac
		;;
	esac
	setvar "${ignore_var}" "${_ignore}"
	# Need all of the output vars set before potentially returning 2.

	# Check if this PKGNAME already exists, which is sometimes fatal.
	# Two different originspecs of the same origin but with
	# different FLAVORS may result in the same PKGNAME.
	if ! noclobber shash_set pkgname-originspec \
	    "${_pkgname}" "${originspec}" 2>/dev/null; then
		shash_get pkgname-originspec "${_pkgname}" _existing_originspec
		case "${_existing_originspec}" in
		"${originspec}")
			err 1 "deps_fetch_vars: ${COLOR_PORT}${originspec}${COLOR_RESET} already known as ${COLOR_PORT}${pkgname}${COLOR_RESET}"
			;;
		esac
		originspec_decode "${_existing_originspec}" _existing_origin \
		    '' ''
		case "${_existing_origin}" in
		"${origin}")
			case "${_pkgname}" in
			"${_default_pkgname}")
				# This originspec is superfluous, just ignore.
				msg_debug "deps_fetch_vars: originspec ${COLOR_PORT}${originspec}${COLOR_RESET} is superfluous for PKGNAME ${COLOR_PORT}${_pkgname}${COLOR_RESET}"
				if [ ${ALL} -eq 0 ]; then
					return 2
				fi
				;;
			esac
		esac
		err 1 "Duplicated origin for ${COLOR_PORT}${_pkgname}${COLOR_RESET}: ${COLOR_PORT}${originspec}${COLOR_RESET} AND ${COLOR_PORT}${_existing_originspec}${COLOR_RESET}. Rerun with -v to see which ports are depending on these."
	fi

	# Discovered a new originspec->pkgname mapping.
	msg_debug "deps_fetch_vars: discovered ${COLOR_PORT}${originspec}${COLOR_RESET} is ${COLOR_PORT}${_pkgname}${COLOR_RESET}"
	shash_set originspec-pkgname "${originspec}" "${_pkgname}"
	case "${_flavor:+set}" in
	set) shash_set pkgname-flavor "${_pkgname}" "${_flavor}" ;;
	esac
	# Set origin-flavors only for the default origin
	case "${_flavors:+set}" in
	set)
		case "${_origin_flavor}" in
		"") shash_set origin-flavors "${origin}" "${_flavors}" ;;
		esac
		;;
	esac
	case "${_ignore:+set}" in
	set)
		shash_set pkgname-ignore "${_pkgname}" "${_ignore}"
		shash_set originspec-ignored "${originspec}" 1
		;;
	esac
	case "${_prefix:+set}" in
	set) shash_set pkgname-prefix "${_pkgname}" "${_prefix}" ;;
	esac
	case "${dist_subdir:+set}" in
	set) shash_set originspec-dist_subdir "${originspec}" "${dist_subdir}" ;;
	esac
	case "${dist_allfiles:+set}" in
	set) shash_set originspec-dist_allfiles "${originspec}" "${dist_allfiles}" ;;
	esac
	case "${_need_root:+set}" in
	set) shash_set pkgname-need_root "${_pkgname}" "${_need_root}" ;;
	esac
	case "${_forbidden:+set}" in
	set) shash_set pkgname-forbidden "${_pkgname}" "${_forbidden}" ;;
	esac
	case "${_no_arch:+set}" in
	set) shash_set pkgname-no_arch "${_pkgname}" "${_no_arch}" ;;
	esac
	case "${_depend_specials:+set}" in
	set)
		shash_set pkgname-depend_specials "${_pkgname}" \
		    "${_depend_specials}"
		;;
	esac
	shash_set pkgname-deps "${_pkgname}" "${_pkg_deps}"
	shash_set pkgname-deps-build "${_pkgname}" "${_build_deps}"
	shash_set pkgname-deps-run "${_pkgname}" "${_run_deps}"
	# Store for delete_old_pkg with CHECK_CHANGED_DEPS==yes
	case "${_lib_depends:+set}" in
	set) shash_set pkgname-lib_deps "${_pkgname}" "${_lib_depends}" ;;
	esac
	case "${_run_depends:+set}" in
	set) shash_set pkgname-run_deps "${_pkgname}" "${_run_depends}" ;;
	esac
	case "${_selected_options:+set}" in
	set) shash_set pkgname-options "${_pkgname}" "${_selected_options}" ;;
	esac
}

ensure_pkg_installed() {
	local force="${1-}"
	local host_ver injail_ver mnt pkg_file

	_my_path mnt
	case "${PKG_BIN:+set}" in
	"")
		err 1 "ensure_pkg_installed: empty PKG_BIN"
		;;
	esac
	case "${force:+set}" in
	"")
		if [ -x "${mnt:?}${PKG_BIN:?}" ]; then
			return 0
		fi
		;;
	esac
	pkg_file="${mnt:?}/packages/Latest/pkg.${PKG_EXT:?}"
	# If we are testing pkg itself then use the new package
	if was_a_testport_run && [ -n "${PKGNAME-}" ] &&
	    [ -r "${mnt:?}/tmp/pkgs/${PKGNAME:?}.${PKG_EXT:?}" ]; then
		pkg_file="${mnt:?}/tmp/pkgs/${PKGNAME:?}.${PKG_EXT:?}"
	fi
	# Hack, speed up QEMU usage on pkg-repo.
	if [ ${QEMU_EMULATING} -eq 1 ] && \
	    [ -x /usr/local/sbin/pkg-static ] &&
	    [ -r "${pkg_file}" ]; then
		injail_ver="$(realpath "${pkg_file}")"
		injail_ver="${injail_ver##*/}"
		injail_ver="${injail_ver##*-}"
		injail_ver="${injail_ver%.*}"
		injail_ver="${injail_ver%_*}"
		host_ver="$(/usr/local/sbin/pkg-static -v)"
		case "${host_var}" in
		"${injail_ver}")
			cp -f /usr/local/sbin/pkg-static "${mnt:?}/${PKG_BIN:?}"
			return 0
			;;
		esac
	fi
	if [ ! -r "${pkg_file}" ]; then
		return 1
	fi
	mkdir -p "${mnt:?}/${PKG_BIN%/*}" ||
	    err 1 "ensure_pkg_installed: mkdir ${mnt}/${PKG_BIN%/*}"
	injail tar xf "${pkg_file#${mnt:?}}" \
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
_delete_old_pkg() {
	[ $# -eq 2 ] || eargs _delete_old_pkg pkgname delete_unqueued
	local pkg="$1"
	local delete_unqueued="$2"
	local mnt pkgfile pkgname new_pkgname
	local origin v v2 compiled_options current_options
	local d key dpath dir found compiled_deps
	local pkg_origin compiled_deps_pkgnames
	local pkgbase new_pkgbase flavor flavors pkg_flavor pkg_subpkg originspec
	local dep_pkgname dep_pkgbase dep_origin dep_flavor
	local ignore new_originspec stale_pkg
	local pkg_arch no_arch arch is_sym
	local -

	pkgfile="${pkg##*/}"
	pkgname="${pkgfile%.*}"
	pkgbase="${pkgname%-*}"

	if patternlist_match "${FORCE_REBUILD_PACKAGES-}" "${pkgbase:?}"; then
		msg_warn "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}:" \
		    "In FORCE_REBUILD_PACKAGES"
		delete_pkg "${pkg}"
		return 0
	fi

	case "${DELETE_UNKNOWN_FILES}" in
	"yes")
		is_sym=0
		if [ -L "${pkg}" ]; then
			is_sym=1
		fi
		case "${pkgfile}" in
		"Hashed")
			if [ -d "${pkg}" ]; then
				msg_debug "Ignoring directory: ${pkgfile}"
				return 0
			fi
			;;
		esac
		if [ "${is_sym}" -eq 1 ] && [ ! -e "${pkg}" ]; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: dead symlink"
			delete_pkg "${pkg}"
			return 0
		fi
		case "${pkgfile}" in
		*".${PKG_EXT}") ;;
		*.txz)
			# If this is a symlink to a .pkg file then just ignore
			# as the ports framework or pkg sometimes creates them.
			if [ "${is_sym}" -eq 1 ]; then
				case "$(realpath "${pkg}")" in
				*".${PKG_EXT}")
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
		;;
	esac

	# Delete FORBIDDEN packages
	if shash_remove pkgname-forbidden "${pkgname}" ignore; then
		shash_get pkgname-ignore "${pkgname}" ignore || \
		    ignore="is forbidden"
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: ${ignore}"
		delete_pkg "${pkg}"
		return 0
	fi

	pkg_subpkg=
	pkg_flavor=
	originspec=
	if ! pkg_get_originspec originspec "${pkg}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: corrupted package (origin)"
		delete_pkg "${pkg}"
		return 0
	fi
	originspec_decode "${originspec}" origin pkg_flavor pkg_subpkg

	if ! pkgbase_is_needed_and_not_ignored "${pkgname}"; then
		# We don't expect this PKGBASE but it may still be an
		# origin that is expected and just renamed.
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

	if check_moved "${originspec}" new_originspec; then
		case "${new_originspec}" in
		"EXPIRED "*)
			msg "Deleting ${pkgfile}: ${COLOR_PORT}${originspec}${COLOR_RESET} ${new_originspec#EXPIRED }"
			;;
		*)
			msg "Deleting ${pkgfile}: ${COLOR_PORT}${originspec}${COLOR_RESET} moved to ${COLOR_PORT}${new_originspec}${COLOR_RESET}"
			;;
		esac
		delete_pkg "${pkg}"
		return 0
		originspec_decode "${new_originspec}" origin flavor subpkg
	fi

	_my_path mnt

	if ! test_port_origin_exist "${origin}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: stale package: nonexistent origin ${COLOR_PORT}${originspec}${COLOR_RESET}"
		delete_pkg "${pkg}"
		return 0
	fi

	v="${pkgname##*-}"
	# Check if any packages were queried for this origin to map it to a
	# new pkgname/version.
	stale_pkg=0
	if have_ports_feature FLAVORS && \
	    ! get_pkgname_from_originspec "${originspec}" new_pkgname; then
		stale_pkg=1
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
	new_pkgbase="${new_pkgname%-*}"

	# Check for changed PKGNAME before version as otherwise a new
	# version may show for a stale package that has been renamed.
	# XXX: Check if the pkgname has changed and rename in the repo
	case "${pkgbase}" in
	"${new_pkgbase}") ;;
	*)
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: package name changed to ${COLOR_PORT}${new_pkgbase}${COLOR_RESET}"
		delete_pkg "${pkg}"
		return 0
		;;
	esac

	v2=${new_pkgname##*-}
	case "${v}" in
	"${v2}") ;;
	*)
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: new version: ${v2}"
		delete_pkg "${pkg}"
		return 0
		;;
	esac

	# Compare ABI
	pkg_arch=
	if ! pkg_get_arch pkg_arch "${pkg}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: corrupted package (pkg_arch)"
		delete_pkg "${pkg}"
		return 0
	fi
	case "${pkg_arch:+set}" in
	set)
		arch="${P_PKG_ABI:?}"
		if shash_remove pkgname-no_arch "${pkgname}" no_arch; then
			arch="${arch%:*}:*"
		fi
		case "${pkg_arch}" in
		"${arch}") ;;
		*)
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: ABI changed: '${pkg_arch}' -> '${arch}'"
			delete_pkg "${pkg}"
			return 0
			;;
		esac
		;;
	esac

	if have_ports_feature FLAVORS; then
		shash_get pkgname-flavor "${pkgname}" flavor || flavor=
		case "${pkg_flavor}" in
		"${flavor}") ;;
		*)
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: FLAVOR changed to '${flavor}' from '${pkg_flavor}'"
			delete_pkg "${pkg}"
			return 0
			;;
		esac

		shash_get origin-flavors "${origin}" flavors || flavors=
		case " ${flavors} " in
		*" ${pkg_flavor} "*) ;;
		*)
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: FLAVOR '${pkg_flavor}' no longer provided. Now: '${flavors}'"
			delete_pkg "${pkg}"
			return 0
			;;
		esac
	fi

	# Lookup deps for various later checks
	compiled_deps=
	compiled_deps_pkgnames=
	if ! pkg_get_dep_origin_pkgnames \
	    compiled_deps compiled_deps_pkgnames "${pkg}"; then
		msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: corrupted package (deps)"
		delete_pkg "${pkg}"
		return 0
	fi

	# Detect ports that have new dependencies that the existing packages
	# do not have and delete them.
	case "${CHECK_CHANGED_DEPS}" in
	"no") ;;
	*)
		local current_deps td dep_types raw_deps
		local compiled_deps_origin compiled_deps_new
		local compiled_deps_pkgname compiled_deps_pkgbases

		current_deps=""
		# FIXME: Move into Infrastructure/scripts and
		# 'make actual-run-depends-list' after enough testing,
		# which will avoida all of the injail hacks

		# pkgname-lib_deps pkgname-run_deps
		dep_types=""
		if have_ports_feature AUTO_LIB_DEPENDS; then
			dep_types="run"
			shash_unset "pkgname-lib_deps" "${new_pkgname}" || :
		else
			dep_types="lib run"
		fi

		for td in ${dep_types}; do
			shash_remove "pkgname-${td}_deps" "${new_pkgname}" \
			    raw_deps || raw_deps=
			for d in ${raw_deps}; do
				key="${d%:*}"
				found=
				case "${td}" in
				lib)
					case "${key}" in
					lib*)
						# libfoo.so
						# libfoo.so.x
						# libfoo.so.x.y
						for dir in /lib /usr/lib ; do
							if injail test -f "${dir:?}/${key}"; then
								found=yes
								break
							fi
						done
						;;
					*.*)
						# foo.x
						# Unsupported since r362031 / July 2014
						# Keep for backwards-compatibility
						case "${CHANGED_DEPS_LIBLIST}" in
						"")
							err 1 "CHANGED_DEPS_LIBLIST not set"
							;;
						esac
						case " ${CHANGED_DEPS_LIBLIST} " in
							*" ${key} "*)
								found=yes
								;;
							*) ;;
						esac
						;;
					*)
						for dir in /lib /usr/lib ; do
							if injail test -f "${dir:?}/lib${key:?}.so"; then
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
						if [ -e "${mnt:?}/${key}" ]; then
							found=yes
						fi
						;;
					*)
						case "$(injail \
						    which "${key:?}")" in
						"") ;;
						*)
							found=yes
							;;
						esac
						;;
					esac
					;;
				esac
				case "${found}" in
				"")
					dpath="${d#*:}"
					case "${dpath}" in
					"${PORTSDIR:?}"/*)
						dpath="${dpath#"${PORTSDIR:?}"/}"
						;;
					esac
					case "${dpath}" in
					"")
						err 1 "Invalid dependency for ${COLOR_PORT}${pkgname}${COLOR_RESET}: ${d}"
						;;
					esac
					current_deps="${current_deps:+${current_deps} }${dpath}"
					;;
				esac
			done
		done
		case "${current_deps:+set}" in
		set)
			for compiled_deps_pkgname in \
			    ${compiled_deps_pkgnames}; do
				compiled_deps_pkgbases="${compiled_deps_pkgbases:+${compiled_deps_pkgbases} }${compiled_deps_pkgname%-*}"
			done
			# Handle MOVED
			for compiled_deps_origin in ${compiled_deps}; do
				if check_moved "${compiled_deps_origin}" \
				    new_origin; then
					compiled_deps_origin="${new_origin}"
				fi
				case "${compiled_deps_origin}" in
				"EXPIRED "*) continue ;;
				esac
				compiled_deps_new="${compiled_deps_new:+${compiled_deps_new} }${compiled_deps_origin}"
			done
			compiled_deps="${compiled_deps_new}"
			;;
		esac
		# To handle FLAVOR here we can't just use
		# a simple origin comparison, which is what is in deps now.
		# We need to map all of the deps to PKGNAMEs which is
		# relatively expensive.  First try to match on an origin
		# and then verify the PKGNAME is a match which assumes
		# that is enough to account for FLAVOR.
		for d in ${current_deps}; do
			dep_pkgname=
			case " ${compiled_deps} " in
			# Matches an existing origin (no FLAVOR)
			*" ${d} "*) ;;
			*)
				# Unknown, but if this origin has a FLAVOR
				# then we need to fallback to a PKGBASE
				# comparison first.
				# XXX: dep_subpkg
				originspec_decode "${d}" dep_origin dep_flavor \
				    ''
				case "${dep_flavor:+set}" in
				set)
					get_pkgname_from_originspec \
					    "${d}" dep_pkgname || \
					    err 1 "delete_old_pkg: Failed to lookup PKGNAME for ${COLOR_PORT}${d}${COLOR_RESET}"
					dep_pkgbase="${dep_pkgname%-*}"
					# Now need to map all of the package's
					# dependencies to PKGBASES.
					case " ${compiled_deps_pkgbases} " in
					# Matches an existing pkgbase
					*" ${dep_pkgbase} "*) continue ;;
					# New dep
					*) ;;
					esac
					;;
				esac
				msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: new dependency: ${COLOR_PORT}${d}${COLOR_RESET}"
				if msg_level verbose; then
					msg_verbose "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: current deps: ${current_deps:+$(sorted ${current_deps})}"
					msg_verbose "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: package deps: ${compiled_deps:+$(sorted ${compiled_deps})}"
				fi
				delete_pkg "${pkg}"
				return 0
				;;
			esac
		done
		;;
	esac

	# Check if the compiled options match the current options from make.conf and /var/db/ports
	case "${CHECK_CHANGED_OPTIONS}" in
	"no") ;;
	*)
		if have_ports_feature SELECTED_OPTIONS; then
			shash_remove pkgname-options "${new_pkgname}" \
			    current_options || current_options=
		else
			# Backwards-compat: Fallback on pretty-print-config.
			current_options=$(injail /usr/bin/make -C \
			    "${PORTSDIR:?}/${origin:?}" \
			    pretty-print-config | \
			    sed -e 's,[^ ]*( ,,g' -e 's, ),,g' -e 's, $,,' | \
			    tr ' ' '\n' | \
			    sort -k1.2 | \
			    paste -d ' ' -s -)
		fi
		compiled_options=
		if ! pkg_get_options compiled_options "${pkg}"; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: corrupted package (options)"
			delete_pkg "${pkg}"
			return 0
		fi
		case "${compiled_options}" in
		"${current_options}") ;;
		*)
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: changed options"
			case "${CHECK_CHANGED_OPTIONS}" in
			"verbose")
				msg "Pkg: ${compiled_options}"
				msg "New: ${current_options}"
				;;
			esac
			delete_pkg "${pkg}"
			return 0
			;;
		esac
		;;
	esac

	# Detect missing dependency package names.
	set -f
	set -- ${compiled_deps}
	set +f
	for dep_pkgname in ${compiled_deps_pkgnames}; do
		dep_origin="$1"
		shift
		dep_pkgbase="${dep_pkgname%-*}"
		# The dependency is registered with both PKGNAME and origin.
		# If the PKGNAME changed then we need to rebuild that package.
		# Note that we do not know what the FLAVOR of the
		# dependency is.
		if ! origin_has_pkgbase "${dep_origin}" "${dep_pkgbase}"; then
			msg "Deleting ${COLOR_PORT}${pkgfile}${COLOR_RESET}: dependency's package name is unknown or changed. Needed: ${COLOR_PORT}${dep_pkgbase}${COLOR_RESET} | ${COLOR_PORT}${dep_origin}${COLOR_RESET}"
			delete_pkg "${pkg}"
			return 0
		fi
	done
}

delete_old_pkg() {
	[ $# -eq 2 ] || eargs delete_old_pkg pkgname delete_unqueued
	local pkg="$1"
	local delete_unqueued="$2"
	local shlib_required_count pkgfile pkgname

	pkgfile="${pkg##*/}"
	pkgname="${pkgfile%.*}"

	_delete_old_pkg "${pkg}" "${delete_unqueued}" || return
	if [ ! -f "${PACKAGES:?}/All/${pkgname:?}.${PKG_EXT}" ]; then
		return 0
	fi
	# The package is kept.

	case "${PKG_NO_VERSION_FOR_DEPS:?}" in
	"no") ;;
	*)
		# If the package has shlib dependencies then we need to
		# recheck it later to ensure those dependencies are still
		# provided by another package.
		pkg_get_shlib_required_count shlib_required_count "${pkg}" || return
		case "${shlib_required_count-}" in
		""|0) return 0 ;;
		esac
		# The count includes base libraries.
		# Base libraries are special and do not require a rebuild
		# check as the JAIL_OSVERSION/.jailversion will rebuild
		# everything if changed. In the longterm this may be wrong
		# if packages start providing base libs, but
		# determine_base_shlibs() will only include libraries that
		# are in the jail's clean snapshot.
		local base_libs pkg_libs cnt

		base_libs="$(mktemp -u)"
		pkg_libs="$(mktemp -u)"
		shash_read global baselibs > "${base_libs}"
		pkg_get_shlib_requires - "${pkg}" > "${pkg_libs}"
		cnt="$(comm -13 "${base_libs}" "${pkg_libs}" |
		    shash_write -T pkgname-shlibs_required "${pkgname:?}" |
		    wc -l)"
		# +0 to trim spaces
		case "$((cnt + 0))" in
		0)
			# No packaged shlibs required. Only base.
			shash_unset pkgname-shlibs_required "${pkgname:?}"
			;;
		*)
			# Depends on packaged shlibs. Check again later.
			shash_set pkgname-check_shlibs "${pkgname}" "1"
			;;
		esac
		rm -f "${base_libs}" "${pkg_libs}"
		;;
	esac
}

determine_base_shlibs() {
	[ "$#" -eq 0 ] || eargs determine_base_shlibs
	local mnt

	_my_path mnt
	{
		find "${mnt:?}/lib" "${mnt:?}/usr/lib" \
		    -maxdepth 1 \
		    -type f \
		    -name 'lib*.so*' \
		    ! -name 'libprivate*' |
		    awk -F/ '{print $NF}'

		if [ -d "${mnt}/usr/lib32" ]; then
			find "${mnt:?}/usr/lib32" \
			    -maxdepth 1 \
			    -type f \
			    -name 'lib*.so*' \
			    ! -name 'libprivate*' |
			    awk -F/ '{print $NF ":32"}'
		fi
	} | sort | shash_write global baselibs
}

delete_old_pkgs() {
	local delete_unqueued

	if ! package_dir_exists_and_has_packages; then
		return 0
	fi

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
		elif [ -n "${LISTPKGS:+set}" ]; then
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

	ensure_pkg_installed ||
	    err ${EX_SOFTWARE} "delete_old_pkgs: Missing bootstrap pkg"

	parallel_start || err 1 "parallel_start"
	for pkg in "${PACKAGES:?}"/All/*; do
		case "${pkg}" in
		"${PACKAGES:?}/All/*")  break ;;
		esac
		parallel_run delete_old_pkg "${pkg}" "${delete_unqueued}"
	done
	if ! parallel_stop; then
		err 1 "Errors deleting packages"
	fi

	run_hook delete_old_pkgs stop
}

__package_recursive_deps() {
	[ "$#" -eq 1 ] || eargs __package_recursive_deps pkgfile
	local pkgfile="$1"
	local dep_pkgname dep_pkgbase dep_pkgfile fn
	local pkgname compiled_deps_originspecs dep_originspec

	pkgname="${pkgfile##*/}"
	pkgname="${pkgname%.*}"
	shash_get pkgname-deps-run "${pkgname:?}" compiled_deps_originspecs ||
	    err 1 "package_recursive_deps: Failed to find run deps for package ${pkgname}"
	for dep_originspec in ${compiled_deps_originspecs}; do
		get_pkgname_from_originspec "${dep_originspec}" \
		    dep_pkgname ||
		    err 1 "package_recursive_deps: Failed to lookup pkgname for originspec=${dep_originspec} processing package ${pkgname}"
		case "${dep_pkgname:?}" in
		*"-(null)")
			dep_pkgbase="${dep_pkgname%-*}"
			for dep_pkgfile in \
			    "${PACKAGES:?}/All/${dep_pkgbase:?}-"*.${PKG_EXT}; do
				fn="${dep_pkgfile##*/}"
				case "${fn}" in
				# No matches
				"${dep_pkgbase}-*.${PKG_EXT}") break ;;
				esac
				case "${fn%-*}" in
				"${dep_pkgbase}") ;;
				# It is probably a -devel close match
				*) continue ;;
				esac
				echo "${fn}"
				package_recursive_deps "${dep_pkgfile:?}"
			done
			;;
		*)
			fn="${dep_pkgname:?}.${PKG_EXT}"
			dep_pkgfile="${PACKAGES:?}/All/${fn:?}"
			if [ ! -f "${dep_pkgfile:?}" ]; then
				continue
			fi
			echo "${fn}"
			package_recursive_deps "${dep_pkgfile:?}"
			;;
		esac
	done
	# # Add in a pseudo "BASE" package.
	# echo "BASE"
}

# wrapper to add sort -u
_package_recursive_deps() {
	__package_recursive_deps "$@" | sort -u
}

package_recursive_deps() {
	[ $# -eq 1 ] || eargs package_recursive_deps pkgfile
	local pkgfile="$1"

	cache_call -K "1-package_recursive_deps-${pkgfile##*/}" - \
	    _package_recursive_deps "${pkgfile:?}"
}

__package_deps_provided_libs() {
	[ $# -eq 1 ] || eargs __package_deps_provided_libs pkgfile
	local pkgfile="$1"

	package_recursive_deps "${pkgfile:?}" |
	    while mapfile_read_loop_redir dep_pkgfile; do
		# case "${dep_pkgfile}" in
		# "BASE")
		# 	shash_read global baselibs
		# 	;;
		# *)
			dep_pkgfile="${PACKAGES:?}/All/${dep_pkgfile:?}"
			pkg_get_shlib_provides - "${dep_pkgfile:?}" ||
			    continue
			package_deps_provided_libs "${dep_pkgfile:?}"
			# ;;
		# esac
	done
}

# Wrapper to handle sort -u
_package_deps_provided_libs() {
	__package_deps_provided_libs "$@" | sort -u
}

package_deps_provided_libs() {
	[ $# -eq 1 ] || eargs package_deps_provided_libs pkgfile
	local pkgfile="$1"

	cache_call -K "1-package_deps_provided_libs-${pkgfile##*/}" - \
	    _package_deps_provided_libs "${pkgfile:?}"
}

# If the package has shlib dependencies we need to ensure that
# their package dependencies provide them.  It is possible that
# a PORTREVISION chase was missed by a committer or from a change
# of quarterly branch.
package_libdeps_satisfied() {
	[ $# -eq 2 ] || eargs package_libdeps_satisfied pkgname reasonvar
	local pkgname="$1"
	local pls_reasonvar="$2"
	local pkgfile pkgbase
	local mapfile_handle ret
	local shlib shlibs_required deps_provided_shlibs shlib_name
	local pls_reason

	unset -v "${pls_reasonvar:?}" || return
	unset pls_reason
	if ! ensure_pkg_installed; then
		# Probably building pkg right now
		return 0
	fi
	ret=0
	pkgbase="${pkgname%-*}"
	pkgfile="${PACKAGES:?}/All/${pkgname:?}.${PKG_EXT:?}"
	# Compare the dependencies in the file to what its dep *packages*
	# provide. The metadata in ports is not relevant here.
	deps_provided_shlibs="$(package_deps_provided_libs "${pkgfile:?}" |
	    paste -d ' ' -s -)"
	msg_debug "${COLOR_PORT}${pkgname}${COLOR_RESET}: provides:" \
	    "${deps_provided_shlibs}"
	case "${deps_provided_shlibs:+set}" in
	"")
		if patternlist_match \
		    "${ORPHAN_SHLIB_REBUILD_IGNORELIST-}" \
		    "${pkgbase:?}"; then
			job_msg_warn "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
			    "will NOT be rebuilt (ignorelisted) but it" \
			    "misses all of its" \
			    "shlibs. May need SHLIB_REQUIRE_IGNORE_GLOB."
		else
			ret=1
			job_msg_warn "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
			    "will be rebuilt as it" \
			    "misses all of its" \
			    "shlibs. May need SHLIB_REQUIRE_IGNORE_GLOB."
		fi
		pls_reason="misses all of its shlibs (may need SHLIB_REQUIRE_IGNORE_GLOB)"
		setvar "${pls_reasonvar:?}" "${pls_reason:?}" || return
		return "${ret}"
		;;
	esac
	shash_read_mapfile pkgname-shlibs_required "${pkgname:?}" \
	    mapfile_handle ||
	    err "${EX_SOFTWARE}" "package_libdeps_satisfied: Failed to lookup shlib_requires from ${pkgname} ret=$?"
	unset shlibs_required
	while mapfile_read "${mapfile_handle}" shlib; do
		shlibs_required="${shlibs_required:+${shlibs_required} }${shlib}"
		shlib_name="${shlib%.so*}"
		case " ${deps_provided_shlibs} " in
		# Success
		*" ${shlib} "*) ;;
		# A different version! We need to rebuild to use it.
		# This supports X.Y.Z for each 0-999.
		# There is probably a better way to do this. We need to see
		# if some package provides a library we need but a different
		# version and thus we need to rebuild.
		# This is avoiding a situation where no package provides the
		# library and we do a needless rebuild. The last case here
		# covers that.
		*" ${shlib_name}.so."[0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9].[0-9][0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9].[0-9][0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9].[0-9][0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9][0-9].[0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9][0-9].[0-9][0-9]" "*|\
		*" ${shlib_name}.so."[0-9][0-9][0-9][0-9].[0-9][0-9][0-9].[0-9][0-9][0-9]" "*|\
		EOL)
			ret=1
			job_msg_warn "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
			    "will be rebuilt as it misses ${shlib}"
			pls_reason="misses shlib ${shlib:?} (likely missed PORTREVISION chase)"
			break
			;;
		# Nothing similar. Bogus dependency. Avoid rebuilding
		# because some library leaked in without a proper LIB_DEPENDS
		# so a rebuild may just yield the same library version again.
		# The port should be fixed to properly track the library.
		# It likely is failing the QA check for leaked libraries.
		*)
			if patternlist_match \
			    "${ORPHAN_SHLIB_REBUILD_IGNORELIST-}" \
			    "${pkgbase:?}"; then
				job_msg_warn "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
				    "will NOT be rebuilt (ignorelisted) but" \
				    "it misses ${shlib} which no" \
				    "dependency provides. It is likely" \
				    "(silently) failing testport/stage-qa." \
				    "Report to maintainer."
			else
				ret=1
				job_msg_warn "${COLOR_PORT}${pkgname}${COLOR_RESET}" \
				    "will be rebuilt as" \
				    "it misses ${shlib} which no" \
				    "dependency provides. It is likely" \
				    "(silently) failing testport/stage-qa." \
				    "Report to maintainer."
			fi
			pls_reason="misses undeclared shlib ${shlib:?}"
			break
			;;
		esac
	done
	case "${pls_reason:+set}" in
	set) setvar "${pls_reasonvar:?}" "${pls_reason:?}" || return ;;
	esac
	mapfile_close "${mapfile_handle}" || :
	shash_unset pkgname-shlibs_required "${pkgname:?}"
	msg_debug "${COLOR_PORT}${pkgname}${COLOR_RESET}: required: ${shlibs_required}"
	return "${ret}"
}

have_ports_feature() {
	local -; set -f
	case " ${P_PORTS_FEATURES} " in
	*" ${1} "*)
		return 0
		;;
	esac
	return 1
}

# Fetch vars from the Makefile and set them locally.
# port_var_fetch ports-mgmt/pkg PKGNAME pkgname PKGBASE pkgbase ...
# Assignments are supported as well, without a subsequent variable for storage.
port_var_fetch() {
	local -; set +x -f
	[ $# -ge 3 ] || eargs port_var_fetch origin PORTVAR var_set ...
	local origin="$1"
	local _make_origin _makeflags pvf_vars pvf_ret
	local _portvar pvf_var pvf_line shiftcnt varcnt
	# Use a tab rather than space to allow FOO='BLAH BLAH' assignments
	# and lookups like -V'${PKG_DEPENDS} ${BUILD_DEPENDS}'
	local IFS sep=$'\t'
	# Use invalid shell var character '!' to ensure we
	# don't setvar it later.
	local assign_var="!"
	local portdir

	case "${origin:+set}" in
	set)
		_lookup_portdir portdir "${origin}"
		_make_origin="-C${sep}${portdir}"
		;;
	"")
		_make_origin="-f${sep}${PORTSDIR}/Mk/bsd.port.mk${sep}PORTSDIR=${PORTSDIR}"
		;;
	esac

	shift

	while [ "$#" -gt 0 ]; do
		_portvar="$1"
		case "${_portvar}" in
		*=*)
			# This is an assignment, no associated variable
			# for storage.
			_makeflags="${_makeflags:+${_makeflags}${sep}}${_portvar}"
			pvf_vars="${pvf_vars:+${pvf_vars} }${assign_var}"
			shift 1
			;;
		*)
			if [ "$#" -eq 1 ]; then
				break
			fi
			pvf_var="$2"
			_makeflags="${_makeflags:+${_makeflags}${sep}}-V${_portvar}"
			pvf_vars="${pvf_vars:+${pvf_vars} }${pvf_var}"
			shift 2
			;;
		esac
	done

	[ $# -eq 0 ] || eargs port_var_fetch origin PORTVAR var_set ...

	pvf_ret=0
	set -o noglob
	set -- ${pvf_vars}
	set +o noglob
	varcnt="$#"
	shiftcnt=0
	local data

	data="$({
		IFS="${sep}"
		${MASTERNAME+injail} /usr/bin/make ${_make_origin} ${_makeflags-}
	})" || pvf_ret=$?
	while mapfile_read_loop_redir pvf_line; do
		# Skip assignment vars.
		# This var was just an assignment, no actual value to read from
		# stdout.  Shift until we find an actual -V var.
		# while [ "${1}" = "${assign_var}" ]; do
		while [ "$#" -gt 0 ]; do
			case "${1}" in
			"${assign_var}")
				shift
				shiftcnt=$((shiftcnt + 1))
				;;
			*)
				break
				;;
			esac
		done
		# We may have more lines than expected on an error, but our
		# errexit output is last, so keep reading until then.
		if [ "$#" -gt 0 ]; then
			setvar "$1" "${pvf_line}" || return "$?"
			shift
			shiftcnt="$((shiftcnt + 1))"
		fi
	done <<-EOF || return $?
	${data}
	EOF
	case "${pvf_ret}" in
	0) ;;
	# Cleanup already-set vars of 'make: stopped in'
	# stuff in case the caller is ignoring our non-0
	# return status.  The shiftcnt handler can deal with
	# this all itself.
	*) shiftcnt=0 ;;
	esac

	# If the entire output was blank, then $() ate all of the excess
	# newlines, which resulted in some vars not getting setvar'd.
	# This could also be cleaning up after the errexit case.
	case "${shiftcnt}" in
	"${varcnt}") ;;
	*)
		set -o noglob
		set -- ${pvf_vars}
		set +o noglob
		# Be sure to start at the last setvar'd value.
		if [ "${shiftcnt}" -gt 0 ]; then
			shift "${shiftcnt}"
		fi
		while [ "$#" -gt 0 ]; do
			# Skip assignment vars.
			while [ "$#" -gt 0 ]; do
				case "${1}" in
				"${assign_var}")
					shift
					;;
				*)
					break
					;;
				esac
			done
			if [ "$#" -gt 0 ]; then
				setvar "$1" "" || return "$?"
				shift
			fi
		done
		;;
	esac

	return "${pvf_ret}"
}

port_var_fetch_originspec() {
	local -; set +x
	[ $# -ge 3 ] || eargs port_var_fetch_originspec originspec \
	    PORTVAR var_set ...
	local originspec="$1"
	shift
	local origin flavor

	originspec_decode "${originspec}" origin flavor ''
	port_var_fetch "${origin}" "$@" ${flavor:+FLAVOR=${flavor}}
}

# Determine if a given origin has a given PKGBASE for any of its FLAVORS
origin_has_pkgbase() {
	[ $# -eq 2 ] || eargs origin_has_pkgbase origin pkgbase
	local origin="$1"
	local pkgbase="$2"
	local flavor flavors originspec flav_pkgname flav_pkgbase
	local all_pkgbases default_flavor

	shash_get origin-flavors "${origin}" flavors || flavors=
	default_flavor="${flavors%% *}"
	for flavor in '' ${flavors}; do
		originspec_encode originspec "${origin}" "${flavor}" ''
		# Not all FLAVOR-PKGNAMES are known. We only know the ones we
		# think we might build.
		shash_get originspec-pkgname "${originspec}" flav_pkgname ||
		    continue
		flav_pkgbase="${flav_pkgname%-*}"
		case "${flav_pkgbase}" in
		"${pkgbase}") return 0 ;;
		esac
		all_pkgbases="${all_pkgbases:+${all_pkgbases} }${flav_pkgbase}"
	done
	msg_debug "origin_has_pkgbase: Unable to map PKGBASE ${COLOR_PORT}${pkgbase}${COLOR_RESET} to ${COLOR_PORT}${origin}${COLOR_RESET} from: ${all_pkgbases}"
	return 1
}

get_originspec_from_pkgname() {
	[ $# -eq 2 ] || eargs get_originspec_from_pkgname var_return pkgname
	local gofp_var_return="$1"
	local gofp_pkgname="$2"
	local gofp_originspec gofp_origin gofp_flavor gofp_subpkg

	setvar "${gofp_var_return}" ""
	shash_get pkgname-originspec "${gofp_pkgname}" gofp_originspec ||
	    err ${EX_SOFTWARE} "get_originspec_from_pkgname: Failed to lookup pkgname-originspec for ${COLOR_PORT}${gofp_pkgname}${COLOR_RESET}"
	# Default originspec won't typically have the flavor in it.
	originspec_decode "${gofp_originspec}" gofp_origin gofp_flavor \
	    gofp_subpkg
	case "${gofp_flavor}" in
	"")
		if shash_get pkgname-flavor "${gofp_pkgname}" gofp_flavor; then
			case "${gofp_flavor:+set}" in
			set)
				originspec_encode gofp_originspec \
				    "${gofp_origin}" "${gofp_flavor}" \
				    "${gofp_subpkg}"
				;;
			esac
		fi
	esac
	setvar "${gofp_var_return}" "${gofp_originspec}"
}

# Look for PKGNAME and strip away @DEFAULT if it is the default FLAVOR.
get_pkgname_from_originspec() {
	[ $# -eq 2 ] || eargs get_pkgname_from_originspec originspec var_return
	local _originspec_lookup="$1"
	local var_return="$2"
	local _pkgname _origin _flavor _default_flavor _flavors _subpkg
	local _originspec

	if shash_get originspec-pkgname "${_originspec_lookup}" \
	    "${var_return}"; then
		return 0
	fi

	# This function is primarily for FLAVORS handling.
	if ! have_ports_feature FLAVORS; then
		return 1
	fi
	_originspec="${_originspec_lookup}"
	originspec_decode "${_originspec}" _origin _flavor _subpkg
	# Trim away FLAVOR_DEFAULT if present
	case "${_flavor}" in
	"${FLAVOR_DEFAULT}")
		_flavor=
		originspec_encode _originspec "${_origin}" "${_flavor}" \
		    "${_subpkg}"
		if shash_get originspec-pkgname "${_originspec}" _pkgname; then
			shash_set originspec-pkgname "${_originspec_lookup}" \
			    "${_pkgname}" || :
			setvar "${var_return}" "${_pkgname}"
			return 0
		fi
		;;
	# If the FLAVOR is empty then it is fatal to not have a result yet.
	"")
		return 1
		;;
	esac
	# See if the FLAVOR is the default and lookup that PKGNAME if so.
	originspec_encode _originspec "${_origin}" '' "${_subpkg}"
	shash_get originspec-pkgname "${_originspec}" _pkgname || return 1
	# Great, compare the flavors and validate we had the default.
	shash_get origin-flavors "${_origin}" _flavors || return 1
	case "${_flavors}" in
	"") return 1 ;;
	esac
	_default_flavor="${_flavors%% *}"
	case "${_default_flavor}" in
	"${_flavor}") ;;
	*) return 1 ;;
	esac
	# Yup, this was the default FLAVOR
	shash_set originspec-pkgname "${_originspec_lookup}" "${_pkgname}" || :
	setvar "${var_return}" "${_pkgname}"
}

originspec_misses_flavor() {
	[ $# -eq 1 ] || eargs originspec_misses_flavor originspec
	local originspec="$1"
	local flavors origin flavor default_flavor

	case "${FLAVOR_DEFAULT_ALL}" in
	yes) return 1 ;;
	esac
	originspec_decode "${originspec}" origin flavor ''
	case "${flavor}" in
	""|"${FLAVOR_DEFAULT}"|"${FLAVOR_ALL}") ;;
	*) return 1 ;;
	esac
	if ! shash_get origin-flavors "${origin}" flavors; then
		return 1
	fi
	# This originspec is ambiguous. We need a FLAVOR specified.
	return 0
}

originspec_is_default_flavor() {
	[ $# -eq 1 ] || eargs originspec_is_default_flavor originspec
	local originspec="$1"
	local flavors origin flavor

	originspec_decode "${originspec}" origin flavor ''
	shash_get origin-flavors "${origin}" flavors || flavors=

	case "${flavors}" in
	"${flavor}"|"${flavor} "*)
		return 0
		;;
	esac
	return 1
}

set_pipe_fatal_error() {
	case "${PIPE_FATAL_ERROR:+set}" in
	set) return 0 ;;
	esac
	case "${ERRORS_ARE_PIPE_FATAL:+set}" in
	set) ;;
	# Running in a context where we should error now rather than delay.
	*) return 1 ;;
	esac
	PIPE_FATAL_ERROR=1
	# Mark the fatal error flag. Must do it like this as this may be
	# running in a sub-shell.
	: > "${PIPE_FATAL_ERROR_FILE:?}"
}

delay_pipe_fatal_error() {
	clear_pipe_fatal_error
	export ERRORS_ARE_PIPE_FATAL=1
}

clear_pipe_fatal_error() {
	unset PIPE_FATAL_ERROR ERRORS_ARE_PIPE_FATAL
	unlink "${PIPE_FATAL_ERROR_FILE:?}" || :
}

check_pipe_fatal_error() {
	case "${PIPE_FATAL_ERROR:+set}" in
	set)
		clear_pipe_fatal_error
		return 0
		;;
	esac
	if [ -f "${PIPE_FATAL_ERROR_FILE:?}" ]; then
		clear_pipe_fatal_error
		return 0
	fi
	unset ERRORS_ARE_PIPE_FATAL
	return 1
}

gather_port_vars() {
	required_env gather_port_vars PWD "${MASTER_DATADIR_ABS:?}"
	local origin qorigin log originspec flavor rdep qlist qdir
	local ports

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
	# items to be processed.  It is possible that a FLAVOR argument
	# to an origin matches the default, and thus we just want to ignore
	# it.  If it provides a new unique PKGNAME though we want to keep
	# it.  This separate queue is done to again avoid processing the
	# same origin concurrently in the previous queues.
	# For the -a case the flavorqueue is not needed since all ports
	# are visited in the gatherqueue for *their default* originspec
	# before processing any dependencies.

	load_moved
	load_blacklist "${JAILNAME:?}" "${PTNAME:?}" "${SETNAME-}"

	msg "Gathering ports metadata"
	bset status "gatheringportvars:"
	run_hook gather_port_vars start

	:> "${MASTER_DATADIR:?}/all_pkgs"

	rm -rf gqueue dqueue mqueue fqueue 2>/dev/null || :
	mkdir gqueue dqueue mqueue fqueue
	qlist=$(mktemp -t poudriere.qlist)

	parallel_start || err 1 "parallel_start"
	ports="$(listed_ports show_moved)" ||
	    err "${EX_SOFTWARE}" "gather_port_vars: listed_ports failure"
	for originspec in ${ports}; do
		originspec_decode "${originspec}" origin flavor ''
		rdep="listed"
		# For -a we skip the initial gatherqueue
		if [ ${ALL} -eq 1 ]; then
			case "${flavor:+set}" in
			set)
				err 1 "Flavor ${COLOR_PORT}${originspec}${COLOR_RESET} with ALL=1"
				;;
			esac
			parallel_run \
			    prefix_stderr_quick \
			    "(${COLOR_PORT}${originspec}${COLOR_RESET})" \
			    gather_port_vars_port "${originspec}" \
			    "${rdep}" || \
			    set_pipe_fatal_error
			continue
		fi
		# Otherwise let's utilize the gatherqueue to simplify
		# FLAVOR handling.
		qorigin="gqueue/${origin%/*}!${origin#*/}"

		# For FLAVOR=all cache that request somewhere for
		# gather_port_vars_port to use later.  Other
		# methods of passing it down the queue are too complex.
		case "${flavor}" in
		"${FLAVOR_ALL}")
			unset flavor
			case "${FLAVOR_DEFAULT_ALL}" in
			"yes") ;;
			*)
				shash_set origin-flavor-all "${origin}" 1
				;;
			esac
		esac

		# If we were passed a FLAVOR-specific origin, we
		# need to delay it into the flavorqueue because
		# it is possible the list has multiple FLAVORS
		# of the origin specified or even the main port.
		# We want to ensure that the main port is looked up
		# first and then FLAVOR-specific ones are processed.
		case "${flavor:+set}" in
		set)
			# We will delay the FLAVOR-specific into
			# the flavorqueue and process the main port
			# here as long as it hasn't already.
			# Don't worry about duplicates from user list.
			qdir="fqueue/${originspec%/*}!${originspec#*/}"
			msg_debug "queueing ${COLOR_PORT}${originspec}${COLOR_RESET} into flavorqueue (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
			mkdir "${qdir:?}" ||
			    err 1 "gather_port_vars: Failed to add ${COLOR_PORT}${originspec}${COLOR_RESET} into flavorqueue (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
			echo "${rdep}" > "${qdir:?}/rdep"

			# Now handle adding the main port without
			# FLAVOR.  Only do this if the main port
			# wasn't already listed.  The 'metadata'
			# will cause gather_port_vars_port to not
			# actually queue it for build unless it
			# is discovered to be the default.
			if [ -d "${qorigin:?}" ]; then
				rdep=
			else
				rdep="metadata ${flavor:?} listed"
			fi
			;;
		esac

		# Duplicate are possible from a user list, it's fine.
		mkdir -p "${qorigin:?}"
		msg_debug "queueing ${COLOR_PORT}${origin}${COLOR_RESET} into gatherqueue (rdep=${COLOR_PORT}${rdep}${COLOR_RESET})"
		case "${rdep:+set}" in
		set)
			echo "${rdep}" > "${qorigin:?}/rdep"
			;;
		esac
	done
	if ! parallel_stop; then
		err 1 "Fatal errors encountered gathering initial ports metadata"
	fi

	until dirempty dqueue && dirempty gqueue && dirempty mqueue && \
	    dirempty fqueue; do
		# Process all newly found deps into the gatherqueue
		if ! dirempty dqueue; then
			msg_debug "Processing depqueue"
			:> "${qlist:?}"
			parallel_start || err 1 "parallel_start"
			for qorigin in dqueue/*; do
				case "${qorigin}" in
				"dqueue/*") break ;;
				esac
				echo "${qorigin}" >> "${qlist:?}"
				origin="${qorigin#*/}"
				# origin is really originspec, but fixup
				# the substitued '/'
				originspec="${origin%!*}/${origin#*!}"
				parallel_run \
				    gather_port_vars_process_depqueue \
				    "${originspec}" || \
				    set_pipe_fatal_error
			done
			if ! parallel_stop; then
				err 1 "Fatal errors encountered processing gathered ports metadata"
			fi
			remove_many_file "${qlist:?}" rmdir ||
			    err 1 "gather_port_vars: remove_many_file"
		fi

		# Now process the gatherqueue

		# Now rerun until the work queue is empty
		# XXX: If the initial run were to use an efficient work queue then
		#      this could be avoided.
		if ! dirempty gqueue; then
			msg_debug "Processing gatherqueue"
			:> "${qlist:?}"
			parallel_start || err 1 "parallel_start"
			for qorigin in gqueue/*; do
				case "${qorigin}" in
				"gqueue/*") break ;;
				esac
				echo "${qorigin}" >> "${qlist:?}"
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
				    set_pipe_fatal_error
			done
			if ! parallel_stop; then
				err 1 "Fatal errors encountered gathering ports metadata"
			fi
			remove_many_file "${qlist:?}" rm -rf ||
			    err 1 "gather_port_vars: remove_many_file"
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
	unlink "${qlist:?}" || :
	run_hook gather_port_vars stop
}

# Dependency policy/assertions.
deps_sanity() {
	[ $# -eq 2 ] || eargs deps_sanity originspec deps
	local originspec="${1}"
	local deps="${2}"
	local origin dep_originspec dep_origin dep_flavor dep_subpkg ret
	local new_originspec moved_reason

	originspec_decode "${originspec}" origin '' ''

	ret=0
	for dep_originspec in ${deps}; do
		originspec_decode "${dep_originspec}" dep_origin dep_flavor dep_subpkg
		msg_verbose "${COLOR_PORT}${originspec}${COLOR_RESET} depends on ${COLOR_PORT}${dep_originspec}"
		case "${dep_origin}" in
		"${origin}")
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} incorrectly depends on itself. Please contact maintainer of the port to fix this."
			ret=1
			;;
		# Detect bad cat/origin/ dependency which pkg will not register properly
		*"/")
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} depends on bad origin ${COLOR_PORT}${dep_origin}${COLOR_RESET}; Please contact maintainer of the port to fix this."
			ret=1
			;;
		esac
		if ! test_port_origin_exist "${dep_origin}"; then
			# Was it moved? We cannot map it here due to the ports
			# framework not supporting it later on, and the
			# PKGNAME would be wrong, but we can at least
			# advise the user about it.
			check_moved "${dep_originspec}" new_originspec ||
			    new_originspec=
			case "${new_originspec}" in
			"EXPIRED "*)
				moved_reason="port EXPIRED: ${new_originspec#EXPIRED }"
				;;
			"")
				unset moved_reason
				;;
			*)
				moved_reason="moved to ${COLOR_PORT}${new_originspec}${COLOR_RESET}"
				;;
			esac
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} depends on nonexistent origin ${COLOR_PORT}${dep_origin}${COLOR_RESET}${moved_reason:+ (${moved_reason})}; Please contact maintainer of the port to fix this."
			ret=1
		fi
		if have_ports_feature FLAVORS && [ -z "${dep_flavor}" ] && \
			[ -z "${dep_subpkg}" ] && \
			[ "${dep_originspec}" != "${dep_origin}" ]; then
			msg_error "${COLOR_PORT}${originspec}${COLOR_RESET} has dependency on ${COLOR_PORT}${dep_origin}${COLOR_RESET} with invalid empty FLAVOR; Please contact maintainer of the port to fix this."
			ret=1
		fi
	done
	return ${ret}
}

gather_port_vars_port() {
	required_env gather_port_vars_port \
	    PWD "${MASTER_DATADIR_ABS:?}" \
	    SHASH_VAR_PATH "var/cache"
	[ $# -eq 2 ] || eargs gather_port_vars_port originspec rdep
	local originspec="$1"
	local rdep="$2"
	local dep_origin deps pkgname dep_originspec
	local dep_ret log flavor flavors dep_flavor
	local origin origin_flavor default_flavor originspec_flavored
	local ignore origin_subpkg qdir

	msg_debug "gather_port_vars_port (${COLOR_PORT}${originspec}${COLOR_RESET}): LOOKUP"
	originspec_decode "${originspec}" origin origin_flavor origin_subpkg
	case "${origin_flavor:+set}" in
	set)
		if ! have_ports_feature FLAVORS; then
			err 1 "gather_port_vars_port: Looking up ${COLOR_PORT}${originspec}${COLOR_RESET} without FLAVORS support in ports"
		fi
		;;
	esac

	# Trim away FLAVOR_DEFAULT and restore it later
	case "${origin_flavor}" in
	"${FLAVOR_DEFAULT}")
		originspec_encode originspec "${origin}" '' "${origin_subpkg}"
		;;
	esac

	# A metadata lookup may have been queued for this port that is no
	# longer needed.
	if [ ${ALL} -eq 0 ]; then
		case "${rdep}" in
		"metadata "*) ;;
		*)
			qdir="mqueue/${originspec%/*}!${originspec#*/}"
			if [ -d "${qdir:?}" ]; then
				rm -rf "${qdir:?}"
			fi
			;;
		esac
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
		shash_get origin-flavors "${origin}" flavors || flavors=
		shash_get pkgname-ignore "${pkgname}" ignore || ignore=
	else
		dep_ret=0
		deps_fetch_vars "${originspec}" deps pkgname flavor \
		    flavors ignore || dep_ret=$?
		case ${dep_ret} in
		0) ;;
		# Non-fatal duplicate should be ignored
		2)
			# The previous depqueue run may have readded
			# this originspec into the flavorqueue.
			# Expunge it.
			qdir="fqueue/${originspec%/*}!${originspec#*/}"
			if [ -d "${qdir}" ]; then
				rm -rf "${qdir}"
			fi
			case "${flavors:+set}" in
			set)
				# If this is the default FLAVOR and we're not already
				# queued then we're the victim of the 'metadata' hack.
				# Fix it.
				default_flavor="${flavors%% *}"
				case "${origin_flavor}" in
				"${FLAVOR_DEFAULT}")
					origin_flavor="${default_flavor}"
					;;
				"${default_flavor}") ;;
				# Not the default FLAVOR.
				*)
					# Is it a valid FLAVOR though?
					case " ${flavors} " in
					*" ${origin_flavor} "*)
						# A superfluous valid FLAVOR,
						# nothing more to do.
						return 0
						;;
					esac
					# The FLAVOR is invalid.  It will be
					# marked IGNORE but we process too late.
					# There is no unique PKGNAME for this
					# looku so we must fail now.
					err 1 "Invalid FLAVOR '${origin_flavor}' for ${COLOR_PORT}${origin}${COLOR_RESET}"
					;;
				esac
				;;
			esac
			if pkgname_metadata_is_known "${pkgname}"; then
				# Nothing more do to.
				return 0
			fi
			msg_debug "gather_port_vars_port: Fixing up from metadata hack on ${COLOR_PORT}${originspec}${COLOR_RESET}"
			# Queue us as the main port
			originspec_encode originspec "${origin}" '' "${origin_subpkg}"
			# Having $origin_flavor set prevents looping later.
			;;
		# Fatal error
		*)
			# An error is printed from deps_fetch_vars
			set_pipe_fatal_error
			return 1
			;;
		esac
	fi

	# If this originspec was added purely for metadata lookups then
	# there's nothing more to do.  Unless it is the default FLAVOR
	# which is also listed to build since the FLAVOR-specific one
	# will be found superfluous later.  None of this is possible with -a
	case "${ALL}.${rdep}" in
	"0.metadata "*)
		# rdep is: metadata flavor original_rdep
		case "${flavors}" in
		"")
			msg_debug "SKIPPING ${COLOR_PORT}${originspec}${COLOR_RESET} - no FLAVORS"
			return 0
			;;
		esac
		local queued_flavor queuespec lflavor

		default_flavor="${flavors%% *}"
		rdep="${rdep#* }"
		queued_flavor="${rdep% *}"
		# Check if we have the default FLAVOR sitting in the
		# flavorqueue and don't skip if so.
		case "${queued_flavor}" in
		"${FLAVOR_DEFAULT}")
			queued_flavor="${default_flavor}"
			;;
		"${default_flavor}") ;;
		# Not the default FLAVOR.
		*)
			msg_debug "SKIPPING ${COLOR_PORT}${originspec}${COLOR_RESET} - metadata lookup queued=${queued_flavor} default=${default_flavor}"
			return 0
			;;
		esac
		# We're keeping this metadata lookup as its original rdep
		# but we need to prevent forcing all FLAVORS to build
		# later, so reset our flavor and originspec.
		rdep="${rdep#* }"
		origin_flavor="${queued_flavor}"
		for lflavor in ${origin_flavor} ${FLAVOR_DEFAULT}; do
			originspec_encode queuespec "${origin}" \
			    "${lflavor}" "${origin_subpkg}"
			msg_debug "gather_port_vars_port: Fixing up ${COLOR_PORT}${originspec}${COLOR_RESET} to be ${COLOR_PORT}${queuespec}${COLOR_RESET}"
			qdir="fqueue/${queuespec%/*}!${queuespec#*/}"
			if [ -d "${qdir:?}" ]; then
				rm -rf "${qdir:?}"
			fi
		done
		;;
	esac

	# For all_pkgs ensure we store the default flavor if we are that pkg.
	case "${origin_flavor:+set}.${flavors:+set}" in
	set.set)
		originspec_encode originspec_flavored "${origin}" \
		    "${origin_flavor}" "${origin_subpkg}"
		;;
	set."")
		err 1 "gather_port_vars_port: ${COLOR_PORT}${originspec}${COLOR_RESET} had FLAVOR=${origin_flavor} but port provided no flavors?"
		;;
	"".set)
		# Was not queued as a flavor but we are the default flavor.
		: "${default_flavor:="${flavors%% *}"}"
		originspec_encode originspec_flavored "${origin}" \
		    "${default_flavor}" "${origin_subpkg}"
		;;
	*)
		originspec_flavored="${originspec}"
		;;
	esac

	msg_debug "WILL BUILD ${COLOR_PORT}${originspec_flavored}${COLOR_RESET}"
	echo "${pkgname} ${originspec_flavored} ${rdep} ${ignore}" >> \
	    "${MASTER_DATADIR:?}/all_pkgs"

	# Add all of the discovered FLAVORS into the flavorqueue if
	# this was the default originspec and this originspec was
	# listed to build.
	case "${rdep}.${origin_flavor:+set}.${flavors:+set}" in
	"listed".""."set")
		if  build_all_flavors "${originspec}"; then
			msg_verbose "Will build all flavors for ${COLOR_PORT}${originspec_flavored}${COLOR_RESET}: ${flavors}"
			for dep_flavor in ${flavors}; do
				# Skip default FLAVOR
				case "${flavor}" in
				"${dep_flavor}") continue ;;
				esac
				originspec_encode dep_originspec "${origin}" \
				    "${dep_flavor}" "${origin_subpkg}"
				msg_debug "gather_port_vars_port (${COLOR_PORT}${originspec}${COLOR_RESET}): Adding to flavorqueue FLAVOR=${dep_flavor}"
				qdir="fqueue/${dep_originspec%/*}!${dep_originspec#*/}"
				mkdir -p "${qdir:?}" ||
				    err 1 "gather_port_vars_port: Failed to add ${COLOR_PORT}${dep_originspec}${COLOR_RESET} to flavorqueue for ${COLOR_PORT}${originspec}${COLOR_RESET}"
				# Copy our own reverse dep over.  This should always
				# just be "listed" in this case ($rdep == listed) but
				# use the actual value to reduce maintenance.
				echo "${rdep}" > "${qdir:?}/rdep"
			done
		fi
		;;
	esac

	# If there are no deps for this port then there's nothing left to do.
	case "${deps}" in
	"") return 0 ;;
	esac
	# Don't bother fetching dependencies if this port is IGNORED.
	case "${ignore:+set}" in
	set) return 0 ;;
	esac
	# Assert some policy before proceeding to process these deps
	# further.
	if ! deps_sanity "${originspec}" "${deps}"; then
		set_pipe_fatal_error
		return 1
	fi

	# In the -a case, there's no need to use the depqueue to add
	# dependencies into the gatherqueue since the default ones will
	# be visited from the category Makefiles anyway.
	if [ ${ALL} -eq 0 ]; then
		msg_debug "gather_port_vars_port (${COLOR_PORT}${originspec}${COLOR_RESET}): Adding to depqueue"
		qdir="dqueue/${originspec%/*}!${originspec#*/}"
		mkdir "${qdir:?}" ||
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

	if ! have_ports_feature FLAVORS; then
		return 1
	fi
	if [ "${ALL}" -eq 1 ]; then
		return 1
	fi
	case "${rdep} " in
	"metadata "*) return 1 ;;
	esac
	if pkgname_metadata_is_known "${pkgname}"; then
		return 1
	fi
	return 0
}

gather_port_vars_process_depqueue_enqueue() {
	required_env gather_port_vars_process_depqueue_enqueue \
	    PWD "${MASTER_DATADIR_ABS:?}" \
	    SHASH_VAR_PATH "var/cache"
	[ $# -eq 4 ] || eargs gather_port_vars_process_depqueue_enqueue \
	    originspec dep_originspec queue rdep
	local originspec="$1"
	local dep_originspec="$2"
	local queue="$3"
	local rdep="$4"
	local dep_pkgname qdir

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
	# mkdir -p is not used here as it would waste time touching $queue/
	qdir="${queue:?}/${dep_originspec%/*}!${dep_originspec#*/}"
	if mkdir "${qdir:?}" 2>&${fd_devnull}; then
		echo "${rdep}" > "${qdir:?}/rdep"
	fi
}

gather_port_vars_process_depqueue() {
	required_env gather_port_vars_process_depqueue \
	    PWD "${MASTER_DATADIR_ABS:?}" \
	    SHASH_VAR_PATH "var/cache"
	[ $# -eq 1 ] || eargs gather_port_vars_process_depqueue originspec
	local originspec="$1"
	local origin pkgname deps dep_origin
	local dep_originspec dep_flavor dep_subpkg queue rdep
	local fd_devnull

	msg_debug "gather_port_vars_process_depqueue (${COLOR_PORT}${originspec}${COLOR_RESET})"

	# Add all of this origin's deps into the gatherqueue to reprocess
	shash_get originspec-pkgname "${originspec}" pkgname || \
	    err 1 "gather_port_vars_process_depqueue failed to find pkgname for origin ${COLOR_PORT}${originspec}${COLOR_RESET}"
	shash_get pkgname-deps "${pkgname}" deps || \
	    err 1 "gather_port_vars_process_depqueue failed to find deps for pkg ${COLOR_PORT}${pkgname}${COLOR_RESET}"

	# Open /dev/null in case gather_port_vars_process_depqueue_enqueue
	# uses it, to avoid opening for every dependency.
	case "${deps:+set}" in
	set)
		exec 5>/dev/null
		fd_devnull=5
		;;
	esac

	originspec_decode "${originspec}" origin '' ''
	for dep_originspec in ${deps}; do
		originspec_decode "${dep_originspec}" dep_origin dep_flavor dep_subpkg
		# First queue the default origin into the gatherqueue if
		# needed.  For the -a case we're guaranteed to already
		# have done this via the category Makefiles.
		# if it's a subpackage process it later
		case "${ALL}.${dep_subpkg:+set}" in
		0."")
			case "${dep_flavor:+set}" in
			set)
				queue=mqueue
				rdep="metadata ${dep_flavor} ${originspec}"
				;;
			"")
				queue=gqueue
				rdep="${originspec}"
				;;
			esac

			msg_debug "Want to enqueue default ${COLOR_PORT}${dep_origin}${COLOR_RESET} rdep=${COLOR_PORT}${rdep}${COLOR_RESET} into ${queue}"
			gather_port_vars_process_depqueue_enqueue \
			    "${originspec}" "${dep_origin}" "${queue}" \
			    "${rdep}"
			;;
		esac
		# XXX: https://github.com/freebsd/poudriere/issues/1121
		case "${dep_flavor:+set}.${dep_subpkg:+set}" in
		"".set)
			msg_debug "Want to enqueue ${COLOR_PORT}${dep_originspec}${COLOR_RESET} rdep=${COLOR_PORT}${origin}${COLOR_RESET} into ${queue}"
			gather_port_vars_process_depqueue_enqueue \
			    "${originspec}" "${dep_originspec}" "${queue}" \
			    "${originspec}"
			;;
		esac

		# Add FLAVOR dependencies into the flavorqueue.
		case "${dep_flavor:+set}" in
		set)
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
			;;
		esac
	done

	case "${deps:+set}" in
	set)
		exec 5>&-
		unset fd_devnull
		;;
	esac
}

# We may gather metadata for more ports than we actually want to build.
# In here will will compute the list of packages that we are actually
# interested in.
compute_needed() {
	[ "$#" -eq 0 ] || eargs compute_needed

	awk 'NF < 4' "${MASTER_DATADIR:?}/all_pkgs" > \
	    "${MASTER_DATADIR:?}/all_pkgs_not_ignored"
}

generate_queue() {
	required_env generate_queue PWD "${MASTER_DATADIR_ABS:?}"
	local pkgname originspec dep_pkgname _rdep _ignored

	pkgqueue_init
	msg "Calculating ports order and dependencies"
	bset status "computingdeps:"
	run_hook generate_queue start
	run_hook compute_deps start

	:> "${MASTER_DATADIR:?}/pkg_deps.unsorted"

	parallel_start || err 1 "parallel_start"
	while mapfile_read_loop "${MASTER_DATADIR:?}/all_pkgs_not_ignored" \
	    pkgname originspec _rdep _ignored; do
		parallel_run generate_queue_pkg "${pkgname}" "${originspec}" \
		    "${MASTER_DATADIR}/pkg_deps.unsorted" || set_pipe_fatal_error
	done
	if ! parallel_stop; then
		err 1 "Fatal errors encountered calculating dependencies"
	fi

	sort -u "${MASTER_DATADIR:?}/pkg_deps.unsorted" \
	    -o "${MASTER_DATADIR:?}/pkg_deps"
	unlink "${MASTER_DATADIR:?}/pkg_deps.unsorted"

	bset status "computingrdeps:"
	pkgqueue_compute_rdeps
	{ find deps rdeps; } > "pkg_pool"

	run_hook compute_deps stop
	run_hook generate_queue stop
	return 0
}

generate_queue_pkg() {
	required_env generate_queue_pkg SHASH_VAR_PATH "var/cache"
	[ $# -eq 3 ] || eargs generate_queue_pkg pkgname originspec pkg_deps
	local pkgname="$1"
	local originspec="$2"
	local pkg_deps="$3"
	local deps dep_pkgname dep_originspec dep_origin dep_flavor dep_subpkg
	local raw_deps d key dpath dep_real_pkgname err_type
	local deps_type

	# build_deps=compiler
	# run_deps=
	# run compiler: build compiler
	# build foo: run compiler

	# Safe to remove pkgname-deps now, it won't be needed later.
	shash_remove pkgname-deps "${pkgname}" deps ||
	    err 1 "generate_queue_pkg failed to find deps for ${COLOR_PORT}${pkgname}${COLOR_RESET}"
	msg_debug "generate_queue_pkg: Will build ${COLOR_PORT}${pkgname}${COLOR_RESET}"
	# We may need to "run" this package during the build. This type is
	# just for ordering and will not execute anything.
	pkgqueue_add "run" "${pkgname}" ||
	    err 1 "generate_queue_pkg: Error creating run queue entry for ${COLOR_PORT}${pkgname}${COLOR_RESET}: There may be a duplicate origin in a category Makefile"
	pkgqueue_add "build" "${pkgname}" ||
	    err 1 "generate_queue_pkg: Error creating build queue entry for ${COLOR_PORT}${pkgname}${COLOR_RESET}: There may be a duplicate origin in a category Makefile"
	# To "run" this package we must first build, or fetch, it.
	pkgqueue_add_dep "run" "${pkgname}" "build" "${pkgname}" ||
	    err 1 "generate_queue_pkg: Error creating build-run queue entry for ${COLOR_PORT}${pkgname}${COLOR_RESET}: There may be a duplicate origin in a category Makefile"
	{
		echo "run:${pkgname} build:${pkgname}"
		for deps_type in build run; do
			shash_get "pkgname-deps-${deps_type}" "${pkgname}" \
			    deps ||
			    err 1 "generate_queue_pkg failed to find deps-${deps_type} for ${COLOR_PORT}${pkgname}${COLOR_RESET}"
			for dep_originspec in ${deps}; do
				if ! get_pkgname_from_originspec \
				    "${dep_originspec}" dep_pkgname; then
					originspec_decode "${dep_originspec}" \
					    dep_origin \
					    dep_flavor dep_subpkg
					if [ ${ALL} -eq 0 ]; then
						msg_error "generate_queue_pkg failed to lookup pkgname for ${COLOR_PORT}${dep_originspec}${COLOR_RESET} processing package ${COLOR_PORT}${pkgname}${COLOR_RESET} from ${COLOR_PORT}${originspec}${COLOR_RESET}${dep_flavor:+ -- Does ${COLOR_PORT}${dep_origin}${COLOR_RESET} provide the '${dep_flavor}' FLAVOR?}"
					else
						msg_error "generate_queue_pkg failed to lookup pkgname for ${COLOR_PORT}${dep_originspec}${COLOR_RESET} processing package ${COLOR_PORT}${pkgname}${COLOR_RESET} from ${COLOR_PORT}${originspec}${COLOR_RESET} -- Is SUBDIR+=${COLOR_PORT}${dep_origin#*/}${COLOR_RESET} missing in ${COLOR_PORT}${dep_origin%/*}${COLOR_RESET}/Makefile?${dep_flavor:+ And does the port provide the '${dep_flavor}' FLAVOR?}"
					fi
					set_pipe_fatal_error
					continue
				fi
				msg_debug "generate_queue_pkg: Will build ${COLOR_PORT}${dep_originspec}${COLOR_RESET} for ${COLOR_PORT}${pkgname}${COLOR_RESET}"
				case "${deps_type}" in
				build)
					# To build this package we need to be
					# able to run/install our BUILD_DEPENDS.
					pkgqueue_add_dep "build" "${pkgname}" \
					    "run" "${dep_pkgname}"
					echo "build:${pkgname} run:${dep_pkgname}"
					;;
				run)
					# To build or run this package we need
					# to be able to run/install our
					# RUN_DEPENDS.
					pkgqueue_add_dep "build" "${pkgname}" \
					    "run" "${dep_pkgname}"
					echo "build:${pkgname} run:${dep_pkgname}"
					pkgqueue_add_dep "run" "${pkgname}" \
					    "run" "${dep_pkgname}"
					echo "run:${pkgname} run:${dep_pkgname}"
					;;
				esac
				case "${CHECK_CHANGED_DEPS}" in
				"no") ;;
				*)
					# Cache for call later in this func
					hash_set generate_queue_originspec-pkgname \
					    "${dep_originspec}" "${dep_pkgname}"
					;;
				esac
			done
		done
	} >> "${pkg_deps}"

	# Check for invalid PKGNAME dependencies which break later incremental
	# 'new dependency' detection.  This is done here rather than
	# delete_old_pkgs since that only covers existing packages, but we
	# need to detect the problem for all new package builds.
	case "${CHECK_CHANGED_DEPS}" in
	"no") ;;
	*)
		case "${BAD_PKGNAME_DEPS_ARE_FATAL}" in
		"yes")
			err_type="msg_error"
			;;
		*)
			err_type="msg_warn"
			;;
		esac
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
				"${PORTSDIR}/"*)
					dpath=${dpath#"${PORTSDIR}"/} ;;
				esac
				case "${dpath}" in
				"")
					msg_error "Invalid dependency line for ${COLOR_PORT}${pkgname}${COLOR_RESET}: ${d}"
					set_pipe_fatal_error
					continue
					;;
				esac
				if ! hash_get \
				    generate_queue_originspec-pkgname \
				    "${dpath}" dep_real_pkgname; then
					msg_error "generate_queue_pkg failed to lookup PKGNAME for ${COLOR_PORT}${dpath}${COLOR_RESET} processing package ${COLOR_PORT}${pkgname}${COLOR_RESET}"
					set_pipe_fatal_error
					continue
				fi
				if shash_exists originspec-ignored "${dpath}"; then
					continue
				fi
				case "${dep_real_pkgname%-*}" in
				"${dep_pkgname}") ;;
				*)
					${err_type} "${COLOR_PORT}${originspec}${COLOR_WARN} dependency on ${COLOR_PORT}${dpath}${COLOR_WARN} has wrong PKGNAME of '${dep_pkgname}' but should be '${dep_real_pkgname%-*}'; Is the dependency missing a @FLAVOR?"
					case "${BAD_PKGNAME_DEPS_ARE_FATAL}" in
					"yes")
						set_pipe_fatal_error
						continue
						;;
					esac
					;;
				esac
				;;
			*) ;;
			esac
		done
		;;
	esac

	return 0
}

test_port_origin_exist() {
	[ $# -eq 1 ] || eargs test_port_origin_exist origin
	local _origin="$1"
	local o

	for o in ${OVERLAYS}; do
		if [ -d "${MASTERMNTREL?}${OVERLAYSDIR:?}/${o:?}/${_origin:?}" ]; then
			return 0
		fi
	done
	if [ -d "${MASTERMNTREL?}/${PORTSDIR:?}/${_origin:?}" ]; then
		return 0
	fi
	return 1
}

listed_ports() {
	_listed_ports "$@"
}

_list_ports_dir() {
	[ $# -eq 2 ] || eargs _list_ports_dir ptdir overlay
	local ptdir="$1"
	local overlay="$2"
	local cat cats

	# skip overlays with no categories listed
	if [ ! -f "${ptdir:?}/Makefile" ]; then
		return 0
	fi
	(
		cd "${ptdir:?}"
		ptdir="."
		cats="$(awk -F= '$1 ~ /^[[:space:]]*SUBDIR[[:space:]]*\+/ {gsub(/[[:space:]]/, "", $2); print $2}' "${ptdir:?}/Makefile")" ||
		    err "${EX_SOFTWARE}" "_list_ports_dir: Failed to find categories"
		for cat in ${cats}; do
			# skip overlays with no ports hooked to the build
			[ -f "${ptdir:?}/${cat:?}/Makefile" ] || continue
			awk -F= -v cat=${cat:?} '$1 ~ /^[[:space:]]*SUBDIR[[:space:]]*\+/ {gsub(/[[:space:]]/, "", $2); print cat"/"$2}' "${ptdir:?}/${cat:?}/Makefile"
		done | while mapfile_read_loop_redir origin; do
			if ! [ -d "${ptdir:?}/${origin:?}" ]; then
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
		if [ -d "${portsdir:?}/ports" ]; then
			portsdir="${portsdir:?}/ports"
		fi
		{
			_list_ports_dir "${portsdir:?}" "${PTNAME:?}"
			for o in ${OVERLAYS}; do
				_pget portsdir "${o}" mnt ||
				    err 1 "Missing mnt metadata for overlay '${o}'"
				_list_ports_dir "${portsdir:?}" "${o}"
			done
		} | {
			# Sort but only if there's OVERLAYS to avoid
			# needless slowdown for pipelining otherwise.
			case "${OVERLAYS:+set}" in
			set) sort -ud ;;
			"") cat -u ;;
			esac
		}
		return 0
	fi

	{
		# -f specified
		case "${LISTPKGS:+set}" in
		set)
			local _ignore_comments

			for file in ${LISTPKGS}; do
				while mapfile_read_loop "${file}" origin \
				    _ignore_comments; do
					# Skip blank lines and comments
					case "${origin}" in
					""|"#"*) continue ;;
					esac
					# Remove excess slashes for mistakes
					origin="${origin#/}"
					echo "${origin%/}"
				done
			done
			;;
		esac
		# Ports specified on cmdline
		case "${LISTPORTS:+set}" in
		set)
			for origin in ${LISTPORTS}; do
				# Remove excess slashes for mistakes
				origin="${origin#/}"
				echo "${origin%/}"
			done
			;;
		esac
	} | sort -u | while mapfile_read_loop_redir originspec; do
		originspec_decode "${originspec}" origin flavor ''
		case "${flavor:+set}" in
		set)
			if ! have_ports_feature FLAVORS; then
				msg_error "Trying to build FLAVOR-specific ${originspec} but ports tree has no FLAVORS support."
				set_pipe_fatal_error || return
				continue
			fi
			;;
		esac
		originspec_listed="${originspec}"
		if check_moved "${originspec}" new_originspec 1; then
			case "${new_originspec}" in
			"EXPIRED "*)
				msg_error "MOVED: ${origin} ${new_originspec}"
				set_pipe_fatal_error || return
				continue
				;;
			esac
			originspec="${new_originspec}"
			originspec_decode "${originspec}" origin flavor ''
		else
			unset new_originspec
		fi
		if ! test_port_origin_exist "${origin}"; then
			msg_error "Nonexistent origin listed: ${COLOR_PORT}${originspec_listed}${new_originspec:+${COLOR_RESET} (moved to nonexistent ${COLOR_PORT}${new_originspec}${COLOR_RESET})}"
			set_pipe_fatal_error || return
			continue
		fi
		case "${tell_moved:+set}.${new_originspec:+set}" in
		set.set)
			msg_warn \
			    "MOVED: ${COLOR_PORT}${originspec_listed}${COLOR_RESET} renamed to ${COLOR_PORT}${new_originspec}${COLOR_RESET}"
			;;
		esac
		echo "${originspec}"
	done
}

listed_pkgnames() {
	[ -e "${MASTER_DATADIR:?}/all_pkgs" ] ||
	    err "${EX_SOFTWARE}" "listed_pkgnames: all_pkgs not yet computed"

	awk '$3 == "listed" { print $1 }' "${MASTER_DATADIR:?}/all_pkgs"
}

# Pkgname was in queue
pkgname_metadata_is_known() {
	[ $# -eq 1 ] || eargs pkgname_metadata_is_known pkgname
	local pkgname="$1"

	awk -vpkgname="${pkgname}" '
	    $1 == pkgname {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTER_DATADIR:?}/all_pkgs"
}

# Pkgname was listed to be built
pkgname_is_listed() {
	[ $# -eq 1 ] || eargs pkgname_is_listed pkgname
	local pkgname="$1"

	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi
	[ -e "${MASTER_DATADIR:?}/all_pkgs" ] ||
	    err "${EX_SOFTWARE}" "pkgname_is_listed: all_pkgs not yet computed"

	awk -vpkgname="${pkgname}" '
	    $3 == "listed" && $1 == pkgname {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTER_DATADIR:?}/all_pkgs"
}

# PKGBASE was requested to be built, or is needed by a port requested to be built
pkgbase_is_needed() {
	[ $# -eq 1 ] || eargs pkgbase_is_needed pkgname
	local pkgname="$1"
	local pkgbase

	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi
	[ -e "${MASTER_DATADIR:?}/all_pkgs_not_ignored" ] ||
	    err "${EX_SOFTWARE}" "pkgbase_is_needed: all_pkgs_not_ignored not yet computed"

	# We check on PKGBASE rather than PKGNAME from pkg_deps
	# since the caller may be passing in a different version
	# compared to what is in the queue to build for.
	pkgbase="${pkgname%-*}"

	awk -vpkgbase="${pkgbase}" '
	    {sub(/-[^-]*$/, "", $1)}
	    $1 == pkgbase {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTER_DATADIR:?}/all_pkgs_not_ignored"
}

pkgbase_is_needed_and_not_ignored() {
	[ $# -eq 1 ] || eargs pkgbase_is_needed_and_not_ignored pkgname
	local pkgname="$1"
	local pkgbase

	[ -e "${MASTER_DATADIR:?}/all_pkgs_not_ignored" ] ||
	    err "${EX_SOFTWARE}" "pkgbase_is_needed_and_not_ignored: all_pkgs_not_ignored not yet computed"

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
	    }' "${MASTER_DATADIR:?}/all_pkgs_not_ignored"
}

ignored_packages() {
	[ $# -eq 0 ] || eargs ignored_packages

	[ -e "${MASTER_DATADIR:?}/all_pkgs" ] ||
	    err "${EX_SOFTWARE}" "ignored_packages: all_pkgs not yet computed"

	awk 'NF >= 4' "${MASTER_DATADIR:?}/all_pkgs"
}

# Port was requested to be built, or is needed by a port requested to be built
originspec_is_needed_and_not_ignored() {
       [ $# -eq 1 ] || eargs originspec_is_needed_and_not_ignored originspec
       local originspec="$1"

	if originspec_misses_flavor "${originspec}"; then
		local origin=

		originspec_decode "${originspec}" origin '' ''
		msg_warn "originspec_is_needed_and_not_ignored: origin ${COLOR_PORT}${origin}${COLOR_RESET} requires a FLAVOR set for originspec"
		return 1
	fi
	[ -e "${MASTER_DATADIR:?}/all_pkgs_not_ignored" ] ||
	    err "${EX_SOFTWARE}" "originspec_is_needed_and_not_ignored: all_pkgs_not_ignored not yet computed"
       awk -voriginspec="${originspec}" '
           $2 == originspec {
               if (NF < 4)
                   found=1
               exit 0
           }
           END {
               if (found != 1)
                       exit 1
           }' "${MASTER_DATADIR:?}/all_pkgs_not_ignored"
}

# Port was listed to be built
originspec_is_listed() {
	[ $# -eq 1 ] || eargs originspec_is_listed originspec
	local originspec="$1"

	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi
	[ -e "${MASTER_DATADIR:?}/all_pkgs" ] ||
	    err "${EX_SOFTWARE}" "originspec_is_listed: all_pkgs not yet computed"
	awk -voriginspec="${originspec}" '
	    $3 == "listed" && $2 == originspec {
		found=1
		exit 0
	    }
	    END {
		if (found != 1)
			exit 1
	    }' "${MASTER_DATADIR:?}/all_pkgs"
}

get_porttesting() {
	[ "$#" -eq 2 ] || eargs get_porttesting pkgname var_return
	local pkgname="$1"
	local var_return="$2"
	local porttesting

	porttesting=0
	if [ "${PORTTESTING}" -eq 1 ]; then
		if [ "${ALL}" -eq 1 -o "${PORTTESTING_RECURSIVE}" -eq 1 ]; then
			porttesting=1
		elif pkgname_is_listed "${pkgname}"; then
			porttesting=1
		fi
	fi
	setvar "${var_return}" "${porttesting}"
}

delete_stale_symlinks_and_empty_dirs() {
	msg_n "Deleting stale symlinks..."
	find -L "${PACKAGES:?}" \
	    -name logs -prune -o \
	    \( -type l -exec rm -f {} + \)
	echo " done"

	msg_n "Deleting empty directories..."
	find "${PACKAGES:?}" -type d -mindepth 1 \
		-empty -delete
	echo " done"
}

load_moved() {
	# Tests and Distclean will run this outside of a jail.
	case "${IN_TEST:-0}.${SCRIPTNAME:?}" in
	1.*|*."distclean.sh") ;;
	*)
		required_env load_moved SHASH_VAR_PATH "var/cache"
		;;
	esac
	msg "Loading MOVED for ${MASTERMNT}${PORTSDIR}"
	bset status "loading_moved:"
	local movedfiles o

	# Duplicated logic so messages can go to stdout
	{
		if [ -f "${MASTERMNT?}${PORTSDIR:?}/MOVED" ]; then
			msg_verbose "Loading MOVED from ${MASTERMNT?}${PORTSDIR:?}/MOVED"
		fi
		for o in ${OVERLAYS}; do
			[ -f "${MASTERMNT?}${OVERLAYSDIR:?}/${o:?}/MOVED" ] ||
			    continue
			msg_verbose "Loading MOVED from ${MASTERMNT?}${OVERLAYSDIR:?}/${o:?}/MOVED"
		done
	}

	{
		if [ -f "${MASTERMNT?}${PORTSDIR:?}/MOVED" ]; then
			echo "${MASTERMNT?}${PORTSDIR:?}/MOVED"
		fi
		for o in ${OVERLAYS}; do
			[ -f "${MASTERMNT?}${OVERLAYSDIR:?}/${o:?}/MOVED" ] ||
			    continue
			echo "${MASTERMNT?}${OVERLAYSDIR:?}/${o:?}/MOVED"
		done
	} | \
	xargs cat |	# cat is so that awk is called at most once.
	awk -f "${AWKPREFIX:?}/parse_MOVED.awk" |
	while mapfile_read_loop_redir old_origin new_origin; do
		# new_origin may be EXPIRED followed by the reason
		# or only a new origin.
		shash_set originspec-moved "${old_origin}" "${new_origin}"
	done
}

check_moved() {
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs check_moved originspec new_originspec_var \
	    recurse
	local cm_originspec="$1"
	local cm_new_originspec_var="$2"
	local cm_recurse="${3-}"
	local cm_new_originspec
	local cm_origin cm_flavor cm_new_origin cm_new_flavor

	while _check_moved "${cm_originspec}" cm_new_originspec; do
		case "${cm_recurse-}" in
		0)
			setvar "${cm_new_originspec_var}" "${cm_new_originspec}"
			return 0
			;;
		esac
		# XXX: subpkg
		originspec_decode "${cm_new_originspec}" cm_new_origin \
		    cm_new_flavor ''
		case "${cm_new_originspec}" in
		""|"EXPIRED "*)
			setvar "${cm_new_originspec_var}" "${cm_new_originspec}"
			return 0
			;;
		esac
		if test_port_origin_exist "${cm_new_origin}"; then
			msg_debug "check_moved: ${COLOR_PORT}${cm_originspec}${COLOR_RESET} MOVED to ${COLOR_PORT}${cm_new_originspec}${COLOR_RESET}" >&2
			setvar "${cm_new_originspec_var}" "${cm_new_originspec}"
			return 0
		fi
		msg_debug "check_moved: ${COLOR_PORT}${cm_originspec}${COLOR_RESET} MOVED to nonexistent ${COLOR_PORT}${cm_new_originspec}${COLOR_RESET}: continuing search" >&2
		cm_originspec="${cm_new_originspec}"
	done
	setvar "${cm_new_originspec_var}" ""
	return 1
}

_check_moved() {
	[ "$#" -eq 2 ] || eargs _check_moved originspec new_originspec_var
	local _cm_originspec="$1"
	local _cm_new_originspec_var="$2"
	local _cm_new_originspec
	local _cm_origin _cm_flavor _cm_new_origin _cm_new_flavor
	local _cm_subpkg _cm_new_subpkg

	# Easy case first.
	if shash_get originspec-moved "${_cm_originspec}" \
	    _cm_new_originspec; then
		setvar "${_cm_new_originspec_var}" "${_cm_new_originspec}"
		return 0
	fi

	# It is possible that the port was MOVED but without
	# FLAVOR desingations. Check for that.
	originspec_decode "${_cm_originspec}" _cm_origin _cm_flavor _cm_subpkg
	case "${_cm_flavor}" in
	# No FLAVOR in the originspec so nothing more to do.
	"") return 1 ;;
	esac
	if ! shash_get originspec-moved "${_cm_origin}" _cm_new_originspec; then
		# This originspec wasn't moved without a FLAVOR either.
		return 1
	fi
	# The originspec *was* moved without a FLAVOR.

	# Check if the new origin has a FLAVOR. If so and the old
	# originspec also has a FLAVOR that does not match then
	# it's unclear what to do.
	originspec_decode "${_cm_new_originspec}" _cm_new_origin \
	    _cm_new_flavor _cm_new_subpkg
	case "${_cm_new_flavor}" in
	# Matching our FLAVOR, or none, is fine.
	"${_cm_flavor}") ;;
	"") _cm_new_flavor="${_cm_flavor}" ;;
	*)
		err "${EX_SOFTWARE}" \
		    "check_moved: ${COLOR_PORT}${_cm_originspec}${COLOR_RESET} moved to ${COLOR_PORT}${cm_new_originspec}${COLOR_RESET} with a different FLAVOR. MOVED src referenced default ${COLOR_PORT}${cm_origin}${COLOR_RESET}. Wrong entry or src should specify default FLAVOR."
		;;
	esac
	originspec_encode "${_cm_new_originspec_var}" \
	    "${_cm_new_origin}" "${_cm_new_flavor}" "${_cm_new_subpkg}"
	return
}

fetch_global_port_vars() {
	case "${P_PORTS_FEATURES:+set}" in
	set)
		if was_a_testport_run; then
			return 0
		fi
		;;
	esac
	export MAKE_OBJDIR_CHECK_WRITABLE=0
	port_var_fetch '' \
	    'USES=python' \
	    PORTS_FEATURES P_PORTS_FEATURES \
	    PKG_NOCOMPRESS:Dyes P_PKG_NOCOMPRESS \
	    PKG_ORIGIN P_PKG_ORIGIN \
	    PKG_SUFX P_PKG_SUFX \
	    UID_FILES P_UID_FILES \
	    LOCALBASE P_LOCALBASE \
	    PREFIX P_PREFIX \
	    || err 1 "Error looking up pre-build ports vars"
	port_var_fetch "${P_PKG_ORIGIN}" \
	    PKGNAME P_PKG_PKGNAME \
	    PKGBASE P_PKG_PKGBASE
	# Ensure not blank so -z checks work properly
	: ${P_PORTS_FEATURES:="none"}
	# Determine if the ports tree supports SELECTED_OPTIONS from r403743
	if [ -f "${MASTERMNT?}${PORTSDIR:?}/Mk/bsd.options.mk" ] && \
	    grep -m1 -q SELECTED_OPTIONS \
	    "${MASTERMNT?}${PORTSDIR:?}/Mk/bsd.options.mk"; then
		P_PORTS_FEATURES="${P_PORTS_FEATURES:+${P_PORTS_FEATURES} }SELECTED_OPTIONS"
	fi
	case "${P_PORTS_FEATURES}" in
	"none") ;;
	*) msg "Ports supports: ${P_PORTS_FEATURES}" ;;
	esac
	export P_PORTS_FEATURES

	if was_a_bulk_run; then
		local git_hash git_modified git_dirty

		if git_get_hash_and_dirty "${MASTERMNT?}/${PORTSDIR:?}" 0 \
		    git_hash git_modified; then
			shash_set ports_metadata top_git_hash "${git_hash}"
			case "${git_modified}" in
			yes) git_dirty="(dirty)" ;;
			*) git_dirty= ;;
			esac
			shash_set ports_metadata top_unclean "${git_modified}"
			msg "Ports top-level git hash: ${git_hash} ${git_dirty}"
		fi
	fi
	: "${LOCALBASE:=${P_LOCALBASE}}"
	: "${PREFIX:=${P_PREFIX}}"
	export LOCALBASE PREFIX

	PKG_EXT="${P_PKG_SUFX#.}"
	: "${PKG_BIN:="/${DATADIR_NAME:?}/pkg-static"}"
	PKG_ADD="${PKG_BIN:?} add"
	PKG_DELETE="${PKG_BIN:?} delete -y -f"
	PKG_VERSION="${PKG_BIN:?} version"
}

git_get_hash_and_dirty() {
	[ "$#" -eq 4 ] || eargs git_get_hash_and_dirty git_dir inport \
	    git_hash_var git_modified_var
	local git_dir="$1"
	local inport="${2:-0}"
	local gghd_git_hash_var="$3"
	local gghd_git_modified_var="$4"
	local gghd_git_hash gghd_git_modified

	case "${NO_GIT:+set}" in
	set) return 0 ;;
	esac

	if [ ! -x "${GIT_CMD}" ]; then
		return 1
	fi

	case "${gghd_git_hash_var-}" in
	"") ;;
	*)
		${GIT_CMD} -C "${git_dir:?}" rev-parse --show-toplevel \
		    >/dev/null 2>&1 || return
		gghd_git_hash=$(${GIT_CMD} -C "${git_dir:?}" \
		    -c core.abbrev=no \
		    log -1 --format=%h .)
		setvar "${gghd_git_hash_var}" "${gghd_git_hash}"
		;;
	esac

	gghd_git_modified=no
	msg_n "Inspecting ${git_dir} for modifications to git checkout..."
	case "${GIT_TREE_DIRTY_CHECK-}" in
	no)
		gghd_git_modified=unknown
		;;
	*)
		if git_tree_dirty "${git_dir:?}" "${inport}"; then
			gghd_git_modified=yes
		fi
		;;
	esac
	echo " ${gghd_git_modified}"
	setvar "${gghd_git_modified_var}" "${gghd_git_modified}"
}

git_tree_dirty() {
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] ||
	    eargs git_tree_dirty git_dir "[inport]"
	local git_dir="$1"
	local inport="${2:-0}"

	case "${inport}" in
	0)
		# Global: Recache.
		git_tree_dirty_cache "${git_dir}"
		;;
	esac
	if shash_exists git_tree_dirty "${git_dir}"; then
		return 0
	fi
	return 1
}

git_tree_dirty_cache() {
	[ "$#" -eq 1 ] ||
	    eargs git_tree_dirty_cache git_dir
	local git_dir="$1"
	local dirty modified
	local portdir

	shash_remove_var "git_tree_dirty"

	${GIT_CMD} -C "${git_dir}" \
	    -c core.checkStat=minimal \
	    -c core.fileMode=off \
	    -c status.renames=false \
	    -c core.untrackedCache=true \
	    -c advice.statusUoption=false \
	    status \
	    --ignored \
	    --porcelain . |
	    awk -f "${AWKPREFIX}/git_dirty.awk" |
	    while mapfile_read_loop_redir portdir; do
		case "${portdir}" in
		".")
			shash_set "git_tree_dirty" "${git_dir}" 1
			;;
		*)
			shash_set "git_tree_dirty" "${git_dir}/${portdir}" 1
			;;
		esac
	done
}

trim_ignored() {
	[ $# -eq 0 ] || eargs trim_ignored
	local pkgname originspec _rdep ignore

	bset status "trimming_ignore:"
	msg "Trimming IGNORED and blacklisted ports"

	parallel_start || err 1 "parallel_start"
	while mapfile_read_loop_redir pkgname originspec _rdep ignore; do
		case "${pkgname}" in
		"") break ;;
		esac
		parallel_run trim_ignored_pkg "${pkgname}" "${originspec}" \
		    "${ignore}"
	done <<-EOF
	$(ignored_packages)
	EOF
	parallel_stop || err "$?" "trim_ignored"
	# Update ignored/skipped stats
	update_stats 2>/dev/null || :
}

trim_ignored_pkg() {
	[ $# -eq 3 ] || eargs trim_ignored_pkg pkgname originspec ignore
	local pkgname="$1"
	local originspec="$2"
	local ignore="$3"
	local origin flavor subpkg logfile

	if ! noclobber shash_set pkgname-trim_ignored \
	    "${pkgname}" 1 2>/dev/null; then
		msg_debug "trim_ignored_pkg: Skipping duplicate ${pkgname}"
		return 0
	fi
	originspec_decode "${originspec}" origin flavor subpkg
	COLOR_ARROW="${COLOR_IGNORE}" \
	    job_msg_status "Ignoring" \
	    "${origin}${flavor:+@${flavor}}${subpkg:+~${subpkg}}" "${pkgname}" \
	    "${ignore}"
	if [ "${DRY_RUN:-0}" -eq 0 ]; then
		case "${LOGS_FOR_IGNORED-}" in
		"yes")
			local log

			_log_path log
			_logfile logfile "${pkgname}"
			{
				local NO_GIT

				NO_GIT=1 buildlog_start "${pkgname}" "${originspec}"
				print_phase_header "check-sanity"
				echo "Ignoring: ${ignore}"
				print_phase_footer
				buildlog_stop "${pkgname}" "${originspec}" 0
			} | write_atomic "${logfile}"
			ln -fs "../${pkgname:?}.log" \
			    "${log:?}/logs/ignored/${pkgname:?}.log"
			;;
		esac
		run_hook pkgbuild ignored "${origin}" "${pkgname}" "${ignore}"
	fi
	badd ports.ignored "${originspec} ${pkgname} ${ignore}"
	pkgbuild_done "${pkgname}"
	clean_pool "build" "${pkgname}" "${originspec}" "ignored"
	clean_pool "run" "${pkgname}" "${originspec}" "ignored"
}

# PWD will be MASTER_DATADIR after this
prepare_ports() {
	local pkg
	local log log_top log_jail
	local resuming_build
	local cache_dir sflag delete_pkg_list shash_bucket

	cd "${MASTER_DATADIR:?}" || return
	case "${SHASH_VAR_PATH:?}" in
	"var/cache") ;;
	*)
		err ${EX_SOFTWARE} "SHASH_VAR_PATH failed to be relpath updated"
		;;
	esac
	# Allow caching values now
	USE_CACHE_CALL=1

	fetch_global_port_vars || \
	    err 1 "Failed to lookup global ports metadata"

	if was_a_bulk_run; then
		msg_n "Acquiring build logs lock for ${MASTERNAME}..."
		if slock_acquire "logs_${MASTERNAME:?}" 60; then
			echo " done"
		else
			err 1 "failed to acquire logs lock (in use by another process)"
		fi
		_log_path log
		_log_path_jail log_jail
		_log_path_top log_top

		if [ -e "${log:?}/.poudriere.ports.built" ]; then
			resuming_build=1
		else
			resuming_build=0
		fi

		# Fetch library list for later comparisons
		case "${CHECK_CHANGED_DEPS}" in
		no) ;;
		*)
			CHANGED_DEPS_LIBLIST="$(injail \
			    ldconfig -r | \
			    awk '$1 ~ /:-l/ { gsub(/.*-l/, "", $1); printf("%s ",$1) } END { printf("\n") }')"
			;;
		esac

		if [ ${resuming_build} -eq 0 ] || ! [ -d "${log:?}" ]; then
			get_cache_dir cache_dir
			# Sync in HTML files through a base dir
			install_html_files "${HTMLPREFIX}" "${log_top:?}/.html" \
			    "${log:?}"
			# Create log dirs
			mkdir -p "${log:?}/../../latest-per-pkg" \
			    "${log:?}/../latest-per-pkg" \
			    "${log:?}/logs" \
			    "${log:?}/logs/built" \
			    "${log:?}/logs/errors" \
			    "${log:?}/logs/fetched" \
			    "${log:?}/logs/ignored" \
			    "${cache_dir:?}"
			bset stats_queued 0
			bset stats_built 0
			bset stats_failed 0
			bset stats_ignored 0
			bset stats_inspected 0
			bset stats_skipped 0
			bset stats_fetched 0
			:> "${log:?}/.data.json"
			:> "${log:?}/.data.mini.json"
			:> "${log:?}/.poudriere.ports.queued"
			:> "${log:?}/.poudriere.ports.tobuild"
			:> "${log:?}/.poudriere.ports.built"
			:> "${log:?}/.poudriere.ports.failed"
			:> "${log:?}/.poudriere.ports.ignored"
			:> "${log:?}/.poudriere.ports.inspected"
			:> "${log:?}/.poudriere.ports.skipped"
			:> "${log:?}/.poudriere.ports.fetched"
			# Link this build as the /latest
			ln -sfh "${BUILDNAME}" "${log_jail:?}/latest"

			# Record the SVN URL@REV in the build
			if [ -d "${MASTERMNT:?}${PORTSDIR:?}/.svn" ]; then
				bset svn_url $(
				${SVN_CMD} info "${MASTERMNT:?}${PORTSDIR:?}" |
				awk '
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
			case "${OVERLAYS:+set}" in
			set)
				bset overlays "${OVERLAYS}"
				;;
			esac
			if shash_exists ports_metadata top_git_hash; then
				local top_git_hash top_unclean

				shash_get ports_metadata "top_git_hash" \
				    top_git_hash ||
				    err "${EX_USAGE}" "shash_get top_git_hash"
				shash_get ports_metadata "top_unclean" \
				    top_unclean ||
				    err "${EX_USAGE}" "shash_get top_unclean"
				bset git_hash "${top_git_hash}"
				bset git_dirty "${top_unclean}"
			fi
		fi

		show_log_info
		case "${HTML_JSON_UPDATE_INTERVAL}" in
		0)
			msg "HTML UI updates are disabled by" \
			    "HTML_JSON_UPDATE_INTERVAL being 0"
			;;
		*)
			coprocess_start html_json
			;;
		esac
	fi

	case "${PKG_REPO_SIGNING_KEY:+set}" in
	set)
		local repokeypath=$(repo_key_path)
		if [ ! -f "${repokeypath}" ]; then
			err 1 "PKG_REPO_SIGNING_KEY defined but the file is missing."
		fi
		;;
	esac

	gather_port_vars
	if was_a_testport_run; then
		testport_post_gather_port_vars
	fi

	compute_needed

	if was_a_bulk_run; then
		generate_queue

		bset status "sanity:"
		msg "Sanity checking the repository"

		# Migrate packages to new sufx
		maybe_migrate_packages
		# Stash dependency graph
		cp -f "${MASTER_DATADIR}/all_pkgs_not_ignored" "${log:?}/.poudriere.all_pkgs_not_ignored%"
		cp -f "${MASTER_DATADIR}/pkg_deps" "${log:?}/.poudriere.pkg_deps%"
		pkgqueue_graph_dot > "${log:?}/.poudriere.pkg_deps.dot%" || :
		cp -f "${MASTER_DATADIR}/pkg_pool" \
		    "${log:?}/.poudriere.pkg_pool%"
		cp -f "${MASTER_DATADIR}/all_pkgs" "${log:?}/.poudriere.all_pkgs%"

		if [ -f "${PACKAGES:?}/.jailversion" ]; then
			local jailversion

			read_line jailversion "${PACKAGES:?}/.jailversion" ||
			    err 1 "failed to read .jailversion"
			case "${jailversion}" in
			"$(jget ${JAILNAME} version)") ;;
			*)
				delete_all_pkgs "newer version of jail"
				;;
			esac
		fi
		if [ ${CLEAN} -eq 1 ]; then
			case "${ATOMIC_PACKAGE_REPOSITORY}" in
			yes) ;;
			*)
				if package_dir_exists_and_has_packages; then
					confirm_if_tty "Are you sure you want to clean all packages?" || \
					    err 1 "Not cleaning all packages"
				fi
			esac
			delete_all_pkgs "-c specified"
		fi
		if [ ${CLEAN_LISTED} -eq 1 ]; then
			local reason

			if was_a_testport_run; then
				reason="testport"
			else
				msg "-C specified, cleaning listed packages"
				reason="-C"
			fi
			delete_pkg_list=$(mktemp -t poudriere.cleanC)
			delay_pipe_fatal_error
			listed_pkgnames | while mapfile_read_loop_redir \
			    pkgname; do
				pkg="${PACKAGES:?}/All/${pkgname:?}.${PKG_EXT}"
				if [ -f "${pkg}" ]; then
					if shash_exists pkgname-ignore \
					    "${pkgname}"; then
						continue
					fi
					msg "(${reason}) Will delete existing package: ${COLOR_PORT}${pkg##*/}${COLOR_RESET}"
					delete_pkg_xargs "${delete_pkg_list:?}" \
					    "${pkg:?}"
					if [ -L "${pkg%.*}.txz" ]; then
						delete_pkg_xargs \
						    "${delete_pkg_list:?}" \
						    "${pkg%.*}.txz"
					fi
				fi
			done
			if check_pipe_fatal_error; then
				err 1 "Error cleaning listed packages"
			fi
			case "${ATOMIC_PACKAGE_REPOSITORY}" in
			yes) ;;
			*)
				if ! was_a_testport_run &&
				    [ -s "${delete_pkg_list}" ]; then
					confirm_if_tty "Are you sure you want to delete the listed packages?" ||
					    err 1 "Not cleaning packages"
				fi
				;;
			esac
			msg "(${reason}) Flushing package deletions"
			remove_many_file "${delete_pkg_list:?}" rm -rf ||
			    err 1 "prepare_ports: remove_many_file"
		fi

		# If the build is being resumed then packages already
		# built/failed/skipped/ignored should not be rebuilt.
		if [ ${resuming_build} -eq 1 ]; then
			awk '{print $2}' \
			    "${log:?}/.poudriere.ports.built" \
			    "${log:?}/.poudriere.ports.failed" \
			    "${log:?}/.poudriere.ports.ignored" \
			    "${log:?}/.poudriere.ports.inspected" \
			    "${log:?}/.poudriere.ports.fetched" \
			    "${log:?}/.poudriere.ports.skipped" | \
			    pkgqueue_remove_many_pipe "build"
		else
			trim_ignored
		fi
		download_from_repo
		if ! ensure_pkg_installed; then
			delete_all_pkgs "pkg bootstrap missing: unable to inspect existing packages"
		fi
		bset status "sanity:"

		delete_bad_pkg_repo_files

		install -lsr "${log:?}" "${PACKAGES:?}/logs"
		# /packages is linked after the build in commit_packages()
		install -lsr "${PACKAGES_ROOT:?}/" "${log:?}/packages_root"

		if ensure_pkg_installed; then
			P_PKG_ABI="$(injail ${PKG_BIN:?} config ABI)" || \
			    err 1 "Failure looking up pkg ABI"
		fi
		determine_base_shlibs
		delete_old_pkgs

		# PKG_NO_VERSION_FOR_DEPS still uses this to trim out old
		# packages with versioned-dependencies which no longer exist.
		if [ ${SKIP_RECURSIVE_REBUILD} -eq 0 ]; then
			msg_verbose "Checking packages for missing dependencies"
			while :; do
				if sanity_check_pkgs; then
					break
				fi
			done
		else
			msg "Skipping recursive rebuild"
		fi

		delete_stale_symlinks_and_empty_dirs
		delete_stale_pkg_cache
		download_from_repo_post_delete
		bset status "sanity:"

		# Cleanup cached data that is no longer needed.
		(
			cd "${SHASH_VAR_PATH:?}" ||
			    err 1 "cd ${SHASH_VAR_PATH:?} failed"
			for shash_bucket in \
			    origin-flavor-all \
			    originspec-ignored \
			    pkgname-ignore \
			    pkgname-options \
			    pkgname-deps \
			    pkgname-deps-build \
			    pkgname-forbidden \
			    pkgname-no_arch \
			    pkgname-run_deps \
			    pkgname-lib_deps \
			    pkgname-trim_ignored \
			    pkgname-skipped \
			    ; do
				shash_remove_var "${shash_bucket}" || :
			done
		)

		pkgqueue_unqueue_existing_packages
		pkgqueue_trim_orphaned_build_deps

		( cd "${MASTER_DATADIR:?}"; find deps rdeps ) > \
		    "${log:?}/.poudriere.pkg_deps_trimmed%" || :
		pkgqueue_graph_dot > \
		    "${log:?}/.poudriere.pkg_deps_trimmed.dot%" || :

		# Call the deadlock code as non-fatal which will check for cycles
		msg "Sanity checking build queue"
		bset status "pkgqueue_sanity_check:"
		pkgqueue_sanity_check 0

		if [ "${resuming_build}" -eq 0 ]; then
			# Generate ports.queued list and stats_queued after
			# the queue was trimmed.
			update_tobuild
			update_stats_queued
			update_remaining
		fi

		case "${ALLOW_MAKE_JOBS-}" in
		yes) ;;
		*)
			echo "DISABLE_MAKE_JOBS=poudriere" \
			    >> "${MASTERMNT:?}/etc/make.conf"
			;;
		esac
		# Don't leak ports-env UID as it conflicts with BUILD_AS_NON_ROOT
		case "${BUILD_AS_NON_ROOT}" in
		yes)
			sed -i '' '/^UID=0$/d' "${MASTERMNT:?}/etc/make.conf"
			sed -i '' '/^GID=0$/d' "${MASTERMNT:?}/etc/make.conf"
			# Will handle manually for now on until build_port.
			export UID=0
			export GID=0
			;;
		esac

		jget ${JAILNAME} version > "${PACKAGES:?}/.jailversion" || \
		    err 1 "Missing version metadata for jail"
		echo "${BUILDNAME}" > "${PACKAGES:?}/.buildname"
	fi

	return 0
}

load_priorities_ptsort() {
	local priority pkgname originspec origin flavor _rdep
	local log pkgbase job_type
	local -

	_log_path log
	{ awk '{print $2 " " $1}' "${MASTER_DATADIR:?}/pkg_deps"; } \
	    > "${MASTER_DATADIR:?}/pkg_deps.ptsort"

	# Add in boosts before running ptsort
	while mapfile_read_loop "${MASTER_DATADIR:?}/tobuild_pkgs" \
	    pkgname originspec _rdep; do
		pkgbase="${pkgname%-*}"
		# Does this pkg have an override?
		if ! patternlist_match "${PRIORITY_BOOST-}" \
		    "${pkgbase#*:}"; then
			continue
		fi
		originspec_decode "${originspec}" origin \
		    flavor subpkg
		msg "Boosting priority: ${COLOR_PORT}${origin}${flavor:+@${flavor}}${subpkg:+~${subpkg}} | ${pkgname}"
		case "${pkgname}" in
		*:*)
			job_type="${pkgname%:*}"
			pkgname="${pkgname#*:}"
			;;
		*)
			job_type="build"
			;;
		esac
		echo "${job_type}:${pkgname}" \
		    "${PRIORITY_BOOST_VALUE}" >> \
		    "${MASTER_DATADIR:?}/pkg_deps.ptsort"
	done

	cp -f "${MASTER_DATADIR:?}/pkg_deps.ptsort" \
	    "${log:?}/.poudriere.pkg_deps.ptsort%"
	ptsort -p "${MASTER_DATADIR:?}/pkg_deps.ptsort" > \
	    "${MASTER_DATADIR:?}/pkg_deps.priority"
	unlink "${MASTER_DATADIR:?}/pkg_deps.ptsort"
	cp -f "${MASTER_DATADIR:?}/pkg_deps.priority" \
	    "${log:?}/.poudriere.pkg_deps_priority%"

	while mapfile_read_loop "${MASTER_DATADIR:?}/pkg_deps.priority" \
	    priority pkgname; do
		pkgqueue_prioritize "build" "${pkgname}" "${priority}"
	done

	return 0
}

load_priorities() {
	msg "Processing PRIORITY_BOOST"
	bset status "load_priorities:"

	load_priorities_ptsort
}

append_make() {
	[ $# -eq 3 ] || eargs append_make srcdir src_makeconf dst_makeconf
	local srcdir="$1"
	local src_makeconf="$2"
	local dst_makeconf="$3"
	local src_makeconf_real

	case "${src_makeconf}" in
	"-") src_makeconf="${srcdir:?}/make.conf" ;;
	*) src_makeconf="${srcdir:?}/${src_makeconf:?}-make.conf" ;;
	esac

	[ -f "${src_makeconf}" ] || return 0
	src_makeconf_real="$(realpath "${src_makeconf}")"
	# Only append if not already done (-z -p or -j match)
	if grep -q "# ${src_makeconf_real} #" "${dst_makeconf}"; then
		return 0
	fi
	msg "Appending to make.conf: ${src_makeconf}"
	{
		echo -n "#### ${src_makeconf_real} ####"
		case "${src_makeconf_real}" in
		"${src_makeconf}")
			echo
			;;
		*)
			echo " ${src_makeconf}"
			;;
		esac
		cat "${src_makeconf}"
	} >> "${dst_makeconf:?}"
}

read_packages_from_params()
{
	if [ $# -eq 0 -o -z "$1" ]; then
		[ -n "${LISTPKGS}" -o ${ALL} -eq 1 ] ||
		    err ${EX_USAGE} "No packages specified"
		if [ ${ALL} -eq 0 ]; then
			for listpkg_name in ${LISTPKGS}; do
				[ -r "${listpkg_name}" ] ||
				    err ${EX_USAGE} "No such list of packages: ${listpkg_name}"
			done
		fi
	else
		[ ${ALL} -eq 0 ] ||
		    err ${EX_USAGE} "command line arguments and -a cannot be used at the same time"
		[ -z "${LISTPKGS}" ] ||
		    err ${EX_USAGE} "command line arguments and list of ports cannot be used at the same time"
		LISTPORTS="$*"
	fi
}

clean_restricted() {
	local o

	msg "Cleaning restricted packages"
	bset status "clean_restricted:"
	remount_packages -o rw
	injail /usr/bin/make -s -C "${PORTSDIR:?}" -j ${PARALLEL_JOBS} \
	    RM="/bin/rm -fv" ECHO_MSG="true" clean-restricted
	for o in ${OVERLAYS}; do
		injail /usr/bin/make -s -C "${OVERLAYSDIR:?}/${o:?}" \
		    -j ${PARALLEL_JOBS} \
		    RM="/bin/rm -fv" ECHO_MSG="true" clean-restricted
	done
	remount_packages -o ro
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

	case "${CFG_SIZE:+set}" in
	set) calculate_size_in_mb CFG_SIZE ;;
	"") CFG_SIZE=0 ;;
	esac
	case "${DATA_SIZE:+set}" in
	set) calculate_size_in_mb DATA_SIZE ;;
	"") DATA_SIZE=0 ;;
	esac
	case "${SWAP_SIZE:+set}" in
	set) calculate_size_in_mb SWAP_SIZE ;;
	"") SWAP_SIZE=0 ;;
	esac

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

	case "${SOURCES_URL:+set}" in
	set)
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
		pkgbase*)
			case "${SOURCES_URL}" in
			http://*) ;;
			https://*) ;;
			file://*) ;;
			pkg+https://*) ;;
			*)
				msg_error "Invalid pkgbase url"
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
		;;
	*)
		# Compat hacks for FreeBSD's special git server
		case "${GIT_URL_DEFAULT}" in
		"${FREEBSD_GIT_BASEURL}"|"${FREEBSD_GIT_PORTSURL}")
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
		;;
	esac
	setvar "${METHOD_var}" "${_METHOD}"
	setvar "${SVN_FULLURL_var}" "${_SVN_FULLURL}"
	setvar "${GIT_FULLURL_var}" "${_GIT_FULLURL}"
}

# Builtin-only functions
_BUILTIN_ONLY=""
for _var in ${_BUILTIN_ONLY}; do
	case "$(type "${_var}" 2>/dev/null)" in
	"${_var} is a shell builtin") ;;
	*)
		eval "${_var}() { return 0; }"
		;;
	esac
done
unset _BUILTIN_ONLY
case "$(type setproctitle 2>/dev/null)" in
"setproctitle is a shell builtin")
	setproctitle() {
		PROC_TITLE="$*"
		command setproctitle "poudriere${MASTERNAME:+[${MASTERNAME}]}${MY_BUILDER_ID:+[${MY_BUILDER_ID}]}: $*"
	}
	;;
*)
	setproctitle() {
		PROC_TITLE="$*"
	}
	;;
esac

STATUS=0 # out of jail #
if [ ${IN_TEST:-0} -eq 0 ]; then
	# cd into / to avoid foot-shooting if running from deleted dirs or
	# NFS dir which root has no access to.
	SAVED_PWD="${PWD}"
	cd /tmp
fi

. ${SCRIPTPREFIX:?}/include/colors.pre.sh
if [ -z "${POUDRIERE_ETC}" ]; then
	POUDRIERE_ETC=$(realpath ${SCRIPTPREFIX:?}/../../etc)
fi
# If this is a relative path, add in ${PWD} as a cd / is done.
if [ "${POUDRIERE_ETC#/}" = "${POUDRIERE_ETC}" ]; then
	POUDRIERE_ETC="${SAVED_PWD:?}/${POUDRIERE_ETC}"
fi
POUDRIERED=${POUDRIERE_ETC}/poudriere.d
include_poudriere_confs "$@"

AWKPREFIX=${SCRIPTPREFIX:?}/awk
HTMLPREFIX=${SCRIPTPREFIX:?}/html
HOOKDIR=${POUDRIERED}/hooks

# If the zfs module is not loaded it means we can't have zfs
case "${NO_ZFS:+set}" in
set) ;;
*)
	lsvfs zfs >/dev/null 2>&1 || NO_ZFS=yes
esac
# Short circuit to prevent running zpool(1) and loading zfs.ko
case "${NO_ZFS:+set}" in
set) ;;
*)
	case "$(zpool list -H -o name 2>/dev/null)" in
	"")
		NO_ZFS=yes
		;;
	esac
	;;
esac
case "${NO_ZFS:+set}.${ZPOOL:+set}" in
""."")
	err 1 "ZPOOL variable is not set"
	;;
esac
case "${BASEFS:+set}" in
set) ;;
*)
	err 1 "Please provide a BASEFS variable in your poudriere.conf"
	;;
esac

# Test if zpool exists
case "${NO_ZFS:+set}" in
set) ;;
*)
	zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool: ${ZPOOL}"
	;;
esac

case "${NO_ZFS:+set}" in
set) ;;
*)
	: ${ZROOTFS="/poudriere"}
	case ${ZROOTFS} in
	[!/]*) err 1 "ZROOTFS should start with a /" ;;
	esac
	;;
esac

HOST_OSVERSION="$(sysctl -n kern.osreldate 2>/dev/null || echo 0)"
case "${NO_ZFS:+set}.${ZFS_DEADLOCK_IGNORED:+set}" in
""."")
	if [ "${HOST_OSVERSION:?}" -gt 900000 -a \
	    "${HOST_OSVERSION:?}" -le 901502 ]; then
		err 1 \
		    "FreeBSD 9.1 ZFS is not safe. It is known to deadlock and cause system hang. Either upgrade the host or set ZFS_DEADLOCK_IGNORED=yes in poudriere.conf"
	fi
	;;
esac

: ${USE_TMPFS:=no}
case "${USE_TMPFS-}.${MFSSIZE:+set}" in
no.*) ;;
*.set)
	err ${EX_USAGE} "You can't use both tmpfs and mdmfs"
	;;
esac

for val in ${USE_TMPFS}; do
	case ${val} in
	wrkdir) TMPFS_WRKDIR=1 ;;
	data) TMPFS_DATA=1 ;;
	all) TMPFS_ALL=1 ;;
	localbase) TMPFS_LOCALBASE=1 ;;
	image) TMPFS_IMAGE=1 ;;
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
case "${MUTABLE_BASE:+set}.${IMMUTABLE_BASE:+set}" in
set."")
	for val in ${MUTABLE_BASE}; do
		case ${val} in
			schg|nullfs)	IMMUTABLE_BASE="${val}" ;;
			yes)		IMMUTABLE_BASE="no" ;;
			no)		IMMUTABLE_BASE="yes" ;;
			*) err 1 "Unknown value for MUTABLE_BASE" ;;
		esac
		msg_warn "MUTABLE_BASE=${val} is deprecated. Change to IMMUTABLE_BASE=${IMMUTABLE_BASE}"
	done
	unset val
	;;
esac

for val in ${IMMUTABLE_BASE-}; do
	case "${val}" in
		schg|no|nullfs) ;;
		yes) IMMUTABLE_BASE="schg" ;;
		*) err 1 "Unknown value for IMMUTABLE_BASE" ;;
	esac
done
unset val

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
: ${WRKDIR_ARCHIVE_FORMAT="txz"}
case "${WRKDIR_ARCHIVE_FORMAT}" in
	tar|tgz|tbz|txz|tzst);;
	*) err 1 "invalid format for WRKDIR_ARCHIVE_FORMAT: ${WRKDIR_ARCHIVE_FORMAT}" ;;
esac

#Converting portstree if any
if [ ! -d "${POUDRIERED:?}/ports" ] &&  [ ! -L "${POUDRIERED:?}/ports" ]; then
	mkdir -p ${POUDRIERED}/ports
	case "${NO_ZFS:+set}" in
	set) ;;
	*)
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
		;;
	esac
	if [ -f ${POUDRIERED}/portstrees ]; then
		while read name method mnt; do
			case "${name}" in
			"#"*) continue ;;
			esac
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
	case "${NO_ZFS:+set}" in
	set) ;;
	*)
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
			zfs inherit -r ${NS}:stats_inspected ${fs}
			zfs inherit -r ${NS}:stats_queued ${fs}
			zfs inherit -r ${NS}:status ${fs}
		done
		;;
	esac
fi

: ${LOIP6:=::1}
: ${LOIP4:=127.0.0.1}
# If in a nested jail we may not even have a loopback to use.
if [ "${JAILED:-0}" -eq 1 ]; then
	# !! Note these exit statuses are inverted
	if ifconfig |
	    awk -vip="${LOIP6}" '$1 == "inet6" && $2 == ip {exit 1}'; then
		LOIP6=
	fi
	if ifconfig |
	    awk -vip="${LOIP4}" '$1 == "inet" && $2 == ip {exit 1}'; then
		LOIP4=
	fi
fi
case "${LOIP6:+set}.${LOIP4:+set}" in
""."")
	msg_warn "No loopback address defined, consider setting LOIP6/LOIP4 or assigning a loopback address to the jail."
	;;
esac
case "${IPS:?}" in
01)
	LOCALIPARGS="${LOIP6:+ip6.addr=${LOIP6}}"
	IPARGS="ip6=inherit"
	;;
10)
	LOCALIPARGS="${LOIP4:+ip4.addr=${LOIP4}}"
	IPARGS="ip4=inherit"
	;;
11)
	LOCALIPARGS="${LOIP4:+ip4.addr=${LOIP4} }${LOIP6:+ip6.addr=${LOIP6}}"
	IPARGS="ip4=inherit ip6=inherit"
	;;
esac

NCPU="$(nproc)"

case ${PARALLEL_JOBS} in
''|*[!0-9]*)
	PARALLEL_JOBS=${NCPU}
	;;
esac

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
case "${CCACHE_DIR:+set}.${CCACHE_DIR_NON_ROOT_SAFE-}" in
set.no)
	case "${BUILD_AS_NON_ROOT-}" in
	yes)
		msg_warn "BUILD_AS_NON_ROOT and CCACHE_DIR are potentially incompatible.  Disabling BUILD_AS_NON_ROOT"
		msg_warn "Either disable one or, set CCACHE_DIR_NON_ROOT_SAFE=yes and do the following procedure _on the host_."
		cat >&2 <<-EOF

		## Summary of https://ccache.dev/manual/3.7.11.html#_sharing_a_cache
			# pw groupadd portbuild -g 65532
			# pw useradd portbuild -u 65532 -g portbuild -d /nonexistent -s /usr/sbin/nologin
			# pw groupmod -n portbuild -m root
			# echo "umask = 0002" >> ${CCACHE_DIR:?}/ccache.conf
			# find ${CCACHE_DIR:?}/ -type d -exec chmod 2775 {} +
			# find ${CCACHE_DIR:?}/ -type f -exec chmod 0664 {} +
			# chown -R :portbuild ${CCACHE_DIR:?}/
			# chmod 1777 ${CCACHE_DIR:?}/tmp

		## If a separate group is wanted:
			# pw groupadd ccache -g 65531
			# pw groupmod -n cacche -m root
			# chown -R :ccache ${CCACHE_DIR:?}/

		## poudriere.conf
			CCACHE_DIR_NON_ROOT_SAFE=yes
			CCACHE_GROUP=ccache
			CCACHE_GID=65531
		EOF
		err ${EX_DATAERR} "BUILD_AS_NON_ROOT + CCACHE_DIR manual action required."
		;;
	esac
	# Default off with CCACHE_DIR.
	: ${BUILD_AS_NON_ROOT:=no}
	;;
esac
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
: ${SKIP_RECURSIVE_REBUILD:=0}
: ${PKG_NO_VERSION_FOR_DEPS:=no}
: ${VERBOSE:=0}
: ${QEMU_EMULATING:=0}
: ${PORTTESTING:=0}
: ${PORTTESTING_FATAL:=yes}
: ${PORTTESTING_RECURSIVE:=0}
: ${PRIORITY_BOOST_VALUE:=99}
: ${RESTRICT_NETWORKING:=yes}
: ${DISALLOW_NETWORKING:=no}
: ${TRIM_ORPHANED_BUILD_DEPS:=yes}
: ${USE_PROCFS:=yes}
: ${USE_FDESCFS:=yes}
: ${IMMUTABLE_BASE:=no}
: ${PKG_REPO_LIST_FILES:=no}
: ${PKG_REPRODUCIBLE:=yes}
: ${HTML_JSON_UPDATE_INTERVAL:=2}
: ${HTML_TRACK_REMAINING:=no}
: ${GIT_TREE_DIRTY_CHECK:=yes}
: ${FORCE_MOUNT_HASH:=no}
: ${DELETE_UNQUEUED_PACKAGES:=no}
: ${DELETE_UNKNOWN_FILES:=yes}
: ${DETERMINE_BUILD_FAILURE_REASON:=yes}
DRY_RUN=0
INTERACTIVE_MODE=0
: ${INTERACTIVE_SHELL:=sh}

# Be sure to update poudriere.conf to document the default when changing these
: ${FREEBSD_SVN_HOST:="svn.FreeBSD.org"}
: ${FREEBSD_GIT_HOST:="git.FreeBSD.org"}
: ${FREEBSD_GIT_BASEURL:="${FREEBSD_GIT_HOST}/src.git"}
: ${FREEBSD_GIT_PORTSURL:="${FREEBSD_GIT_HOST}/ports.git"}
: ${FREEBSD_HOST:="https://download.FreeBSD.org"}
: ${FREEBSD_GIT_SSH_USER="anongit"}
case "${PRESERVE_TIMESTAMP:-no}" in
yes)
	SVN_PRESERVE_TIMESTAMP="--config-option config:miscellany:use-commit-times=yes"
	;;
esac
: ${SVN_HOST:="${FREEBSD_SVN_HOST}"}
: ${GIT_HOST:="${FREEBSD_GIT_HOST}"}
: ${GIT_BASEURL:=${FREEBSD_GIT_BASEURL}}
# GIT_URL is old compat
: ${GIT_PORTSURL:=${GIT_URL:-${FREEBSD_GIT_PORTSURL}}}

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
: "${TIMESTAMP_FLAGS:=}"
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
: ${FORCE_REBUILD_PACKAGES=}
: ${FLAVOR_DEFAULT_ALL:=no}
: ${NULLFS_PATHS:="/rescue /usr/share /usr/tests /usr/lib32"}
: ${PACKAGE_FETCH_URL:="pkg+http://pkg.FreeBSD.org/\${ABI}"}
: "${PACKAGE_FETCH_WHITELIST="*"}"
: ${DEVFS_RULESET:=4}
: ${PKG_HASH:=no}

: "${POUDRIERE_TMPDIR:=$(command mktemp -dt poudriere)}"
case "${IN_TEST:-0}" in
0)
# POUDRIERE_TMPDIR will be used for now on in mktemp() override.
unset TMPDIR
;;
esac
: "${SHASH_VAR_PATH_DEFAULT:=${POUDRIERE_TMPDIR:?}}"
: ${SHASH_VAR_PATH:=${SHASH_VAR_PATH_DEFAULT}}
: ${SHASH_VAR_PREFIX:=sh-}
: ${DATADIR_NAME:=".p"}

: ${BUILDNAME_FORMAT:="%Y-%m-%d_%Hh%Mm%Ss"}
: ${BUILDNAME:=$(date +${BUILDNAME_FORMAT})}

: ${HTML_TYPE:=inline}
: ${LC_COLLATE:=C}
export LC_COLLATE

: ${MAX_FILES:=8192}
: ${PIPE_FATAL_ERROR_FILE:="${POUDRIERE_TMPDIR:?}/pipe_fatal_error-$$"}
HAVE_FDESCFS=0
case "$(mount -t fdescfs | awk '$3 == "/dev/fd" {print $3}')" in
"/dev/fd")
	HAVE_FDESCFS=1
	;;
esac

: ${OVERLAYSDIR:=/overlays}

TIME_START=$(clock -monotonic)
EPOCH_START=$(clock -epoch)

. ${SCRIPTPREFIX:?}/include/colors.sh
. ${SCRIPTPREFIX:?}/include/display.sh
. ${SCRIPTPREFIX:?}/include/html.sh
. ${SCRIPTPREFIX:?}/include/parallel.sh
. ${SCRIPTPREFIX:?}/include/shared_hash.sh
. ${SCRIPTPREFIX:?}/include/cache.sh
. ${SCRIPTPREFIX:?}/include/fs.sh
. ${SCRIPTPREFIX:?}/include/pkg.sh
. ${SCRIPTPREFIX:?}/include/pkgqueue.sh

if [ -e /nonexistent ]; then
	err 1 "You may not have a /nonexistent.  Please remove it."
fi

if [ "${IN_TEST:-0}" -eq 0 ]; then
	setup_traps exit_handler
	enable_siginfo_handler
fi
