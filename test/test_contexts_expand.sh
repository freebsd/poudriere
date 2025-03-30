. ./common.sh

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
