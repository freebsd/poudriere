#include <sys/types.h>
#include <sys/sbuf.h>
#include <sys/stat.h>

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>
#include <errno.h>
#include <err.h>

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
portsnap_create(struct pport_tree *p)
{
	char *argv[8];
	char snap[MAXPATHLEN], ports[MAXPATHLEN];

	snprintf(snap, sizeof(snap), "%s/snap", p->mountpoint);
	snprintf(ports, sizeof(ports), "%s/ports", p->mountpoint);

	if (mkdir(snap, 0755) != 0 && errno != EEXIST)
		err(1, "Unable to create snap dir: %s", snap);
	if (mkdir(ports, 0755) != 0 && errno != EEXIST)
		err(1, "Unable to create snap dir: %s", ports);

	argv[0] = "portsnap";
	argv[1] = "-d";
	argv[2] = snap;
	argv[3] = "-p";
	argv[4] = ports;
	argv[5] = "fetch";
	argv[6] = "extract";
	argv[7] = NULL;

	if (exec("/usr/sbin/portsnap", argv) != 0)
		fprintf(stderr, "Fail to create the ports tree\n");

	return;
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
	char *argv[6];
	char csup[MAXPATHLEN], db[MAXPATHLEN];
	FILE *csupf;

	snprintf(csup, sizeof(csup), "%s/csup", p->mountpoint);
	snprintf(db, sizeof(db), "%s/db", p->mountpoint);

	if (mkdir(db, 0755) != 0 && errno != EEXIST)
		err(1, "Unable to create db dir: %s", db);

	if ((csupf = fopen(csup, "w+")) == NULL)
		err(1, "Unable to open %s", csup);

	fprintf(csupf, "*default prefix=%s\n"
	    "*default base=%s/db\n"
	    "*default release=cvs tag=.\n"
	    "*default delete use-rel-suffix\n"
	    "ports-all", p->mountpoint, p->mountpoint);
	fclose(csupf);

	argv[0] = "csup";
	argv[1] = "-z";
	argv[2] = "-h";
	argv[3] = conf.csup_host;
	argv[4] = csup;
	argv[5] = NULL;

	if (exec("/usr/bin/csup", argv) != 0)
		err(1, "Fail to update the ports tree");

}

static void
port_create(struct pport_tree *p, bool fake)
{
	char *argv[13];
	char mnt[MAXPATHLEN + 11];
	char method[BUFSIZ];
	char name[BUFSIZ];

	int i;
	struct pmethod {
		const char *method;
		void (*exec)(struct pport_tree *p);
	} pm [] = {
		{ "portsnap", portsnap_create },
		{ "csup", csup_update },
		{ "svn", NULL },
		{ NULL, NULL },
	};

	/* TODO make sure the mountpoint has no // */
	if (p->mountpoint[0] == '\0')
		snprintf(p->mountpoint, sizeof(p->mountpoint),
		    "%s/ports/%s", conf.basefs, p->name);

	/* TODO make sure the fs has no // */
	if (p->fs[0] == '\0')
		snprintf(p->fs, sizeof(p->fs),
		    "%s/poudriere/ports/%s", conf.zfs_pool, p->name);

	if (p->method[0] == '\0')
		strlcpy(p->method, "portsnap", sizeof(p->method));

	snprintf(mnt, sizeof(mnt), "mountpoint=%s", p->mountpoint);
	snprintf(method, sizeof(method), "poudriere:method=%s", p->method);
	snprintf(name, sizeof(name), "poudriere:name=%s", p->name);

	argv[0] = "zfs";
	argv[1] = "create";
	argv[2] = "-p";
	argv[3] = "-o";
	argv[4] = mnt;
	argv[5] = "-o";
	argv[6] = "poudriere:type=ports";
	argv[7] = "-o";
	argv[8] = method;
	argv[9] = "-o";
	argv[10] = name;
	argv[11] = p->fs;
	argv[12] = NULL;

	if (exec("/sbin/zfs", argv) != 0)
		err(1, "Fail to create the ports tree");

	for (i = 0; pm[i].exec != NULL; i++) {
		if (strcmp(p->method, pm[i].method) == 0) {
			pm[i].exec(p);
			return;
		}
	}
}

static void
port_delete(struct pport_tree *p)
{
	char *argv[5];

	/* TODO check if already mounted */

	argv[0] = "zfs";
	argv[1] = "destroy";
	argv[2] = "-r";
	argv[3] = p->fs;
	argv[4] = NULL;

	if (exec("/sbin/zfs", argv) != 0)
		fprintf(stderr, "Fail to delete the ports tree\n");

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
		{ "-", portsnap_update }, /* default on portsnap */
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
	bool fake = false;
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
	memset(&pt, 0, sizeof(pt));
	strlcpy(pt.name, "default", sizeof(pt.name));

	while ((ch = getopt(argc, argv, "cFudlp:f:M:m:")) != -1) {
		switch(ch) {
		case 'c':
			if (p != NONE)
				usage_ports();
			p = CREATE;
			break;
		case 'F':
			fake = true;
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
			strlcpy(pt.fs, optarg, sizeof(pt.fs));
			break;
		case 'M':
			strlcpy(pt.mountpoint, optarg, sizeof(pt.mountpoint));
			break;
		case 'm':
			strlcpy(pt.method, optarg, sizeof(pt.method));
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
		if (zfs_query("ports", pt.name, q, sizeof(q) / sizeof(struct zfs_query ))) {
			fprintf(stderr, "This ports tree already exists\n");
		} else {
			port_create(&pt, fake);
		}
		break;
	case LIST:
		zfs_list(props, "ports", sizeof(props) / sizeof(struct zfs_prop));
		break;
	case UPDATE:
		if (zfs_query("ports", pt.name, q, sizeof(q) / sizeof(struct zfs_query ))) {
			port_update(&pt);
		} else {
			fprintf(stderr, "No such ports\n");
		}
		break;
	case DELETE:
		if (zfs_query("ports", pt.name, q, sizeof(q) / sizeof(struct zfs_query ))) {
			port_delete(&pt);
		} else {
			fprintf(stderr, "No such ports\n");
		}
		break;
	case NONE:
		usage_ports();
		break;
	}

	return (EX_OK);
}
