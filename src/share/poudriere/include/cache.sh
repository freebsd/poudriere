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

: ${USE_CACHE_CALL:=0}

cache_invalidate() {
	local -; set +x
	[ "$#" -ge 1 ] || eargs cache_invalidate [-K key] function [params]
	local flag Kflag
	local OPTIND=1

	Kflag=
	while getopts "K:" flag; do
		case "${flag}" in
		K)
			# If key is empty just use a (.)
			Kflag="${OPTARG:-.}"
			;;
		*) err "${EX_USAGE}" "cache_invalidate: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 1 ] || eargs cache_invalidate [-K key] function [params]
	local function="$1"
	shift
	local var key

	# USE_CACHE_CALL not checked here as it may have been disabled
	# since having a value cached.  Still respect an invalidation
	# request.

	var="cached-${function}"
	encode_args key "${Kflag:-$@}"

	msg_dev "cache_invalidate: Invalidating ${function}($*)"
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
	[ "$#" -ge 2 ] || eargs cache_set [-K key] value function [params]
	local flag Kflag
	local OPTIND=1

	Kflag=
	while getopts "K:" flag; do
		case "${flag}" in
		K)
			# If key is empty just use a (.)
			Kflag="${OPTARG:-.}"
			;;
		*) err "${EX_USAGE}" "cache_set: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 2 ] || eargs cache_set [-K key] value function [params]
	local value="$1"
	local function="$2"
	shift 2
	local var key

	if [ "${USE_CACHE_CALL}" -eq 0 ]; then
		return 0
	fi

	var="cached-${function}"
	encode_args key "${Kflag:-$@}"
	msg_dev "cache_set: Caching value for ${function}($*)"
	_cache_set "${var}" "${key}" "${value}"
}

_cache_get() {
	local -; set +x
	[ "$#" -eq 3 ] || eargs _cache_get var key var_return
	local cg_var="$1"
	local cg_key="$2"
	local cg_var_return="$3"

	shash_get "${cg_var}" "${cg_key}" "${cg_var_return}"
}

_cache_read() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs _cache_read var key
	local cr_var="$1"
	local cr_key="$2"

	shash_read "${cr_var}" "${cr_key}"
}

_cache_write() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs _cache_write var key
	local cw_var="$1"
	local cw_key="$2"

	shash_write "${cw_var}" "${cw_key}"
}

_cache_tee() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs _cache_tee var key
	local cw_var="$1"
	local cw_key="$2"

	shash_write -T "${cw_var}" "${cw_key}"
}

_cache_exists() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs _cache_exists var key
	local ce_var="$1"
	local ce_key="$2"

	shash_exists "${ce_var}" "${ce_key}"
}

# Execute a function and store its results in the cache.  Use the
# cached value after that.
# Usage: cache_call result_var function args
cache_call() {
	local -; set +x
	[ "$#" -ge 2 ] || eargs cache_call [-K key] "<var_return | ->" function [params]
	local flag Kflag
	local OPTIND=1

	Kflag=
	while getopts "K:" flag; do
		case "${flag}" in
		K)
			# If key is empty just use a (.)
			Kflag="${OPTARG:-.}"
			;;
		*) err "${EX_USAGE}" "cache_call: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 2 ] || eargs cache_call [-K key] "<var_return | ->" function [params]
	local var_return="$1"
	local function="$2"
	shift 2
	local -; set +e # Need to capture error without ||
	local cc_var cc_key _cc_value ret

	case "${var_return}" in
	-)
		_cache_call_pipe ${Kflag:+-K "${Kflag}"} "${function}" "$@"
		return
		;;
	esac

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	cc_var="cached-${function}"
	encode_args cc_key "${Kflag:-$@}"

	if [ "${USE_CACHE_CALL}" -eq 0 ] ||
	    ! _cache_get "${cc_var}" "${cc_key}" "${var_return}"; then
		msg_dev "cache_call: Fetching ${function}($*)"
		_cc_value=$(${function} "$@")
		ret=$?
		if [ "${USE_CACHE_CALL}" -eq 1 ]; then
			_cache_set "${cc_var}" "${cc_key}" "${_cc_value}"
		fi
		setvar "${var_return}" "${_cc_value}"
	else
		msg_dev "cache_call: Using cached ${function}($*)"
		ret=0
		# Value set by _cache_get already
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
	[ "$#" -ge 2 ] || eargs cache_call_sv [-K key] var_return function [params] [sv_value for return var]
	local flag Kflag
	local OPTIND=1

	Kflag=
	while getopts "K:" flag; do
		case "${flag}" in
		K)
			# If key is empty just use a (.)
			Kflag="${OPTARG:-.}"
			;;
		*) err "${EX_USAGE}" "cache_call_sv: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 2 ] || eargs cache_call_sv [-K key] var_return function [params] [sv_value for return var]
	local var_return="$1"
	local function="$2"
	shift 2
	local -; set +e # Need to capture error without ||
	local cc_var cc_key sv_value ret

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	cc_var="cached-${function}"
	encode_args cc_key "${Kflag:-$@}"

	if [ "${USE_CACHE_CALL}" -eq 0 ] ||
	    ! _cache_get "${cc_var}" "${cc_key}" "${var_return}"; then
		msg_dev "cache_call_sv: Fetching ${function}($*)"
		sv_value=sv__null
		${function} "$@"
		ret=$?
		case "${ret}.${sv_value}" in
		"0.sv__null")
			# Function did not properly set sv_value,
			# so ensure ret is >0
			ret=76
			;;
		esac
		if [ "${USE_CACHE_CALL}" -eq 1 ]; then
			_cache_set "${cc_var}" "${cc_key}" "${sv_value}"
		fi
		setvar "${var_return}" "${sv_value}"
	else
		msg_dev "cache_call_sv: Using cached ${function}($*)"
		ret=0
		# Value set by _cache_get already
	fi
	return ${ret}
}

# Execute a function and store its results in the cache.  Use the
# cached value after that.
# Send output to stdout.
# Usage: cache_call function args
_cache_call_pipe() {
	local -; set +x
	[ "$#" -ge 1 ] || eargs _cache_call_pipe [-K key] function [params]
	local flag Kflag
	local OPTIND=1

	Kflag=
	while getopts "K:" flag; do
		case "${flag}" in
		K)
			# If key is empty just use a (.)
			Kflag="${OPTARG:-.}"
			;;
		*) err "${EX_USAGE}" "_cache_call_pipe: Invalid flag ${flag}" ;;
		esac
	done
	shift $((OPTIND-1))
	[ "$#" -ge 1 ] || eargs _cache_call_pipe [-K key] function [params]
	local function="$1"
	shift 1
	local -; set +e # Need to capture error without ||
	local ccp_var ccp_key ccp_value ccp_line ret
	local IFS

	# If the value is not already in the cache then
	# look it up and store the result in the cache.
	ccp_var="cached-${function}"
	encode_args ccp_key "${Kflag:-$@}"

	if [ "${USE_CACHE_CALL}" -eq 0 ]; then
		${function} "$@"
		return
	elif ! _cache_exists "${ccp_var}" "${ccp_key}"; then
		msg_dev "_cache_call_pipe: Fetching ${function}($*)"
		${function} "$@" | _cache_tee "${ccp_var}" "${ccp_key}"
		ret="$?"
	else
		msg_dev "_cache_call_pipe: Using cached ${function}($*)"
		ret=0
		# Value set by _cache_get already
		_cache_read "${ccp_var}" "${ccp_key}"
	fi
	return "${ret}"
}
