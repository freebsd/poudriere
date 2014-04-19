# Read a single errorlogfile and output a phase
/Filesystem touched during build/	{ res[0]="build_fs_violation" }
/Filesystem touched during stage/	{ res[1]="stage_fs_violation" }
/check\-plist failures/			{ res[2]="check-plist" }
/stage\-qa failures/			{ res[3]="stage-qa" }
/Files or directories (left over|removed|modified)/	{ res[4]="leftovers" }

END {
	for(i=0; i<5; i++) {
		if (res[i]) { print res[i]; exit; }
	}
	print "???"
}
