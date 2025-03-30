TEST_OVERRIDE_ERR=0
set -e
. ./common.sh
set +e

# Must run at least 1 assert
assert_true true
# Test that catch_err() does not break default err()
err 1 "error"
