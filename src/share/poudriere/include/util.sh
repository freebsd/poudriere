# Copyright (c) 2016-2017 Bryan Drewery <bdrewery@FreeBSD.org>
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

# shellcheck shell=ksh disable=SC2128

: "${ENCODE_SEP:="$'\002'"}"

if ! type eargs 2>/dev/null >&2; then
	eargs() {
		local badcmd="$1"
		shift
		echo "Bad arguments, ${badcmd}: $*" >&2
		exit 1
	}
fi

if ! type setproctitle 2>/dev/null >&2; then
	setproctitle() { :; }
fi

unimplemented() {
	[ "$#" -ge 1 ] || eargs unimplemented funcname '[args]'
	local funcname="$1"
	shift
	err "${EX_SOFTWARE-70}" "${funcname} unimplemented. Args: $*"
}

deprecated() {
	[ "$#" -ge 2 ] || eargs deprecated funcname reason '[args]'
	local funcname="$1"
	local reason="$2"
	shift 2
	err "${EX_SOFTWARE-70}" "${funcname} deprecated, ${reason}. Args: $*"
}

# Encode $@ for later decoding
encode_args() {
	local -; set +x
	[ "$#" -ge 1 ] || eargs encode_args var_return '[args]'
	local ea_var_return="$1"
	shift
	local ea_args IFS

	IFS="${ENCODE_SEP}"
	ea_args="$*"
	unset IFS
	# Trailing empty fields need special handling.
	case "${ea_args}" in
	*"${ENCODE_SEP}")
		setvar "${ea_var_return}" "${ea_args}${ENCODE_SEP}" || return
		;;
	*)
		setvar "${ea_var_return}" "${ea_args}" || return
		;;
	esac
}

# Decode data from encode_args
# Usage: eval "$(decode_args data_var_name)"
decode_args() {
	local -; set +x
	[ $# -eq 1 ] || eargs decode_args encoded_args_var
	local encoded_args_var="$1"
	local _decode_args

	_decode_args _decode_args "${encoded_args_var}"
	echo "${_decode_args}"
}

# Decode data from encode_args without a fork
# Usage: _decode_args evalstr data_var_name; eval "${evalstr}"; unset evalstr
_decode_args() {
	local -; set +x
	[ $# -eq 2 ] || eargs decode_args var_return_eval encoded_args_var
	local var_return_eval="$1"
	local encoded_args_var="$2"

	# local -; set -f; IFS="${ENCODE_SEP}"; set -- ${data}; unset IFS
	setvar "${var_return_eval}" "
		local IFS 2>/dev/null || :;
		case \$- in *f*) set_f=1 ;; *) set_f=0 ;; esac;
		if [ \"\${set_f}\" -eq 0 ]; then
			set -f;
		fi;
		IFS=\"\${ENCODE_SEP}\";
		set -- \${${encoded_args_var}};
		unset IFS;
		if [ \"\${set_f}\" -eq 0 ]; then
			set +f;
		fi;
		unset set_f;
		unset ${var_return_eval};
		"
}

# Decode data from encode_args
decode_args_vars() {
	local -; set +x -f
	[ $# -ge 2 ] || eargs decode_args_vars data var1 '[var2... varN]'
	local encoded_args_data="$1"
	local dav_val dav_var IFS
	local -
	shift
	local dav_vars="$*"

	IFS="${ENCODE_SEP}"
	set -o noglob
	# shellcheck disable=SC2086
	set -- ${encoded_args_data}
	set +o noglob
	unset IFS
	for dav_val; do
		# Select the next var to populate.
		dav_var="${dav_vars%% *}"
		case "${dav_vars}" in
		# Last one - set all remaining to here
		"${dav_var}")
			setvar "${dav_var}" "$*" || return
			break
			;;
		*)
			setvar "${dav_var}" "${dav_val}" || return
			# Pop off the var
			dav_vars="${dav_vars#"${dav_var}" }"
			shift
			;;
		esac
	done
}

if ! type isset >/dev/null 2>&1; then
isset() {
	[ $# -eq 1 ] || eargs isset var
	local isset_var="$1"
	local isset_val

	eval "isset_val=\${${isset_var}-isv__null}"

	case "${isset_val}" in
	"isv__null") return 1 ;;
	esac
	return 0
}
fi

issetvar() {
	deprecated issetvar "use isset" "$@"
}

if ! type setvar >/dev/null 2>&1; then
setvar() {
	[ $# -eq 2 ] || eargs setvar variable value
	local _setvar_var="$1"
	shift
	local _setvar_value="$*"

	eval "${_setvar_var:?}=\"\${_setvar_value}\""
}
fi

if ! type getvar >/dev/null 2>&1; then
getvar() {
	local sx="$-"; local -; set +x
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || eargs getvar var '[var_return]'
	local _getvar_var="$1"
	local _getvar_var_return="$2"
	local _getvar_ret _getvar_value
	local _getvar_dbg

	eval "_getvar_value=\${${_getvar_var}-gv__null}"

	case "${sx}" in
	*x*)
		_getvar_dbg="echo"
		;;
	*)
		_getvar_dbg=":"
		;;
	esac

	case "${_getvar_value}" in
	gv__null)
		_getvar_value=
		_getvar_ret=1
		case "${_getvar_var_return}" in
		""|-) ;;
		*) unset "${_getvar_var_return}" ;;
		esac
		"${_getvar_dbg}" "${PS4}unset ${_getvar_var_return}" >&2
		;;
	*)
		_getvar_ret=0
		case "${_getvar_var_return}" in
		""|-) echo "${_getvar_value}" ;;
		*)
			setvar "${_getvar_var_return}" "${_getvar_value}" ||
			    return
			;;
		esac
		"${_getvar_dbg}" "${PS4}${_getvar_var_return}=${_getvar_value}" >&2
		;;
	esac

	return "${_getvar_ret}"
}
fi

incrvar() {
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || eargs incrvar var '[diff]'
	local incv_var="$1"
	local incv_diff="${2:-1}"
	local incv_value

	getvar "${incv_var}" incv_value || incv_value=0
	setvar "${incv_var}" "$((incv_value + incv_diff))"
}

decrvar() {
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || eargs decrvar var '[diff]'
	local decv_var="$1"
	local decv_diff="${2:-1}"
	local decv_value

	getvar "${decv_var}" decv_value || return 1
	setvar "${decv_var}" "$((decv_value - decv_diff))"
}

# Given 2 directories, make both of them relative to their
# common directory.
# $1 = _relpath_common = common directory
# $2 = _relpath_common_dir1 = dir1 relative to common
# $3 = _relpath_common_dir2 = dir2 relative to common
_relpath_common() {
	local -; set +x
	[ $# -eq 2 ] || eargs _relpath_common dir1 dir2
	local _rc_dir1 _rc_dir2 _rc_common _rc_other

	# shellcheck disable=SC2001
	_rc_dir1=$(realpath -q "$1" || echo "$1" | sed -e 's,//*,/,g') ||
	    return "${EX_OSERR:-71}"
	_rc_dir1="${_rc_dir1%/}/"
	# shellcheck disable=SC2001
	_rc_dir2=$(realpath -q "$2" || echo "$2" | sed -e 's,//*,/,g') ||
	    return "${EX_OSERR:-71}"
	_rc_dir2="${_rc_dir2%/}/"
	if [ "${#_rc_dir1}" -ge "${#_rc_dir2}" ]; then
		_rc_common="${_rc_dir1}"
		_rc_other="${_rc_dir2}"
	else
		_rc_common="${_rc_dir2}"
		_rc_other="${_rc_dir1}"
	fi
	# Trim away path components until they match
	#while [ "${_rc_other#${_rc_common%/}/}" = "${_rc_other}" -a -n "${_rc_common}" ]; do
	#	_rc_common="${_rc_common%/*}"
	#done
	while :; do
		case "${_rc_common:+set}" in
		set)
			case "${_rc_other}" in
			"${_rc_common%/}/"*)
				break
				;;
			*)
				_rc_common="${_rc_common%/*}"
				;;
			esac
			;;
		"") break ;;
		esac
	done
	_rc_common="${_rc_common%/}"
	_rc_common="${_rc_common:-/}"
	_rc_dir1="${_rc_dir1#"${_rc_common}"/}"
	_rc_dir1="${_rc_dir1#/}"
	_rc_dir1="${_rc_dir1%/}"
	_rc_dir1="${_rc_dir1:-.}"
	_rc_dir2="${_rc_dir2#"${_rc_common}"/}"
	_rc_dir2="${_rc_dir2#/}"
	_rc_dir2="${_rc_dir2%/}"
	_rc_dir2="${_rc_dir2:-.}"

	_relpath_common="${_rc_common}"
	_relpath_common_dir1="${_rc_dir1}"
	_relpath_common_dir2="${_rc_dir2}"
}

# See _relpath_common
relpath_common() {
	local -; set +x
	[ $# -eq 2 ] || eargs relpath_common dir1 dir2
	local rc_dir1="$1"
	local rc_dir2="$2"
	local _relpath_common _relpath_common_dir1 _relpath_common_dir2

	_relpath_common "${rc_dir1}" "${rc_dir2}"
	echo "${_relpath_common} ${_relpath_common_dir1} ${_relpath_common_dir2}"
}

: "${RELPATH_DEFAULT_VAR:=_relpath}"

# Given 2 paths, return the relative path from the 2nd to the first
_relpath() {
	local -; set +x -f
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] ||
	    eargs _relpath dir1 dir2 '[var_return]'
	local _r_dir1="$1"
	local _r_dir2="$2"
	local _r_var="${3:-"${RELPATH_DEFAULT_VAR}"}"
	local _relpath_common _relpath_common_dir1 _relpath_common_dir2
	local _r_newpath IFS
	local -

	# Find the common prefix
	_relpath_common "${_r_dir1}" "${_r_dir2}"

	case "${_relpath_common_dir2}" in
	".")
		_r_newpath="${_relpath_common_dir1}"
		;;
	*)
		# Replace each component in _relpath_common_dir2 with
		# a ..
		IFS="/"
		case "${_relpath_common_dir1}" in
		".")
			_r_newpath=
			;;
		*)
			_r_newpath="${_relpath_common_dir1}"
			;;
		esac
		set -o noglob
		# shellcheck disable=SC2086
		set -- ${_relpath_common_dir2}
		set +o noglob
		while [ $# -gt 0 ]; do
			_r_newpath="..${_r_newpath:+/}${_r_newpath}"
			shift
		done
		;;
	esac

	case "${_r_var}" in
	-) echo "${_r_newpath}" ;;
	*) setvar "${_r_var}" "${_r_newpath}" || return ;;
	esac
}

# See _relpath
relpath() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] ||
	    eargs relpath dir1 dir2 '[var_return]'
	local r_dir1="$1"
	local r_dir2="$2"
	local r_var="${3:-"-"}"
	local "${RELPATH_DEFAULT_VAR}"

	_relpath "${r_dir1}" "${r_dir2}" "${r_var}"
}

in_reldir() {
	[ "$#" -ge 2 ] || eargs in_reldir reldir_var cmd 'args...'
	local reldir_var="$1"
	shift
	local reldir_val nested_dir wanted_dir
	# shellcheck disable=SC2034
	local reldir_abs_val
	local ir_ret ir_oldpwd

	case "${reldir_var}" in
	*/*)
		nested_dir="${reldir_var#*/}"
		reldir_var="${reldir_var%%/*}"
		;;
	*)
		nested_dir=
	esac

	getvar "${reldir_var}" reldir_val ||
	    err "${EX_SOFTWARE}" "in_reldir: Failed to find value for '${reldir_var}'"
	getvar "${reldir_var}_ABS" reldir_abs_val ||
	    err "${EX_SOFTWARE}" "in_reldir: Failed to find value for '${reldir_var}_ABS'"
	wanted_dir="${reldir_val:?}${nested_dir:+/${nested_dir}}"
	case "${PWD}" in
	"${wanted_dir:?}")
		ir_oldpwd=
		;;
	*)
		cd "${wanted_dir:?}"
		ir_oldpwd="${OLDPWD}"
		;;
	esac

	ir_ret=0
	"$@" || ir_ret="$?"

	case "${ir_oldpwd:+set}" in
	set) cd "${ir_oldpwd}" ;;
	esac

	return "${ir_ret}"
}

make_relative() {
	[ "$#" -eq 1 ] || [ "$#" -eq 3 ] || eargs make_relative varname \
	    [oldroot newroot]
	local mr_var="$1"
	local mr_oldroot="${2:-${PWD}}"
	local mr_newroot="${3:-${PWD}}"
	local mr_val

	getvar "${mr_var}" mr_val || return 0
	case "${mr_val}" in
	"") return 0 ;;
	esac
	case "${mr_val}" in
	/*)	_relpath "${mr_val}" "${mr_newroot}" "${mr_var}" ;;
	*)	_relpath "${mr_oldroot}/${mr_val}" "${mr_newroot}" "${mr_var}" ;;
	esac
}

_update_relpaths() {
	local -; set +x
	[ $# -eq 2 ] || eargs _update_relpaths oldroot newroot
	local _ur_oldroot="$1"
	local _ur_newroot="$2"
	local _ur_var

	for _ur_var in ${RELATIVE_PATH_VARS}; do
		make_relative "${_ur_var}" "${_ur_oldroot}" "${_ur_newroot}"
	done
}

add_relpath_var() {
	[ $# -eq 1 ] || eargs add_relpath_var varname
	local arv_var="$1"
	local arv_val

	getvar "${arv_var}" arv_val ||
	    err "${EX_SOFTWARE}" "add_relpath_var: \$${arv_var} path must be set"
	case " ${RELATIVE_PATH_VARS} " in
	*" ${arv_var} "*) ;;
	*) RELATIVE_PATH_VARS="${RELATIVE_PATH_VARS:+${RELATIVE_PATH_VARS} }${arv_var}" ;;
	esac
	if ! isset "${arv_var}_ABS"; then
		case "${arv_val}" in
		/*) ;;
		*)
			[ -e "${arv_val}" ] ||
			    err "${EX_SOFTWARE}" "add_relpath_var: \$${arv_var} value '${arv_val}' must exist or be absolute already"
			arv_val="$(realpath "${arv_val}")"
		    ;;
		esac
		setvar "${arv_var}_ABS" "${arv_val}" || return
	fi
	make_relative "${arv_var}"
}

# Handle relative path change needs
cd() {
	local ret

	ret=0
	critical_start
	command cd "$@" || ret=$?
	# Handle fixing relative paths
	case "${OLDPWD}" in
	"${PWD}") ;;
	*)
		_update_relpaths "${OLDPWD}" "${PWD}" || :
		;;
	esac
	critical_end
	return ${ret}
}

case "$(type unlink 2>/dev/null)" in
"unlink is a shell builtin") ;;
*)
unlink() {
	[ $# -eq 2 ] || [ $# -eq 1 ] || eargs unlink '[--]' file

	command unlink "$@" 2>/dev/null || :
}
;;
esac

case "$(type randint 2>/dev/null)" in
"randint is a shell builtin") ;;
*)
randint() {
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] ||
	    eargs randint max_val '[var_return]'
	local max_val="$1"
	local r_outvar="${2-}"
	local val

	if [ "$#" -eq 1 ]; then
		jot -r 1 "${max_val}"
		return
	fi
	val=$(jot -r 1 "${max_val}")
	setvar "${r_outvar}" "${val}"
}
;;
esac

_trap_ignore_block() {
	local -; set +x
	[ "$#" -ge 3 ] ||
	    eargs _trap_ignore_block ignore_bool tmp_var SIG '[SIG...]'
	local tib_ignore_bool="$1"
	local tib_tmp_var="$2"
	local sig tmp_val oact bucket
	shift 2

	if getvar "${tib_tmp_var}" tmp_val; then
		bucket="trap_ignore_${tmp_val}"
		for sig; do
			hash_remove "${bucket}" "${sig}" oact ||
			    err "${EX_SOFTWARE}" "_trap_ignore_block: No saved action for signal ${sig}"
			trap_pop "${sig}" "${oact}" ||
			    err "${EX_USAGE}" "_trap_ignore_block: trap_pop ${sig} '${oact}' failed"
		done
		unset "${tib_tmp_var}"
		return 1
	fi
	randint 1000000000 tmp_val
	bucket="trap_ignore_${tmp_val}"
	setvar "${tib_tmp_var}" "${tmp_val}" || return
	for sig; do
		trap_push "${sig}" "oact" ||
		    err "${EX_USAGE}" "_trap_ignore_block: trap_push ${sig} failed"
		hash_set "${bucket}" "${sig}" "${oact}"
		if [ "${tib_ignore_bool}" -eq 1 ]; then
			trap '' "${sig}"
		fi
	done
}

trap_save_block() {
	[ "$#" -ge 2 ] || eargs trap_save_block tmp_var SIG '[SIG...]'
	_trap_ignore_block 0 "$@"
}

trap_ignore_block() {
	[ "$#" -ge 2 ] || eargs trap_save_block tmp_var SIG '[SIG...]'
	_trap_ignore_block 1 "$@"
}

case "$(type trap_push 2>/dev/null)" in
"trap_push is a shell builtin")
critical_inherit() { :; }
	;;
*)
trap_push() {
	local -; set +x
	[ $# -eq 2 ] || eargs trap_push signal var_return
	local signal="$1"
	local tp_outvar="$2"
	local _trap ldash lhandler lsig

	_trap="-"
	# shellcheck disable=SC2034
	while read -r ltrap ldash lhandler lsig; do
		case "${lsig}" in
		*" "*)
			# Multi-word handler, need to shift it back into
			# lhandler and find the real lsig
			lhandler="${lhandler} ${lsig% *}"
			lsig="${lsig##* }"
			;;
		esac
		case "${lsig}" in
		"${signal}") ;;
		*) continue ;;
		esac
		_trap="${lhandler}"
		trap - "${signal}"
		break
	done <<-EOF
	$(trap)
	EOF

	setvar "${tp_outvar}" "${_trap}"
}

trap_pop() {
	local -; set +x
	[ $# -eq 2 ] || eargs trap_pop signal saved_trap
	local signal="$1"
	local _trap="$2"

	case "${_trap:+set}" in
	set) eval trap -- "${_trap}" "${signal}" || : ;;
	"")
		msg_error "Invalid saved_trap"
		return 1
		;;
	esac
}

# Start a "critical section", disable INT/TERM while in here and delay until
# critical_end is called.
# Unfortunately this can not block signals to our commands. The builtin
# uses sigprocmask(3) which does.
CRITICAL_START_BLOCK_SIGS="INT TERM INFO HUP PIPE"
critical_start() {
	local -; set +x
	local sig saved_trap caught_sig

	_CRITSNEST=$((${_CRITSNEST:-0} + 1))
	if [ ${_CRITSNEST} -gt 1 ]; then
		return 0
	fi

	for sig in ${CRITICAL_START_BLOCK_SIGS}; do
		trap_push "${sig}" saved_trap
		if ! getvar "_crit_caught_${sig}" caught_sig; then
			setvar "_crit_caught_${sig}" 0 || return
		fi
		# shellcheck disable=SC2064
		trap "{ _crit_caught_${sig}=1; } 2>/dev/null" "${sig}"
		hash_set crit_saved_trap "${sig}-${_CRITSNEST}" "${saved_trap}"
	done
}

critical_inherit() {
	case "${_CRITSNEST:-0}" in
	0) return 0 ;;
	esac
	local sig

	for sig in ${CRITICAL_START_BLOCK_SIGS}; do
		trap '' "${sig}"
	done
}

critical_end() {
	local -; set +x
	local sig saved_trap caught_sig oldnest

	[ "${_CRITSNEST:--1}" -ne -1 ] ||
	    err 1 "critical_end called without critical_start"

	oldnest="${_CRITSNEST}"
	_CRITSNEST="$((_CRITSNEST - 1))"
	[ "${_CRITSNEST}" -eq 0 ] || return 0
	for sig in ${CRITICAL_START_BLOCK_SIGS}; do
		if hash_remove crit_saved_trap "${sig}-${oldnest}" saved_trap; then
			trap_pop "${sig}" "${saved_trap}"
		fi
	done
	# Deliver the signals if this was the last critical section block.
	# Send the signal to our real PID, not the rootshell.
	for sig in ${CRITICAL_START_BLOCK_SIGS}; do
		getvar "_crit_caught_${sig}" caught_sig
		case "${caught_sig}.${_CRITSNEST}" in
		"1.0")
			setvar "_crit_caught_${sig}" 0 || return
			raise "${sig}"
			;;
		esac
	done
}
;;
esac

# Read a file into the given variable.
read_file() {
	local -; set +x
	[ $# -eq 2 ] || eargs read_file var_return file
	local rf_outvar="$1"
	local rf_file="$2"
	local rf_ret - IFS

	# rf_outvar may be empty if only $_read_file_lines_read is being
	# used.
	rf_ret=0
	_read_file_lines_read=0

	set +e

	if ! mapfile_builtin && [ "${READ_FILE_USE_CAT:-0}" -eq 1 ]; then
		local rf_data

		case "${rf_file:?}" in
		-|/dev/stdin|/dev/fd/0) ;;
		*)
			if [ ! -r "${rf_file:?}" ]; then
				case "${rf_outvar}" in
				""|-) ;;
				*) unset "${rf_outvar}" ;;
				esac
				return "${EX_NOINPUT:-66}"
			fi
			;;
		esac
		case "${rf_outvar:+set}" in
		set)
			rf_data="$(cat "${rf_file}")" || rf_ret="$?"
			;;
		esac
		case "${rf_ret}" in
		0)
			count_lines "${rf_file}" _read_file_lines_read ||
			    _read_file_lines_read=0
			;;
		esac
		case "${rf_outvar}" in
		"") ;;
		-) echo "${rf_data}" ;;
		*) setvar "${rf_outvar}" "${rf_data}" || return ;;
		esac

		return "${rf_ret}"
	else
		readlines_file "${rf_file}" ${rf_outvar:+"${rf_outvar}"} ||
		    rf_ret="$?"
		_read_file_lines_read="${_readlines_lines_read:?}"
		return "${rf_ret}"
	fi
}

# Read a file until 0 status is found. Partial reads not accepted.
read_line() {
	local -; set +x
	[ $# -eq 2 ] || eargs read_line var_return file
	local rl_var="$1"
	local rl_file="$2"
	local rl_max_reads rl_reads rl_ret rl_line rl_handle IFS

	if [ ! -f "${rl_file}" ]; then
		unset "${rl_var}"
		return "${EX_NOINPUT:-66}"
	fi

	rl_ret=0
	if mapfile_builtin; then
		if mapfile -F rl_handle "${rl_file}"; then
			IFS= mapfile_read "${rl_handle}" "${rl_var}" ||
			    rl_ret="$?"
			mapfile_close "${rl_handle}" || :
		else
			rl_ret="$?"
		fi

		return "${rl_ret}"
	fi

	rl_max_reads=100
	rl_reads=0

	# Read until a full line is returned.
	until [ ${rl_reads} -eq ${rl_max_reads} ] || \
	    IFS= read -t 1 -r rl_line < "${rl_file}"; do
		sleep 0.1
		rl_reads=$((rl_reads + 1))
	done
	if [ "${rl_reads}" -eq "${rl_max_reads}" ]; then
		rl_ret=1
	fi

	setvar "${rl_var}" "${rl_line}" || return

	return "${rl_ret}"
}

readlines() {
	[ "$#" -ge 0 ] || eargs readlines '[-T]' '[vars...]'
	local flag Tflag
	local OPTIND=1

	Tflag=
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "readlines: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 0 ] || eargs readlines '[-T]' '[vars...]'

	readlines_file ${Tflag:+-T} "/dev/stdin" "$@"
}

readlines_file() {
	# Blank vars will still read and output $_readlines_lines_read
	[ "$#" -ge 1 ] || eargs readlines_file '[-T]' file '[-|vars...]'
	local rlf_file
	local rlf_var rlf_line rlf_var_count
	local rlf_rest rlf_nl rlf_handle rlf_ret
	local flag Tflag
	local OPTIND=1 IFS

	Tflag=
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "readlines_file: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 1 ] || eargs readlines_file '[-T]' file '[-|vars...]'
	rlf_file="$1"
	shift

	_readlines_lines_read=0
	case "${rlf_file:?}" in
	-|/dev/stdin|/dev/fd/0) rlf_file="/dev/fd/0" ;;
	*)
		if [ ! -r "${rlf_file:?}" ]; then
			for rlf_var in "$@"; do
				unset "${rlf_var}"
			done
			return "${EX_NOINPUT:-66}"
		fi
		;;
	esac
	rlf_ret=0
	case "$#.${1-}" in
	1.-)
		mapfile_cat_file "${rlf_file:?}" || rlf_ret="$?"
		_readlines_lines_read="${_mapfile_cat_file_lines_read:?}"
		return "${rlf_ret}"
		;;
	esac
	rlf_nl=${RL_NL-$'\n'}
	rlf_var_count="$#"
	unset rlf_rest
	if mapfile -F rlf_handle "${rlf_file:?}" "r"; then
		while IFS= mapfile_read "${rlf_handle}" rlf_line; do
			_readlines_lines_read="$((_readlines_lines_read + 1))"
			case "${Tflag}" in
			1)
				echo "${rlf_line}"
				;;
			esac
			case "${rlf_var_count}" in
			0)
				;;
			1)
				rlf_rest="${rlf_rest:+${rlf_rest}${rlf_nl}}${rlf_line}"
				;;
			*)
				rlf_var_count="$((rlf_var_count - 1))"
				rlf_var="${1?}"
				shift
				case "${rlf_var:+set}" in
				set)
					setvar "${rlf_var}" "${rlf_line}" ||
					    rlf_ret="$?"
					case "${rlf_ret}" in
					0) ;;
					*) break ;;
					esac
					;;
				esac
				;;
			esac
		done
		mapfile_close "${rlf_handle}" || rlf_ret="$?"
	else
		rlf_ret="${EX_NOINPUT:-66}"
	fi
	case "${rlf_var_count}" in
	0) ;;
	*)
		case "${rlf_rest+set}" in
		set)
			rlf_var="${1?}"
			shift
			case "${rlf_var:+set}" in
			set)
				setvar "${rlf_var}" "${rlf_rest}" || return
				;;
			esac
			;;
		esac
		for rlf_var in "$@"; do
			unset "${rlf_var}"
		done
		;;
	esac
	return "${rlf_ret}"
}

readarray() {
	local -; set +x
	[ "$#" -eq 1 ] || eargs readarray array_var

	readarray_file "/dev/fd/0" "$@"
}

readarray_file() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs readarray_file file array_var
	local raf_file="$1"
	local raf_array_var="$2"
	local raf_line
	local IFS

	while IFS= mapfile_read_loop "${raf_file}" raf_line; do
		array_push_back "${raf_array_var}" "${raf_line}"
	done
}

# SIGINFO traps won't abort the read.
read_blocking() {
	local -; set +x
	[ $# -ge 1 ] || eargs read_blocking read_args
	local rb_ret
	local OPTIND=1 flag tflag timeout time_start now

	tflag=
	while getopts "t:" flag; do
		case "${flag}" in
		t) tflag="${OPTARG:?}" ;;
		*) err 1 "read_blocking: Invalid flag ${flag}" ;;
		esac
	done
	shift "$((OPTIND-1))"
	case "${tflag}" in
	"") ;;
	*.*) timeout="${tflag}" ;;
	*) time_start="$(clock -monotonic)" ;;
	esac
	while :; do
		rb_ret=0
		# Adjust timeout
		case "${tflag}" in
		""|*.*) ;;
		*)
			now="$(clock -monotonic)"
			timeout="$((tflag - (now - time_start)))"
			case "${timeout}" in
			"-"*) timeout=0 ;;
			esac
			;;
		esac
		set -o noglob
		# shellcheck disable=SC2086
		read -r ${tflag:+-t "${timeout}"} "$@" || rb_ret="$?"
		set +o noglob
		case ${rb_ret} in
			# Read again on SIGINFO interrupts
			157) continue ;;
			# Valid EOF
			1) break ;;
			# Success
			0) break ;;
			# Unknown problem or signal, just return the error.
			*) break ;;
		esac
	done
	return "${rb_ret}"
}

# Same as read_blocking() but it reads an entire raw line.
# Needed because 'IFS= read_blocking' doesn't reset IFS like the normal read
# builtin does.
read_blocking_line() {
	local -; set +x
	[ $# -ge 1 ] || eargs read_blocking_line read_args
	local rbl_ret IFS
	local OPTIND=1 flag tflag timeout time_start now

	tflag=
	while getopts "t:" flag; do
		case "${flag}" in
		t) tflag="${OPTARG:?}" ;;
		*) err 1 "read_blocking_line: Invalid flag ${flag}" ;;
		esac
	done
	shift "$((OPTIND-1))"
	case "${tflag}" in
	"") ;;
	*.*) timeout="${tflag}" ;;
	*) time_start="$(clock -monotonic)" ;;
	esac
	while :; do
		rbl_ret=0
		# Adjust timeout
		case "${tflag}" in
		""|*.*) ;;
		*)
			now="$(clock -monotonic)"
			timeout="$((tflag - (now - time_start)))"
			case "${timeout}" in
			"-"*) timeout=0 ;;
			esac
			;;
		esac
		set -o noglob
		# shellcheck disable=SC2086
		IFS= read -r ${tflag:+-t "${timeout}"} "$@" || rbl_ret="$?"
		set +o noglob
		case "${rbl_ret}" in
			# Read again on SIGINFO interrupts
			157) continue ;;
			# Valid EOF
			1) break ;;
			# Success
			0) break ;;
			# Unknown problem or signal, just return the error.
			*) break ;;
		esac
	done
	return "${rbl_ret}"
}

# SIGINFO traps won't abort the read, and if the pipe goes away or
# turns into a file then an error is returned.
read_pipe() {
	local -; set +x
	[ $# -ge 2 ] || eargs read_pipe fifo read_args
	local fifo="$1"
	local rp_ret resread resopen
	local OPTIND=1 flag tflag timeout time_start now
	shift

	rp_ret=0
	tflag=
	while getopts "t:" flag; do
		case "${flag}" in
		t) tflag="${OPTARG:?}" ;;
		*) err 1 "read_pipe: Invalid flag ${flag}" ;;
		esac
	done
	shift "$((OPTIND-1))"
	case "${tflag}" in
	"") ;;
	*.*) timeout="${tflag}" ;;
	*) time_start="$(clock -monotonic)" ;;
	esac
	while :; do
		if ! [ -p "${fifo}" ]; then
			rp_ret=32
			break
		fi
		# Separately handle open(2) and read(builtin) errors
		# since opening the pipe blocks and may be interrupted.
		resread=0
		resopen=0
		# Adjust timeout
		case "${tflag}" in
		""|*.*) ;;
		*)
			now="$(clock -monotonic)"
			timeout="$((tflag - (now - time_start)))"
			case "${timeout}" in
			"-"*) timeout=0 ;;
			esac
			;;
		esac
		set -o noglob
		# shellcheck disable=SC2086
		{ { read -r ${tflag:+-t "${timeout}"} "$@" || resread=$?; } \
		    < "${fifo}" || resopen=$?; } \
		    2>/dev/null
		set +o noglob
		msg_dev "read_pipe ${fifo}: resread=${resread} resopen=${resopen}"
		# First check the open errors
		case ${resopen} in
			# Open error.  We do a test -p in every iteration,
			# so it was either a race or an interrupt.  Retry
			# in case it was just an interrupt.
			2) continue ;;
			# Success
			0) ;;
			# Unknown problem or signal, just return the error.
			*) rp_ret="${resopen}"; break ;;
		esac
		case ${resread} in
			# Read again on SIGINFO interrupts
			157) continue ;;
			# Valid EOF
			1) rp_ret="${resread}"; break ;;
			# Success
			0) break ;;
			# Unknown problem or signal, just return the error.
			*) rp_ret="${resread}"; break ;;
		esac
	done
	return "${rp_ret}"
}

# Ignore EOF
read_pipe_noeof() {
	local -; set +x
	[ $# -ge 2 ] || eargs read_pipe_noeof fifo read_args
	local fifo="$1"
	local rpn_ret
	shift
	local OPTIND=1 flag tflag timeout time_start now

	tflag=
	while getopts "t:" flag; do
		case "${flag}" in
		t) tflag="${OPTARG:?}" ;;
		*) err 1 "read_pipe_noeof: Invalid flag ${flag}" ;;
		esac
	done
	shift "$((OPTIND-1))"
	case "${tflag}" in
	"") ;;
	*.*) timeout="${tflag}" ;;
	*) time_start="$(clock -monotonic)" ;;
	esac
	while :; do
		rpn_ret=0
		# Adjust timeout
		case "${tflag}" in
		""|*.*) ;;
		*)
			now="$(clock -monotonic)"
			timeout="$((tflag - (now - time_start)))"
			case "${timeout}" in
			"-"*) timeout=0 ;;
			esac
			;;
		esac
		set -o noglob
		# shellcheck disable=SC2086
		read_pipe "${fifo}" ${tflag:+-t "${timeout}"} "$@" || rpn_ret="$?"
		set +o noglob
		case "${rpn_ret}" in
		1) ;;
		*) break ;;
		esac
	done
	return "${rpn_ret}"
}

# This is avoiding EINTR errors when writing to a pipe due to SIGINFO traps
write_pipe() {
	local -; set +x
	[ "$#" -ge 1 ] || eargs write_pipe fifo '[write_args]'
	local fifo="$1"
	local ret
	# shellcheck disable=SC2034
	local tmp
	shift

	# If this is not a pipe then return an error immediately
	if ! [ -p "${fifo}" ]; then
		msg_dev "write_pipe FAILED to send to ${fifo} (NOT A PIPE? ret=2):" "$@"
		return 2
	fi

	ret=0
	msg_dev "write_pipe ${fifo}:" "$@"
	unset tmp
	while trap_ignore_block tmp INFO; do
		# shellcheck disable=SC2320
		echo "$@" > "${fifo}" || ret=$?
	done

	if [ "${ret}" -ne 0 ]; then
		msg_warn "write_pipe FAILED to send to ${fifo} (ret: ${ret}):" "$@"
	fi

	return "${ret}"
}

_pipe_hold_exit() {
	rm -f "${PIPE_HOLD_SYNC_FIFO:?}"
}

_pipe_hold_child() {
	[ $# -ge 3 ] || eargs _pipe_hold_child sync_fifo watch_pid fifos...
	local sync_fifo="$1"
	local watch_pid="$2"
	shift 2
	local -; set +x
	local ret

	PIPE_HOLD_SYNC_FIFO="${sync_fifo}"
	setup_traps _pipe_hold_exit
	setproctitle "pipe_hold($*)"
	exec 3> "${sync_fifo}"
	case "$#" in
	6) exec 9<> "$6" ;;
	5) exec 8<> "$5" ;;
	4) exec 7<> "$4" ;;
	3) exec 6<> "$3" ;;
	2) exec 5<> "$2" ;;
	1) exec 4<> "$1" ;;
	esac || err "$?" "_pipe_hold_child: exec"
	# Alert parent we're ready
	# shellcheck disable=SC2320
	echo ready >&3 || err "$?" "pwrite"
	exec pwait "${watch_pid}" 3<&- 2>/dev/null || err "$?" "pwait"
}

# This keeps the given fifos open to avoid EOF in writers.
# If the watch_pid exits then the holder will exit automatically.
# Use watch_pid==1 to keep the pipe open until explicitly killing the holder.
pipe_hold() {
	[ $# -ge 3 ] || eargs pipe_hold var_return_jobid watch_pid fifos...
	local var_return_jobid="$1"
	local ph_pid="$2"
	shift 2
	local spawn_jobid ph_fifo ph_sync ph_ret

	ph_ret=0
	ph_sync=
	ph_fifo=$(mktemp -ut pipe_hold)
	mkfifo "${ph_fifo}"

	unset spawn_jobid
	spawn_job_protected _pipe_hold_child "${ph_fifo}" "${ph_pid}" "$@"
	setvar "${var_return_jobid}" "${spawn_jobid}" || ph_ret="$?"
	read_pipe "${ph_fifo}" ph_sync || ph_ret="$?"
	case "${ph_sync}" in
	ready) ;;
	*) err 1 "pipe_hold failure" ;;
	esac
	unlink "${ph_fifo}"
	return "${ph_ret}"
}

case "$(type mapfile 2>/dev/null)" in
"mapfile is a shell builtin")
mapfile_builtin() {
	return 0
}

mapfile_keeps_file_open_on_eof() {
	[ $# -eq 1 ] || eargs mapfile_keeps_file_open_on_eof handle
	return 0
}

mapfile_supports_multiple_read_handles() {
	return 0
}

# Wrap builtin mapfile_close() to handle mapfile_read_proc() cleanup needs.
mapfile_close() {
	[ "$#" -eq 1 ] || eargs mapfile_close handle
	local handle="$1"
	local ret

	ret=0
	command mapfile_close "${handle}" || ret="$?"
	_mapfile_read_proc_close "${handle}" || ret="$?"
	return "${ret}"
}
;;
*)
mapfile() {
	local -; set +x
	[ "$#" -ge 2 ] || eargs mapfile '[-q'] handle_name file modes
	local OPTIND=1 qflag flag

	qflag=0
	while getopts "Fq" flag; do
		case "${flag}" in
		q) qflag=1 ;;
		F)
			# builtin compat
			;;
		*) err 1 "mapfile: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))

	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs mapfile handle_name file modes
	local handle_name="$1"
	local _file="$2"
	local _modes="$3"
	local mypid _hkey ret

	ret=0
	mypid=$(getpid)
	case "${_file}" in
	-) _file="/dev/fd/0" ;;
	esac
	_hkey="${_file}.${mypid}"

	case " ${_modes} " in
	*r*w*|*w*r*|*+*) ;;
	*w*|*a*) ;;
	*r*)
		if [ ! -e "${_file}" ]; then
			case "${qflag}" in
			0)
				msg_error "mapfile: ${_file}: No such file or directory"
				;;
			esac
			return "${EX_NOINPUT:-66}"
		fi
		;;
	esac

	case "${_MAPFILE_HANDLE-}" in
	""|"${_hkey}") ;;
	*)
		# New file or new process
		case "${_MAPFILE_HANDLE##*.}" in
		"${mypid}")
			# Same process so far...
			case "${_MAPFILE_HANDLE%.*}" in
			"${_file}")
				err 1 "mapfile: earlier case _hkey should cover this"
				;;
			*)
				case "${_file}" in
				/dev/fd/[0-9]) ;;
				*)
					case " ${_modes} " in
					*r*w*|*w*r*|*+*|*r*)
						if mapfile_supports_multiple_read_handles; then
							err "${EX_SOFTWARE}" "mapfile() needs updated for multiple read handle support"
						fi
						err "${EX_SOFTWARE}" "mapfile only supports 1 reader at a time without builtin. ${_MAPFILE_HANDLE} already open: tried to open ${_file}"
						;;
					esac
					;;
				esac
				;;
			esac
			;;
		*)
			# Different process. Nuke the tracker.
			unset _MAPFILE_HANDLE
			;;
		esac
	esac
	setvar "${handle_name}" "${_hkey}" || ret="$?"
	case "${_file}" in
	-|/dev/stdin|/dev/fd/0)
		case "${_modes}" in
		*r*|*+*)
			hash_set mapfile_fd "${_hkey}" "0"
			;;
		*)
			err 1 "mapfile: Invalid operation on stdin"
			;;
		esac
		;;
	/dev/stdout|/dev/fd/1)
		case "${_modes}" in
		*w*|*a*)
			hash_set mapfile_fd "${_hkey}" "1"
			;;
		*)
			err 1 "mapfile: Invalid operation on stdout"
			;;
		esac
		;;
	/dev/stderr|/dev/fd/2)
		case "${_modes}" in
		*w*|*a*)
			hash_set mapfile_fd "${_hkey}" "2"
			;;
		*)
			err 1 "mapfile: Invalid operation on stderr"
			;;
		esac
		;;
	/dev/fd/[0-9])
		hash_set mapfile_fd "${_hkey}" "${_file#/dev/fd/}"
		;;
	*)
		case "${_modes}" in
		*r*|*+*)
			: "${_MAPFILE_HANDLE:="${_hkey}"}"
			;;
		*w*|*a*) ;;
		esac
		case "${_MAPFILE_HANDLE-}" in
		"${_hkey}")
			case " ${_modes} " in
			*r*w*|*w*r*|*+*)
				exec 7<> "${_file}" || ret="$?"
				;;
			*r*)
				exec 7< "${_file}" || ret="$?"
				;;
			*w*|*a*)
				exec 7> "${_file}" || ret="$?"
				;;
			esac
			hash_set mapfile_fd "${_hkey}" "7"
			;;
		*)
			case "${_modes}" in
			*a*) :>> "${_file}" ;;
			*w*) :> "${_file}" ;;
			esac
			;;
		esac
		;;
	esac
	hash_set mapfile_file "${_hkey}" "${_file}"
	hash_set mapfile_modes "${_hkey}" "${_modes}"
	return "${ret}"
}

mapfile_read() {
	local -; set +x -u
	[ $# -ge 2 ] || eargs mapfile_read handle output_var ...
	local mapfile_read_handle="$1"
	shift
	local mapfile_read_fd mapfile_read_modes

	if ! hash_get mapfile_fd "${mapfile_read_handle}" mapfile_read_fd; then
		err "${EX_SOFTWARE}" "mapfile_read: ${mapfile_read_handle} is not open"
	fi
	hash_get mapfile_modes "${mapfile_read_handle}" mapfile_read_modes
	case "${mapfile_read_modes}" in
	*r*|*+*) ;;
	*)
		err "${EX_SOFTWARE}" "mapfile_read: ${mapfile_read_handle} is not open for reading, modes=${mapfile_read_modes}"
		;;
	esac

	read_blocking "$@" <&"${mapfile_read_fd}"
}

mapfile_write() {
	local -; set +x -u
	[ $# -ge 1 ] || eargs mapfile_write handle '[-nT]' '[data]'
	local handle="$1"
	shift
	local ret handle fd nflag Tflag flag OPTIND=1 file

	ret=0
	nflag=
	Tflag=
	while getopts "nT" flag; do
		case "${flag}" in
		n) nflag=1 ;;
		T) Tflag=1 ;;
		*) err "${EX_USAGE}" "mapfile_write: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -ge 0 ] || eargs mapfile_write handle '[-nT]' '[data]'

	if [ "$#" -eq 0 ]; then
		local data

		read_file data - || ret="$?"
		if [ "${ret}" -ne 0 ]; then
			return "${ret}"
		fi
		case "${data-}-${_read_file_lines_read}" in
		# Nothing to write. An alternative here is nflag=1 ;;
		"-0") return 0 ;;
		esac
		mapfile_write "${handle}" ${nflag:+-n} ${Tflag:+-T} -- \
		    "${data}" || ret="$?"
		return "${ret}"
	fi

	if [ "${Tflag:-0}" -eq 1 ]; then
		echo ${nflag:+-n} "$@"
	fi
	if hash_get mapfile_fd "${handle}" fd; then
		echo ${nflag:+-n} "$@" >&"${fd}"
		return
	fi

	hash_get mapfile_file "${handle}" file ||
	    err "${EX_SOFTWARE}" "mapfile_write: Failed to find file for ${handle}"
	echo ${nflag:+-n} "$@" >> "${file}"
}

mapfile_close() {
	local -; set +x
	[ $# -eq 1 ] || eargs mapfile_close handle
	local handle="$1"
	local fd

	# Only close fd that we opened.
	if hash_remove mapfile_fd "${handle}" fd; then
		case "${fd}" in
		7)
			exec 7>&-
			case "${handle}" in
			"${_MAPFILE_HANDLE-}")
				unset _MAPFILE_HANDLE
				;;
			esac
			;;
		esac
	fi
	hash_unset mapfile_file "${handle}"
	hash_unset mapfile_modes "${handle}"
	_mapfile_read_proc_close "${handle}"
}

# This is for reading from a file in a loop while avoiding a pipe.
# It is analogous to read(builtin).For example these are mostly equivalent:
# cat $file | while read -r col1 rest; do echo "$col1 $rest"; done
# while mapfile_read_loop $file col1 rest; do echo "$col1 $rest"; done
mapfile_read_loop() {
	local -; set +x
	[ $# -ge 2 ] || eargs mapfile_read_loop file vars
	local mrl_file="$1"
	shift
	local mrl_hkey mrl_handle mrl_ret

	case "${mrl_file}" in
	-|/dev/stdin|/dev/fd/0)
		mrl_ret=0
		read_blocking "$@" || mrl_ret="$?"
		return "${mrl_ret}"
		;;
	esac

	# Store the handle based on the params passed in since it is
	# using an anonymous handle on stdin - which if nested in a
	# pipe would reuse the already-opened handle from the parent
	# pipe.
	mrl_hkey="${mrl_file}.$*"

	if ! hash_get mapfile_handle "${mrl_hkey}" mrl_handle; then
		# shellcheck disable=SC2034
		mapfile mrl_handle "${mrl_file}" "re" || return "$?"
		hash_set mapfile_handle "${mrl_hkey}" "${mrl_handle}"
	fi

	if mapfile_read "${mrl_handle}" "$@"; then
		return 0
	else
		mrl_ret="$?"
		mapfile_close "${mrl_handle}" || mrl_ret="$?"
		hash_unset mapfile_handle "${mrl_hkey}"
		return "${mrl_ret}"
	fi
}

# Pipe to STDOUT from handle.
mapfile_cat() {
	[ $# -ge 1 ] || eargs mapfile_cat '[-T fd]' handle...
	local OPTIND=1 Tflag flag ret

	_mapfile_cat_lines_read=0
	Tflag=
	while getopts "T:" flag; do
		case "${flag}" in
		T) Tflag="${OPTARG:?}" ;;
		*) err 1 "mapfile_cat: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -ge 1 ] || eargs mapfile_cat '[-T fd]' handle...
	local IFS handle line

	ret=0
	for handle in "$@"; do
		while IFS= mapfile_read "${handle}" line; do
			_mapfile_cat_lines_read="$((_mapfile_cat_lines_read + 1))"
			# shellcheck disable=SC2320
			echo "${line}" || ret=$?
			case "${Tflag}" in
			"") ;;
			*)
				# shellcheck disable=SC2320
				echo "${line}" > "/dev/fd/${Tflag}" || ret=$?
			;;
			esac
		done
	done
	return "${ret}"
}

# Pipe to STDOUT from a file.
# Basically an optimized loop of mapfile_read_loop_redir, or read_file
mapfile_cat_file() {
	local -; set +x
	[ $# -ge 0 ] || eargs mapfile_cat_file '[-q] [-T fd]' file...
	local  _handle ret _file
	local OPTIND=1 Tflag qflag flag

	_mapfile_cat_file_lines_read=0
	qflag=
	Tflag=
	while getopts "qT:" flag; do
		case "${flag}" in
		q) qflag=1 ;;
		T) Tflag="${OPTARG:?}" ;;
		*) err 1 "mapfile_cat_file: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))

	if [ $# -eq 0 ]; then
		# Read from stdin
		set -- "-"
	fi
	ret=0
	for _file in "$@"; do
		case "${_file}" in
		-) _file="/dev/fd/0" ;;
		esac
		# shellcheck disable=SC2034
		if mapfile ${qflag:+-q} -F _handle "${_file}" "r"; then
			mapfile_cat ${Tflag:+-T "${Tflag}"} "${_handle}" ||
			    ret="$?"
			mapfile_close "${_handle}" || ret="$?"
			_mapfile_cat_file_lines_read="${_mapfile_cat_lines_read:?}"
		else
			ret="$?"
		fi
	done
	return "${ret}"
}

mapfile_builtin() {
	return 1
}

mapfile_keeps_file_open_on_eof() {
	[ $# -eq 1 ] || eargs mapfile_keeps_file_open_on_eof handle
	return 1
}

mapfile_supports_multiple_read_handles() {
	return 1
}
;;
esac

# Alias for mapfile_read_loop "/dev/stdin" vars...
mapfile_read_loop_redir() {
	mapfile_read_loop "/dev/stdin" "$@"
}

# Helper to workaround lack of process substitution.
mapfile_read_proc() {
	[ "$#" -ge 1 ] || eargs mapfile_read_proc handle_name cmd...
	local _mapfile_read_proc_handle="$1"
	shift 1
	local spawn_jobid ret tmp _real_handle

	tmp="$(mktemp -ut mapfile_read_proc_fifo)"
	mkfifo "${tmp}" || return
	spawn_job _pipe_func_job "${tmp}" "$@"
	# shellcheck disable=SC2034
	if mapfile "${_mapfile_read_proc_handle}" "${tmp}" "re"; then
		getvar "${_mapfile_read_proc_handle}" _real_handle
		hash_set mapfile_read_proc_job "${_real_handle}" "${spawn_jobid}"
	else
		kill_job 1 "%${spawn_jobid}" || ret="$?"
	fi
	return "${ret}"
}

_mapfile_read_proc_close() {
	[ "$#" -eq 1 ] || eargs _mapfile_read_proc_close handle
	local handle="$1"
	local job ret

	ret=0
	if hash_remove mapfile_read_proc_job "${handle}" job; then
		kill_job 1 "%${job}" || ret="$?"
	fi
	return "${ret}"
}

_pipe_func_job() {
	[ "$#" -gt 2 ] || eargs _pipe_func_job _mf_fifo function '[args...]'
	local _mf_fifo="$1"
	shift 1

	setproctitle "pipe_func($1)"
	#exec < /dev/null
	exec > "${_mf_fifo}"
	unlink "${_mf_fifo}"
	"$@"
}

# Read output from a given function asynchronously. Like a read-only coprocess.
# This is to allow piping from the function, in the current process, without
# needing to wait for its entire response like a heredoc for x in $(func) loop
# would.
# Note that due to the kernel pipe write buffer the child will not block
# between every read from the child.
pipe_func() {
	[ "$#" -ge 4 ] ||
	    eargs pipe_func '[-H handle_var]' 'read' read-params '[...]' \
	    -- func '[params]'
	local _mf_handle_var _mf_cookie_val
	local _mf_key _mf_read_params _mf_handle _mf_ret _mf_var
	local _mf_fifo _mf_job spawn_jobid
	local OPTIND=1 flag Hflag
	local -

	Hflag=0
	while getopts "H:" flag; do
		case "${flag}" in
		H)
			Hflag=1
			_mf_handle_var="${OPTARG}"
			;;
		*) err "${EX_USAGE}" "pipe_func: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))

	if [ "${Hflag}" -eq 0 ]; then
		_mf_key="$*"
	else
		if ! getvar "${_mf_handle_var}" _mf_cookie_val; then
			randint 1000000000 _mf_cookie_val
			setvar "${_mf_handle_var}" "${_mf_cookie_val}" ||
			    return
		else
			if [ "${_mf_cookie_val}" -eq "${_mf_cookie_val}" ]; then
				:
			else
				err "${EX_USAGE}" "pipe_func: Invalid cookie var: ${_mf_handle_var}='${_mf_cookie_val}'; should be unset"
			fi
		fi
		_mf_key="${_mf_cookie_val}"
	fi
	# 'read' is used to make the usage more clear.
	case "$1" in
	read) shift ;;
	*) err "${EX_USAGE}" "pipe_func: Missing 'read'" ;;
	esac
	_mf_ret=0
	if hash_get pipe_func_handle "${_mf_key}" _mf_handle; then
		hash_get pipe_func_read_params "${_mf_key}" _mf_read_params ||
		    err "${EX_SOFTWARE}" "pipe_func: No stored read params for ${_mf_key}"
	else
		_mf_read_params=
		while :; do
			_mf_var="$1"
			shift
			case "${_mf_var}" in
			"--")
				break
				;;
			*)
				_mf_read_params="${_mf_read_params:+${_mf_read_params} }${_mf_var}"
				;;
			esac
		done
		# "$@" is now the function and params
		hash_set pipe_func_read_params "${_mf_key}" "${_mf_read_params}"
		_mf_fifo="$(mktemp -ut pipe_func.fifo)"
		mkfifo "${_mf_fifo}"
		hash_set pipe_func_fifo "${_mf_key}" "${_mf_fifo}"
		spawn_job _pipe_func_job "${_mf_fifo}" "$@"
		hash_set pipe_func_job "${_mf_key}" "${spawn_jobid}"
		mapfile _mf_handle "${_mf_fifo}" "re" ||
		    err "${EX_SOFTWARE}" "pipe_func: Failed to open ${_mf_fifo}"
		hash_set pipe_func_handle "${_mf_key}" "${_mf_handle}"
	fi

	# Read from fifo back to caller
	set -o noglob
	# shellcheck disable=SC2086
	mapfile_read "${_mf_handle}" ${_mf_read_params} || _mf_ret="$?"
	set +o noglob
	case "${_mf_ret}" in
	0)
		return
		;;
	esac
	# EOF
	mapfile_close "${_mf_handle}" || _mf_ret="$?"
	hash_unset pipe_func_read_params "${_mf_key}"
	hash_unset pipe_func_handle "${_mf_key}"
	hash_unset pipe_func_shift "${_mf_key}"
	hash_remove pipe_func_fifo  "${_mf_key}" _mf_fifo ||
	    err "${EX_SOFTWARE}" "pipe_func: No stored fifo for ${_mf_key}"
	unlink "${_mf_fifo}"
	hash_remove pipe_func_job  "${_mf_key}" _mf_job ||
	    err "${EX_SOFTWARE}" "pipe_func: No stored job for ${_mf_key}"
	kill_job 1 "%${_mf_job}" || _mf_ret="$?"
	unset "${_mf_handle_var}"
	return "${_mf_ret}"
}

# Create a new temporary file and return a handle to it
mapfile_mktemp() {
	local -; set +x
	[ $# -ge 2 ] || eargs mapfile_mktemp handle_var_return \
	    tmpfile_var_return "mktemp(1)-params"
	local handle_var_return="$1"
	local tmpfile_var_return="$2"
	shift 2
	local mm_tmpfile ret

	ret=0
	_mktemp mm_tmpfile "$@" || ret="$?"
	if [ "${ret}" -ne 0 ]; then
		setvar "${handle_var_return}" "" || return
		setvar "${tmpfile_var_return}" "" || return
		return "${ret}"
	fi
	ret=0
	# shellcheck disable=SC2034
	mapfile "${handle_var_return}" "${mm_tmpfile}" "we" || ret="$?"
	if [ "${ret}" -ne 0 ]; then
		setvar "${handle_var_return}" "" || return
		setvar "${tmpfile_var_return}" "" || return
		return "${ret}"
	fi
	setvar "${tmpfile_var_return}" "${mm_tmpfile}"
}

noclobber() {
	local -
	set -C

	"$@"
}

# Ignore SIGPIPE
nopipe() {
	local opipe nopipe_ret

	trap_push PIPE opipe
	trap '' PIPE
	nopipe_ret=0
	"$@" || nopipe_ret=$?
	trap_pop PIPE "${opipe}"

	return "${nopipe_ret}"
}

# Detect if pipefail support is available in the shell.  The shell
# will just exit if we try 'set -o pipefail' and it doesn't support it.
have_pipefail() {
	case $(set -o) in
	*pipefail*)
		return 0
		;;
	esac
	return 1
}

set_pipefail() {
	command set -o pipefail 2>/dev/null || :
}

prefix_stderr_quick() {
	local flags="$-" -; set +x
	local extra="$1"
	local MSG_NESTED_STDERR prefix
	shift 1

	set_pipefail

	{
		{
			# shellcheck disable=SC2034
			MSG_NESTED_STDERR=1
			case "${flags}" in
			*x*) set -x ;;
			esac
			"$@"
		} 2>&1 1>&3 | {
			if [ "${USE_TIMESTAMP:-1}" -eq 1 ] && \
			    command -v timestamp >/dev/null && \
			    [ "$(type timestamp)" = \
			    "timestamp is a shell builtin" ]; then
				# Let timestamp handle showing the proper time.
				prefix="$(NO_ELAPSED_IN_MSG=1 msg_warn "${extra}:" 2>&1)"
				TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
				    timestamp -1 "${prefix}" \
				    -P "poudriere: ${PROC_TITLE} (prefix_stderr_quick)" \
				    >&2
			else
				setproctitle "${PROC_TITLE} (prefix_stderr_quick)"
				while mapfile_read_loop_redir line; do
					msg_warn "${extra}: ${line}"
				done
			fi
		}
	} 3>&1
}

prefix_stderr() {
	local extra="$1"
	shift 1
	local prefixpipe prefix_job prefixpid ret
	local prefix MSG_NESTED_STDERR
	local - errexit

	prefixpipe=$(mktemp -ut prefix_stderr.pipe)
	mkfifo "${prefixpipe}"
	set -m
	(
		_spawn_wrapper :

		if [ "${USE_TIMESTAMP:-1}" -eq 1 ] && \
		    command -v timestamp >/dev/null; then
			# Let timestamp handle showing the proper time.
			prefix="$(NO_ELAPSED_IN_MSG=1 msg_warn "${extra}:" 2>&1)"
			TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
			    timestamp -1 "${prefix}" \
			    -P "poudriere: ${PROC_TITLE} (prefix_stderr)" \
			    >&2
		else
			set +x
			setproctitle "${PROC_TITLE} (prefix_stderr)"
			while mapfile_read_loop_redir line; do
				msg_warn "${extra}: ${line}"
			done
		fi
	) < "${prefixpipe}" &
	set +m
	prefixpid="$!"
	get_job_id "${prefixpid}" prefix_job
	exec 4>&2
	exec 2> "${prefixpipe}"
	unlink "${prefixpipe}"

	# shellcheck disable=SC2034
	MSG_NESTED_STDERR=1
	ret=0
	case $- in *e*) errexit=1; set +e ;; *) errexit=0 ;; esac
	"$@"
	ret=$?
	if [ "${errexit}" -eq 1 ]; then
		set -e
	fi

	exec 2>&4 4>&-
	timed_wait_and_kill_job 5 "%${prefix_job}" || :

	return ${ret}
}

prefix_stdout() {
	local extra="$1"
	shift 1
	local prefixpipe prefix_job prefixpid ret
	local prefix MSG_NESTED
	local - errexit

	prefixpipe=$(mktemp -ut prefix_stdout.pipe)
	mkfifo "${prefixpipe}"
	set -m
	(
		_spawn_wrapper :
		if [ "${USE_TIMESTAMP:-1}" -eq 1 ] && \
		    command -v timestamp >/dev/null; then
			# Let timestamp handle showing the proper time.
			prefix="$(NO_ELAPSED_IN_MSG=1 msg "${extra}:")"
			TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
			    timestamp -1 "${prefix}" \
			    -P "poudriere: ${PROC_TITLE} (prefix_stdout)"
		else
			set +x
			setproctitle "${PROC_TITLE} (prefix_stdout)"
			while mapfile_read_loop_redir line; do
				msg "${extra}: ${line}"
			done
		fi
	) < "${prefixpipe}" &
	set +m
	prefixpid="$!"
	get_job_id "${prefixpid}" prefix_job
	exec 3>&1
	exec > "${prefixpipe}"
	unlink "${prefixpipe}"

	# shellcheck disable=SC2034
	MSG_NESTED=1
	ret=0
	case $- in *e*) errexit=1; set +e ;; *) errexit=0 ;; esac
	"$@"
	ret=$?
	if [ "${errexit}" -eq 1 ]; then
		set -e
	fi

	exec 1>&3 3>&-
	timed_wait_and_kill_job 5 "%${prefix_job}" || :

	return ${ret}
}

prefix_output() {
	local extra="$1"
	local prefix_stdout prefix_stderr prefixpipe_stdout prefixpipe_stderr
	local ret MSG_NESTED MSG_NESTED_STDERR prefix_job
	local - errexit
	shift 1

	if [ "${USE_TIMESTAMP:-1}" -eq 0 ] || \
	    ! command -v timestamp >/dev/null; then
		prefix_stderr "${extra}" prefix_stdout "${extra}" "$@"
		return
	fi
	# Use timestamp's multiple file input feature.
	# Let timestamp handle showing the proper time.

	prefixpipe_stdout=$(mktemp -ut prefix_stdout.pipe)
	mkfifo "${prefixpipe_stdout}"
	prefix_stdout="$(NO_ELAPSED_IN_MSG=1 msg "${extra}:")"

	prefixpipe_stderr=$(mktemp -ut prefix_stderr.pipe)
	mkfifo "${prefixpipe_stderr}"
	prefix_stderr="$(NO_ELAPSED_IN_MSG=1 msg_warn "${extra}:" 2>&1)"

	TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
	    spawn_job \
	    timestamp \
	    -1 "${prefix_stdout}" -o "${prefixpipe_stdout}" \
	    -2 "${prefix_stderr}" -e "${prefixpipe_stderr}" \
	    -P "poudriere: ${PROC_TITLE} (prefix_output)"
	prefix_job="${spawn_jobid}"
	exec 3>&1
	exec > "${prefixpipe_stdout}"
	unlink "${prefixpipe_stdout}"
	exec 4>&2
	exec 2> "${prefixpipe_stderr}"
	unlink "${prefixpipe_stderr}"

	# shellcheck disable=SC2034
	MSG_NESTED=1
	# shellcheck disable=SC2034
	MSG_NESTED_STDERR=1
	ret=0
	case $- in *e*) errexit=1; set +e ;; *) errexit=0 ;; esac
	"$@"
	ret=$?
	if [ "${errexit}" -eq 1 ]; then
		set -e
	fi

	exec 1>&3 3>&- 2>&4 4>&-
	timed_wait_and_kill_job 5 "%${prefix_job}" || :

	return ${ret}
}

timespecsub() {
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs timespecsub now 'then' '[var_return]'
	local now_timespec="$1"
	local then_timespec="$2"
	local _var_return="$3"
	local now_sec now_nsec then_sec then_nsec res_sec res_nsec

	case ${now_timespec} in
	*.*)
		now_sec="${now_timespec%.*}"
		now_nsec="${now_timespec#*.}"
		while :; do
			case "${now_nsec}" in
			0*) now_nsec="${now_nsec#0}" ;;
			*) break ;;
			esac
		done
		;;
	*)
		now_sec="${now_timespec}"
		now_nsec="0"
		;;
	esac
	case ${then_timespec} in
	*.*)
		then_sec="${then_timespec%.*}"
		then_nsec="${then_timespec#*.}"
		while :; do
			case "${then_nsec}" in
			0*) then_nsec="${then_nsec#0}" ;;
			*) break ;;
			esac
		done
		;;
	*)
		then_sec="${then_timespec}"
		then_nsec="0"
		;;
	esac

	res_sec="$((now_sec - then_sec))"
	res_nsec="$((now_nsec - then_nsec))"
	if [ "${res_nsec}" -lt 0 ]; then
		res_sec="$((res_sec - 1))"
		res_nsec="$((res_nsec + 1000000000))"
	fi

	case "${_var_return}" in
	""|-)
		echo "${res_sec}.${res_nsec}"
		;;
	*)
		setvar "${_var_return}" "${res_sec}.${res_nsec}" || return
		;;
	esac
}

calculate_duration() {
	[ $# -eq 2 ] || eargs calculate_duration var_return elapsed
	local cd_outvar="$1"
	local _elapsed="$2"
	local seconds minutes hours days _duration

	days="$((_elapsed / 86400))"
	_elapsed="$((_elapsed % 86400))"
	hours="$((_elapsed / 3600))"
	_elapsed="$((_elapsed % 3600))"
	minutes="$((_elapsed / 60))"
	_elapsed="$((_elapsed % 60))"
	seconds="${_elapsed}"

	_duration=
	if [ "${days}" -gt 0 ]; then
		_duration=$(printf "%s%dD:" "${_duration}" "${days}")
	fi
	_duration=$(printf "%s%02d:%02d:%02d" "${_duration}" \
	    "${hours}" "${minutes}" "${seconds}")

	setvar "${cd_outvar}" "${_duration}"
}

_write_atomic() {
	local -; set +x
	[ $# -eq 3 ] || [ $# -ge 4 ] ||
	    eargs _write_atomic cmp tee destfile '< data | data'
	local cmp="$1"
	local tee="$2"
	local dest="$3"
	local data
	local tmpfile_handle tmpfile ret tmpdir Tflag

	shift 3
	unset data
	case "$#" in
	0) ;;
	*) data=1 ;;
	esac
	case "$-${tee-}" in
	C1)
		err "${EX_USAGE:-64}" "_write_atomic: Teeing with noclobber" \
			              "cannot work"
		;;
	esac
	case "${dest}" in
	*/*) tmpdir="${dest%/*}" ;;
	*)   tmpdir="." ;;
	esac
	mapfile_mktemp tmpfile_handle tmpfile \
	    -p "${tmpdir}" -ut ".write_atomic-${dest##*/}" ||
	    err "$?" "write_atomic unable to create tmpfile in ${tmpdir}"
	ret=0
	case "${tee}" in
	1) Tflag=1 ;;
	*) Tflag= ;;
	esac
	mapfile_write "${tmpfile_handle}" ${Tflag:+-T} -- ${data+"$@"} ||
	    ret="$?"
	case "${ret}" in
	0) ;;
	*)
		msg_error "write_atomic: mapfile_write file=${tmpfile} dest=${dest} ret=${ret}"
		unlink "${tmpfile}" || :
		return "${ret}"
		;;
	esac
	ret=0
	mapfile_close "${tmpfile_handle}" || ret="$?"
	case "${ret}" in
	0) ;;
	*)
		msg_dev "write_atomic: mapfile_close file=${tmpfile} dest=${dest} ret=${ret}"
		unlink "${tmpfile}" || :
		return "${ret}"
		;;
	esac
	ret=0
	case "$-" in
	*C*) # noclobber
		# If comparing, we can only succeed if there is no file
		# so no need to compare.
		ln "${tmpfile}" "${dest}" 2>/dev/null || ret="$?"
		case "${ret}" in
		0) ;;
		*)
			msg_dev "write_atomic: ln file=${tmpfile} dest=${dest} ret=${ret}"
			;;
		esac
		unlink "${tmpfile}" || :
		return "${ret}"
		;;
	esac
	case "${cmp}" in
	1)
		if cmp -s "${dest}" "${tmpfile}"; then
			unlink "${tmpfile}" || :
			return 0
		fi
		;;
	esac
	rename "${tmpfile}" "${dest}" || ret="$?"
	case "${ret}" in
	0) ;;
	*)
		msg_dev "write_atomic: rename file=${tmpfile} dest=${dest} ret=${ret}"
		unlink "${tmpfile}" || :
		;;
	esac
	return "${ret}"
}

# -T is for teeing
write_atomic_cmp() {
	local -; set +x
	[ $# -ge 1 ] || eargs write_atomic_cmp '[-T]' destfile '< data | data'
	local flag Tflag
	local OPTIND=1

	Tflag=0
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "write_atomic_cmp: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -eq 1 ] || [ $# -ge 2 ] ||
	    eargs write_atomic_cmp '[-T]' destfile '< data | data'

	_write_atomic 1 "${Tflag}" "$@" || return
}

# -T is for teeing
write_atomic() {
	local -; set +x
	[ $# -ge 1 ] || eargs write_atomic '[-T]' destfile '< data | data'
	local flag Tflag
	local OPTIND=1

	Tflag=0
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "write_atomic: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -eq 1 ] || [ $# -ge 2 ] ||
	    eargs write_atomic '[-T]' destfile '< data | data'

	_write_atomic 0 "${Tflag}" "$@" || return
}

# Place environment requirements on entering a function
# Using VALUE of re__null requires a variable is NOT SET
# Using VALUE of "" requires a variable is SET but BLANK
# Using VAR! negates the value comparison (re__null is SET, "" is SET+NOT EMPTY)
required_env() {
	local -; set +x
	[ $# -ge 3 ] || eargs required_env function VAR VALUE VAR... VALUE...
	local re_func="$1"
	local re_var re_expected_val re_val re_ret re_neg
	local re_errors

	# shellcheck disable=SC2034
	re_errors=
	shift
	re_ret=0
	re_neg=
	if [ $(($# % 2)) -ne 0 ]; then
		err "${EX_SOFTWARE}" "wrong number of arguments to required_env() calling ${re_func}: expected function followed by pairs of VAR VALUE"
	fi
	while [ $# -ne 0 ]; do
		re_var="$1"
		re_expected_val="$2"
		shift 2 || \
		    err "${EX_SOFTWARE}" "wrong number of arguments to required_env()"
		case "${re_var}" in
		*!)
			re_neg="!"
			re_var="${re_var%!}"
			getvar "${re_var}" re_val || re_val=re__null
			# !expected
			case "${re_expected_val}" in
			"")
				case "${re_val}" in
				# Special case: SET and not blank is wanted
				"re__null"|"")
					re_expected_val="empty or re__null"
					;;
				*) continue ;;
				esac
				;;
			"${re_val}") ;;
			*) continue ;;
			esac
			;;
		*)
			re_neg=
			getvar "${re_var}" re_val || re_val=re__null
			case "${re_val}" in
			"${re_expected_val}") continue ;;
			esac
			;;
		esac
		re_ret=$((re_ret + 1))
		stack_push re_errors "expected ${re_var} ${re_neg}= '${re_expected_val}' actual: '${re_val}'"
	done
	if [ "${re_ret}" -ne 0 ]; then
		err "${EX_SOFTWARE}" "entered ${re_func}() with wrong environment:"$'\n'$'\t'"$(stack_expand re_errors $'\n'$'\t')"
	fi
	return "${re_ret}"
}

if ! type getpid >/dev/null 2>&1; then
# $$ is not correct in subshells.
getpid() {
	sh -c 'echo $PPID'
}
fi

# Export handling is different in builtin vs external
case "$(type mktemp)" in
"mktemp is a shell builtin")
	MKTEMP_BUILTIN=1
	;;
esac
_mktemp() {
	local -; set +x
	local _mktemp_var_return="$1"
	shift
	local TMPDIR ret _mktemp_tmpfile datatmpdir

	# If no preferred dir is passed in then use ${POUDRIERE_TMPDIR}
	case "${@}" in
	*'-p '*|*--tmpdir=*)
		;;
	*)
		case "${TMPDIR-}" in
		"")
			TMPDIR="${POUDRIERE_TMPDIR-}"
			case "${STATUS:-0}.${MNT_DATADIR-}" in
			1."") ;;
			1.*)
				datatmpdir="${MNT_DATADIR:?}/tmp"
				if [ -d "${datatmpdir}" ]; then
					TMPDIR="${datatmpdir}"
				fi
				;;
			esac
			;;
		esac
		;;
	esac
	ret=0
	case "${MKTEMP_BUILTIN:+set}" in
	set)
		# No export needed here since TMPDIR is set above in scope.
		builtin _mktemp "${_mktemp_var_return}" "$@" || ret="$?"
		return "${ret}"
		;;
	esac

	export TMPDIR
	_mktemp_tmpfile="$(command mktemp "$@")" || ret="$?"
	setvar "${_mktemp_var_return}" "${_mktemp_tmpfile}" || return
	return "${ret}"
}

case "$(type dirempty 2>/dev/null)" in
"dirempty is a shell builtin") ;;
*)
dirempty() {
	[ $# -eq 1 ] || eargs dirempty
	local dir="$1"

	! globmatch "${dir}/*"
}
;;
esac

globmatch() {
	[ $# -eq 1 ] || eargs globmatch glob
	local glob="$1"
	local match

	case "${glob}" in
	*"*"*|*"?"*|*"["*) ;;
	*) err "${EX_DATAERR}" "globmatch: '${glob}' is not a glob" ;;
	esac

	for match in ${glob}; do
		case "${match}" in
		"${glob}") return 1 ;;
		esac
		return 0
	done
}

stripansi() {
        [ $# -eq 2 ] || eargs stripansi input output_var
        local _input="$1"
        local _output_var="$2"
        local _gsub

	case "${_input}" in
	*$'\033'"["*) ;;
	*)
		setvar "${_output_var}" "${_input}" || return
		return 0
		;;
	esac

        _gsub="${_input}"
        _gsub "${_gsub}"        $'\033'"[?m" ""
        _gsub "${_gsub}"        $'\033'"[??m" ""
        _gsub "${_gsub}"        $'\033'"[?;?m" ""
        _gsub "${_gsub}"        $'\033'"[?;??m" ""

        setvar "${_output_var}" "${_gsub}"
}

sorted() {
	[ "$#" -ge 0 ] || eargs sorted string...
	local LC_ALL

	case "$#" in
	0)
		LC_ALL=C sort -u
		;;
	*)
		echo "$@" | tr ' ' '\n' | LC_ALL=C sort -u
		;;
	esac | sed -e '/^$/d' | paste -s -d ' ' -
}

# Wrapper to make wc -l only return a number.
count_lines() {
	[ "$#" -le 2 ] || eargs count_lines file '[var_return]'
	local cl_file="$1"
	local cl_var_return="${2-}"
	local cl_count cl_ret

	cl_ret=0
	case "${cl_file}" in
	-|/dev/stdin|/dev/fd/0) cl_file="/dev/stdin" ;;
	*)
		if [ ! -r "${cl_file}" ]; then
			cl_count=0
			cl_ret="${EX_NOINPUT:-66}"
		fi
		;;
	esac
	case "${cl_ret}" in
	0)
		# Avoid blank value on signal (see critical_inherit).
		until cl_count=0; [ ! -r "${cl_file}" ] ||
		    cl_count="$(wc -l "${cl_file}")"; do :; done
		cl_count="${cl_count% *}"
		cl_count="${cl_count##* }"
		;;
	esac
	case "${cl_var_return}" in
	""|-) echo "${cl_count}" ;;
	*) setvar "${cl_var_return}" "${cl_count}" || return ;;
	esac
	return "${cl_ret}"
}

case "$(type sleep)" in
"sleep is a shell builtin") ;;
*)
sleep() {
	local -

	set -T
	command sleep "$@"
}
;;
esac

_lock_read_pid() {
	[ $# -eq 2 ] || eargs _lock_read_pid pidfile pid_var_return
	local _lrp_pidfile="$1"
	local _lrp_var_return="$2"
	local _lrp_pid _lrp_tries _lrp_max

	# The pidfile has no newline, so read until we have a value
	# regardless of the read error. The rereads are to avoid
	# racing with signals.
	_lrp_pid=
	_lrp_tries=0
	_lrp_max=20
	until [ "${_lrp_pid:+set}" == "set" ] ||
	    [ "${_lrp_tries:?}" -eq "${_lrp_max:?}" ]; do
		read -r _lrp_pid < "${_lrp_pidfile:?}" || :
		_lrp_tries="$((_lrp_tries + 1))"
	done
	# This || return to make it clear this function may error.
	setvar "${_lrp_var_return:?}" "${_lrp_pid:?}" || return
}

_lock_acquire() {
	local -; set +x
	[ $# -eq 3 ] || [ $# -eq 4 ] ||
	    eargs _lock_acquire quiet lockpath lockname '[waittime]'
	local have_lock mypid lock_pid real_lock_pid
	local quiet="$1"
	local lockname="$2"
	local lockpath="$3"
	local waittime="${4:-30}"

	# Avoid blank value on signal (see critical_inherit).
	until mypid="$(getpid)"; do :; done
	hash_get have_lock "${lockname}" have_lock || have_lock=0
	# lock_pid is in case a subshell tries to reacquire/relase my lock
	hash_get lock_pid "${lockname}" lock_pid || lock_pid=
	# If the pid is set and does not match I'm a subshell and should wait
	case "${lock_pid}" in
	"${mypid}"|"") ;;
	*)
		hash_unset have_lock "${lockname}"
		hash_unset lock_pid "${lockname}"
		lock_pid=
		have_lock=0
		;;
	esac
	if [ "${have_lock}" -eq 0 ]; then
		local lm_ret

		lm_ret=0
		locked_mkdir "${waittime}" "${lockpath}" "${mypid}" ||
		    lm_ret="$?"
		case "${lm_ret}" in
		0) ;;
		*)
			if [ "${quiet}" -eq 0 ]; then
				msg_warn "Failed to acquire ${lockname} lock ret=${lm_ret}"
			fi
			return "${lm_ret}"
			;;
		esac
	# XXX: Remove this block with locked_mkdir [EINTR] fixes.
	{
		# locked_mkdir is quite racy. We may have gotten a false-success
		# and need to consider it a failure.
		if [ ! -d "${lockpath}" ]; then
			if [ "${quiet}" -eq 0 ]; then
				msg_warn "Lost race grabbing ${lockname} lock: no dir"
			fi
			return 1
		fi
		_lock_read_pid "${lockpath:?}.pid" real_lock_pid ||
		    real_lock_pid=
		case "${real_lock_pid}" in
		"${mypid}") ;;
		*)
			if [ "${quiet}" -eq 0 ]; then
				msg_warn "Lost race grabbing ${lockname} lock: wrong pid: mypid=${mypid} lock_pid=${real_lock_pid}"
			fi
			return 1
			;;
		esac
	}
	elif [ "${have_lock}" -eq 1 ]; then
		# Lock recursion may happen in a trap handler if the lock
		# was held before the trap.
		:
	else
		# However it should not happen once.
		err 1 "Attempted double recursive locking of ${lockname}"
	fi
	hash_set have_lock "${lockname}" $((have_lock + 1))
	case "${lock_pid}" in
	"")
		hash_set lock_pid "${lockname}" "${mypid}"
		;;
	esac
}

# Acquire local build lock
lock_acquire() {
	local -; set +x
	[ $# -eq 1 ] || [ $# -eq 2 ] || [ $# -eq 3 ] ||
	    eargs lock_acquire '[-q]' lockname '[waittime]'
	local lockname waittime lockpath

	case "$1" in
	"-q")
		quiet=1
		shift
		;;
	*)
		quiet=0
		;;
	esac
	lockname="$1"
	waittime="$2"

	lockpath="${POUDRIERE_TMPDIR:?}/lock-${MASTERNAME:+${MASTERNAME}-}${lockname:?}"
	_lock_acquire "${quiet}" "${lockname}" "${lockpath}" "${waittime}"
}

# while locked tmp NAME timeout; do <locked code>; done
locked() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs locked tmp_var lockname \
	    '[waittime]'
	local l_tmp_var="$1"
	local lockname="$2"
	local waittime="${3-}"

	if isset "${l_tmp_var}"; then
		lock_release "${lockname}"
		unset "${l_tmp_var}"
		return 1
	fi
	setvar "${l_tmp_var}" "1"
	until lock_acquire "${lockname}" "${waittime}"; do
		sleep 1
	done
}

# Acquire system wide lock
slock_acquire() {
	local -; set +x
	[ $# -eq 1 ] || [ $# -eq 2 ] || [ $# -eq 3 ] ||
	    eargs slock_acquire '[-q]' lockname '[waittime]'
	local lockname waittime lockpath quiet

	case "$1" in
	"-q")
		quiet=1
		shift
		;;
	*)
		quiet=0
		;;
	esac
	lockname="$1"
	waittime="$2"

	mkdir -p "${SHARED_LOCK_DIR:?}" || return
	lockpath="${SHARED_LOCK_DIR:?}/lock-poudriere-shared-${lockname:?}"
	_lock_acquire "${quiet}" "${lockname}" "${lockpath}" "${waittime}" ||
	    return
	# This assumes SHARED_LOCK_DIR isn't overridden by caller
	SLOCKS="${SLOCKS:+${SLOCKS} }${lockname}"
}

# while slocked tmp NAME timeout; do <locked code>; done
slocked() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs slocked tmp_var lockname \
	    '[waittime]'
	local s_tmp_var="$1"
	local lockname="$2"
	local waittime="${3-}"

	if isset "${s_tmp_var}"; then
		slock_release "${lockname}"
		unset "${s_tmp_var}"
		return 1
	fi
	setvar "${s_tmp_var}" "1"
	until slock_acquire "${lockname}" "${waittime}"; do
		sleep 1
	done
}

_lock_release() {
	local -; set +x
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
	# Avoid blank value on signal (see critical_inherit).
	until mypid="$(getpid)"; do :; done
	case "${mypid}" in
	"${lock_pid}") ;;
	*)
		err 1 "Releasing lock pid ${lock_pid} owns ${lockname}"
		;;
	esac
	if [ "${have_lock}" -gt 1 ]; then
		hash_set have_lock "${lockname}" $((have_lock - 1))
	else
		hash_unset have_lock "${lockname}"
		[ -f "${lockpath:?}.pid" ] ||
			err 1 "No pidfile found for ${lockpath}"
		_lock_read_pid "${lockpath:?}.pid" pid || pid=
		case "${pid}" in
		"")
			err 1 "Pidfile is empty for ${lockpath}"
			;;
		esac
		case "${pid}" in
		"${mypid}") ;;
		*)
			err 1 "Releasing lock pid ${lock_pid} owns ${lockname}"
			;;
		esac
		rmdir "${lockpath:?}" ||
			err 1 "Held lock dir not found: ${lockpath}"
	fi

	# Callers assume _lock_release cannot fail.
	return 0
}

# Release local build lock
lock_release() {
	local -; set +x
	[ $# -eq 1 ] || eargs lock_release lockname
	local lockname="$1"
	local lockpath

	lockpath="${POUDRIERE_TMPDIR:?}/lock-${MASTERNAME:+${MASTERNAME}-}${lockname:?}"
	_lock_release "${lockname}" "${lockpath}"
}

# Release system wide lock
slock_release() {
	local -; set +x
	[ $# -eq 1 ] || eargs slock_release lockname
	local lockname="$1"
	local lockpath

	lockpath="${SHARED_LOCK_DIR:?}/lock-poudriere-shared-${lockname:?}"
	_lock_release "${lockname}" "${lockpath}" || return
	list_remove SLOCKS "${lockname}"
}

slock_release_all() {
	local -; set +x
	[ $# -eq 0 ] || eargs slock_release_all
	local lockname

	case "${SLOCKS-}" in
	"") return 0 ;;
	esac
	for lockname in ${SLOCKS:?}; do
		slock_release "${lockname}"
	done
}

lock_have() {
	local -; set +x
	[ $# -eq 1 ] || eargs lock_have lockname
	local lockname="$1"
	local mypid lock_pid

	if hash_isset have_lock "${lockname}"; then
		hash_get lock_pid "${lockname}" lock_pid ||
			err 1 "have_lock: Lock had no pid ${lockname}"
		# Avoid blank value on signal (see critical_inherit).
		until mypid="$(getpid)"; do :; done
		case "${lock_pid}" in
		"${mypid}") return 0 ;;
		esac
	fi
	return 1
}

# This is mostly for tests to assert without having the assert hidden.
hide_stderr() {
	"$@" 2>/dev/null
}
