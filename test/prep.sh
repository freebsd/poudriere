#! /bin/sh
set -e

: ${THISDIR:=$(realpath "${0%/*}")}

BOOTSTRAP_ONLY=1
. ${THISDIR}/common.bulk.sh
