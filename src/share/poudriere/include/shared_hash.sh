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

: ${SHASH_VAR_NAME_SUB_BADCHARS:=" /"}
: ${SHASH_VAR_PATH:=${TMPDIR:-/tmp}}
: ${SHASH_VAR_PREFIX=$$}
add_relpath_var SHASH_VAR_PATH || err "Failed to add SHASH_VAR_PATH to relpaths"

_shash_var_name() {
	local var="${1}"

	# Replace SHASH_VAR_NAME_SUB_BADCHARS matches with _
	_gsub_badchars "${var}" "${SHASH_VAR_NAME_SUB_BADCHARS}" _shash_var_name
}

_shash_varkey_file() {
	local varkey="${1}%${2}"
	local _shash_var_name

	_shash_var_name "${varkey}"
	_shash_varkey_file="${SHASH_VAR_PATH}/${SHASH_VAR_PREFIX}${_shash_var_name}"
}

shash_get() {
	local -; set +x
	[ $# -ne 3 ] && eargs shash_get var key var_return
	local var="$1"
	local key="$2"
	local var_return="$3"
	local _shash_varkey_file _f _sh_value _sh_values
	local ret handle IFS

	ret=0
	_sh_values=
	_shash_varkey_file "${var}" "${key}"
	# This assumes globbing works
	for _f in ${_shash_varkey_file}; do
		case "${_f}" in
		# no file found
		*"*"*)
			ret=1
			break
			;;
		esac
		if ! mapfile -qF handle "${_f}" "r"; then
			ret=1
			continue
		fi
		if IFS= mapfile_read "${handle}" _sh_value; then
			_sh_values="${_sh_values:+${_sh_values} }${_sh_value}"
		fi
		mapfile_close "${handle}" || :
	done

	setvar "${var_return}" "${_sh_values}"

	return ${ret}
}

shash_exists() {
	local -; set +x
	[ $# -ne 2 ] && eargs shash_exists var key
	local var="$1"
	local key="$2"
	local _shash_varkey_file _f

	_shash_varkey_file "${var}" "${key}"
	# This assumes globbing works
	for _f in ${_shash_varkey_file}; do
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
	set) echo "${value}" ;;
	esac > "${_shash_varkey_file}"
}

shash_read() {
	local -; set +x
	[ $# -eq 2 ] || eargs shash_read var key
	local var="$1"
	local key="$2"
	local _shash_varkey_file handle line

	_shash_varkey_file "${var}" "${key}"
	mapfile_cat_file -q "${_shash_varkey_file}"
}

shash_read_mapfile() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_read_mapfile var key mapfile_handle_var
	local var="$1"
	local key="$2"
	local mapfile_handle_var="$3"
	local _shash_varkey_file

	_shash_varkey_file "${var}" "${key}"
	mapfile -q "${mapfile_handle_var}" "${_shash_varkey_file}" "re"
}

shash_write() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || eargs shash_write [-T] var key
	local flag Tflag
	local OPTIND=1

	Tflag=
	while getopts "T" flag; do
		case "${flag}" in
		T)
			Tflag=1
			;;
		*) err "${EX_USAGE}" "write_atomic: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -eq 2 ] || eargs shash_write [-T] var key
	local var="$1"
	local key="$2"
	local _shash_varkey_file

	_shash_varkey_file "${var}" "${key}"
	write_atomic ${Tflag:+-T} "${_shash_varkey_file}"
}

shash_remove_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs shash_remove_var var
	local var="$1"
	local _shash_varkey_file

	# This assumes globbing works
	_shash_var_name "${var}%*"
	find -x "${SHASH_VAR_PATH:?}" \
	    -name "${SHASH_VAR_PREFIX}${_shash_var_name}" \
	    -delete || :
}

shash_remove() {
	local -; set +x
	[ $# -ne 3 ] && eargs shash_remove var key var_return
	local var="$1"
	local key="$2"
	local ret

	ret=0
	shash_get "$@" || ret=$?
	if [ ${ret} -eq 0 ]; then
		shash_unset "${var}" "${key}"
	fi
	return ${ret}
}

shash_unset() {
	local -; set +x
	[ $# -eq 2 ] || eargs shash_unset var key
	local var="$1"
	local key="$2"
	local _shash_varkey_file

	_shash_varkey_file "${var}" "${key}"
	# Unquoted for globbing
	rm -f ${_shash_varkey_file}
}
