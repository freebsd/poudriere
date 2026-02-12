. ./common.sh

set_test_contexts - "" "" <<-EOF
path="/";		expected="/";
path="";		expected=".";
path=".";		expected=".";
path=".";		expected=".";
path="./";		expected=".";
path="foo";		expected=".";
path="foo/bar";		expected="foo";
path="foo//bar";	expected="foo";
path="./foo/bar";	expected="./foo";
path=".//foo//bar";	expected=".//foo";
path="/foo/bar";	expected="/foo";
path="/foo/bar";	expected="/foo";
path="/foo/bar/";	expected="/foo";
path="/foo/bar//";	expected="/foo";
EOF

while get_test_context; do
	assert "${expected:?}" "$(command dirname "${path?}")"
	assert "${expected:?}" "$(dirname "${path?}")"
	dirname=
	dirname "${path?}" dirname
	assert "${expected:?}" "${dirname:?}"
	unset dirname
done
