#! /bin/sh

. $(realpath $(dirname $0))/common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh

assert_list() {
	local expected="${1}"
	local reason="${2}"
	local have_tmp=$(mktemp -t assert_list)
	local expected_tmp=$(mktemp -t assert_list)
	local ret=0

	echo "${LIST}" | tr ' ' '\n' | sort | sed -e '/^$/d' > "${have_tmp}"
	echo "${expected}" | tr ' ' '\n' | sort | sed -e '/^$/d' > \
	    "${expected_tmp}"
	cmp -s "${have_tmp}" "${expected_tmp}" || ret=$?
	[ ${ret} -ne 0 ] && comm "${have_tmp}" "${expected_tmp}" >&2

	rm -f "${have_tmp}" "${expected_tmp}"
	assert 0 "${ret}" "${reason} - Have: '${LIST}' Expected: '${expected}'"
}

LIST=
assert_list "" "Empty list expected"

list_add LIST 01
assert_list "01" "Expected 01"

list_add LIST 01
assert_list "01" "Expected 01 after ading duplicate"
# Don't really care about excess spaces
assert_list " 01    " "Expected 01, spaces"

list_remove LIST 01
assert_list "" "Empty list expected after removing 01"

list_add LIST 02
assert_list "02" "Expected 02"

list_add LIST 01
assert_list "02 01" "Expected 01 02"

list_add LIST 03
assert_list "02 01 03" "Expected 01 02 03"

# Remove the middle
list_remove LIST 01
assert_list "02 03" "02 03 expected after removing 01"

# Remove something not there.  This one used to be surprisingly problematic.
list_remove LIST 99
assert_list "02 03" "02 03 expected after removing nonexistent 99"

# Add back in a duplicate and remove it
list_add LIST 03
assert_list "02 03" "Expected 02 03 after adding 03 duplicate"

list_remove LIST 03
assert_list "02" "02 expected after removing 03"

# Reset so we can test removing the left
LIST=
list_add LIST 01
list_add LIST 02
list_add LIST 03
assert_list "01 02 03" "Expected 01 02 03 - left"

list_remove LIST 01
assert_list "02 03" "Expected 02 03 - left"

list_remove LIST 02
assert_list "03" "Expected 03 - left"

list_remove LIST 03
assert_list "" "Expected empty - left"

# Reset so we can test removing the right
LIST=
list_add LIST 01
list_add LIST 02
list_add LIST 03
assert_list "01 02 03" "Expected 01 02 03 - right"

list_remove LIST 03
assert_list "01 02" "Expected 01 02 - right"

list_remove LIST 02
assert_list "01" "Expected 01 - right"

list_remove LIST 02
assert_list "01" "Expected 01 - right"

list_remove LIST 01
assert_list "" "Expected blank - right"

# Test eval parsing
LIST=
list_add LIST 01
list_add LIST "02;"
list_add LIST "03"
list_remove LIST 03
assert_list "01 02;" "Parsing error"

# Test subst parsing
LIST=
list_add LIST 01
list_add LIST "0*"
assert_list "01 0*"
list_add LIST "/*"
assert_list "01 0* /*"

list_remove LIST "0*"
assert_list "01 /*"

list_remove LIST "/*"
assert_list "01"

# Test removing of duplicates causing duplicate items of unremoved
LIST="01 02 03 04 03 "
list_remove LIST 03
assert_list "01 02 03 04"
