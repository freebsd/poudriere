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
	local -; set +x
	[ $# -eq 1 ] || eargs decode_args encoded_args_var
	local encoded_args_var="$1"

	# IFS="${ENCODE_SEP}"
	# set -- ${data}
	# unset IFS

	echo "IFS=\"\${ENCODE_SEP}\"; set -- \${${encoded_args_var}}; unset IFS"
}

# Given 2 directories, make both of them relative to their
# common directory.
# $1 = _relpath_common = common directory
# $2 = _relpath_common_dir1 = dir1 relative to common
# $3 = _relpath_common_dir2 = dir2 relative to common
_relpath_common() {
	local -; set +x
	[ $# -eq 2 ] || eargs _relpath_common dir1 dir2
	local dir1=$(realpath -q "$1" || echo "${1}")
	local dir2=$(realpath -q "$2" || echo "${2}")
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
	local -; set +x
	[ $# -eq 2 ] || eargs _relpath dir1 dir2
	local dir1="$1"
	local dir2="$2"
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

	_relpath="${newpath}"
}

# See _relpath
relpath() {
	local -; set +x
	[ $# -eq 2 ] || eargs relpath dir1 dir2
	local dir1="$1"
	local dir2="$2"
	local _relpath

	_relpath "${dir1}" "${dir2}"
	echo "${_relpath}"
}

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
		eval trap -- ${_trap} ${signal} || :
	else
		return 1
	fi
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
