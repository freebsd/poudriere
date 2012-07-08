#include <sys/types.h>
#include <sys/sbuf.h>

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#include "commands.h"
#include "poudriere.h"
#include "utils.h"

typedef enum {
	NONE = 0,
	CREATE,
	DELETE,
	UPDATE,
	LIST,
	START,
	KILL,
} params;

void
usage_jail(void)
{
	fprintf(stderr, "usage: poudriere jail [parameters] [options]\n\n");
	fprintf(stderr,"Parameters:\n");
	fprintf(stderr,"\t%-15s%s\n", "-c", "creates a jail");
	fprintf(stderr,"\t%-15s%s\n", "-d", "deletes a jail");
	fprintf(stderr,"\t%-15s%s\n", "-u", "updates a jail");
	fprintf(stderr,"\t%-15s%s\n", "-l", "lists all jails");
	fprintf(stderr,"\t%-15s%s\n", "-s", "start a jail");
	fprintf(stderr,"\t%-15s%s\n\n", "-k", "kill (stop) a jail");
	fprintf(stderr,"Options:\n");
	fprintf(stderr,"\t%-15s%s\n", "-v", "Specifies which version of FreeBSD we want in jail");
	fprintf(stderr,"\t%-15s%s\n", "-j", "Specifies the jailname");
	fprintf(stderr,"\t%-15s%s\n", "-a", "Indicates architecture of the jail: i386 or amd64");
	fprintf(stderr,"\t%-15s%s\n", "-f", "FS name (tank/jails/myjail)");
	fprintf(stderr,"\t%-15s%s\n", "-t", "Indicates which version you want to upgrade to");
	fprintf(stderr,"\t%-15s%s\n", "-M", "mountpoint");
	fprintf(stderr,"\t%-15s%s\n\n", "-m", "method (to be used with -c). (default: \"ftp\"). Valid method: \"ftp\", \"csup\", \"svn\"");
}

int
exec_jail(int argc, char **argv)
{
	signed char ch;
	params p;
	struct zfs_prop props[] = {
		{ "JAILNAME", "name", "%-20s " },
		{ "VERSION", "version", "%-13s " },
		{ "ARCH", "arch", "%-7s " },
		{ "SUCCESS", "stats_built", "%-7s " },
		{ "FAILED", "stats_failed", "%-7s " },
		{ "IGNORED", "stats_ignored", "%-7s " },
		{ "QUEUED", "stats_queued", "%-7s " },
		{ "STATUS", "status", "%s\n" },
	};

	p = NONE;

	while ((ch = getopt(argc, argv, "cdulskj:v:a:f:M:m:t:")) != -1) {
		switch(ch) {
		case 'c':
			if (p != NONE)
				usage_jail();
			p = CREATE;
			break;
		case 'u':
			if (p != NONE)
				usage_jail();
			p = UPDATE;
			break;
		case 'd':
			if (p != NONE)
				usage_jail();
			p = DELETE;
			break;
		case 'l':
			if (p != NONE)
				usage_jail();
			p = LIST;
			break;
		case 's':
			if (p != NONE)
				usage_jail();
			p = START;
			break;
		case 'k':
			if (p != NONE)
				usage_jail();
			p = KILL;
			break;
		default:
			usage_jail();
			break;
		}
	}
	argc -= optind;
	argv += optind;

	switch (p) {
	case CREATE:
		break;
	case LIST:
		zfs_list(props, "rootfs", 8);
		break;
	case UPDATE:
		break;
	case DELETE:
		break;
	case START:
		break;
	case KILL:
		break;
	case NONE:
		usage_jail();
		break;
	}

	return (EX_OK);
}
