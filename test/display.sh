. ./common.sh

{
	# Basic test
	display_setup "%%-%ds %%-%ds" "-k2,2V -k1,1d"
	display_add "Name 1" "Release"
	display_add "blah" "11.2-RELEASE-p1"
	display_add "blah" "10.0-RELEASE"
	display_add "blah 1" "10.2-RELEASE"
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
	Name 1 Release
	blah   8.2-RELEASE-p1
	blah   9.3-RELEASE-p1
	blah   9.3-RELEASE-p10
	blah   10.0-RELEASE
	blah 1 10.2-RELEASE
	blah   10.2-RELEASE-p1
	blah2  10.2-RELEASE-p1
	blah   10.2-RELEASE-p10
	blah   11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	# Basic test via filter path
	display_setup "%%-%ds %%-%ds" "-k2,2V -k1,1d"
	display_add "Name 1" "Release"
	display_add "blah" "11.2-RELEASE-p1"
	display_add "blah" "10.0-RELEASE"
	display_add "blah 1" "10.2-RELEASE"
	display_add "blah" "10.2-RELEASE-p10"
	display_add "blah2" "10.2-RELEASE-p1"
	display_add "blah" "10.2-RELEASE-p1"
	display_add "blah" "9.3-RELEASE-p10"
	display_add "blah" "9.3-RELEASE-p1"
	display_add "blah" "8.2-RELEASE-p1"
	outfile=$(mktemp -t outfile)
	display_output "Name 1" "Release" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name 1 Release
	blah   8.2-RELEASE-p1
	blah   9.3-RELEASE-p1
	blah   9.3-RELEASE-p10
	blah   10.0-RELEASE
	blah 1 10.2-RELEASE
	blah   10.2-RELEASE-p1
	blah2  10.2-RELEASE-p1
	blah   10.2-RELEASE-p10
	blah   11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	# Basic test
	old="${DISPLAY_USE_COLUMN}"
	DISPLAY_USE_COLUMN=1
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
	Name   Release
	blah   8.2-RELEASE-p1
	blah   9.3-RELEASE-p1
	blah   9.3-RELEASE-p10
	blah   10.0-RELEASE
	blah   10.2-RELEASE
	blah   10.2-RELEASE-p1
	blah2  10.2-RELEASE-p1
	blah   10.2-RELEASE-p10
	blah   11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
	DISPLAY_USE_COLUMN="${old}"
}

{
	# Basic test
	old="${DISPLAY_USE_COLUMN}"
	DISPLAY_USE_COLUMN=1
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
	display_output "Name" "Release" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name   Release
	blah   8.2-RELEASE-p1
	blah   9.3-RELEASE-p1
	blah   9.3-RELEASE-p10
	blah   10.0-RELEASE
	blah   10.2-RELEASE
	blah   10.2-RELEASE-p1
	blah2  10.2-RELEASE-p1
	blah   10.2-RELEASE-p10
	blah   11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
	DISPLAY_USE_COLUMN="${old}"
}

{
	# Basic test without trimming trailing field
	old="${DISPLAY_TRIM_TRAILING_FIELD}"
	DISPLAY_TRIM_TRAILING_FIELD=0
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
	DISPLAY_TRIM_TRAILING_FIELD="${old}"
}

{
	# Test quiet mode
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
	display_output -q > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
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
}

{
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
	# Test for blank and null params
	display_add "blah3"
	display_add "blah4" ""
	display_add "" "11-RELEASE"
	outfile=$(mktemp -t outfile)
	display_output > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name  Release
	blah3 
	blah4 
	blah  8.2-RELEASE-p1
	blah  9.3-RELEASE-p1
	blah  9.3-RELEASE-p10
	blah  10.0-RELEASE
	blah  10.2-RELEASE
	blah  10.2-RELEASE-p1
	blah2 10.2-RELEASE-p1
	blah  10.2-RELEASE-p10
	      11-RELEASE
	blah  11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
}

{
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
	display_output "Name" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name
	blah
	blah
	blah
	blah
	blah
	blah
	blah2
	blah
	blah
	EOF
	assert_file "${expected}" "${outfile}" "Filtered column"
}

{
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
	display_output "Release" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Release
	8.2-RELEASE-p1
	9.3-RELEASE-p1
	9.3-RELEASE-p10
	10.0-RELEASE
	10.2-RELEASE
	10.2-RELEASE-p1
	10.2-RELEASE-p1
	10.2-RELEASE-p10
	11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}" "Filtered column"
}

{
	display_setup "%%-%ds %%%ds" "-k2,2V -k1,1d"
	display_add "Name" "Memory"
	display_add "foo" "10"
	display_add "blah" "5"
	display_footer "" "15 G"
	outfile=$(mktemp -t outfile)
	display_output > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name Memory
	blah      5
	foo      10
	       15 G
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	# Test footer with dynamic
	display_setup "%%-%ds %%%ds" "-k2,2V -k1,1d"
	display_add "Name" "Memory"
	display_add "foo" "10"
	display_add "blah" "5"
	display_footer "" "15 G"
	outfile=$(mktemp -t outfile)
	display_output "Name" "Memory" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name Memory
	blah      5
	foo      10
	       15 G
	EOF
	assert_file "${expected}" "${outfile}" "dynamic with footer"
}

{
	display_setup "%%-%ds %%-%ds" "-k2,2V -k1,1d"
	display_add "Name" "Memory"
	display_add "foo" "10"
	display_add "blah" "5"
	display_footer "" "15 G"
	outfile=$(mktemp -t outfile)
	display_output > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name Memory
	blah 5
	foo  10
	     15 G
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	display_setup "%%-%ds %%-%ds %%-%ds" "-k2,2V -k1,1d"
	display_add "Name 1" "Mem" "Blah"
	display_add "foo bar" "10" "0"
	display_add "blah" "5" "0"
	display_footer "" "15 GiB" "0"
	outfile=$(mktemp -t outfile)
	display_output > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name 1  Mem    Blah
	blah    5      0
	foo bar 10     0
	        15 GiB 0
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	display_setup "%%-%ds %%-%ds" "-k2,2V -k1,1d"
	display_add "Name" "Release"
	display_add "" "11.2-RELEASE-p1"
	outfile=$(mktemp -t outfile)
	display_output > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	Name Release
	     11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	display_setup "%s %s" "-k2,2V -k1,1d"
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
	Name Release
	blah 8.2-RELEASE-p1
	blah 9.3-RELEASE-p1
	blah 9.3-RELEASE-p10
	blah 10.0-RELEASE
	blah 10.2-RELEASE
	blah 10.2-RELEASE-p1
	blah2 10.2-RELEASE-p1
	blah 10.2-RELEASE-p10
	blah 11.2-RELEASE-p1
	EOF
	assert_file "${expected}" "${outfile}"
}

{
	# Test no trailing spaces
	display_setup "%%-%ds %%s" "-k2,2V -k1,1d"
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
}

{
	# Test a case that was totally wrong due to quoting the first field
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
}

{
	# Test with dynamic formats
	display_setup "dynamic" "-k1,1n"
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
	85  192.168.2.52       0
	87  192.168.2.38       0
	99  10.2.1.3,127.0.1.3 0
	150 10.2.1.4,127.0.1.4 0
	187                    0
	188                    0
	189                    0
	EOF
	assert_file "${expected}" "${outfile}" "dynamic formats"
}

{
	# Test with dynamic formats with specified field format
	display_setup "dynamic" "-k1,1n"
	display_add "JID:%%%ds" "IP Address:%%%ds" "vnet_num"
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
	JID         IP Address vnet_num
	 85       192.168.2.52 0
	 87       192.168.2.38 0
	 99 10.2.1.3,127.0.1.3 0
	150 10.2.1.4,127.0.1.4 0
	187                    0
	188                    0
	189                    0
	EOF
	assert_file "${expected}" "${outfile}" "dynamic formats with specified field format"
}

{
	# Test filter/reorder
	display_setup "%%%ds %%-%ds %%-%ds" "-k1,1n"
	display_add "JID" "IP Address super long" "vnet_num"
	display_add "189" "" 0
	display_add "188" "" 0
	display_add "187" "" 0
	display_add "150" "10.2.1.4,127.0.1.4" 0
	display_add "99" "10.2.1.3,127.0.1.3" 0
	display_add "87" "192.168.2.38" 0
	display_add "85" "192.168.2.52" 0
	outfile=$(mktemp -t outfile)
	display_output "vnet_num" "IP Address" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	vnet_num IP Address super long
	0        192.168.2.52
	0        192.168.2.38
	0        10.2.1.3,127.0.1.3
	0        10.2.1.4,127.0.1.4
	0        
	0        
	0        
	EOF
	assert_file "${expected}" "${outfile}" "filtered/reordered column"
}

{
	# Test filter/reorder with quiet
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
	display_output -q "vnet_num" "IP Address" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	0        192.168.2.52
	0        192.168.2.38
	0        10.2.1.3,127.0.1.3
	0        10.2.1.4,127.0.1.4
	0        
	0        
	0        
	EOF
	assert_file "${expected}" "${outfile}" "filtered/reordered column + quiet"
}

{
	# Test filter/reorder
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
	display_output "vnet_num" "IP Address" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	vnet_num IP Address
	0        192.168.2.52
	0        192.168.2.38
	0        10.2.1.3,127.0.1.3
	0        10.2.1.4,127.0.1.4
	0        
	0        
	0        
	EOF
	assert_file "${expected}" "${outfile}" "filtered column"
}

{
	# Test with dynamic formats with filter/reorder
	display_setup "dynamic" "-k1,1n"
	display_add "JID" "IP Address" "vnet_num"
	display_add "189" "" 0
	display_add "188" "" 0
	display_add "187" "" 0
	display_add "150" "10.2.1.4,127.0.1.4" 0
	display_add "99" "10.2.1.3,127.0.1.3" 0
	display_add "87" "192.168.2.38" 0
	display_add "85" "192.168.2.52" 0
	outfile=$(mktemp -t outfile)
	display_output "JID" "vnet_num" "IP Address" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	JID vnet_num IP Address
	85  0        192.168.2.52
	87  0        192.168.2.38
	99  0        10.2.1.3,127.0.1.3
	150 0        10.2.1.4,127.0.1.4
	187 0        
	188 0        
	189 0        
	EOF
	assert_file "${expected}" "${outfile}" "dynamic formats with reordered cols"
}

{
	# Test with dynamic formats and filtered/reordered
	display_setup "dynamic" "-k1,1n"
	display_add "JID" "IP Address" "vnet_num"
	display_add "189" "" 0
	display_add "188" "" 0
	display_add "187" "" 0
	display_add "150" "10.2.1.4,127.0.1.4" 0
	display_add "99" "10.2.1.3,127.0.1.3" 0
	display_add "87" "192.168.2.38" 0
	display_add "85" "192.168.2.52" 0
	outfile=$(mktemp -t outfile)
	display_output "vnet_num" "IP Address" "JID" > "${outfile}"
	expected=$(mktemp -t expected)
	cat > "${expected}" <<-EOF
	vnet_num IP Address         JID
	0        192.168.2.52       85
	0        192.168.2.38       87
	0        10.2.1.3,127.0.1.3 99
	0        10.2.1.4,127.0.1.4 150
	0                           187
	0                           188
	0                           189
	EOF
	assert_file "${expected}" "${outfile}" "dynamic format with reordered column"
}
