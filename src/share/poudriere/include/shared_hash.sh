# Copyright (c) 2016 Bryan Drewery <bdrewery@FreeBSD.org>
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

# Requires util.sh and hash.sh
# shellcheck shell=ksh

: "${SHASH_VAR_NAME_SUB_BADCHARS:=" /"}"
: "${SHASH_VAR_PATH:="${TMPDIR:-/tmp}"}"
: "${SHASH_VAR_PREFIX="$$"}"
add_relpath_var SHASH_VAR_PATH || err "Failed to add SHASH_VAR_PATH to relpaths"

_shash_var_name() {
	[ $# -eq 2 ] || eargs _shash_var_name var key
	local _svn_var="${1}"
	local _svn_key="${2}"
	local _svn_varkey

	_svn_varkey="${_svn_var:?}%${_svn_key:?}"
	# Replace SHASH_VAR_NAME_SUB_BADCHARS matches with _
	_gsub_badchars "${_svn_varkey:?}" \
	    "${SHASH_VAR_NAME_SUB_BADCHARS:?}" _shash_var_name
}

_shash_var_path() {
	_shash_var_path="${SHASH_VAR_PATH:+${SHASH_VAR_PATH}/}${SHASH_VAR_PREFIX}"
}

_shash_varkey_file() {
	[ $# -eq 2 ] || eargs _shash_varkey_file var key
	local _svf_var="${1}"
	local _svf_key="${2}"
	local _shash_var_name _shash_var_path

	_shash_var_name "${_svf_var:?}" "${_svf_key:?}"
	_shash_var_path
	_shash_varkey_file="${_shash_var_path}${_shash_var_name:?}"
}

shash_get() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_get var key var_return
	local sg_var="$1"
	local sg_key="$2"
	local sg_var_return="$3"
	local _shash_var_name _shash_var_path _f _sh_value _sh_values
	local sg_ret sg_rret
	local -

	sg_ret=0
	_sh_values=
	_shash_var_path
	_shash_var_name "${sg_var:?}" "${sg_key:?}"
	# Ensure globbing is on
	set +o noglob
	# Don't glob the path.
	for _f in "${_shash_var_path}"${_shash_var_name:?}; do
		case "${_shash_var_path}${_shash_var_name:?}" in
		*"*"*|*"["*|*"?"*)
			case "${_f:?}" in
			"${_shash_var_path}${_shash_var_name:?}")
				# No file found
				sg_ret=1
				break
			esac
			;;
		*)
			;;
		esac
		sg_rret=0
		case "${sg_var_return:?}" in
		-)
			readlines_file -- "${_f:?}" - || sg_rret=$?
			;;
		*)
			readlines_file -- "${_f:?}" _sh_value || sg_rret=$?
			;;
		esac
		case "${sg_rret}" in
		0)
			case "${sg_var_return:?}" in
			-) ;;
			*) _sh_values="${_sh_values:+${_sh_values} }${_sh_value}" ;;
			esac
			;;
		*)
			sg_ret="${sg_rret}"
			continue
			;;
		esac
	done
	case "${sg_var_return}" in
	-) ;;
	*) setvar "${sg_var_return}" "${_sh_values}" || return ;;
	esac
	return "${sg_ret}"
}

shash_exists() {
	local -; set +x
	[ $# -eq 2 ] || eargs shash_exists var key
	local var="$1"
	local key="$2"
	local _shash_var_path _shash_var_name _f

	_shash_var_path
	_shash_var_name "${var:?}" "${key:?}"
	# Ensure globbing is on
	set +o noglob
	# Don't glob the path.
	for _f in "${_shash_var_path}"${_shash_var_name}; do
		case "${_shash_var_path}${_shash_var_name:?}" in
		*"*"*|*"["*|*"?"*)
			case "${_f:?}" in
			"${_shash_var_path}${_shash_var_name:?}")
				# No file found
				return 1
			esac
			;;
		*)
			;;
		esac
		if [ ! -r "${_f:?}" ]; then
			return 1
		fi
		return 0
	done
	return 1
}

shash_set() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_set var key value
	local var="$1"
	local key="$2"
	local value="$3"
	local _shash_varkey_file

	_shash_varkey_file "${var}" "${key}"
	case "${value+set}" in
	set)
		write_atomic -- "${_shash_varkey_file:?}" "${value}" || return
		;;
	*)
		: > "${_shash_varkey_file:?}" || return
		;;
	esac
}

shash_read() {
	local -; set +x
	[ $# -eq 2 ] || eargs shash_read var key
	local sr_var="$1"
	local sr_key="$2"

	shash_get "${sr_var}" "${sr_key}" -
}

shash_read_mapfile() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_read_mapfile var key mapfile_handle_var
	local srm_var="$1"
	local srm_key="$2"
	local srm_mapfile_hadle_var="$3"
	local _shash_varkey_file

	_shash_varkey_file "${srm_var}" "${srm_key}"
	# shellcheck disable=SC2034
	mapfile -q "${srm_mapfile_hadle_var}" "${_shash_varkey_file}" "re"
}

shash_write() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs shash_write '[-T]' var key
	local flag Tflag
	local OPTIND=1

	Tflag=
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "shash_write: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -eq 2 ] || eargs shash_write '[-T]' var key
	local var="$1"
	local key="$2"
	local _shash_varkey_file

	_shash_varkey_file "${var}" "${key}"
	write_atomic ${Tflag:+-T} -- "${_shash_varkey_file:?}"
}

shash_remove_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs shash_remove_var var
	local srv_var="$1"

	# This assumes globbing works for shash.
	shash_unset "${srv_var:?}" "*"
}

shash_remove() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_remove var key var_return
	local sr_var="$1"
	local sr_key="$2"
	local sr_ret

	sr_ret=0
	shash_get "$@" || sr_ret="$?"
	case "${sr_ret}" in
	0)
		shash_unset "${sr_var}" "${sr_key}"
		;;
	esac
	return "${sr_ret}"
}

shash_unset() {
	local -; set +x
	[ $# -eq 2 ] || eargs shash_unset var key
	local var="$1"
	local key="$2"
	local _shash_var_path _shash_var_name

	_shash_var_path
	_shash_var_name "${var:?}" "${key:?}"
	# Ensure globbing is on
	set +o noglob
	# Don't glob the path.
	# shellcheck disable=SC2086
	rm -f -- "${_shash_var_path}"${_shash_var_name:?}
}
