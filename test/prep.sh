set -e

: ${THISDIR:=$(realpath "${0%/*}")}

BOOTSTRAP_ONLY=1
. ./common.bulk.sh
assert_true true
