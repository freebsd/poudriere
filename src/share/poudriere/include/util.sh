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
		echo "Bad arguments, ${badcmd}: ""$@" >&2
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
	local _args lastempty

	_args=
	lastempty=0
	while [ "$#" -gt 0 ]; do
		_args="${_args}${_args:+${ENCODE_SEP}}${1}"
		[ "$#" -eq 1 -a -z "$1" ] && lastempty=1
		shift
	done
	# If the string ends in ENCODE_SEP then add another to
	# fix 'set' later eating it.
	[ "${lastempty}" -eq 1 ] && _args="${_args}${_args:+${ENCODE_SEP}}"

	setvar "${var_return}" "${_args}"
}

# Decode data from encode_args
# Usage: eval $(decode_args data_var_name)
decode_args() {
	local -; set +x
	[ $# -eq 1 ] || eargs decode_args encoded_args_var
	local encoded_args_var="$1"

	# oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
	echo "\
		local IFS 2>/dev/null || :; \
		case \$- in *f*) set_f=1 ;; *) set_f=0 ;; esac; \
		[ \"\${set_f}\" -eq 0 ] && set -f; \
		IFS=\"\${ENCODE_SEP}\"; \
		set -- \${${encoded_args_var}}; \
		unset IFS; \
		[ \"\${set_f}\" -eq 0 ] && set +f; \
		unset set_f; \
		"
}


# Decode data from encode_args
decode_args_vars() {
	local -; set +x -f
	[ $# -ge 2 ] || eargs decode_args_vars data var1 [var2... varN]
	local encoded_args_data="$1"
	local _value _var _vars IFS
	shift
	local _vars="$*"

	IFS="${ENCODE_SEP}"
	set -- ${encoded_args_data}
	unset IFS
	for _value; do
		_var="${_vars%% *}"
		_vars="${_vars#${_var} }"
		if [ "${_var}" = "${_vars}" ]; then
			setvar "${_var}" "$*"
			break
		else
			setvar "${_var}" "${_value}"
		fi
		shift
	done
}

if ! type issetvar >/dev/null 2>&1; then
issetvar() {
	[ $# -eq 1 ] || eargs issetvar var
	local var="$1"
	local _evalue

	eval "_evalue=\${${var}-__null}"

	[ "${_evalue}" != "__null" ]
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

	eval "_getvar_value=\${${_getvar_var}-__null}"

	if [ "${_getvar_value}" = "__null" ]; then
		_getvar_value=
		ret=1
	else
		ret=0
	fi

	if [ -n "${_getvar_var_return}" ]; then
		setvar "${_getvar_var_return}" "${_getvar_value}"
	else
		echo "${_getvar_value}"
	fi

	return ${ret}
}
fi

# Given 2 directories, make both of them relative to their
# common directory.
# $1 = _relpath_common = common directory
# $2 = _relpath_common_dir1 = dir1 relative to common
# $3 = _relpath_common_dir2 = dir2 relative to common
_relpath_common() {
	local -; set +x
	[ $# -eq 2 ] || eargs _relpath_common dir1 dir2
	local dir1=$(realpath -q "$1" || echo "$1" | sed -e 's,//*,/,g')
	local dir2=$(realpath -q "$2" || echo "$2" | sed -e 's,//*,/,g')
	local common other

	dir1="${dir1%/}/"
	dir2="${dir2%/}/"
	if [ "${#dir1}" -ge "${#dir2}" ]; then
		common="${dir1}"
		other="${dir2}"
	else
		common="${dir2}"
		other="${dir1}"
	fi
	# Trim away path components until they match
	while [ "${other#${common%/}/}" = "${other}" -a -n "${common}" ]; do
		common="${common%/*}"
	done
	common="${common%/}"
	common="${common:-/}"
	dir1="${dir1#${common}/}"
	dir1="${dir1#/}"
	dir1="${dir1%/}"
	dir1="${dir1:-.}"
	dir2="${dir2#${common}/}"
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

	if [ "${_relpath_common_dir2}" = "." ]; then
		newpath="${_relpath_common_dir1}"
	else
		# Replace each component in _relpath_common_dir2 with
		# a ..
		IFS="/"
		if [ "${_relpath_common_dir1}" != "." ]; then
			newpath="${_relpath_common_dir1}"
		else
			newpath=
		fi
		set -- ${_relpath_common_dir2}
		while [ $# -gt 0 ]; do
			newpath="..${newpath:+/}${newpath}"
			shift
		done
	fi

	setvar "${var_return}" "${newpath}"
}

# See _relpath
relpath() {
	local -; set +x
	[ $# -eq 2 -o $# -eq 3 ] || eargs relpath dir1 dir2 [var_return]
	local dir1="$1"
	local dir2="$2"
	local _relpath

	_relpath "$@"
	if [ -z "$3" ]; then
		echo "${_relpath}"
	fi
}

make_relative() {
	[ $# -eq 1 -o $# -eq 3 ] || eargs make_relative varname \
	    [oldroot newroot]
	local varname="$1"
	local oldroot="${2:-${PWD}}"
	local newroot="${3:-${PWD}}"
	local value

	getvar "${varname}" value || return 0
	if [ -z "${value}" ]; then
		return 0
	fi
	case "${value}" in
	/*)	_relpath "${value}" "${newroot}" "${varname}" ;;
	*)	_relpath "${oldroot}/${value}" "${newroot}" "${varname}" ;;
	esac
}

if [ "$(type trap_push 2>/dev/null)" != "trap_push is a shell builtin" ]; then
trap_push() {
	local -; set +x
	[ $# -eq 2 ] || eargs trap_push signal var_return
	local signal="$1"
	local var_return="$2"
	local _trap ltrap ldash lhandler lsig

	_trap="-"
	while read -r ltrap ldash lhandler lsig; do
		if [ -z "${lsig%%* *}" ]; then
			# Multi-word handler, need to shift it back into
			# lhandler and find the real lsig
			lhandler="${lhandler} ${lsig% *}"
			lsig="${lsig##* }"
		fi
		[ "${lsig}" = "${signal}" ] || continue
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

	if [ -n "${_trap}" ]; then
		eval trap -- "${_trap}" ${signal} || :
	else
		return 1
	fi
}

# Start a "critical section", disable INT/TERM while in here and delay until
# critical_end is called.
critical_start() {
	local -; set +x
	local saved_int saved_term

	_CRITSNEST=$((${_CRITSNEST:-0} + 1))
	if [ ${_CRITSNEST} -gt 1 ]; then
		return 0
	fi

	trap_push INT saved_int
	: ${_crit_caught_int:=0}
	trap '_crit_caught_int=1' INT
	hash_set crit_saved_trap "INT-${_CRITSNEST}" "${saved_int}"

	trap_push TERM saved_term
	: ${_crit_caught_term:=0}
	trap '_crit_caught_term=1' TERM
	hash_set crit_saved_trap "TERM-${_CRITSNEST}" "${saved_term}"
}

critical_end() {
	local -; set +x
	local saved_int saved_term oldnest

	[ ${_CRITSNEST:--1} -ne -1 ] || \
	    err 1 "critical_end called without critical_start"

	oldnest=${_CRITSNEST}
	_CRITSNEST=$((_CRITSNEST - 1))
	[ ${_CRITSNEST} -eq 0 ] || return 0
	if hash_remove crit_saved_trap "INT-${oldnest}" saved_int; then
		trap_pop INT "${saved_int}"
	fi
	if hash_remove crit_saved_trap "TERM-${oldnest}" saved_term; then
		trap_pop TERM "${saved_term}"
	fi
	# Deliver the signals if this was the last critical section block.
	# Send the signal to our real PID, not the rootshell.
	if [ ${_crit_caught_int} -eq 1 -a ${_CRITSNEST} -eq 0 ]; then
		_crit_caught_int=0
		kill -INT $(getpid)
	fi
	if [ ${_crit_caught_term} -eq 1 -a ${_CRITSNEST} -eq 0 ]; then
		_crit_caught_term=0
		kill -TERM $(getpid)
	fi
}
fi

# Read a file into the given variable.
read_file() {
	local -; set +x
	[ $# -eq 2 ] || eargs read_file var_return file
	local var_return="$1"
	local file="$2"
	local _data _line newline
	local _ret - IFS

	# var_return may be empty if only $_read_file_lines_read is being
	# used.

	set +e
	_data=
	_read_file_lines_read=0
	_ret=0
	newline=$'\n'

	if [ ! -f "${file}" ]; then
		if [ -n "${var_return}" ]; then
			setvar "${var_return}" ""
		fi
		return 1
	fi

	if mapfile_builtin; then
		if [ -n "${var_return}" ]; then
			while IFS= mapfile_read_loop "${file}" _line; do
				_data="${_data:+${_data}${newline}}${_line}"
				_read_file_lines_read=$((_read_file_lines_read + 1))
			done
		else
			while IFS= mapfile_read_loop "${file}" _line; do
				_read_file_lines_read=$((_read_file_lines_read + 1))
			done
		fi
		if [ -n "${var_return}" ]; then
			setvar "${var_return}" "${_data}"
		fi
		return 0
	fi

	if [ ${READ_FILE_USE_CAT:-0} -eq 1 ]; then
		if [ -n "${var_return}" ]; then
			_data="$(cat "${file}")"
		fi
		_read_file_lines_read=$(wc -l < "${file}")
		_read_file_lines_read=${_read_file_lines_read##* }
	else
		while :; do
			IFS= read -r _line
			_ret=$?
			case ${_ret} in
				# Success, process data and keep reading.
				0) ;;
				# EOF
				1)
					_ret=0
					break
					;;
				# Some error or interruption/signal. Reread.
				*) continue ;;
			esac
			if [ -n "${var_return}" ]; then
				_data="${_data:+${_data}${newline}}${_line}"
			fi
			_read_file_lines_read=$((_read_file_lines_read + 1))
		done < "${file}" || _ret=$?
	fi

	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_data}"
	fi

	return ${_ret}
}

# Read a file until 0 status is found. Partial reads not accepted.
read_line() {
	local -; set +x
	[ $# -eq 2 ] || eargs read_line var_return file
	local var_return="$1"
	local file="$2"
	local max_reads reads _ret _line maph IFS

	if [ ! -f "${file}" ]; then
		setvar "${var_return}" ""
		return 1
	fi

	_ret=0
	if mapfile_builtin; then
		if mapfile maph "${file}"; then
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
	[ ${reads} -eq ${max_reads} ] && _ret=1

	setvar "${var_return}" "${_line}"

	return ${_ret}
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
	local ret siginfo_trap
	shift

	# If this is not a pipe then return an error immediately
	if ! [ -p "${fifo}" ]; then
		msg_dev "write_pipe FAILED to send to ${fifo} (NOT A PIPE? ret=2): $@"
		return 2
	fi

	msg_dev "write_pipe ${fifo}: $@"
	ret=0
	echo "$@" > "${fifo}" || ret=$?

	if [ ${ret} -ne 0 ]; then
		err 1 "write_pipe FAILED to send to ${fifo} (ret: ${ret}): $*"
	fi

	return ${ret}
}

if [ "$(type mapfile 2>/dev/null)" != "mapfile is a shell builtin" ]; then
mapfile() {
	local -; set +x
	[ $# -eq 2 -o $# -eq 3 ] || eargs mapfile handle_name file modes
	local handle_name="$1"
	local _file="$2"
	local mypid _hkey

	mypid=$(getpid)
	case "${_file}" in
		-|/dev/stdin) _file="/dev/fd/0" ;;
	esac
	_hkey="${_file}.${mypid}"

	case "${_mapfile_handle-}" in
	""|${_hkey}) ;;
	*)
		# New file or new process
		case "${_mapfile_handle##*.}" in
		${mypid})
			# Same process so far...
			case "${_mapfile_handle%.*}" in
			${_file})
				err 1 "mapfile: earlier case _hkey should cover this"
				;;
			# Different file. Is this even possible?
			*)
				err 1 "mapfile only supports 1 file at a time without builtin. ${_mapfile_handle} already open"
				;;
			esac
			;;
		*)
			# Different process. Nuke the tracker.
			unset _mapfile_handle
			;;
		esac
	esac
	_mapfile_handle="${_hkey}"
	setvar "${handle_name}" "${_mapfile_handle}"
	case "${_file}" in
	/dev/fd/[0-9])
		hash_set mapfile_fd "${_mapfile_handle}" "${_file#/dev/fd/}"
		;;
	*)
		exec 8<> "${_file}" ;;
	esac
	hash_set mapfile_file "${_mapfile_handle}" "${_file}"
}

mapfile_read() {
	local -; set +x
	[ $# -ge 2 ] || eargs mapfile_read handle output_var ...
	local handle="$1"
	shift

	if [ "${handle}" != "${_mapfile_handle}" ]; then
		err 1 "mapfile_read: Handle '${handle}' is not open, '${_mapfile_handle}' is"
	fi

	hash_get mapfile_fd "${handle}" fd || fd=8
	read_blocking "$@" <&${fd}
}

mapfile_write() {
	local -; set +x
	[ $# -ge 1 ] || eargs mapfile_write handle [data]
	local handle="$1"
	local ret

	if [ $# -eq 1 ]; then
		ret=0
		_mapfile_write_from_stdin "$@" || ret="$?"
		return "${ret}"
	fi
	_mapfile_write "$@"
}

_mapfile_write_from_stdin() {
	[ $# -eq 1 ] || eargs _mapfile_write_from_stdin handle
	local data

	data="$(cat)"
	_mapfile_write "$@" "${data}"
}

_mapfile_write() {
	[ $# -eq 2 ] || eargs mapfile_write handle data
	local handle="$1"
	shift
	local fd

	if [ "${handle}" != "${_mapfile_handle}" ]; then
		err 1 "mapfile_write: Handle '${handle}' is not open, '${_mapfile_handle}' is"
	fi
	hash_get mapfile_fd "${handle}" fd || fd=8
	echo "$@" >&${fd}
}

mapfile_close() {
	local -; set +x
	[ $# -eq 1 ] || eargs mapfile_close handle
	local handle="$1"
	local fd _

	if [ "${handle}" != "${_mapfile_handle}" ]; then
		err 1 "mapfile_close: Handle '${handle}' is not open, '${_mapfile_handle}' is"
	fi
	# Only close fd that we opened.
	if ! hash_remove mapfile_fd "${handle}" _; then
		exec 8>&-
	fi
	unset _mapfile_handle
	hash_unset mapfile_file "${handle}"
}

mapfile_builtin() {
	return 1
}

mapfile_keeps_file_open_on_eof() {
	[ $# -eq 1 ] || eargs mapfile_keeps_file_open_on_eof handle
	return 1
}
else

mapfile_builtin() {
	return 0
}

mapfile_keeps_file_open_on_eof() {
	[ $# -eq 1 ] || eargs mapfile_keeps_file_open_on_eof handle
	return 0
}
fi

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
	case "${_file}" in
	-|\
	/dev/stdin|\
	/dev/fd/0)	_hkey="$*" ;;
	*)		_hkey="${_file}" ;;
	esac

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

# Alias for mapfile_read_loop "/dev/stdin" vars...
mapfile_read_loop_redir() {
	[ $# -ge 1 ] || eargs mapfile_read_loop_redir vars

	mapfile_read_loop "/dev/fd/0" "$@"
}

# Basically an optimized loop of mapfile_read_loop_redir, or read_file
mapfile_cat() {
	local -; set +x
	[ $# -ge 0 ] || eargs mapfile_cat [-u] file...
	local  _handle ret _line _file ret flag
	local nflag lines
	local IFS

	if ! mapfile_builtin; then
		ret=0
		cat "$@" || ret="$?"
		return "${ret}"
	fi
	nflag=
	while getopts "n" flag; do
		case "${flag}" in
		n)
			nflag=1
			;;
		esac
		shift $((OPTIND-1))
	done
	if [ $# -eq 0 ]; then
		# Read from stdin
		set -- "-"
	fi
	ret=0
	lines=0
	for _file in "$@"; do
		case "${_file}" in
		-) _file="/dev/fd/0" ;;
		esac
		if mapfile _handle "${_file}" "re"; then
			while IFS= mapfile_read "${_handle}" _line; do
				lines=$((lines + 1))
				case "${nflag}" in
				"") ;;
				*) printf "%6d\t" "${lines}" ;;
				esac
				echo "${_line}"
			done
			mapfile_close "${_handle}"
		else
			ret="$?"
		fi
	done
	return "${ret}"
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
	mapfile "${handle_var_return}" "${mm_tmpfile}" "we+" || ret="$?"
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
	local -; set +x
	local extra="$1"
	local MSG_NESTED_STDERR prefix
	shift 1

	set_pipefail

	{
		{
			MSG_NESTED_STDERR=1
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
	local prefixpipe prefixpid ret
	local prefix MSG_NESTED_STDERR
	local - errexit

	prefixpipe=$(mktemp -ut prefix_stderr.pipe)
	mkfifo "${prefixpipe}"
	if [ "${USE_TIMESTAMP:-1}" -eq 1 ] && \
	    command -v timestamp >/dev/null; then
		# Let timestamp handle showing the proper time.
		prefix="$(NO_ELAPSED_IN_MSG=1 msg_warn "${extra}:" 2>&1)"
		TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
		    timestamp -1 "${prefix}" \
		    -P "poudriere: ${PROC_TITLE} (prefix_stderr)" \
		    < "${prefixpipe}" >&2 &
	else
		(
			set +x
			setproctitle "${PROC_TITLE} (prefix_stderr)"
			while mapfile_read_loop_redir line; do
				msg_warn "${extra}: ${line}"
			done
		) < ${prefixpipe} &
	fi
	prefixpid=$!
	exec 4>&2
	exec 2> "${prefixpipe}"
	unlink "${prefixpipe}"

	MSG_NESTED_STDERR=1
	ret=0
	case $- in *e*) errexit=1; set +e ;; *) errexit=0 ;; esac
	"$@"
	ret=$?
	[ ${errexit} -eq 1 ] && set -e

	exec 2>&4 4>&-
	timed_wait_and_kill 5 ${prefixpid} 2>/dev/null || :
	_wait ${prefixpid} || :

	return ${ret}
}

prefix_stdout() {
	local extra="$1"
	shift 1
	local prefixpipe prefixpid ret
	local prefix MSG_NESTED
	local - errexit

	prefixpipe=$(mktemp -ut prefix_stdout.pipe)
	mkfifo "${prefixpipe}"
	if [ "${USE_TIMESTAMP:-1}" -eq 1 ] && \
	    command -v timestamp >/dev/null; then
		# Let timestamp handle showing the proper time.
		prefix="$(NO_ELAPSED_IN_MSG=1 msg "${extra}:")"
		TIME_START="${TIME_START_JOB:-${TIME_START:-0}}" \
		    timestamp -1 "${prefix}" \
		    -P "poudriere: ${PROC_TITLE} (prefix_stdout)" \
		    < "${prefixpipe}" &
	else
		(
			set +x
			setproctitle "${PROC_TITLE} (prefix_stdout)"
			while mapfile_read_loop_redir line; do
				msg "${extra}: ${line}"
			done
		) < ${prefixpipe} &
	fi
	prefixpid=$!
	exec 3>&1
	exec > "${prefixpipe}"
	unlink "${prefixpipe}"

	MSG_NESTED=1
	ret=0
	case $- in *e*) errexit=1; set +e ;; *) errexit=0 ;; esac
	"$@"
	ret=$?
	[ ${errexit} -eq 1 ] && set -e

	exec 1>&3 3>&-
	timed_wait_and_kill 5 ${prefixpid} 2>/dev/null || :
	_wait ${prefixpid} || :

	return ${ret}
}

prefix_output() {
	local extra="$1"
	local prefix_stdout prefix_stderr prefixpipe_stdout prefixpipe_stderr
	local ret MSG_NESTED MSG_NESTED_STDERR
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
	    timestamp \
	    -1 "${prefix_stdout}" -o "${prefixpipe_stdout}" \
	    -2 "${prefix_stderr}" -e "${prefixpipe_stderr}" \
	    -P "poudriere: ${PROC_TITLE} (prefix_output)" \
	    &

	prefixpid=$!
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
	[ ${errexit} -eq 1 ] && set -e

	exec 1>&3 3>&- 2>&4 4>&-
	timed_wait_and_kill 5 ${prefixpid} 2>/dev/null || :
	_wait ${prefixpid} || :

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

	if [ -n "${_var_return}" ]; then
		setvar "${_var_return}" "${res_sec}.${res_nsec}"
	else
		echo "${res_sec}.${res_nsec}"
	fi
}

calculate_duration() {
	[ $# -eq 2 ] || eargs calculate_duration var_return elapsed
	local var_return="$1"
	local _elapsed="$2"
	local seconds minutes hours _duration

	seconds="$((_elapsed % 60))"
	minutes="$(((_elapsed / 60) % 60))"
	hours="$((_elapsed / 3600))"

	_duration=$(printf "%02d:%02d:%02d" ${hours} ${minutes} ${seconds})

	setvar "${var_return}" "${_duration}"
}

_write_atomic() {
	local -; set +x
	[ $# -eq 2 ] || eargs _write_atomic cmp destfile "< content"
	local cmp="$1"
	local dest="$2"
	local tmpfile_handle tmpfile ret

	TMPDIR="${dest%/*}" mapfile_mktemp tmpfile_handle tmpfile \
	    -ut ".tmp-${dest##*/}" ||
	    err $? "write_atomic unable to create tmpfile in ${dest%/*}"
	ret=0
	mapfile_write "${tmpfile_handle}" || ret="$?"
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

	_write_atomic 1 "${dest}" || return
}

write_atomic() {
	local -; set +x
	[ $# -eq 1 ] || eargs write_atomic destfile "< content"
	local dest="$1"

	_write_atomic 0 "${dest}" || return
}

# Place environment requirements on entering a function
# Using VALUE of __null requires a variable is NOT SET
# Using VALUE of "" requires a variable is SET but BLANK
# Using VAR! negates the value comparison (__null is SET, "" is SET+NOT EMPTY)
required_env() {
	local -; set +x
	[ $# -ge 3 ] || eargs required_env function VAR VALUE VAR... VALUE...
	local function="$1"
	local var expected_value actual_value ret neg

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
			;;
		esac
		getvar "${var}" actual_value || actual_value=__null
		# Special case: SET and not blank is wanted
		if [ "${neg}" = "!" ] && [ -z "${expected_value}" ]; then
			case "${actual_value}" in
			__null|"") ;;
			*) continue ;;
			esac
			expected_value="empty or __null"
		elif [ "${actual_value}" ${neg}= "${expected_value}" ]; then
			continue
		fi
		ret=$((ret + 1))
		msg_error "entered ${function}() with wrong environment: expected ${var} ${neg}= '${expected_value}' actual: '${actual_value}'"
	done
	if [ "${ret}" -ne 0 ]; then
		exit ${EX_SOFTWARE}
	fi
}

if ! type getpid >/dev/null 2>&1; then
# $$ is not correct in subshells.
getpid() {
	sh -c 'echo $PPID'
}
fi

# Export handling is different in builtin vs external
if [ "$(type mktemp)" = "mktemp is a shell builtin" ]; then
	MKTEMP_BUILTIN=1
fi
_mktemp() {
	local -; set +x
	local _mktemp_var_return="$1"
	shift
	local TMPDIR ret _mktemp_tmpfile

	if [ -z "${TMPDIR-}" ]; then
		if [ -n "${MASTERMNT}" -a ${STATUS} -eq 1 ]; then
			TMPDIR="${MNT_DATADIR}/tmp"
			[ -d "${TMPDIR}" ] || unset TMPDIR
		else
			TMPDIR="${POUDRIERE_TMPDIR}"
		fi
	fi

	ret=0
	if [ -n "${MKTEMP_BUILTIN-}" ]; then
		# No export needed here since TMPDIR is set above in scope.
		builtin _mktemp "${_mktemp_var_return}" "$@" || ret="$?"
		return "${ret}"
	fi

	export TMPDIR
	_mktemp_tmpfile="$(command mktemp "$@")" || ret="$?"
	setvar "${_mktemp_var_return}" "${_mktemp_tmpfile}"
	return "${ret}"
}
