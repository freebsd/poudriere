#! /bin/sh

set -e
. common.sh
. ${SCRIPTPREFIX}/common.sh
set +e

assert "hEllo world" "$(gsub "hello world" "e" "E")" "gsub should match line ${LINENO}"
assert "hELLO world" "$(gsub "hello world" "ello" "ELLO")" "gsub should match line ${LINENO}"
assert "h world" "$(gsub "hello world" "ello" "")" "gsub should match line ${LINENO}"
assert "hELLOBLAH world" "$(gsub "hello world" "ello" "ELLOBLAH")" "gsub should match line ${LINENO}"
assert "hello worl" "$(gsub "hello world" "d" "")" "gsub should match line ${LINENO}"
assert "hello world123" "$(gsub "hello world" "d" "d123")" "gsub should match line ${LINENO}"
assert "hello world" "$(gsub "hello world" "D" "")" "gsub should match line ${LINENO}"
assert "ello world" "$(gsub "hello world" "h" "")" "gsub should match line ${LINENO}"
assert "//blah" "$(gsub "////blah" "//" "/")" "gsub should match line ${LINENO}"
x="hello world"
ret=0
output=
_gsub "${x}" "o" "O" output || ret=$?
assert 0 "${ret}" "_gsub should pass line ${LINENO}"
assert "hellO wOrld" "${output}" "_gsub should give expected result line ${LINENO}"

assert_ret 0 _gsub "!" "[!a-zA-Z0-9_]" _ output
assert "_" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "!" "!" _ output
assert "_" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "f" "[!a-zA-Z0-9_]" _ output
assert "f" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "" "[!a-zA-Z0-9_]" _ output
assert "" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "" "foo" _ output
assert "" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "x" "t" _ output
assert "x" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "x" "" _ output
assert "x" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "" "" _ output
assert "" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "foooooooooooooood" "o*d" _ output
assert "f_" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "oodood" "o*d" _ output
assert "__" "${output}" "_gsub should match line ${LINENO}"

# XXX: This doesn't match actual shell globbing
assert_ret 0 _gsub "oodood" "o*do" _ output
assert "_od" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "fooooooooooooooodbarod" "o*d" _ output
assert "f_bar_" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "!foo/\$%bar%" "[!a-zA-Z0-9_]" _ output
assert "_foo___bar_" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "!foo/\$%bar%q" "[!a-zA-Z0-9_]" _ output
assert "_foo___bar_q" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub "foobar" "o" "" output
assert "fbar" "${output}" "_gsub should match line ${LINENO}"

assert_ret 0 _gsub_var_name "!foo/\$%bar%" output
assert "_foo___bar_" "${output}" "_gsub_var_name should match line ${LINENO}"

assert_ret 0 _gsub_badchars "!foo/\$%bar%" "!/%" output
assert "_foo_\$_bar_" "${output}" "_gsub_badchars should match line ${LINENO}"

assert_ret 0 _gsub_badchars "!foo/\$%bar%" "!a-zA-Z0-9_" output
assert "_foo/\$%b_r%" "${output}" "_gsub_badchars should match line ${LINENO}"
