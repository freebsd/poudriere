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
	# assert_true [ -s "${tmp}" ]

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
	# assert_true [ -s "${tmp}" ]

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
	# assert_true [ -s "${tmp}" ]

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
	# assert_true [ -s "${tmp}" ]

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
	# assert_true [ -s "${tmp}" ]

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
	# assert_true [ -s "${tmp}" ]

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

# 2 named groups
add_test_function test_expand_2_groups
test_expand_2_groups() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	+queue-tests PKG_NO_VERSION_FOR_DEPS no yes
	+queue-tests SKIP_RECURSIVE_REBUILD 0 1
	+build-order-tests JFLAG 1:1 4:4
	+build-order-tests misc_foo_option SET=SLEEP UNSET=SLEEP
	EOF
	assert 0 "$?" "expand_test_contexts status"
	# assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	EOF
}

# 2 named groups and an unnamed group
add_test_function test_expand_3_groups
test_expand_3_groups() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	+queue-tests PKG_NO_VERSION_FOR_DEPS no yes
	+queue-tests SKIP_RECURSIVE_REBUILD 0 1
	+build-order-tests JFLAG 1:1 4:4
	+build-order-tests misc_foo_option SET=SLEEP UNSET=SLEEP
	D 1 2
	E 1 2
	EOF
	assert 0 "$?" "expand_test_contexts status"
	# assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	D="1"; E="1";
	D="1"; E="2";
	D="2"; E="1";
	D="2"; E="2";
	PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	EOF
}

# 2 named groups and an unnamed group with default group
add_test_function test_expand_3_groups_default
test_expand_3_groups_default() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	+queue-tests PKG_NO_VERSION_FOR_DEPS no yes
	+queue-tests SKIP_RECURSIVE_REBUILD 0 1
	+build-order-tests JFLAG 1:1 4:4
	+build-order-tests misc_foo_option SET=SLEEP UNSET=SLEEP
	+_default D 1 2
	+_default E 1 2
	EOF
	assert 0 "$?" "expand_test_contexts status"
	# assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	D="1"; E="1";
	D="1"; E="2";
	D="2"; E="1";
	D="2"; E="2";
	PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	EOF
}

# test it all together
add_test_function test_expand_everything
test_expand_everything() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	- SUDO no yes
	- DRY_RUN 0 1
	+queue-tests PKG_NO_VERSION_FOR_DEPS no yes
	+queue-tests SKIP_RECURSIVE_REBUILD 0 1
	+build-order-tests JFLAG 1:1 4:4
	+build-order-tests misc_foo_option SET=SLEEP UNSET=SLEEP
	EOF
	assert 0 "$?" "expand_test_contexts status"
	# assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	SUDO="no"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	SUDO="no"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	SUDO="no"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	SUDO="no"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	SUDO="yes"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	SUDO="yes"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	SUDO="yes"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	SUDO="yes"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="0"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	DRY_RUN="0"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="0"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	DRY_RUN="0"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="1"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	DRY_RUN="1"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="1"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	DRY_RUN="1"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	EOF
}

# test it all together
add_test_function test_expand_everything_named
test_expand_everything_named() {
	local tmp

	tmp="$(mktemp -ut test_contexts_expanded)"
	expand_test_contexts - > "${tmp}" <<-EOF
	-invocation-types SUDO no yes
	-invocation-types DRY_RUN 0 1
	+queue-tests PKG_NO_VERSION_FOR_DEPS no yes
	+queue-tests SKIP_RECURSIVE_REBUILD 0 1
	+build-order-tests JFLAG 1:1 4:4
	+build-order-tests misc_foo_option SET=SLEEP UNSET=SLEEP
	EOF
	assert 0 "$?" "expand_test_contexts status"
	# assert_true [ -s "${tmp}" ]

	assert_file_unordered - "${tmp}" <<-EOF
	SUDO="no"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	SUDO="no"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	SUDO="no"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	SUDO="no"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="no"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	SUDO="yes"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	SUDO="yes"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	SUDO="yes"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	SUDO="yes"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	SUDO="yes"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="0"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	DRY_RUN="0"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="0"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	DRY_RUN="0"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="0"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="1"; JFLAG="1:1"; misc_foo_option="SET=SLEEP";
	DRY_RUN="1"; JFLAG="1:1"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="1"; JFLAG="4:4"; misc_foo_option="SET=SLEEP";
	DRY_RUN="1"; JFLAG="4:4"; misc_foo_option="UNSET=SLEEP";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="no"; SKIP_RECURSIVE_REBUILD="1";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="0";
	DRY_RUN="1"; PKG_NO_VERSION_FOR_DEPS="yes"; SKIP_RECURSIVE_REBUILD="1";
	EOF
}

run_test_functions
