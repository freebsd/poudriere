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

static void
portsnap_update(struct pport_tree *p)
{
	char *argv[8];
	char snap[MAXPATHLEN], ports[MAXPATHLEN];

	snprintf(snap, sizeof(snap), "%s/snap", p->mountpoint);
	snprintf(ports, sizeof(ports), "%s/ports", p->mountpoint);
	argv[0] = "portsnap";
	argv[1] = "-d";
	argv[2] = snap;
	argv[3] = "-p";
	argv[4] = ports;
	argv[5] = "fetch";
	argv[6] = "update";
	argv[7] = NULL;

	if (exec("/usr/sbin/portsnap", argv) != 0)
		fprintf(stderr, "Fail to update the ports tree\n");

	return;
}

static void
csup_update(struct pport_tree *p)
{
}

static void
port_update(struct pport_tree *p)
{
	int i;
	struct pmethod {
		const char *method;
		void (*exec)(struct pport_tree *p);
	} pm [] = {
		{ "portsnap", portsnap_update },
		{ "csup", csup_update },
		{ "svn", NULL },
		{ NULL, NULL },
	};

	for (i = 0; pm[i].exec != NULL; i++) {
		if (strcmp(p->method, pm[i].method) == 0) {
			pm[i].exec(p);
			return;
		}
	}
	fprintf(stderr, "Unknown method: %s\n", p->method);
}

int
exec_ports(int argc, char **argv)
{
	signed char ch;
	params p;
	struct pport_tree pt;
	struct zfs_prop props[] = {
		{ "PORTSTREE", "name", "%-20s " },
		{ "METHOD", "method", "%-10s\n" },
	};

	struct zfs_query q[] = {
		{ "poudriere:method", STRING, pt.method, sizeof(pt.method), 0 },
		{ "mountpoint", STRING, pt.mountpoint, sizeof(pt.mountpoint), 0 },
		{ "name", STRING, pt.fs, sizeof(pt.fs), 0 },
	};
	p = NONE;
	strlcpy(pt.name, "default", sizeof(pt.name));

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
			strlcpy(pt.name, optarg, sizeof(pt.name));
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
		if (zfs_query("ports", pt.name, q, sizeof(q) / sizeof(struct zfs_query ))) {
			port_update(&pt);
		} else {
			fprintf(stderr, "No such ports\n");
		}
		break;
	case DELETE:
		break;
	case NONE:
		usage_ports();
		break;
	}

	return (EX_OK);
}
