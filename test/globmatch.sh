set -e
. ./common.sh
set +e

tdir=$(mktemp -d)

assert_ret 1 globmatch "${tdir}/*"
assert_ret 0 dirempty "${tdir}"
touch "${tdir}/blah"
echo ${tdir}/*
assert_ret 0 globmatch "${tdir}/*"
assert_ret 1 dirempty "${tdir}"

rm -rf "${tdir}"
