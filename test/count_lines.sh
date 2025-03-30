set +e
. ./common.sh

TMP="$(mktemp -ut count_lines)"
cat > "${TMP}" <<-EOF
1
2
3
4
EOF
assert_true count_lines "${TMP}" cnt
assert 4 "${cnt}"

x="$(count_lines "${TMP}")"
assert 0 "$?"
assert 4 "${x}"

x="$(echo 1 | count_lines -)"
assert 0 "$?"
assert 1 "$x"

rm -f "${TMP}"

cnt=0
assert_false count_lines /nonexistent cnt
assert "0" "${cnt}"
