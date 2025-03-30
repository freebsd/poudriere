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
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list "build" | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "bash patchutils pkg")" "${pkgqueue_list}"
assert_out 0 "" pkgqueue_find_dead_packages
assert_true pkgqueue_move_ready_to_pool

assert_out 0 - pkgqueue_remaining <<EOF
build:pkg ready-to-run
build:bash waiting-on-dependency
build:patchutils waiting-on-dependency
EOF

assert_out 0 - pkgqueue_graph <<-EOF
build:pkg build:bash
build:bash build:patchutils
build:pkg build:patchutils
EOF
assert_out 0 - pkgqueue_graph_dot <<EOF
digraph Q {
	"build:patchutils" -> "build:bash";
	"build:bash" -> "build:pkg";
	"build:patchutils" -> "build:pkg";
}
EOF

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "pkg" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

assert_out 0 - pkgqueue_remaining <<EOF
build:bash ready-to-run
build:patchutils waiting-on-dependency
EOF

assert_out 0 - pkgqueue_graph <<-EOF
build:bash build:patchutils
EOF
assert_out 0 - pkgqueue_graph_dot <<EOF
digraph Q {
	"build:patchutils" -> "build:bash";
}
EOF

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "bash" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

assert_out 0 - pkgqueue_remaining <<EOF
build:patchutils ready-to-run
EOF

assert_out 0 - pkgqueue_graph <<-EOF
EOF
assert_out 0 - pkgqueue_graph_dot <<EOF
digraph Q {
}
EOF

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "patchutils" "${pkgname}"
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
