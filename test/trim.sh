set -e
. ./common.sh
set +e

x="   foo bar"
assert "foo bar" "$(ltrim "${x}" " ")"

x="foo bar    "
assert "foo bar" "$(rtrim "${x}" " ")"
