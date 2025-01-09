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

: ${ENCODE_SEP:=$'\002'}

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

# Encode $@ for later decoding
encode_args() {
	local -; set +x
	[ $# -ge 1 ] || eargs encode_args var_return [args]
	local var_return="$1"
	shift
	local _args IFS

	IFS="${ENCODE_SEP}"
	_args="$*"
	unset IFS
	# Trailing empty fields need special handling.
	case "${_args}" in
	*"${ENCODE_SEP}")
		setvar "${var_return}" "${_args}${ENCODE_SEP}"
		;;
	*)
		setvar "${var_return}" "${_args}"
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
	[ $# -ge 2 ] || eargs decode_args_vars data var1 [var2... varN]
	local encoded_args_data="$1"
	local _value _var IFS
	shift
	local _vars="$*"

	IFS="${ENCODE_SEP}"
	set -- ${encoded_args_data}
	unset IFS
	for _value; do
		# Select the next var to populate.
		_var="${_vars%% *}"
		case "${_vars}" in
		# Last one - set all remaining to here
		"${_var}")
			setvar "${_var}" "$*"
			break
			;;
		*)
			setvar "${_var}" "${_value}"
			# Pop off the var
			_vars="${_vars#"${_var}" }"
			shift
			;;
		esac
	done
}

if ! type issetvar >/dev/null 2>&1; then
issetvar() {
	[ $# -eq 1 ] || eargs issetvar var
	local var="$1"
	local _evalue

	eval "_evalue=\${${var}-isv__null}"

	case "${_evalue}" in
	"isv__null") return 1 ;;
	esac
	return 0
}
fi

if ! type setvar >/dev/null 2>&1; then
setvar() {
	[ $# -eq 2 ] || eargs setvar variable value
	local _setvar_var="$1"
	shift
	local _setvar_value="$*"

	read -r "${_setvar_var}" <<-EOF
	${_setvar_value}
	EOF
}
fi

if ! type getvar >/dev/null 2>&1; then
getvar() {
	[ $# -eq 1 -o $# -eq 2 ] || eargs getvar var [var_return]
	local _getvar_var="$1"
	local _getvar_var_return="$2"
	local ret _getvar_value

	eval "_getvar_value=\${${_getvar_var}-gv__null}"

	case "${_getvar_value}" in
	gv__null)
		_getvar_value=
		ret=1
		case "${_getvar_var_return}" in
		""|-) ;;
		*) unset "${_getvar_var_return}" ;;
		esac
		;;
	*)
		ret=0
		case "${_getvar_var_return}" in
		""|-) echo "${_getvar_value}" ;;
		*) setvar "${_getvar_var_return}" "${_getvar_value}" ;;
		esac
		;;
	esac

	return "${ret}"
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
	local dir1 dir2 common other

	dir1=$(realpath -q "$1" || echo "$1" | sed -e 's,//*,/,g') || return 1
	dir1="${dir1%/}/"
	dir2=$(realpath -q "$2" || echo "$2" | sed -e 's,//*,/,g') || return 1
	dir2="${dir2%/}/"
	if [ "${#dir1}" -ge "${#dir2}" ]; then
		common="${dir1}"
		other="${dir2}"
	else
		common="${dir2}"
		other="${dir1}"
	fi
	# Trim away path components until they match
	#while [ "${other#${common%/}/}" = "${other}" -a -n "${common}" ]; do
	#	common="${common%/*}"
	#done
	while :; do
		case "${common:+set}" in
		set)
			case "${other}" in
			"${common%/}/"*)
				break
				;;
			*)
				common="${common%/*}"
				;;
			esac
			;;
		"") break ;;
		esac
	done
	common="${common%/}"
	common="${common:-/}"
	dir1="${dir1#"${common}"/}"
	dir1="${dir1#/}"
	dir1="${dir1%/}"
	dir1="${dir1:-.}"
	dir2="${dir2#"${common}"/}"
	dir2="${dir2#/}"
	dir2="${dir2%/}"
	dir2="${dir2:-.}"

	_relpath_common="${common}"
	_relpath_common_dir1="${dir1}"
	_relpath_common_dir2="${dir2}"
}

# See _relpath_common
relpath_common() {
	local -; set +x
	[ $# -eq 2 ] || eargs relpath_common dir1 dir2
	local dir1="$1"
	local dir2="$2"
	local _relpath_common _relpath_common_dir1 _relpath_common_dir2

	_relpath_common "${dir1}" "${dir2}"
	echo "${_relpath_common} ${_relpath_common_dir1} ${_relpath_common_dir2}"
}

# Given 2 paths, return the relative path from the 2nd to the first
_relpath() {
	local -; set +x -f
	[ $# -eq 2 -o $# -eq 3 ] || eargs _relpath dir1 dir2 [var_return]
	local dir1="$1"
	local dir2="$2"
	local var_return="${3:-_relpath}"
	local _relpath_common _relpath_common_dir1 _relpath_common_dir2
	local newpath IFS

	# Find the common prefix
	_relpath_common "${dir1}" "${dir2}"

	case "${_relpath_common_dir2}" in
	".")
		newpath="${_relpath_common_dir1}"
		;;
	*)
		# Replace each component in _relpath_common_dir2 with
		# a ..
		IFS="/"
		case "${_relpath_common_dir1}" in
		".")
			newpath=
			;;
		*)
			newpath="${_relpath_common_dir1}"
			;;
		esac
		set -- ${_relpath_common_dir2}
		while [ $# -gt 0 ]; do
			newpath="..${newpath:+/}${newpath}"
			shift
		done
		;;
	esac

	case "${var_return}" in
	-) echo "${newpath}" ;;
	*) setvar "${var_return}" "${newpath}" ;;
	esac
}

# See _relpath
relpath() {
	local -; set +x
	[ $# -eq 2 -o $# -eq 3 ] || eargs relpath dir1 dir2 [var_return]
	local dir1="$1"
	local dir2="$2"
	local outvar="${3:-"-"}"
	local _relpath

	_relpath "${dir1}" "${dir2}" "${outvar}"
}

in_reldir() {
	[ "$#" -ge 2 ] || eargs in_reldir reldir_var cmd 'args...'
	local reldir_var="$1"
	shift
	local reldir_val reldir_abs_val nested_dir wanted_dir
	local ret oldpwd

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
		oldpwd=
		;;
	*)
		cd "${wanted_dir:?}"
		oldpwd="${OLDPWD}"
		;;
	esac

	ret=0
	"$@" || ret="$?"

	case "${oldpwd:+set}" in
	set) cd "${oldpwd}" ;;
	esac

	return "${ret}"
}

make_relative() {
	[ $# -eq 1 -o $# -eq 3 ] || eargs make_relative varname \
	    [oldroot newroot]
	local varname="$1"
	local oldroot="${2:-${PWD}}"
	local newroot="${3:-${PWD}}"
	local value

	getvar "${varname}" value || return 0
	case "${value}" in
	"") return 0 ;;
	esac
	case "${value}" in
	/*)	_relpath "${value}" "${newroot}" "${varname}" ;;
	*)	_relpath "${oldroot}/${value}" "${newroot}" "${varname}" ;;
	esac
}

case "$(type randint 2>/dev/null)" in
"randint is a shell builtin") ;;
*)
randint() {
	[ "$#" -eq 1 -o "$#" -eq 2 ] || eargs randint max_val [var_return]
	local max_val="$1"
	local var_return="${2-}"
	local val

	if [ "$#" -eq 1 ]; then
		jot -r 1 "${max_val}"
		return
	fi
	val=$(jot -r 1 "${max_val}")
	setvar "${var_return}" "${val}"
}
;;
esac

_trap_ignore_block() {
	local -; set +x
	[ "$#" -ge 3 ] || eargs _trap_ignore_block ignore_bool tmp_var SIG [SIG...]
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
	setvar "${tib_tmp_var}" "${tmp_val}"
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
	[ "$#" -ge 2 ] || eargs trap_save_block tmp_var SIG [SIG...]
	_trap_ignore_block 0 "$@"
}

trap_ignore_block() {
	[ "$#" -ge 2 ] || eargs trap_save_block tmp_var SIG [SIG...]
	_trap_ignore_block 1 "$@"
}

case "$(type trap_push 2>/dev/null)" in
"trap_push is a shell builtin") ;;
*)
trap_push() {
	local -; set +x
	[ $# -eq 2 ] || eargs trap_push signal var_return
	local signal="$1"
	local var_return="$2"
	local _trap ltrap ldash lhandler lsig

	_trap="-"
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
		trap - ${signal}
		break
	done <<-EOF
	$(trap)
	EOF

	setvar "${var_return}" "${_trap}"
}

trap_pop() {
	local -; set +x
	[ $# -eq 2 ] || eargs trap_pop signal saved_trap
	local signal="$1"
	local _trap="$2"

	case "${_trap:+set}" in
	set) eval trap -- "${_trap}" ${signal} || : ;;
	"") return 1 ;;
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
			setvar "_crit_caught_${sig}" 0
		fi
		trap "_crit_caught_${sig}=1" "${sig}"
		hash_set crit_saved_trap "${sig}-${_CRITSNEST}" "${saved_trap}"
	done
}

critical_end() {
	local -; set +x
	local sig saved_trap caught_sig oldnest

	[ ${_CRITSNEST:--1} -ne -1 ] || \
	    err 1 "critical_end called without critical_start"

	oldnest=${_CRITSNEST}
	_CRITSNEST=$((_CRITSNEST - 1))
	[ ${_CRITSNEST} -eq 0 ] || return 0
	for sig in ${CRITICAL_START_BLOCK_SIGS}; do
		if hash_remove crit_saved_trap "${sig}-${oldnest}" saved_trap; then
			trap_pop "${sig}" "${saved_trap}"
		fi
	done
	# Deliver the signals if this was the last critical section block.
	# Send the signal to our real PID, not the rootshell.
	for sig in ${CRITICAL_START_BLOCK_SIGS}; do
		getvar "_crit_caught_${sig}" caught_sig
		if [ "${caught_sig}" -eq 1 -a "${_CRITSNEST}" -eq 0 ]; then
			setvar "_crit_caught_${sig}" 0
			raise "${sig}"
		fi
	done
}
;;
esac

# Read a file into the given variable.
read_file() {
	local -; set +x
	[ $# -eq 2 ] || eargs read_file var_return file
	local var_return="$1"
	local file="$2"
	local _data
	local _ret - IFS

	# var_return may be empty if only $_read_file_lines_read is being
	# used.
	_ret=0
	_read_file_lines_read=0

	set +e

	if ! mapfile_builtin && [ "${READ_FILE_USE_CAT:-0}" -eq 1 ]; then
		local _data

		case "${file:?}" in
		-|/dev/stdin|/dev/fd/0) ;;
		*)
			if [ ! -r "${file:?}" ]; then
				case "${var_return}" in
				""|-) ;;
				*) unset "${var_return}" ;;
				esac
				return 1
			fi
			;;
		esac
		case "${var_return:+set}" in
		set)
			_data="$(cat "${file}")" || _ret="$?"
			;;
		esac
		count_lines "${file}" _read_file_lines_read ||
		    _read_file_lines_read=0

		case "${var_return}" in
		"") ;;
		-) echo "${_data}" ;;
		*) setvar "${var_return}" "${_data}" ;;
		esac

		return "${_ret}"
	else
		readlines_file "${file}" ${var_return:+"${var_return}"} ||
		    _ret="$?"
		_read_file_lines_read="${_readlines_lines_read:?}"
		return "${_ret}"
	fi
}

# Read a file until 0 status is found. Partial reads not accepted.
read_line() {
	local -; set +x
	[ $# -eq 2 ] || eargs read_line var_return file
	local var_return="$1"
	local file="$2"
	local max_reads reads _ret _line maph IFS

	if [ ! -f "${file}" ]; then
		unset "${var_return}"
		return 1
	fi

	_ret=0
	if mapfile_builtin; then
		if mapfile -F maph "${file}"; then
			IFS= mapfile_read "${maph}" "${var_return}" || _ret=$?
			mapfile_close "${maph}" || :
		else
			_ret=$?
		fi

		return ${_ret}
	fi

	max_reads=100
	reads=0

	# Read until a full line is returned.
	until [ ${reads} -eq ${max_reads} ] || \
	    IFS= read -t 1 -r _line < "${file}"; do
		sleep 0.1
		reads=$((reads + 1))
	done
	if [ "${reads}" -eq "${max_reads}" ]; then
		_ret=1
	fi

	setvar "${var_return}" "${_line}"

	return ${_ret}
}

readlines() {
	[ "$#" -ge 0 ] || eargs readlines [-T] '[vars...]'
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
	[ "$#" -ge 0 ] || eargs readlines [-T] '[vars...]'

	readlines_file ${Tflag:+-T} "/dev/stdin" "$@"
}

readlines_file() {
	# Blank vars will still read and output $_readlines_lines_read
	[ "$#" -ge 1 ] || eargs readlines_file [-T] file '[vars...]'
	local rl_file
	local rl_var rl_line rl_var_count rl_line_count
	local rl_rest rl_nl rl_handle ret
	local flag Tflag
	local OPTIND=1 IFS

	Tflag=0
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "readlines_file: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 1 ] || eargs readlines_file [-T] file '[vars...]'
	rl_file="$1"
	shift

	_readlines_lines_read=0
	case "${rl_file:?}" in
	-|/dev/stdin|/dev/fd/0) rl_file="/dev/fd/0" ;;
	*)
		if [ ! -r "${rl_file:?}" ]; then
			for rl_var in "$@"; do
				unset "${rl_var}"
			done
			return 1
		fi
		;;
	esac

	rl_nl=${RL_NL-$'\n'}
	rl_var_count="$#"
	unset rl_rest
	ret=0
	if mapfile -F rl_handle "${rl_file:?}" "r"; then
		while IFS= mapfile_read "${rl_handle}" rl_line; do
			_readlines_lines_read="$((_readlines_lines_read + 1))"
			case "${Tflag}" in
			1)
				echo "${rl_line}"
				;;
			esac
			case "${rl_var_count}" in
			0)
				;;
			1)
				rl_rest="${rl_rest:+${rl_rest}${rl_nl}}${rl_line}"
				;;
			*)
				rl_var_count="$((rl_var_count - 1))"
				rl_var="${1?}"
				shift
				case "${rl_var:+set}" in
				set)
					setvar "${rl_var}" "${rl_line}"
					;;
				esac
				;;
			esac
		done
		mapfile_close "${rl_handle}" || ret="$?"
	else
		ret=1
	fi
	case "${rl_var_count}" in
	0) ;;
	*)
		case "${rl_rest+set}" in
		set)
			rl_var="${1?}"
			shift
			case "${rl_var:+set}" in
			set)
				setvar "${rl_var}" "${rl_rest}"
				;;
			esac
			;;
		esac
		for rl_var in "$@"; do
			unset "${rl_var}"
		done
		;;
	esac
	return "${ret}"
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
	local _ret

	while :; do
		_ret=0
		read "$@" || _ret=$?
		case ${_ret} in
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
	return ${_ret}
}

# Same as read_blocking() but it reads an entire raw line.
# Needed because 'IFS= read_blocking' doesn't reset IFS like the normal read
# builtin does.
read_blocking_line() {
	local -; set +x
	[ $# -ge 1 ] || eargs read_blocking_line read_args
	local _ret IFS

	while :; do
		_ret=0
		IFS= read -r "$@" || _ret=$?
		case ${_ret} in
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
	return ${_ret}
}

# SIGINFO traps won't abort the read, and if the pipe goes away or
# turns into a file then an error is returned.
read_pipe() {
	local -; set +x
	[ $# -ge 2 ] || eargs read_pipe fifo read_args
	local fifo="$1"
	local _ret resread resopen
	shift

	_ret=0
	while :; do
		if ! [ -p "${fifo}" ]; then
			_ret=32
			break
		fi
		# Separately handle open(2) and read(builtin) errors
		# since opening the pipe blocks and may be interrupted.
		resread=0
		resopen=0
		{ { read -r "$@" || resread=$?; } < "${fifo}" || resopen=$?; } \
		    2>/dev/null
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
			*) _ret=${resopen}; break ;;
		esac
		case ${resread} in
			# Read again on SIGINFO interrupts
			157) continue ;;
			# Valid EOF
			1) _ret=${resread}; break ;;
			# Success
			0) break ;;
			# Unknown problem or signal, just return the error.
			*) _ret=${resread}; break ;;
		esac
	done
	return ${_ret}
}

# Ignore EOF
read_pipe_noeof() {
	local -; set +x
	[ $# -ge 2 ] || eargs read_pipe_noeof fifo read_args
	local fifo="$1"
	local _ret
	shift

	while :; do
		_ret=0
		read_pipe "${fifo}" "$@" || _ret=$?
		[ ${_ret} -eq 1 ] || break
	done
	return ${_ret}
}

# This is avoiding EINTR errors when writing to a pipe due to SIGINFO traps
write_pipe() {
	local -; set +x
	[ $# -ge 1 ] || eargs write_pipe fifo [write_args]
	local fifo="$1"
	local ret tmp
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
	[ $# -ge 3 ] || eargs _pipe_hold_child watch_pid sync_fifo fifos...
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
	echo ready >&3 || err "$?" "pwrite"
	exec pwait "${watch_pid}" 3<&- 2>/dev/null || err "$?" "pwait"
}

# This keeps the given fifos open to avoid EOF in writers.
pipe_hold() {
	[ $# -ge 3 ] || eargs pipe_hold var_return_jobid watch_pid fifos...
	local var_return_jobid="$1"
	local watch_pid="$2"
	shift 2
	local sync_fifo sync ret

	ret=0
	sync=
	sync_fifo=$(mktemp -ut pipe_hold)
	mkfifo "${sync_fifo}"

	spawn_job_protected _pipe_hold_child "${sync_fifo}" "${watch_pid}" "$@"
	setvar "${var_return_jobid}" "${spawn_jobid}"
	read_pipe "${sync_fifo}" sync || ret="$?"
	case "${sync}" in
	ready) ;;
	*) err 1 "pipe_hold failure" ;;
	esac
	unlink "${sync_fifo}"
	return "${ret}"
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

mapfile_supports_multiple_handles() {
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
		F) # builtin compat ;;
		esac
	done
	shift $((OPTIND-1))

	[ $# -eq 2 -o $# -eq 3 ] || eargs mapfile handle_name file modes
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
			return 1
		fi
		;;
	esac

	case "${_mapfile_handle-}" in
	""|"${_hkey}") ;;
	*)
		# New file or new process
		case "${_mapfile_handle##*.}" in
		"${mypid}")
			# Same process so far...
			case "${_mapfile_handle%.*}" in
			"${_file}")
				err 1 "mapfile: earlier case _hkey should cover this"
				;;
			*)
				case "${_file}" in
				/dev/fd/[0-9]) ;;
				*)
					case " ${_modes} " in
					*r*w*|*w*r*|*+*|*r*)
						if mapfile_supports_multiple_handles; then
							err "${EX_SOFTWARE}" "mapfile() needs updated for multiple handle support"
						fi
						err "${EX_SOFTWARE}" "mapfile only supports 1 file at a time without builtin for r+w and r. ${_mapfile_handle} already open: tried to open ${_file}"
						;;
					esac
					;;
				esac
				;;
			esac
			;;
		*)
			# Different process. Nuke the tracker.
			unset _mapfile_handle
			;;
		esac
	esac
	setvar "${handle_name}" "${_hkey}"
	case "${_file}" in
	/dev/fd/[0-9])
		hash_set mapfile_fd "${_hkey}" "${_file#/dev/fd/}"
		;;
	*)
		: "${_mapfile_handle:="${_hkey}"}"
		case "${_mapfile_handle}" in
		"${_hkey}")
			case " ${_modes} " in
			*r*w*|*w*r*|*+*)
				exec 8<> "${_file}" || ret="$?"
				;;
			*r*)
				exec 8< "${_file}" || ret="$?"
				;;
			*w*|*a*)
				exec 8> "${_file}" || ret="$?"
				;;
			esac
			hash_set mapfile_fd "${_hkey}" "8"
			;;
		*)
			case "${_modes}" in
			*a*) ;;
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
	local -; set +x
	[ $# -ge 2 ] || eargs mapfile_read handle output_var ...
	local handle="$1"
	shift

	if hash_get mapfile_fd "${handle}" fd; then
		read_blocking -r "$@" <&"${fd}"
	else
		err "${EX_SOFTWARE}" "mapfile_read: ${handle} is not open for reading"
		err "${EX_SOFTWARE}" "mapfile_read: Handle '${handle}' is not open${_mapfile_handle:+, '${_mapfile_handle}' is}."
	fi
}

mapfile_write() {
	local -; set +x
	[ $# -ge 1 ] || eargs mapfile_write handle [-nT] [data]
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
	[ $# -ge 0 ] || eargs mapfile_write handle [-nT] [data]

	if [ "$#" -eq 0 ]; then
		local data

		read_file data - || ret="$?"
		if [ "${ret}" -ne 0 ]; then
			return "${ret}"
		fi
		case "${data}-${_read_file_lines_read}" in
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
		8)
			exec 8>&-
			case "${handle}" in
			"${_mapfile_handle-}")
				unset _mapfile_handle
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
	local _file="$1"
	shift
	local _hkey _handle ret

	# Store the handle based on the params passed in since it is
	# using an anonymous handle on stdin - which if nested in a
	# pipe would reuse the already-opened handle from the parent
	# pipe.
	_hkey="${_file}.$*"

	if ! hash_get mapfile_handle "${_hkey}" _handle; then
		mapfile _handle "${_file}" "re" || return "$?"
		hash_set mapfile_handle "${_hkey}" "${_handle}"
	fi

	if mapfile_read "${_handle}" "$@"; then
		return 0
	else
		ret=$?
		mapfile_close "${_handle}"
		hash_unset mapfile_handle "${_hkey}"
		return ${ret}
	fi
}

# Pipe to STDOUT from handle.
mapfile_cat() {
	[ $# -ge 1 ] || eargs mapfile_cat handle...
	local IFS handle line

	for handle in "$@"; do
		while IFS= mapfile_read "${handle}" line; do
			echo "${line}"
		done
	done
}

# Pipe to STDOUT from a file.
# Basically an optimized loop of mapfile_read_loop_redir, or read_file
mapfile_cat_file() {
	local -; set +x
	[ $# -ge 0 ] || eargs mapfile_cat_file '[-q]' file...
	local  _handle ret _file
	local OPTIND=1 qflag flag

	qflag=
	while getopts "q" flag; do
		case "${flag}" in
		q) qflag=1 ;;
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
		if mapfile ${qflag:+-q} -F _handle "${_file}" "r"; then
			mapfile_cat "${_handle}" || ret="$?"
			mapfile_close "${_handle}" || ret="$?"
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

mapfile_supports_multiple_handles() {
	return 1
}
;;
esac

# Alias for mapfile_read_loop "/dev/stdin" vars...
mapfile_read_loop_redir() {
	[ $# -ge 1 ] || eargs mapfile_read_loop_redir vars

	if mapfile_builtin; then
		mapfile_read_loop "-" "$@"
	else
		read -r "$@"
	fi
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
	[ "$#" -gt 2 ] || eargs _pipe_func_job _mf_fifo function [args...]
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
	[ $# -ge 4 ] || eargs pipe_func [-H handle_var] 'read' read-params [...] -- func [params]
	local _mf_handle_var _mf_cookie_val
	local _mf_key _mf_read_params _mf_handle _mf_ret _mf_shift _mf_var
	local _mf_fifo _mf_job spawn_jobid
	local OPTIND=1 flag Hflag

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
			setvar "${_mf_handle_var}" "${_mf_cookie_val}"
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
		hash_get pipe_func_shift "${_mf_key}" _mf_shift ||
		    err "${EX_SOFTWARE}" "pipe_func: No stored shift for ${_mf_key}"
		shift "${_mf_shift}"
	else
		_mf_read_params=
		_mf_shift=0
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
		hash_set pipe_func_shift "${_mf_key}" "${_mf_shift}"
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
	if mapfile_read "${_mf_handle}" ${_mf_read_params}; then
		return 0
	else
		# EOF
		_mf_ret="$?"
		mapfile_close "${_mf_handle}"
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
	fi
}

# Create a new temporary file and return a handle to it
mapfile_mktemp() {
	local -; set +x
	[ $# -gt 2 ] || eargs mapfile_mktemp handle_var_return \
	    tmpfile_var_return "mktemp(1)-params"
	local handle_var_return="$1"
	local tmpfile_var_return="$2"
	shift 2
	local mm_tmpfile ret

	ret=0
	_mktemp mm_tmpfile "$@" || ret="$?"
	if [ "${ret}" -ne 0 ]; then
		setvar "${handle_var_return}" ""
		setvar "${tmpfile_var_return}" ""
		return "${ret}"
	fi
	ret=0
	mapfile "${handle_var_return}" "${mm_tmpfile}" "we" || ret="$?"
	if [ "${ret}" -ne 0 ]; then
		setvar "${handle_var_return}" ""
		setvar "${tmpfile_var_return}" ""
		return "${ret}"
	fi
	setvar "${tmpfile_var_return}" "${mm_tmpfile}"
}

# This uses open(O_CREAT), woot.
noclobber() {
	local -
	set -C

	"$@" 2>/dev/null
}

# Ignore SIGPIPE
nopipe() {
	local opipe _ret

	trap_push PIPE opipe
	trap '' PIPE
	_ret=0
	"$@" || _ret=$?
	trap_pop PIPE "${opipe}"

	return ${_ret}
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
	local prefixpipe prefix_job ret
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
	get_job_id "$!" prefix_job
	exec 4>&2
	exec 2> "${prefixpipe}"
	unlink "${prefixpipe}"

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
	local prefixpipe prefix_job ret
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
	get_job_id "$!" prefix_job
	exec 3>&1
	exec > "${prefixpipe}"
	unlink "${prefixpipe}"

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

	MSG_NESTED=1
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
	[ $# -eq 2 -o $# -eq 3 ] || eargs timespecsub now then [var_return]
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
		setvar "${_var_return}" "${res_sec}.${res_nsec}"
		;;
	esac
}

calculate_duration() {
	[ $# -eq 2 ] || eargs calculate_duration var_return elapsed
	local var_return="$1"
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

	setvar "${var_return}" "${_duration}"
}

_write_atomic() {
	local -; set +x
	[ $# -eq 3 ] || eargs _write_atomic cmp tee destfile "< content"
	local cmp="$1"
	local tee="$2"
	local dest="$3"
	local tmpfile_handle tmpfile ret

	TMPDIR="${dest%/*}" mapfile_mktemp tmpfile_handle tmpfile \
	    -ut ".write_atomic-${dest##*/}" ||
	    err $? "write_atomic unable to create tmpfile in ${dest%/*}"
	ret=0
	if [ "${tee}" -eq 1 ]; then
		mapfile_write "${tmpfile_handle}" -T || ret="$?"
	else
		mapfile_write "${tmpfile_handle}" || ret="$?"
	fi
	if [ "${ret}" -ne 0 ]; then
		unlink "${tmpfile}" || :
		return "${ret}"
	fi
	ret=0
	mapfile_close "${tmpfile_handle}" || ret="$?"
	if [ "${ret}" -ne 0 ]; then
		unlink "${tmpfile}" || :
		return "${ret}"
	fi
	if [ "${cmp}" -eq 1 ] && cmp -s "${dest}" "${tmpfile}"; then
		unlink "${tmpfile}" || :
		return 0
	fi
	ret=0
	rename "${tmpfile}" "${dest}" || ret="$?"
	if [ "${ret}" -ne 0 ]; then
		unlink "${tmpfile}" || :
		return "${ret}"
	fi
}


write_atomic_cmp() {
	local -; set +x
	[ $# -eq 1 ] || eargs write_atomic_cmp destfile "< content"
	local dest="$1"

	_write_atomic 1 0 "${dest}" || return
}

# -T is for teeing
write_atomic() {
	local -; set +x
	[ $# -ge 1 ] || eargs write_atomic [-T] destfile "< content"
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
	[ $# -eq 1 ] || eargs write_atomic [-T] destfile "< content"
	local dest="$1"

	_write_atomic 0 "${Tflag}" "${dest}" || return
}

# Place environment requirements on entering a function
# Using VALUE of re__null requires a variable is NOT SET
# Using VALUE of "" requires a variable is SET but BLANK
# Using VAR! negates the value comparison (re__null is SET, "" is SET+NOT EMPTY)
required_env() {
	local -; set +x
	[ $# -ge 3 ] || eargs required_env function VAR VALUE VAR... VALUE...
	local function="$1"
	local var expected_value actual_value ret neg
	local errors

	errors=
	shift
	ret=0
	neg=
	if [ $(($# % 2)) -ne 0 ]; then
		err ${EX_SOFTWARE} "wrong number of arguments to required_env() calling ${function}: expected function followed by pairs of VAR VALUE"
	fi
	while [ $# -ne 0 ]; do
		var="$1"
		expected_value="$2"
		shift 2 || \
		    err ${EX_SOFTWARE} "wrong number of arguments to required_env()"
		case "${var}" in
		*!)
			neg="!"
			var="${var%!}"
			getvar "${var}" actual_value || actual_value=re__null
			# !expected
			case "${expected_value}" in
			"")
				case "${actual_value}" in
				# Special case: SET and not blank is wanted
				"re__null"|"")
					expected_value="empty or re__null"
					;;
				*) continue ;;
				esac
				;;
			"${actual_value}") ;;
			*) continue ;;
			esac
			;;
		*)
			neg=
			getvar "${var}" actual_value || actual_value=re__null
			case "${actual_value}" in
			"${expected_value}") continue ;;
			esac
			;;
		esac
		ret=$((ret + 1))
		stack_push errors "expected ${var} ${neg}= '${expected_value}' actual: '${actual_value}'"
	done
	if [ "${ret}" -ne 0 ]; then
		err "${EX_SOFTWARE}" "entered ${function}() with wrong environment:"$'\n'$'\t'"$(stack_expand errors $'\n'$'\t')"
	fi
	return "${ret}"
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
	setvar "${_mktemp_var_return}" "${_mktemp_tmpfile}"
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
	*) err ${EX_DATAERR} "globmatch: '${glob}' is not a glob" ;;
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
		setvar "${_output_var}" "${_input}"
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
	[ "$#" -le 2 ] || eargs count_lines file [var_return]
	local cl_file="$1"
	local cl_var_return="${2-}"
	local cl_count cl_ret

	cl_ret=0
	case "${cl_file}" in
	-|/dev/stdin|/dev/fd/0) cl_file="/dev/stdin" ;;
	*)
		if [ ! -r "${cl_file}" ]; then
			cl_count=0
			cl_ret=1
		fi
		;;
	esac
	case "${cl_ret}" in
	0)
		cl_count="$(wc -l "${cl_file}")"
		cl_count="${cl_count% *}"
		cl_count="${cl_count##* }"
		;;
	esac
	case "${cl_var_return}" in
	""|-) echo "${cl_count}" ;;
	*) setvar "${cl_var_return}" "${cl_count}" ;;
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
