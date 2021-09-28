set -e
. common.sh
. ${SCRIPTPREFIX}/include/util.sh
set +e

# Use more precision for these tests to avoid some rounding errors if we start
# at N.9 rather than N.0. (or else seconds tend to not match randomly)
assert 1.0 "$(timespecsub 6 5)" "timespecsub result"
assert 1.0 "$(timespecsub 6.0 5)" "timespecsub result"
assert 1.0 "$(timespecsub 6 5.0)" "timespecsub result"
assert 1.0 "$(timespecsub 6.0 5.0)" "timespecsub result"
assert 0.$((5 * 100000000)) "$(timespecsub 5.$((5 * 100000000)) 5)" "timespecsub result"
assert 1.$((5 * 100000000)) "$(timespecsub 6.$((5 * 100000000)) 5)" "timespecsub result"
assert 1.0 "$(timespecsub 6.$((5 * 100000000)) 5.$((5 * 100000000)))" "timespecsub result"
assert -1.0 "$(timespecsub 4.$((5 * 100000000)) 5.$((5 * 100000000)))" "timespecsub result"
assert 1.$((4 * 100000000)) "$(timespecsub 6.$((9 * 100000000)) 5.$((5 * 100000000)))" "timespecsub result"
assert 1.$((8 * 100000000)) "$(timespecsub 6.$((9 * 100000000)) 5.$((1 * 100000000)))" "timespecsub result"
assert 1.$((9 * 100000000)) "$(timespecsub 6.$((9 * 100000000)) 5.0)" "timespecsub result"
assert 2.0 "$(timespecsub 6.$((9 * 100000000)) 4.$((9 * 100000000)))" "timespecsub result"
assert -2.$((6 * 100000000)) "$(timespecsub 3.$((5 * 100000000)) 4.$((9 * 100000000)))" "timespecsub result"
assert 0.$((2 * 100000000)) "$(timespecsub 3.$((1 * 100000000)) 2.$((9 * 100000000)))" "timespecsub result"
