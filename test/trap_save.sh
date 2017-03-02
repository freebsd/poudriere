#! /bin/sh

. common.sh
. ${SCRIPTPREFIX}/include/util.sh

assert_traps() {
	local expected_file="$1"
	local extra="$2"
	local IFS n expectedn

	# Load expected results into $1,$2,...,$n by line
	IFS=$'\n'
	expected="$(grep -v '^#' "${expected_file}")"
	set -- ${expected}
	expectedn=$#

	n=0
	# Compare line-by-line.  This assumes the ordering is stable.
	while read -r line; do
		# no traps
		[ -z "${line}" ] && break
		# comment
		[ -z "${line%#*}" ] && continue
		n=$((${n} + 1))
		assert "$1" "${line}" "${extra}: mismatch line ${n}"
		# go to next line of expected
		shift
	done <<-EOF
	$(trap)
	EOF
	assert ${expectedn} ${n} \
	    "${extra}: trap count does not match actual"
}

ORIGINAL=$(mktemp -ut trap_save)
cat > "${ORIGINAL}" <<'EOF'
trap -- 'gotint=1' INT
trap -- '' TERM
# This chaos is to ensure that trap_push and trap_pop don't execute anything
# in the trap since an eval is required.  It's also testing all of the
# various quoting needs.
trap -- $'var="gotusr1"; evalled_usr1=1; [ -z $dokill ] && `kill -9 $$`; setvar "${var}" \'1\'' USR1
EOF

while read -r line; do
	eval ${line}
done < "${ORIGINAL}"

# Verify our traps match expections
assert_traps "${ORIGINAL}" "initial traps should match"

# Verify the USR1 trap works, it will be tried later too
gotusr1=0
dokill=0
kill -USR1 $$
unset dokill
assert 1 ${gotusr1} "initial USR1 trap should work"

# Save 0 traps and ensure the rest match
echo "Save 0 - INFO"
trap
EXPECTED_0=$(mktemp -ut trap_save)
cp "${ORIGINAL}" "${EXPECTED_0}"
trap_push INFO oact_info
assert 0 $? "trap_push INFO"
assert "-" "${oact_info}" "INFO had no trap so should be -"
assert_traps "${EXPECTED_0}" "saved 0 traps should match"

# Save 1 trap and ensure the rest match
echo "Save 1 - INT"
trap
EXPECTED_1=$(mktemp -ut trap_save)
awk '$NF != "INT"' "${ORIGINAL}" > "${EXPECTED_1}"
trap_push INT oact_int
assert 0 $? "trap_push INT"
assert "'gotint=1'" "${oact_int}" "INT trap should match"
assert_traps "${EXPECTED_1}" "saved 1 traps should match"

# Save 2 trap and ensure the rest match
echo "Save 2 - USR1"
trap
EXPECTED_2=$(mktemp -ut trap_save)
awk '$NF != "INT" && $NF != "USR1"' "${ORIGINAL}" > "${EXPECTED_2}"
evalled_usr1=0
trap_push USR1 oact_usr1
assert 0 $? "trap_push USR1"
assert 0 ${evalled_usr1} "trap_push USR1 should not have evalled it"
assert $'$\'var="gotusr1"; evalled_usr1=1; [ -z $dokill ] && `kill -9 $$`; setvar "${var}" \\\'1\\\'\'' "${oact_usr1}" "USR1 trap should match"
assert_traps "${EXPECTED_2}" "saved 2 traps should match"

# Save 3 trap and ensure the rest match
echo "Save 3 - TERM"
trap
EXPECTED_3=$(mktemp -ut trap_save)
awk '$NF != "INT" && $NF != "USR1" && $NF != "TERM"' "${ORIGINAL}" > "${EXPECTED_3}"
trap_push TERM oact_term
assert 0 $? "trap_push TERM"
assert "''" "${oact_term}" "TERM trap should match"
assert_traps "${EXPECTED_3}" "saved 3 traps should match"

# Traps should be empty now
assert_traps "/dev/null" "all saved traps should be empty"

# Now start restoring, but not in the same order

# First add some random bogus traps that will be replaced
CRITICAL=$(mktemp -ut trap_save)
# In real code these would all be '', but toss it up for tests.
cat > "${CRITICAL}" <<'EOF'
trap -- 'echo ignore' TERM
trap -- '' INFO
trap -- 'echo ignore' USR1
EOF

while read -r line; do
	eval ${line}
done < "${CRITICAL}"

# Verify our traps match expections
assert_traps "${CRITICAL}" "critical traps should match"


# Restore 0 trap and ensure the rest match
echo "Restore 0 - bad INFO"
EXPECTED_0=$(mktemp -ut trap_save)
cp "${CRITICAL}" "${EXPECTED_0}"
trap_pop INFO ""
assert 1 $? "trap_pop INFO blank"
trap
assert_traps "${EXPECTED_0}" "restore 0 traps should match"

# Restore 1 trap and ensure the rest match
echo "Restore 1 - INFO"
EXPECTED_1=$(mktemp -ut trap_save)
# Must construct manually due to ordering
cat > "${EXPECTED_1}" <<'EOF'
trap -- 'echo ignore' TERM
trap -- 'echo ignore' USR1
EOF
# While the original had no INFO, a push did give '-' for SIG_DFL.
# Our critical trap is '' though.
trap_pop INFO "${oact_info}"
assert 0 $? "trap_pop INFO"
trap
assert_traps "${EXPECTED_1}" "restore 1 traps should match"

# Restore 2 trap and ensure the rest match
echo "Restore 2 - USR1"
EXPECTED_2=$(mktemp -ut trap_save)
# Must construct manually due to ordering
cat > "${EXPECTED_2}" <<'EOF'
trap -- 'echo ignore' TERM
trap -- $'var="gotusr1"; evalled_usr1=1; [ -z $dokill ] && `kill -9 $$`; setvar "${var}" \'1\'' USR1
EOF
evalled_usr1=0
trap_pop USR1 "${oact_usr1}"
assert 0 $? "trap_pop USR1"
assert 0 ${evalled_usr1} "trap_pop USR1 should not have evalled it"
trap
assert_traps "${EXPECTED_2}" "restore 2 traps should match"

# Restore 3 trap and ensure the rest match
echo "Restore 3 - TERM"
EXPECTED_3=$(mktemp -ut trap_save)
# Must construct manually due to ordering
cat > "${EXPECTED_3}" <<'EOF'
trap -- '' TERM
trap -- $'var="gotusr1"; evalled_usr1=1; [ -z $dokill ] && `kill -9 $$`; setvar "${var}" \'1\'' USR1
EOF
trap_pop TERM "${oact_term}"
assert 0 $? "trap_pop TERM"
trap
assert_traps "${EXPECTED_3}" "restore 3 traps should match"

# Restore 4 trap and ensure the rest match
echo "Restore 4 - INT"
EXPECTED_4=$(mktemp -ut trap_save)
# Must construct manually due to ordering
cp "${ORIGINAL}" "${EXPECTED_4}"
trap_pop INT "${oact_int}"
assert 0 $? "trap_pop INT"
trap
assert_traps "${EXPECTED_4}" "restore 4 traps should match"

# Now that everything is restored, test that they work
gotusr1=0
dokill=0
kill -USR1 $$
unset dokill
assert 1 ${gotusr1} "restored USR1 trap should work"

trap '' EXIT
trap '' INT
trap '' TERM

rm -rf "${ORIGINAL}" "${CRITICAL}" \
    "${EXPECTED_0}" "${EXPECTED_1}" "${EXPECTED_2}" "${EXPECTED_3}" \
    "${EXPECTED_4}"
