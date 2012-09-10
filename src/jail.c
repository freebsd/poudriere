#include <sys/types.h>
#include <sys/sbuf.h>
#include <sys/param.h>

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
	char *jailname = NULL;
	struct pjail j;
	struct zfs_prop props[] = {
		{ "JAILNAME", "name", "%-20s " },
		{ "VERSION", "version", "%-13s " },
		{ "ARCH", "arch", "%-7s " },
		{ "METHOD", "method", "%-7s " },
		{ "SUCCESS", "stats_built", "%-7s " },
		{ "FAILED", "stats_failed", "%-7s " },
		{ "IGNORED", "stats_ignored", "%-7s " },
		{ "SKIPPED", "stats_skipped", "%-7s " },
		{ "QUEUED", "stats_queued", "%-7s " },
		{ "STATUS", "status", "%s\n" },
	};

	struct zfs_query q[] = {
		{ "poudriere:name", STRING, j.name, sizeof(j.name), 0 },
		{ "poudriere:version", STRING, j.version, sizeof(j.version), 0 },
		{ "poudriere:arch", STRING, j.arch, sizeof(j.arch), 0 },
		{ "poudriere:method", STRING, j.method, sizeof(j.method), 0 },
		{ "poudriere:stats_built", INTEGER, NULL, 0,  j.built },
		{ "poudriere:stats_failed", INTEGER, NULL, 0,  j.failed },
		{ "poudriere:stats_ignored", INTEGER, NULL, 0,  j.ignored },
		{ "poudriere:stats_skipped", INTEGER, NULL, 0, j.skipped },
		{ "poudriere:stats_queued", INTEGER, NULL, 0, j.queued },
		{ "poudriere:status", STRING, j.status, sizeof(j.status), 0 },
		{ "mountpoint", STRING, j.mountpoint, sizeof(j.mountpoint), 0 },
		{ "name", STRING, j.fs, sizeof(j.fs), 0 },
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
		case 'j':
			jailname = optarg;
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
		zfs_list(props, "rootfs", sizeof(props) / sizeof(struct zfs_prop));
		break;
	case UPDATE:
		break;
	case DELETE:
		break;
	case START:
		if (zfs_query("rootfs", jailname, q, sizeof(q) / sizeof(struct zfs_query))) {
			jail_start(&j, true);
		} else {
			fprintf(stderr, "No such jail: %s\n", jailname);
		}
		break;
	case KILL:
		if (zfs_query("rootfs", jailname, q, sizeof(q) / sizeof(struct zfs_query))) {
			STAILQ_INIT(&j.children);
			jail_stop(&j);
		} else {
			fprintf(stderr, "No such jail: %s\n", jailname);
		}
		break;
	case NONE:
		usage_jail();
		break;
	}

	return (EX_OK);
}
