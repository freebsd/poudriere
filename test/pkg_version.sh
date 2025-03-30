set -e
. ./common.sh
set +e


assert_true assert_out 0 '<$' pkg_version -t 1 2
assert_true assert_out 0 '>$' pkg_version -t 2 1
assert_true assert_out 0 '=$' pkg_version -t 2 2
assert_true assert_out 0 '<$' pkg_version -t 2 1,1
assert_true assert_out 0 '<$' pkg_version -t 1.17.5_1 1.18.3
assert_true assert_out 0 '=$' pkg_version -t 1.17.5_1,0 1.17.5_1,0
assert_true assert_out 0 '=$' pkg_version -t 1.17.5_1,0 1.17.5_1
assert_true assert_out 0 '>$' pkg_version -t 1.17.5_1,1 1.18.3

if true; then
assert_true assert_out 0 '<$' pkg_version -t 1.21.3 2.0.b2_1
# Test cases taken from pkg/tests/frontend/version.sh
# Special prefixes
assert_true assert_out 0 '<$' pkg_version -t 1.pl1 1.alpha1
assert_true assert_out 0 '<$' pkg_version -t 1.alpha1 1.beta1
assert_true assert_out 0 '<$' pkg_version -t 1.beta1 1.pre1
assert_true assert_out 0 '<$' pkg_version -t 1.pre1 1.rc1
assert_true assert_out 0 '<$' pkg_version -t 1.rc1 1

assert_true assert_out 0 '<$' pkg_version -t 1.pl1 1.snap1
assert_true assert_out 0 '>$' pkg_version -t 1.snap1 1.alpha1
fi
