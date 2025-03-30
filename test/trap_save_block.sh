set -e
. ./common.sh
set +e

trap - INT
trap - EXIT
trap - PIPE
trap - TERM

builtin=0
if [ "$(type trap_push 2>/dev/null)" = "trap_push is a shell builtin" ]; then
	builtin=1
fi

_assert_traps() {
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
	assert "${expectedn}" "${n}" \
	    "${extra}: trap count does not match actual"
}
alias assert_traps='stack_lineinfo _assert_traps '

# Older /bin/sh (before r275766 and r275346) did not qoute assignments
# always, so our expected "trap -- 'gotint=1' INT" may come out as
# "trap -- gotint=1 INT".  Check for which version it is first.
trap - INT
trap -- 'gothup=1' HUP
trap -- 'gotint=1' INT
sh_quotes_assignments=0
while read -r line; do
	case "${line}" in
		*"'gotint=1'"*) sh_quotes_assignments=1 ;;
	esac
done <<-EOF
$(trap)
EOF
if [ ${sh_quotes_assignments} -eq 1 ]; then
	orig_intrap="'gotint=1'"
	orig_huprap="'gothup=1'"
else
	orig_intrap="gotint=1"
	orig_huprap="gothup=1"
fi

ORIGINAL=$(mktemp -ut trap_save)
cat > "${ORIGINAL}" <<-EOF
trap -- ${orig_huprap} HUP
trap -- ${orig_intrap} INT
trap -- '' TERM
EOF
if [ ${sh_quotes_assignments} -eq 1 ]; then
cat >> "${ORIGINAL}" <<'EOF'
# This chaos is to ensure that trap_push and trap_pop don't execute anything
# in the trap since an eval is required.  It's also testing all of the
# various quoting needs.
trap -- $'var="gotusr1"; evalled_usr1=1; [ -z $dokill ] && `kill -9 $$`; setvar "${var}" \'1\'' USR1
EOF
fi

while read -r line; do
	eval ${line}
done < "${ORIGINAL}"

# Verify our traps match expections
assert_traps "${ORIGINAL}" "initial traps should match"

{
	echo "Save - INT"
	trap
	EXPECTED_0=$(mktemp -ut trap_save)
	awk '$NF != "INT"' "${ORIGINAL}" > "${EXPECTED_0}"
	n=0
	while trap_save_block tmp INT; do
		trap
		assert_traps "${EXPECTED_0}" "saved 0 traps should match"
		n=$((n + 1))
		trap foo INT
	done
	assert 1 "${n}" "should loop once"
	assert "null" "${tmp-null}" "tmp cookie should be null"

	# Verify our traps were restored
	assert_traps "${ORIGINAL}" "restored traps should match"
}

{
	echo "Save - HUP INT"
	trap
	EXPECTED_0=$(mktemp -ut trap_save)
	awk '$NF != "INT" && $NF != "HUP"' "${ORIGINAL}" > "${EXPECTED_0}"
	n=0
	while trap_save_block tmp INT HUP; do
		trap
		assert_traps "${EXPECTED_0}" "saved 0 traps should match"
		n=$((n + 1))
		trap foo INT
		trap bar HUP
	done
	assert 1 "${n}" "should loop once"
	assert "null" "${tmp-null}" "tmp cookie should be null"

	# Verify our traps were restored
	assert_traps "${ORIGINAL}" "restored traps should match"
}

assert_traps "${ORIGINAL}" "restored traps should match"
trap '' EXIT
trap '' HUP
trap '' INT
trap '' TERM

rm -rf "${ORIGINAL}" "${EXPECTED_0}"
