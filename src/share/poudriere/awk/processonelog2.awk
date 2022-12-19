# Read a single errorlogfile and output a phase
function found(reason) {
	if (!REASON && !REASON_LAST) {
		REASON = reason
	}
}
function found_last(reason) {
	if (!REASON) {
		REASON_LAST = reason
	}
}
/Filesystem touched during build/	{ found("build_fs_violation") }
/Filesystem touched during stage/	{ found("stage_fs_violation") }
/check\-plist failures/			{ found("check-plist") }
/stage\-qa failures/			{ found("stage-qa") }
/Files or directories (left over|removed|modified)/	{ found("leftovers") }
/=======================<phase: .*/     { found_last($2); }

END {
	if (REASON_LAST) {
		REASON = REASON_LAST
	}
	if (!REASON) {
		REASON = "???"
	}
	print REASON
}
