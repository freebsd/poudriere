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
	local _svn_var="${1}"

	# Replace SHASH_VAR_NAME_SUB_BADCHARS matches with _
	_gsub_badchars "${_svn_var}" "${SHASH_VAR_NAME_SUB_BADCHARS}" _shash_var_name
}

_shash_varkey_file() {
	local _svf_varkey="${1}%${2}"
	local _shash_var_name

	_shash_var_name "${_svf_varkey:?}"
	_shash_varkey_file="${SHASH_VAR_PATH}/${SHASH_VAR_PREFIX}${_shash_var_name:?}"
}

shash_get() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_get var key var_return
	local sg_var="$1"
	local sg_key="$2"
	local sg_var_return="$3"
	local _shash_varkey_file _f _sh_value _sh_values
	local sg_ret sg_rret

	sg_ret=0
	_sh_values=
	_shash_varkey_file "${sg_var}" "${sg_key}"
	set +o noglob
	for _f in ${_shash_varkey_file:?}; do
		set -o noglob
		case "${_shash_varkey_file:?}" in
		*"*"*|*"["*|*"?"*)
			case "${_f:?}" in
			"${_shash_varkey_file:?}")
				# No file found
				sg_ret=1
				break
			esac
			;;
		*)
			;;
		esac
		sg_rret=0
		readlines_file "${_f:?}" _sh_value || sg_rret=$?
		case "${sg_rret}" in
		0)
			_sh_values="${_sh_values:+${_sh_values} }${_sh_value}"
			;;
		*)
			sg_ret="${sg_rret}"
			continue
			;;
		esac
	done
	set -o noglob

	setvar "${sg_var_return}" "${_sh_values}" || return
	return "${sg_ret}"
}

shash_exists() {
	local -; set +x
	[ $# -eq 2 ] || eargs shash_exists var key
	local var="$1"
	local key="$2"
	local _shash_varkey_file _f

	_shash_varkey_file "${var}" "${key}"
	set +o noglob
	for _f in ${_shash_varkey_file:?}; do
		set -o noglob
		case "${_f}" in
		*"*"*) break ;; # no file found
		esac
		[ -r "${_f}" ] || break
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
		write_atomic "${_shash_varkey_file:?}" "${value}" || return
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
	local _shash_varkey_file

	_shash_varkey_file "${sr_var}" "${sr_key}"
	mapfile_cat_file -q "${_shash_varkey_file}"
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
	write_atomic ${Tflag:+-T} "${_shash_varkey_file:?}"
}

shash_remove_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs shash_remove_var var
	local srv_var="$1"
	local _shash_var_name

	# This assumes globbing works for shash, which it does for now
	# due to using find.
	_shash_var_name "${srv_var}%*"
	find -x "${SHASH_VAR_PATH:?}" \
	    -name "${SHASH_VAR_PREFIX}${_shash_var_name}" \
	    -delete || :
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
	local _shash_varkey_file

	_shash_varkey_file "${var}" "${key}"
	set +o noglob
	# shellcheck disable=SC2086
	rm -f ${_shash_varkey_file}
}
