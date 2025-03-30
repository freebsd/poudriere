set -e
. ./common.sh
set +e

if [ ! -x "${GIT_CMD}" ]; then
	assert_true true
	exit 0
fi
PORTSDIR_SRC="${THISDIR%/*}/test-ports/default"
PORTSDIR="$(mktemp -dt git_tree_dirty)"

# Setup a test ports tree
{
	assert_true do_clone "${PORTSDIR_SRC}" "${PORTSDIR}"
	assert_true git -C "${PORTSDIR}" init
	assert_true git -C "${PORTSDIR}" add .
	assert_true git -C "${PORTSDIR}" commit -m "initial commit"
}

assert_false git_tree_dirty "${PORTSDIR}" 0
assert_false git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1

echo >> "${PORTSDIR}/Mk/bsd.port.mk"
assert_true git_tree_dirty "${PORTSDIR}" 0
assert_false git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1
git -C "${PORTSDIR}" checkout Mk/bsd.port.mk

touch "${PORTSDIR}/ports-mgmt/Makefile.local"
assert_true git_tree_dirty "${PORTSDIR}" 0
assert_false git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1
rm -f "${PORTSDIR}/ports-mgmt/Makefile.local"

touch "${PORTSDIR}/Makefile.local"
assert_true git_tree_dirty "${PORTSDIR}" 0
assert_false git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1
rm -f "${PORTSDIR}/Makefile.local"

mkdir "${PORTSDIR}/ports-mgmt/pkg/files"
assert_false git_tree_dirty "${PORTSDIR}" 0
assert_false git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1

touch "${PORTSDIR}/ports-mgmt/pkg/files/patch-foo.orig"
assert_false git_tree_dirty "${PORTSDIR}" 0
assert_false git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1

touch "${PORTSDIR}/ports-mgmt/pkg/files/patch-foo"
assert_true git_tree_dirty "${PORTSDIR}" 0
assert_true git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1
rm -f "${PORTSDIR}/ports-mgmt/pkg/files/patch-foo"

touch "${PORTSDIR}/ports-mgmt/pkg/Makefile.local"
assert_true git_tree_dirty "${PORTSDIR}" 0
assert_true git_tree_dirty "${PORTSDIR}/ports-mgmt/pkg" 1
rm -f "${PORTSDIR}/ports-mgmt/pkg/Makefile.local"

rm -Rf "${PORTSDIR}"
