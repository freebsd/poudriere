. common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/display.sh

_assert_file() {
	local lineinfo="$1"
	local expected="$2"
	local have="$3"
	local reason="$4"
	local ret=0

	cmp -s "${have}" "${expected}" || ret=$?

	reason="${reason:+${reason} -}
HAVE:
$(cat -vet "${have}")
EXPECTED:
$(cat -vet "${expected}")"
	rm -f "${have}" "${expected}"
	_assert "${lineinfo}" 0 "${ret}" "${reason}"
}
alias assert_file='_assert_file "$0:$LINENO"'

display_setup "%%-%ds %%-%ds" "-k2,2V -k1,1d"
display_add "Name" "Release"
display_add "blah" "11.2-RELEASE-p1"
display_add "blah" "10.0-RELEASE"
display_add "blah" "10.2-RELEASE"
display_add "blah" "10.2-RELEASE-p10"
display_add "blah2" "10.2-RELEASE-p1"
display_add "blah" "10.2-RELEASE-p1"
display_add "blah" "9.3-RELEASE-p10"
display_add "blah" "9.3-RELEASE-p1"
display_add "blah" "8.2-RELEASE-p1"
outfile=$(mktemp -t outfile)
display_output > "${outfile}"
expected=$(mktemp -t expected)
cat > "${expected}" <<-EOF
Name  Release         
blah  8.2-RELEASE-p1  
blah  9.3-RELEASE-p1  
blah  9.3-RELEASE-p10 
blah  10.0-RELEASE    
blah  10.2-RELEASE    
blah  10.2-RELEASE-p1 
blah2 10.2-RELEASE-p1 
blah  10.2-RELEASE-p10
blah  11.2-RELEASE-p1 
EOF
assert_file "${expected}" "${outfile}"
