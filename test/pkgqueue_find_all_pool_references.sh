# Depends on pkgqueue_basic.sh passing
# Depends on pkgqueue_prioritize.sh passing
. common.sh

set_pipefail

MASTER_DATADIR=$(mktemp -dt datadir)
assert_true cd "${MASTER_DATADIR}"
assert_true add_relpath_var MASTER_DATADIR

assert_true pkgqueue_init
assert_true pkgqueue_add pkg
assert_true pkgqueue_add bash
assert_true pkgqueue_add_dep bash pkg
assert_true pkgqueue_add patchutils
assert_true pkgqueue_add_dep patchutils bash
assert_true pkgqueue_add_dep patchutils pkg
assert_true pkgqueue_add devtools
assert_true pkgqueue_add_dep devtools patchutils
assert_true pkgqueue_add_dep devtools bash
assert_true pkgqueue_add_dep devtools pkg
assert_true pkgqueue_add zsh
assert_true pkgqueue_add_dep zsh pkg
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "bash devtools zsh patchutils pkg")" "${pkgqueue_list}"
assert_out "" pkgqueue_find_dead_packages
assert_true pkgqueue_prioritize bash 50
assert_true pkgqueue_prioritize zsh 49

assert_out_unordered - pkgqueue_find_all_pool_references pkg <<-EOF
deps/p/pkg
deps/b/bash/pkg
deps/d/devtools/pkg
deps/p/patchutils/pkg
deps/z/zsh/pkg
rdeps/p/pkg
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references patchutils <<-EOF
rdeps/b/bash/patchutils
rdeps/p/pkg/patchutils
deps/p/patchutils
deps/d/devtools/patchutils
rdeps/p/patchutils
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references bash <<-EOF
rdeps/p/pkg/bash
deps/b/bash
deps/d/devtools/bash
deps/p/patchutils/bash
rdeps/b/bash
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references devtools <<-EOF
rdeps/b/bash/devtools
rdeps/p/patchutils/devtools
rdeps/p/pkg/devtools
deps/d/devtools
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references zsh <<-EOF
rdeps/p/pkg/zsh
deps/z/zsh
EOF
assert 0 "$?"

assert_true pkgqueue_move_ready_to_pool

# Nothing should have changed except that deps/p/pkg is moved out of the queue.

assert_out_unordered - pkgqueue_find_all_pool_references pkg <<-EOF
deps/b/bash/pkg
deps/d/devtools/pkg
deps/p/patchutils/pkg
deps/z/zsh/pkg
rdeps/p/pkg
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references patchutils <<-EOF
rdeps/b/bash/patchutils
rdeps/p/pkg/patchutils
deps/p/patchutils
deps/d/devtools/patchutils
rdeps/p/patchutils
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references bash <<-EOF
rdeps/p/pkg/bash
deps/b/bash
deps/d/devtools/bash
deps/p/patchutils/bash
rdeps/b/bash
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references devtools <<-EOF
rdeps/b/bash/devtools
rdeps/p/patchutils/devtools
rdeps/p/pkg/devtools
deps/d/devtools
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references zsh <<-EOF
rdeps/p/pkg/zsh
deps/z/zsh
EOF
assert 0 "$?"

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "pkg" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

# pkg is gone, zsh and bash are moved out as well as they are reday-to-build

assert_out_unordered - pkgqueue_find_all_pool_references pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references patchutils <<-EOF
rdeps/b/bash/patchutils
deps/p/patchutils
deps/d/devtools/patchutils
rdeps/p/patchutils
EOF
assert 0 "$?"
assert_out_unordered - pkgqueue_find_all_pool_references bash <<-EOF
deps/d/devtools/bash
deps/p/patchutils/bash
rdeps/b/bash
EOF

assert_out_unordered - pkgqueue_find_all_pool_references devtools <<-EOF
rdeps/b/bash/devtools
rdeps/p/patchutils/devtools
deps/d/devtools
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references zsh <<-EOF
EOF
assert 0 "$?"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "bash" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

# bash is gone, patchutils is eligible now

assert_out_unordered - pkgqueue_find_all_pool_references pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references patchutils <<-EOF
deps/d/devtools/patchutils
rdeps/p/patchutils
EOF
assert 0 "$?"
assert_out_unordered - pkgqueue_find_all_pool_references bash <<-EOF
EOF

assert_out_unordered - pkgqueue_find_all_pool_references devtools <<-EOF
rdeps/p/patchutils/devtools
deps/d/devtools
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references zsh <<-EOF
EOF
assert 0 "$?"


assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "zsh" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

# zsh is gone, patchutils is next and then devtools

assert_out_unordered - pkgqueue_find_all_pool_references pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references patchutils <<-EOF
deps/d/devtools/patchutils
rdeps/p/patchutils
EOF
assert 0 "$?"
assert_out_unordered - pkgqueue_find_all_pool_references bash <<-EOF
EOF

assert_out_unordered - pkgqueue_find_all_pool_references devtools <<-EOF
rdeps/p/patchutils/devtools
deps/d/devtools
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references zsh <<-EOF
EOF
assert 0 "$?"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "patchutils" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

# patchutils is gone, only devtools remains

assert_out_unordered - pkgqueue_find_all_pool_references pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references patchutils <<-EOF
EOF
assert 0 "$?"
assert_out_unordered - pkgqueue_find_all_pool_references bash <<-EOF
EOF

assert_out_unordered - pkgqueue_find_all_pool_references devtools <<-EOF
EOF
assert 0 "$?"

assert_out_unordered - pkgqueue_find_all_pool_references zsh <<-EOF
EOF
assert 0 "$?"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "devtools" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"


assert_true pkgqueue_empty
assert_true pkgqueue_sanity_check 0
assert_true pkgqueue_get_next pkgname
assert "" "${pkgname}"

assert_true cd "${POUDRIERE_TMPDIR:?}"
rm -rf "${MASTER_DATADIR:?}"
