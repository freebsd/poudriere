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
} params;


void
usage_ports(void)
{
	fprintf(stderr, "usage: poudriere ports [parameters] [options]\n\n");
	fprintf(stderr,"Parameters:\n");
	fprintf(stderr,"\t%-15s%s\n", "-c", "creates a ports tree");
	fprintf(stderr,"\t%-15s%s\n", "-d", "deletes a ports tree");
	fprintf(stderr,"\t%-15s%s\n", "-u", "updates a ports tree");
	fprintf(stderr,"\t%-15s%s\n\n", "-l", "lists all ports trees");
	fprintf(stderr,"Options:\n");
	fprintf(stderr,"\t%-15s%s\n", "-F", "when used with -c, only create the needed ZFS, filesystems and directories, but do not populate them.");
	fprintf(stderr,"\t%-15s%s\n", "-p", "specifies on which portstree we work. (defaule: \"default\").");
	fprintf(stderr,"\t%-15s%s\n", "-f", "FS name (tank/jails/myjail)");
	fprintf(stderr,"\t%-15s%s\n", "-M", "mountpoint");
	fprintf(stderr,"\t%-15s%s\n\n", "-m", "method (to be used with -c). (default: \"portsnap\"). Valid method: \"portsnap\", \"csup\"");

}

int
exec_ports(int argc, char **argv)
{
	signed char ch;
	params p;

	struct zfs_prop props[] = {
		{ "PORTSTREE", "name", "%-20s " },
		{ "METHOD", "method", "%-10s\n" },
	};
	p = NONE;

	while ((ch = getopt(argc, argv, "cFudlp:f:M:m:")) != -1) {
		switch(ch) {
		case 'c':
			if (p != NONE)
				usage_ports();
			p = CREATE;
			break;
		case 'F':
			break;
		case 'u':
			if (p != NONE)
				usage_ports();
			p = UPDATE;
			break;
		case 'd':
			if (p != NONE)
				usage_ports();
			p = DELETE;
			break;
		case 'l':
			if (p != NONE)
				usage_ports();
			p = LIST;
			break;
		case 'p':
			break;
		case 'f':
			break;
		case 'M':
			break;
		case 'm':
			break;
		default:
			usage_ports();
			break;
		}
	}
	argc -= optind;
	argv += optind;

	switch (p) {
	case CREATE:
		break;
	case LIST:
		zfs_list(props, "ports", 2);
		break;
	case UPDATE:
		break;
	case DELETE:
		break;
	case NONE:
		usage_ports();
		break;
	}

	return (EX_OK);
}
