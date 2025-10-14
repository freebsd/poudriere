. ./common.sh

if ! have_builtin wc; then
	exit 77;
fi

val=$(echo 1 | wc -l)
assert "1" ${val}
