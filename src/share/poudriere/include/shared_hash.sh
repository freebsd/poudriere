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

: ${SHASH_VAR_NAME_SUB_GLOB:="[ /]"}
: ${SHASH_VAR_PATH:=${TMPDIR:-/tmp}}

_shash_var_name() {
	local var="${1}"
	local _gsub

	# Replace anything not SHASH_VAR_NAME_SUB_GLOB with _
	_gsub "${var}" "${SHASH_VAR_NAME_SUB_GLOB}" _
	_shash_var_name=${_gsub}
}

_shash_varkey_file() {
	local varkey="${1}%${2}"

	_shash_var_name "${varkey}"
	_shash_varkey_file="${SHASH_VAR_PATH}/${_shash_var_name}"
}

shash_get() {
	local -; set +x
	[ $# -ne 3 ] && eargs shash_get var key var_return
	local var="$1"
	local key="$2"
	local var_return="$3"
	local _shash_varkey_file _value
	local ret

	ret=1
	if [ "${USE_CACHED}" = "yes" ]; then
		# XXX: This is ignoring var
		# XXX: This only supports origin-pkgname and pkgname-origin
		[ "${var}" = "pkgname-origin" ] || \
		    [ "${var}" = "origin-pkgname" ] || \
		    err 1 "shash_get with USE_CACHED does not support ${var}"
		_value="$(cachec -s "/${MASTERNAME}" "get ${key}")"
		if [ -n "${_value}" ]; then
			ret=0
		fi
	else
		_shash_varkey_file "${var}" "${key}"
		if [ -f "${_shash_varkey_file}" ]; then
			if read_line _value "${_shash_varkey_file}"; then
				ret=0
			fi
		fi
	fi

	setvar "${var_return}" "${_value}"

	return ${ret}
}

shash_set() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_set var key value
	local var="$1"
	local key="$2"
	local value="$3"
	local _shash_varkey_file

	if [ "${USE_CACHED}" = "yes" ]; then
		# XXX: This is ignoring var
		# XXX: This only supports origin-pkgname and pkgname-origin
		[ "${var}" = "pkgname-origin" ] || \
		    [ "${var}" = "origin-pkgname" ] || \
		    err 1 "shash_set with USE_CACHED does not support ${var}"
		cachec -s "/${MASTERNAME}" "set ${key} ${value}"
	else
		_shash_varkey_file "${var}" "${key}"
		echo "${value}" > "${_shash_varkey_file}"
	fi
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

	if [ "${USE_CACHED}" = "yes" ]; then
		err 1 "shash_unset unimplemented for USE_CACHED"
		cachec -s /${MASTERNAME} "unset ${var}-${key}"
	else
		_shash_varkey_file "${var}" "${key}"
		rm -f "${_shash_varkey_file}"
	fi
}
