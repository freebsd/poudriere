. ./common.sh

# 1 var
add_test_function test_expand_1_var
test_expand_1_var() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	A "1" 2
	EOF
	assert 0 "$?" "expand_test_contexts status"
	assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	A="1";
	A="2";
	EOF
}

# matrix context
add_test_function test_expand_matrix
test_expand_matrix() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	A "1" 2
	#B 3 4
	C "5 # !" 6 "7 @"
	D 8 ""
	EOF
	assert 0 "$?" "expand_test_contexts status"
	assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	A="1"; C="5 # !"; D="8";
	A="1"; C="6"; D="8";
	A="1"; C="7 @"; D="8";
	A="2"; C="5 # !"; D="8";
	A="2"; C="6"; D="8";
	A="2"; C="7 @"; D="8";
	#
	A="1"; C="5 # !"; D="";
	A="1"; C="6"; D="";
	A="1"; C="7 @"; D="";
	A="2"; C="5 # !"; D="";
	A="2"; C="6"; D="";
	A="2"; C="7 @"; D="";
	EOF
}

# 1 var per-line
add_test_function test_expand_perline_1_var
test_expand_perline_1_var() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	- A "1" 2
	EOF
	assert 0 "$?" "expand_test_contexts status"
	assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	A="1";
	A="2";
	EOF
}

# per-line context
add_test_function test_expand_perline
test_expand_perline() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	- A "1" 2
	#B 3 4
	- C "5 # !" 6 "7 @"
	- D 8 ""
	EOF
	assert 0 "$?" "expand_test_contexts status"
	assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	A="1";
	A="2";
	C="5 # !";
	C="6";
	C="7 @";
	D="8";
	D="";
	EOF
}

# a mix of per-line and matrix (2/3 are per-line)
add_test_function test_expand_perline_combo_mostly_perline
test_expand_perline_combo_mostly_perline() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	- A "1" 2
	#B 3 4
	- C "5 # !" 6 "7 @"
	D 8 ""
	EOF
	assert 0 "$?" "expand_test_contexts status"
	assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	A="1"; D="8";
	A="1"; D="";
	A="2"; D="8";
	A="2"; D="";
	C="5 # !"; D="8";
	C="5 # !"; D="";
	C="6"; D="8";
	C="6"; D="";
	C="7 @"; D="8";
	C="7 @"; D="";
	EOF
}

# a mix of per-line and matrix (2/3 are matrix)
add_test_function test_expand_perline_combo_mostly_combo
test_expand_perline_combo_mostly_combo() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	A "1" 2
	#B 3 4
	- C "5 # !" 6 "7 @"
	D 8 ""
	EOF
	assert 0 "$?" "expand_test_contexts status"
	assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	C="5 # !"; A="1"; D="8";
	C="6"; A="1"; D="8";
	C="7 @"; A="1"; D="8";
	C="5 # !"; A="2"; D="8";
	C="6"; A="2"; D="8";
	C="7 @"; A="2"; D="8";
	C="5 # !"; A="1"; D="";
	C="6"; A="1"; D="";
	C="7 @"; A="1"; D="";
	C="5 # !"; A="2"; D="";
	C="6"; A="2"; D="";
	C="7 @"; A="2"; D="";
	EOF
}

run_test_functions
