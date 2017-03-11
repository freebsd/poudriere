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
: ${SHASH_VAR_PREFIX:=$$}

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
	_shash_varkey_file="${SHASH_VAR_PATH}/${SHASH_VAR_PREFIX}${_shash_var_name}"
}

shash_get() {
	local -; set +x
	[ $# -ne 3 ] && eargs shash_get var key var_return
	local var="$1"
	local key="$2"
	local var_return="$3"
	local _shash_varkey_file _f _value _values
	local ret

	ret=1
	_values=
	if [ "${USE_CACHED}" = "yes" ] && \
	    [ "${var}" = "pkgname-origin" -o "${var}" = "origin-pkgname" ]; then
		# XXX: This is ignoring var
		# XXX: This only supports origin-pkgname and pkgname-origin
		_values="$(cachec -s "/${MASTERNAME}" "get ${key}")"
		if [ -n "${_values}" ]; then
			ret=0
		fi
	else
		_shash_varkey_file "${var}" "${key}"
		# This assumes globbing works
		for _f in ${_shash_varkey_file}; do
			case "${_f}" in
			"*") break ;; # no file found
			esac
			if read_line _value "${_f}"; then
				_values="${_values}${_values:+ }${_value}"
				ret=0
			else
			fi
		done
	fi

	setvar "${var_return}" "${_values}"

	return ${ret}
}

shash_set() {
	local -; set +x
	[ $# -eq 3 ] || eargs shash_set var key value
	local var="$1"
	local key="$2"
	local value="$3"
	local _shash_varkey_file

	if [ "${USE_CACHED}" = "yes" ] && \
	    [ "${var}" = "pkgname-origin" -o "${var}" = "origin-pkgname" ]; then
		# XXX: This is ignoring var
		# XXX: This only supports origin-pkgname and pkgname-origin
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
		rm -f ${_shash_varkey_file}
	fi
}

# Execute a function and store its results in the cache.  Use the
# cached value after that.
# Usage: shash_get_cached result_var function args
shash_get_cached() {
	local -; set +x
	[ $# -ge 2 ] || eargs shash_get_cached var_return function [params]
	local var_return="$1"
	local function="$2"
	shift 2
	local -; set +e # Need to capture error without ||
	local var key _value ret

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	var="cached-${function}"
	encode_args key "$@"

	if [ ${SHASH_USE_CACHE:-0} -eq 0 ] || \
	    ! shash_get "${var}" "${key}" "${var_return}"; then
		msg_dev "shash_get_cached: Fetching ${function}($@)"
		_value=$(${function} "$@")
		ret=$?
		shash_set "${var}" "${key}" "${_value}"
		setvar "${var_return}" "${_value}"
	else
		msg_dev "shash_get_cached: Using cached ${function}($@)"
		ret=0
		# Value set by shash_get already
	fi
	return ${ret}
}

# Same as shash_get_cached but it is for functions that use
# setvar/var_return for returning their results rather than stdout.
# Usage: shash_get_cached_sv result_var function sv_value args
# The sv_value should be used where the result would normally be
# from the function.
shash_get_cached_sv() {
	local -; set +x
	[ $# -ge 2 ] || eargs shash_get_cached_sv var_return function [params] [sv_value for return var]
	local var_return="$1"
	local function="$2"
	shift 2
	local -; set +e # Need to capture error without ||
	local var key sv_value ret

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	var="cached-${function}"
	encode_args key "$@"

	if [ ${SHASH_USE_CACHE:-0} -eq 0 ] || \
	    ! shash_get "${var}" "${key}" "${var_return}"; then
		msg_dev "shash_get_cached_sv: Fetching ${function}($@)"
		sv_value=__null
		${function} "$@"
		ret=$?
		if [ "${sv_value}" = "__null" ] && [ ${ret} -eq 0 ]; then
			# Function did not properly set sv_value,
			# so ensure ret is >0
			ret=76
		fi
		shash_set "${var}" "${key}" "${sv_value}"
		setvar "${var_return}" "${sv_value}"
	else
		msg_dev "shash_get_cached_sv: Using cached ${function}($@)"
		ret=0
		# Value set by shash_get already
	fi
	return ${ret}
}
