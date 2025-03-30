# Depends on pkgqueue_basic.sh passing
# Depends on pkgqueue_prioritize "build".sh passing
. ./common.sh

set_pipefail

MASTER_DATADIR=$(mktemp -dt datadir)
assert_true cd "${MASTER_DATADIR}"
assert_true add_relpath_var MASTER_DATADIR

assert_true pkgqueue_init
assert_true pkgqueue_add "build" pkg
assert_true pkgqueue_add "build" bash
assert_true pkgqueue_add_dep "build" bash "build" pkg
assert_true pkgqueue_add "build" patchutils
assert_true pkgqueue_add_dep "build" patchutils "build" bash
assert_true pkgqueue_add_dep "build" patchutils "build" pkg
assert_true pkgqueue_add "build" devtools
assert_true pkgqueue_add_dep "build" devtools "build" patchutils
assert_true pkgqueue_add_dep "build" devtools "build" bash
assert_true pkgqueue_add_dep "build" devtools "build" pkg
assert_true pkgqueue_add "build" zsh
assert_true pkgqueue_add_dep "build" zsh "build" pkg
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list "build" | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "bash devtools zsh patchutils pkg")" "${pkgqueue_list}"
assert_out 0 "" pkgqueue_find_dead_packages
assert_true pkgqueue_prioritize "build" bash 50
assert_true pkgqueue_prioritize "build" zsh 49

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" pkg <<-EOF
deps/p/build${PKGQUEUE_JOB_SEP:?}pkg
deps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}pkg
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}pkg
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}pkg
deps/z/build${PKGQUEUE_JOB_SEP:?}zsh/build${PKGQUEUE_JOB_SEP:?}pkg
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" patchutils <<-EOF
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}patchutils
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" bash <<-EOF
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}bash
deps/b/build${PKGQUEUE_JOB_SEP:?}bash
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}bash
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}bash
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" devtools <<-EOF
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}devtools
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}devtools
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}devtools
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" zsh <<-EOF
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}zsh
deps/z/build${PKGQUEUE_JOB_SEP:?}zsh
EOF
assert 0 "$?"

assert_true pkgqueue_move_ready_to_pool

# Nothing should have changed except that deps/p/pkg is moved out of the queue.

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" pkg <<-EOF
deps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}pkg
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}pkg
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}pkg
deps/z/build${PKGQUEUE_JOB_SEP:?}zsh/build${PKGQUEUE_JOB_SEP:?}pkg
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" patchutils <<-EOF
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}patchutils
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" bash <<-EOF
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}bash
deps/b/build${PKGQUEUE_JOB_SEP:?}bash
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}bash
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}bash
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" devtools <<-EOF
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}devtools
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}devtools
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}devtools
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" zsh <<-EOF
rdeps/p/build${PKGQUEUE_JOB_SEP:?}pkg/build${PKGQUEUE_JOB_SEP:?}zsh
deps/z/build${PKGQUEUE_JOB_SEP:?}zsh
EOF
assert 0 "$?"

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "pkg" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

# pkg is gone, zsh and bash are moved out as well as they are reday-to-"build"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" patchutils <<-EOF
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}patchutils
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
EOF
assert 0 "$?"
assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" bash <<-EOF
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}bash
deps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}bash
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash
EOF

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" devtools <<-EOF
rdeps/b/build${PKGQUEUE_JOB_SEP:?}bash/build${PKGQUEUE_JOB_SEP:?}devtools
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}devtools
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" zsh <<-EOF
EOF
assert 0 "$?"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "bash" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

# bash is gone, patchutils is eligible now

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" patchutils <<-EOF
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
EOF
assert 0 "$?"
assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" bash <<-EOF
EOF

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" devtools <<-EOF
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}devtools
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" zsh <<-EOF
EOF
assert 0 "$?"


assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "zsh" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

# zsh is gone, patchutils is next and then devtools

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" patchutils <<-EOF
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools/build${PKGQUEUE_JOB_SEP:?}patchutils
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils
EOF
assert 0 "$?"
assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" bash <<-EOF
EOF

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" devtools <<-EOF
rdeps/p/build${PKGQUEUE_JOB_SEP:?}patchutils/build${PKGQUEUE_JOB_SEP:?}devtools
deps/d/build${PKGQUEUE_JOB_SEP:?}devtools
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" zsh <<-EOF
EOF
assert 0 "$?"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "patchutils" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

# patchutils is gone, only devtools remains

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" pkg <<-EOF
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" patchutils <<-EOF
EOF
assert 0 "$?"
assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" bash <<-EOF
EOF

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" devtools <<-EOF
EOF
assert 0 "$?"

assert_out_unordered 0 - pkgqueue_find_all_pool_references "build" zsh <<-EOF
EOF
assert 0 "$?"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "devtools" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"


assert_true pkgqueue_empty
assert_true pkgqueue_sanity_check 0
assert_true pkgqueue_get_next job_type pkgname
assert "" "${pkgname}"
assert "" "${job_type}"

assert_true cd "${POUDRIERE_TMPDIR:?}"
rm -rf "${MASTER_DATADIR:?}"
