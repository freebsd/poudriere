ALL=1
OVERLAYS="subpkg"
set -e
. common.bulk.sh
set +e

do_bulk -c -n -a
assert 0 $? "Bulk should pass"

allports="\
converters/libiconv \
devel/ccache \
devel/gettext \
devel/gettext-runtime \
devel/gettext-tools \
devel/libffi \
devel/libtextstyle \
devel/pkgconf \
devel/readline \
lang/perl5.36 \
lang/python \
lang/python2 \
lang/python27 \
lang/python3 \
lang/python39 \
misc/pciids \
ports-mgmt/pkg \
ports-mgmt/subpkgtest \
print/indexinfo \
security/openssl \
sysutils/pstree \
"

for port in ${allports}; do
	EXPECTED_QUEUED="${EXPECTED_QUEUED:+${EXPECTED_QUEUED} }${port}"
	EXPECTED_LISTED="${EXPECTED_LISTED:+${EXPECTED_LISTED} }${port}"
done

assert_bulk_queue_and_stats
assert_bulk_dry_run
