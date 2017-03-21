#! /bin/sh

. $(realpath $(dirname $0))/common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/shared_hash.sh
. ${SCRIPTPREFIX}/include/cache.sh

USE_CACHE_CALL=1

MASTERMNT=$(mktemp -d)

_lookup_key() {
	[ $# -ge 2 ] || eargs _lookup_key var_return func [args]
	local var_return="$1"
	local func="$2"
	shift 2
	local encoded

	encode_args encoded "$@"
	setvar "${var_return}" "${func}-${encoded}"
}

real_func() {
	msg_warn "in real_func $# $@"
	local lookup lookup_key

	_lookup_key lookup_key "real_func" "$@"
	shash_get lookupcnt "${lookup_key}" lookup || lookup=0
	lookup=$((lookup + 1))
	shash_set lookupcnt "${lookup_key}" ${lookup}

	echo "$# $@"
}

real_func_sv() {
	msg_warn "in real_func_sv $# $@"
	local var_return="$1"
	shift
	local lookup lookup_key

	_lookup_key lookup_key "real_func_sv" "$@"
	shash_get lookupcnt "${lookup_key}" lookup || lookup=0
	lookup=$((lookup + 1))
	shash_set lookupcnt "${lookup_key}" ${lookup}

	setvar "${var_return}" "$# $@"
}

real_func_sv_2() {
	msg_warn "in real_func_sv_2 $# $@"
	local data="$1"
	local var_return="$2"
	local lookup lookup_key

	_lookup_key lookup_key "real_func_sv_2" "${data}"
	shash_get lookupcnt "${lookup_key}" lookup || lookup=0
	lookup=$((lookup + 1))
	shash_set lookupcnt "${lookup_key}" ${lookup}

	setvar "${var_return}" "1 ${data}"
}

get_lookup_cnt() {
	[ $# -ge 2 ] || eargs get_lookup_cnt var_return func [args]
	local var_return="$1"
	local func="$2"
	shift 2
	local key _lookup

	_lookup_key key "${func}" "$@"
	shash_get lookupcnt "${key}" _lookup || _lookup=0
	setvar "${var_return}" "${_lookup}"
}

echo "Working on ${MASTERMNT}"
SHASH_VAR_PATH="${MASTERMNT}"

# Simple test with 1 argument
{
	# First lookup, will call into the real function
	lookup=0
	value=
	cache_call value real_func "1"
	assert 0 $? "real_func 1 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func 1 argcnt"
	assert "1" "${value}" "real_func 1 value"
	get_lookup_cnt lookup real_func "1"
	assert 0 $? "lookupcnt real_func-1"
	assert 1 ${lookup} "real_func 1 lookup count"

	# Second lookup, should not call into the function
	value=
	cache_call value real_func "1"
	assert 0 $? "real_func 1 return status 2"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func 1 argcnt 2"
	assert "1" "${value}" "real_func 1 value 2"
	get_lookup_cnt lookup real_func "1"
	assert 0 $? "lookupcnt real_func-1 2"
	assert 1 ${lookup} "real_func 1 lookup count 2"
}

# More complex argument test
{
	# First lookup, will call into the real function
	lookup=0
	get_lookup_cnt lookup real_func "1" "2.0" "3 4"
	value=
	cache_call value real_func "1" "2.0" "3 4"
	assert 0 $? "real_func 1 2.0 '3 4' return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 3 "${argcnt}" "real_func 1 2.0 '3 4' argcnt"
	assert "1 2.0 3 4" "${value}" "real_func 1 2.0 '3 4' value"
	get_lookup_cnt lookup real_func "1" "2.0" "3 4"
	assert 0 $? "lookupcnt real_func-1 2.0 '3 4'"
	assert 1 ${lookup} "real_func 1 2.0 '3 4' lookup count"

	# Second lookup, should not call into the function
	value=
	cache_call value real_func "1" "2.0" "3 4"
	assert 0 $? "real_func 1 2.0 '3 4' return status 2"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 3 "${argcnt}" "real_func 1 2.0 '3 4' argcnt 2"
	assert "1 2.0 3 4" "${value}" "real_func 1 2.0 '3 4' value 2"
	get_lookup_cnt lookup real_func "1" "2.0" "3 4"
	assert 0 $? "lookupcnt real_func-1 2.0 '3 4' 2"
	assert 1 ${lookup} "real_func 1 2.0 '3 4' lookup count 2"

	# Manually call the function with the first data to force the
	# counter up for later tests to ensure the new data find count 0
	# and not 1 (as already cached).
	real_func "1" "2.0" "3 4" >/dev/null
	assert 0 $? "actual real_func 1 2.0 '3 4' return status"
	get_lookup_cnt lookup real_func "1" "2.0" "3 4"
	assert 2 ${lookup} "actual real_func 1 2.0 '3 4' lookup count"

	# Third lookup with trailing empty argument
	lookup=0
	value=
	cache_call value real_func "1" "2.0" "3" "4" ""
	assert 0 $? "real_func 1 2.0 3 4 _ return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 5 "${argcnt}" "real_func 1 2.0 3 4 _ argcnt"
	assert "1 2.0 3 4 " "${value}" "real_func 1 2.0 3 4 _ value"
	get_lookup_cnt lookup real_func "1" "2.0" "3" "4" ""
	assert 0 $? "lookupcnt real_func-1 2.0 3 4 _"
	assert 1 ${lookup} "real_func 1 2.0 3 4 _ lookup count"

	# Fouth lookup with similar data as first but last is split into 2,
	# should be unique.

	lookup=0
	value=
	cache_call value real_func "1" "2.0" "3" "4"
	assert 0 $? "real_func 1 2.0 3 4 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 4 "${argcnt}" "real_func 1 2.0 3 4 argcnt"
	assert "1 2.0 3 4" "${value}" "real_func 1 2.0 3 4 value"
	get_lookup_cnt lookup real_func "1" "2.0" "3" "4"
	assert 0 $? "lookupcnt real_func-1 2.0 3 4"
	assert 1 ${lookup} "real_func 1 2.0 3 4 lookup count"

	# Fifth lookup with similar data as the last

	lookup=0
	value=
	cache_call value real_func "1" "2.0" "3 " "4"
	assert 0 $? "real_func 1 2.0 3_ 4 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 4 "${argcnt}" "real_func 1 2.0 3_ 4 argcnt"
	assert "1 2.0 3  4" "${value}" "real_func 1 2.0 3_ 4 value"
	get_lookup_cnt lookup real_func "1" "2.0" "3 " "4"
	assert 0 $? "lookupcnt real_func-1 2.0 3_ 4"
	assert 1 ${lookup} "real_func 1 2.0 3_ 4 lookup count"
}

# Test a lookup with a function with uses setvar rather than stdout for results.
{
	# First lookup, will call into the real function
	lookup=0
	value=
	cache_call_sv value real_func_sv sv_value "1"
	assert 0 $? "real_func_sv 1 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func_sv 1 argcnt"
	assert "1" "${value}" "real_func_sv 1 value"
	get_lookup_cnt lookup real_func_sv "1"
	assert 0 $? "lookupcnt real_func_sv-1"
	assert 1 ${lookup} "real_func_sv 1 lookup count"

	# Second lookup, should not call into the function
	value=
	cache_call_sv value real_func_sv sv_value "1"
	assert 0 $? "real_func_sv 1 return status 2"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func_sv 1 argcnt 2"
	assert "1" "${value}" "real_func_sv 1 value 2"
	get_lookup_cnt lookup real_func_sv "1"
	assert 0 $? "lookupcnt real_func_sv-1 2"
	assert 1 ${lookup} "real_func_sv 1 lookup count 2"
}

# Test a lookup with a function with uses setvar rather than stdout for results,
# but with return var not in first place.
{
	# First lookup, will call into the real function
	lookup=0
	value=
	cache_call_sv value real_func_sv_2 "1" sv_value
	assert 0 $? "real_func_sv_2 1 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func_sv_2 1 argcnt"
	assert "1" "${value}" "real_func_sv_2 1 value"
	get_lookup_cnt lookup real_func_sv_2 "1"
	assert 0 $? "lookupcnt real_func_sv_2-1"
	assert 1 ${lookup} "real_func_sv_2 1 lookup count"

	# Second lookup, should not call into the function
	value=
	cache_call_sv value real_func_sv_2 "1" sv_value
	assert 0 $? "real_func_sv_2 1 return status 2"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func_sv_2 1 argcnt 2"
	assert "1" "${value}" "real_func_sv_2 1 value 2"
	get_lookup_cnt lookup real_func_sv_2 "1"
	assert 0 $? "lookupcnt real_func_sv_2-1 2"
	assert 1 ${lookup} "real_func_sv_2 1 lookup count 2"
}

# Invalidation test
{
	# First lookup, will call into the real function
	lookup=0
	value=
	cache_call value real_func "1"
	assert 0 $? "real_func 1 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func 1 argcnt"
	assert "1" "${value}" "real_func 1 value"
	get_lookup_cnt lookup real_func "1"
	assert 0 $? "lookupcnt real_func-1"
	assert 1 ${lookup} "real_func 1 lookup count"

	# now invalidate the cache and ensure it is looked up again.
	cache_invalidate real_func "1"

	cache_call value real_func "1"
	assert 0 $? "real_func 1 return status - invalidated"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func 1 argcnt - invalidated"
	assert "1" "${value}" "real_func 1 value - invalidated"
	get_lookup_cnt lookup real_func "1"
	assert 0 $? "lookupcnt real_func-1 - invalidated"
	assert 2 ${lookup} "real_func 1 lookup count - invalidated"
}

# Forced cached set test
{
	# First lookup, will call into the real function
	lookup=0
	value=
	cache_call value real_func "5"
	assert 0 $? "real_func 5 return status"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func 5 argcnt"
	assert "5" "${value}" "real_func 5 value"
	get_lookup_cnt lookup real_func "5"
	assert 0 $? "lookupcnt real_func-5"
	assert 1 ${lookup} "real_func 5 lookup count"

	# now change the value in the cache ("1 " is due to real_func
	# adding in its $#)
	cache_set "1 SET-5-SET" real_func "5"

	cache_call value real_func "5"
	assert 0 $? "real_func 5 return status - set"
	argcnt=${value%% *}
	value="${value#[0-9] }"
	assert 1 "${argcnt}" "real_func 5 argcnt - set"
	assert "SET-5-SET" "${value}" "real_func 5 value - set"
	get_lookup_cnt lookup real_func "5"
	assert 0 $? "lookupcnt real_func-5 - set"
	# Should not have called the real func
	assert 1 ${lookup} "real_func 5 lookup count - set"
}


rm -rf "${MASTERMNT}"
exit 0
