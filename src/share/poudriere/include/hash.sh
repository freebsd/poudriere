# Copyright (c) 2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

_hash_var_name() {
	# Replace all HASH_VAR_NAME_SUB_GLOB with _
	_gsub "_HASH_${1}_${2}" ${HASH_VAR_NAME_SUB_GLOB} _
	_hash_var_name=${_gsub}
}

hash_get() {
	[ $# -ne 3 ] && eargs hash_get var key var_return
	local var="$1"
	local key="$2"
	local var_return="$3"
	local hash_var_name value
	local ret

	_hash_var_name "${var}" "${key}"
	hash_var_name=${_hash_var_name}

	# Look value from cache
	eval "value=\${${hash_var_name}-__null}"

	if [ "${value}" = "__null" ]; then
		value=
		ret=1
	else
		ret=0
	fi

	setvar "${var_return}" "${value}"

	return ${ret}
}

hash_set() {
	[ $# -eq 3 ] || eargs hash_set var key value
	local var="$1"
	local key="$2"
	local value="$3"
	local hash_var_name

	_hash_var_name "${var}" "${key}"
	hash_var_name=${_hash_var_name}

	# Set value in cache
	setvar "${hash_var_name}" "${value}"
}

hash_unset() {
	[ $# -eq 2 ] || eargs hash_unset var key
	local var="$1"
	local key="$2"
	local hash_var_name

	_hash_var_name "${var}" "${key}"
	unset "${_hash_var_name}"
}
