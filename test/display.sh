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

display_setup "%%%ds %%-%ds %%-%ds" "-k1,1n"
display_add "JID" "IP Address" "vnet_num"
display_add "189" "" 0
display_add "188" "" 0
display_add "187" "" 0
display_add "150" "10.2.1.4,127.0.1.4" 0
display_add "99" "10.2.1.3,127.0.1.3" 0
display_add "87" "192.168.2.38" 0
display_add "85" "192.168.2.52" 0
outfile=$(mktemp -t outfile)
display_output > "${outfile}"
expected=$(mktemp -t expected)
cat > "${expected}" <<-EOF
JID IP Address         vnet_num
 85 192.168.2.52       0       
 87 192.168.2.38       0       
 99 10.2.1.3,127.0.1.3 0       
150 10.2.1.4,127.0.1.4 0       
187                    0       
188                    0       
189                    0       
EOF
assert_file "${expected}" "${outfile}"
