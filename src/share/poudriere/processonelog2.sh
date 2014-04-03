#!/bin/sh
# Read a single errorlogfile and output a phase

filename=$1

if grep -qF "Filesystem touched during build" $1; then
  phase="build_fs_violation"
elif grep -qF "Filesystem touched during stage" $1; then
  phase="stage_fs_violation"
elif grep -qF "Files or directories orphaned" $1; then
  phase="stage_orphans"
elif grep -qF "stage-qa failures" $1; then
  phase="stage-qa"
elif grep -qE "Files or directories (left over|removed|modified)" $1; then
  phase="leftovers"
else
  phase="???"
fi

echo "$phase"

