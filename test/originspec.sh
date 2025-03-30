set -e
. ./common.sh
set +e

originspec_encode originspec 'origin' '' ''
assert "origin" "${originspec}"
origin=bad
originspec_decode "${originspec}" origin '' ''
assert "origin" "${origin}"
origin=bad
flavor=bad
originspec_decode "${originspec}" origin flavor ''
assert "origin" "${origin}"
assert "" "${flavor}"
origin=bad
subpkg=bad
originspec_decode "${originspec}" origin '' subpkg
assert "origin" "${origin}"
assert "" "${subpkg}"
origin=bad
flavor=bad
subpkg=bad
originspec_decode "${originspec}" origin flavor subpkg
assert "origin" "${origin}"
assert "" "${flavor}"
assert "" "${subpkg}"

originspec_encode originspec 'origin' 'flavor' ''
assert "origin${ORIGINSPEC_FL_SEP?}flavor" "${originspec}"
origin=bad
originspec_decode "${originspec}" origin '' ''
assert "origin" "${origin}"
assert "origin" "${origin}"
origin=bad
flavor=bad
originspec_decode "${originspec}" origin flavor ''
assert "origin" "${origin}"
assert "flavor" "${flavor}"
origin=bad
subpkg=bad
originspec_decode "${originspec}" origin '' subpkg
assert "origin" "${origin}"
assert "" "${subpkg}"
origin=bad
flavor=bad
subpkg=bad
originspec_decode "${originspec}" origin flavor subpkg
assert "origin" "${origin}"
assert "flavor" "${flavor}"
assert "" "${subpkg}"

originspec_encode originspec 'origin' '' 'subpkg'
assert "origin${ORIGINSPEC_SP_SEP?}subpkg" "${originspec}"
origin=bad
originspec_decode "${originspec}" origin '' ''
assert "origin" "${origin}"
origin=bad
flavor=bad
originspec_decode "${originspec}" origin flavor ''
assert "origin" "${origin}"
assert "" "${flavor}"
origin=bad
subpkg=bad
originspec_decode "${originspec}" origin '' subpkg
assert "origin" "${origin}"
assert "subpkg" "${subpkg}"
origin=bad
flavor=bad
subpkg=bad
originspec_decode "${originspec}" origin flavor subpkg
assert "origin" "${origin}"
assert "" "${flavor}"
assert "subpkg" "${subpkg}"

originspec_encode originspec 'origin' 'flavor' 'subpkg'
assert "origin${ORIGINSPEC_FL_SEP?}flavor${ORIGINSPEC_SP_SEP?}subpkg" "${originspec}"
origin=bad
originspec_decode "${originspec}" origin '' ''
assert "origin" "${origin}"
origin=bad
flavor=bad
originspec_decode "${originspec}" origin flavor ''
assert "origin" "${origin}"
assert "flavor" "${flavor}"
origin=bad
subpkg=bad
originspec_decode "${originspec}" origin '' subpkg
assert "origin" "${origin}"
assert "subpkg" "${subpkg}"
origin=bad
flavor=bad
subpkg=bad
originspec_decode "${originspec}" origin flavor subpkg
assert "origin" "${origin}"
assert "flavor" "${flavor}"
assert "subpkg" "${subpkg}"
