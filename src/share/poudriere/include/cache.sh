# Copyright (c) 2017 Bryan Drewery <bdrewery@FreeBSD.org>
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

# Requires shared_hash

cache_invalidate() {
	local -; set +x
	[ $# -ge 1 ] || eargs cache_invalidate function [params]
	local function="$1"
	shift
	local var key

	# USE_CACHE_CALL not checked here as it may have been disabled
	# since having a value cached.  Still respect an invalidation
	# request.

	var="cached-${function}"
	encode_args key "$@"
	msg_dev "cache_invalidate: Invalidating ${function}($@)"
	shash_unset "${var}" "${key}" || :
}

_cache_set() {
	local -; set +x
	[ $# -eq 3 ] || eargs _cache_set var key value
	local var="${1}"
	local key="${2}"
	local value="${3}"

	# The main difference between these is that -vvv (dev) will see
	# the shash_set error while normally it will be hidden.  It can
	# happen with SIGINT races and is non-fatal.
	if [ ${VERBOSE} -gt 2 ]; then
		shash_set "${var}" "${key}" "${value}" || \
		    msg_dev "_cache_set: Failed to set value for V: ${var} K: ${key}"
	else
		shash_set "${var}" "${key}" "${value}" 2>/dev/null || :
	fi
}

cache_set() {
	local -; set +x
	[ $# -ge 2 ] || eargs cache_set value function [params]
	local value="$1"
	local function="$2"
	shift 2
	local var key

	[ ${USE_CACHE_CALL:-0} -eq 0 ] && return 0

	var="cached-${function}"
	encode_args key "$@"
	msg_dev "cache_set: Caching value for ${function}($@)"
	_cache_set "${var}" "${key}" "${value}"
}

# Execute a function and store its results in the cache.  Use the
# cached value after that.
# Usage: cache_call result_var function args
cache_call() {
	local -; set +x
	[ $# -ge 2 ] || eargs cache_call var_return function [params]
	local var_return="$1"
	local function="$2"
	shift 2
	local -; set +e # Need to capture error without ||
	local var key _value ret

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	var="cached-${function}"
	encode_args key "$@"

	if [ ${USE_CACHE_CALL:-0} -eq 0 ] || \
	    ! shash_get "${var}" "${key}" "${var_return}"; then
		msg_dev "cache_call: Fetching ${function}($@)"
		_value=$(${function} "$@")
		ret=$?
		_cache_set "${var}" "${key}" "${_value}"
		setvar "${var_return}" "${_value}"
	else
		msg_dev "cache_call: Using cached ${function}($@)"
		ret=0
		# Value set by shash_get already
	fi
	return ${ret}
}

# Same as cache_call but it is for functions that use
# setvar/var_return for returning their results rather than stdout.
# Usage: cache_call_sv result_var function sv_value args
# The sv_value should be used where the result would normally be
# from the function.
cache_call_sv() {
	local -; set +x
	[ $# -ge 2 ] || eargs cache_call_sv var_return function [params] [sv_value for return var]
	local var_return="$1"
	local function="$2"
	shift 2
	local -; set +e # Need to capture error without ||
	local var key sv_value ret

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	var="cached-${function}"
	encode_args key "$@"

	if [ ${USE_CACHE_CALL:-0} -eq 0 ] || \
	    ! shash_get "${var}" "${key}" "${var_return}"; then
		msg_dev "cache_call_sv: Fetching ${function}($@)"
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
		msg_dev "cache_call_sv: Using cached ${function}($@)"
		ret=0
		# Value set by shash_get already
	fi
	return ${ret}
}
