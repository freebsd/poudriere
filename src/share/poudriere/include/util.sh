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
	setproctitle() { }
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
	while [ $# -gt 0 ]; do
		_args="${_args}${_args:+${ENCODE_SEP}}${1}"
		[ $# -eq 1 -a -z "$1" ] && lastempty=1
		shift
	done
	# If the string ends in ENCODE_SEP then add another to
	# fix 'set' later eating it.
	[ ${lastempty} -eq 1 ] && _args="${_args}${_args:+${ENCODE_SEP}}"

	setvar "${var_return}" "${_args}"
}

# Decode data from encode_args
# Usage: eval $(decode_args data_var_name)
decode_args() {
	local -; set +x -f
	[ $# -eq 1 ] || eargs decode_args encoded_args_var
	local encoded_args_var="$1"

	# oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
	echo "oldIFS=\"\${IFS}\"; IFS=\"\${ENCODE_SEP}\"; set -- \${${encoded_args_var}}; IFS=\"\${oldIFS}\"; unset oldIFS"
}

if ! type issetvar >/dev/null 2>&1; then
issetvar() {
	[ $# -eq 1 ] || eargs issetvar
	local var="$1"
	local _evalue

	eval "_evalue=\${${var}-__null}"

	[ "${_evalue}" != "__null" ]
}
fi

if ! type getvar >/dev/null 2>&1; then
getvar() {
	[ $# -eq 1 -o $# -eq 2 ] || eargs getvar var [var_return]
	local var="$1"
	local var_return="$2"
	local ret _evalue

	eval "_evalue=\${${var}-__null}"

	if [ "${_evalue}" = "__null" ]; then
		_evalue=
		ret=1
	else
		ret=0
	fi

	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_evalue}"
	else
		echo "${_evalue}"
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
	local common

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
	_rel_found=0
	while [ "${other#${common%/}/}" = "${other}" -a -n "${common}" ]; do
		common="${common%/*}"
		_rel_found=$((_rel_found + 1))
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
	[ -z "${value}" ] && return 0
	if [ -n "${value##/*}" ]; then
		# It was relative.
		_relpath "${oldroot}/${value}" "${newroot}" "${varname}"
	else
		# It was absolute.
		_relpath "${value}" "${newroot}" "${varname}"
	fi
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
	_CRITSNEST=$((${_CRITSNEST} - 1))
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
		kill -INT $(sh -c 'echo ${PPID}')
	fi
	if [ ${_crit_caught_term} -eq 1 -a ${_CRITSNEST} -eq 0 ]; then
		_crit_caught_term=0
		kill -TERM $(sh -c 'echo ${PPID}')
	fi
}
fi

# Read a file into the given variable.
read_file() {
	[ $# -eq 2 ] || eargs read_file var_return file
	local var_return="$1"
	local file="$2"
	local _data _line newline maph
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
		if mapfile maph "${file}" "r"; then
			if [ -n "${var_return}" ]; then
				while IFS= mapfile_read "${maph}" _line; do
					_data="${_data:+${_data}${newline}}${_line}"
					_read_file_lines_read=$((${_read_file_lines_read} + 1))
				done
				setvar "${var_return}" "${_data}"
			else
				while IFS= mapfile_read "${maph}" _line; do
					_read_file_lines_read=$((${_read_file_lines_read} + 1))
				done
			fi
			mapfile_close "${maph}"
		else
			_ret=$?
		fi

		return ${_ret}
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
			_read_file_lines_read=$((${_read_file_lines_read} + 1))
		done < "${file}" || _ret=$?
	fi

	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_data}"
	fi

	return ${_ret}
}

# Read a file until 0 status is found. Partial reads not accepted.
read_line() {
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
		reads=$((${reads} + 1))
	done
	[ ${reads} -eq ${max_reads} ] && _ret=1

	setvar "${var_return}" "${_line}"

	return ${_ret}
}

# SIGINFO traps won't abort the read.
read_blocking() {
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
	[ $# -ge 1 ] || eargs read_blocking_line read_args
	local _ret

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
		{ { read "$@" || resread=$?; } < "${fifo}" || resopen=$?; } \
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
		err 1 "write_pipe FAILED to send to ${fifo} (ret: ${ret}): $@"
	fi

	return ${ret}
}

if [ "$(type mapfile 2>/dev/null)" != "mapfile is a shell builtin" ]; then
mapfile() {
	[ $# -eq 2 -o $# -eq 3 ] || eargs mapfile handle_name file modes
	local handle_name="$1"
	local _file="$2"

	[ -e "${_file}" ] || return 1
	[ -p "${file}" ] && return 32
	setvar "${handle_name}" "${_file}"
}

mapfile_read() {
	[ $# -ge 2 ] || eargs mapfile_read handle output_var ...
	local handle="$1"
	shift
	local -; set -f

	if [ -p "${handle}" ]; then
		read_pipe "${handle}" "$@"
	elif [ -f "${handle}" ]; then
		read_blocking_line "$@" < "${handle}"
	elif [ "${handle}" = "/dev/fd/0" ]; then
		# mapfile_read_loop_redir pipe
		read "$@"
	else
		return 1
	fi
}

mapfile_write() {
	[ $# -eq 2 ] || eargs mapfile_write handle data
	local handle="$1"
	shift

	if [ -p "${handle}" ]; then
		nopipe write_pipe "${handle}" "$@"
	else
		echo "$@" > "${handle}"
	fi
}

mapfile_close() {
	[ $# -eq 1 ] || eargs mapfile_close handle
	local handle="$1"

	[ -e "${handle}" ] || return 1
	# Nothing to do for non-builtin.
}

mapfile_builtin() {
	return 1
}

mapfile_read_loop() {
	[ $# -ge 2 ] || eargs mapfile_read_loop file vars
	local _file="$1"
	shift
	local ret

	# Low effort compatibility attempt
	if [ -z "${_mapfile_read_loop}" ]; then
		exec 8< "${_file}"
		_mapfile_read_loop="${_file}"
	elif [ "${_mapfile_read_loop}" != "${_file}" ]; then
		err 1 "mapfile_read_loop only supports 1 file at a time without builtin"
	fi
	ret=0
	read "$@" <&8 || ret=$?
	if [ ${ret} -ne 0 ]; then
		exec 8>&-
		unset _mapfile_read_loop
	fi
	return ${ret}
}

mapfile_read_loop_redir() {
	read "$@"
}
else

mapfile_builtin() {
	return 0
}

mapfile_read_loop() {
	[ $# -ge 2 ] || eargs mapfile_read_loop file vars
	local _file="$1"
	shift
	local _handle

	if ! hash_get mapfile_handle "${_file}" _handle; then
		mapfile _handle "${_file}" "re"
		hash_set mapfile_handle "${_file}" "${_handle}"
	fi

	if mapfile_read "${_handle}" "$@"; then
		return 0
	else
		local ret=$?
		mapfile_close "${_handle}"
		hash_unset mapfile_handle "${_file}"
		return ${ret}
	fi
}

# This syntax works with non-builtin mapfile but requires a redirection.
# It also supports pipes more naturally than mapfile_read_loop().
mapfile_read_loop_redir() {
	[ $# -ge 1 ] || eargs mapfile_read_loop_redir vars
	local _hkey _handle

	# Store the handle based on the params passed in since it is
	# using an anonymous handle on stdin - which if nested in a
	# pipe would reuse the already-opened handle from the parent
	# pipe.
	# Getting a nested call is simple when mapfile_read_loop_redir()
	# is used in abstractions that pipe to each other.
	# It would be great to have a PIPELEVEL or SHPID rather than this.
	local _hkey="$*"

	if ! hash_get mapfile_handle "${_hkey}" _handle; then
		# Read from stdin
		mapfile _handle "/dev/fd/0" "re"
		hash_set mapfile_handle "${_hkey}" "${_handle}"
	fi

	if mapfile_read "${_handle}" "$@"; then
		return 0
	else
		local ret=$?
		mapfile_close "${_handle}"
		hash_unset mapfile_handle "${_hkey}"
		return ${ret}
	fi
}
fi

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

	if ! [ "${USE_TIMESTAMP:-1}" -eq 1 ] && \
	    command -v timestamp >/dev/null; then
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
