/* 
 * Copyright (c) 2011-2012 Baptiste Daroussin <bapt@FreeBSD.org>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <assert.h>
#include <err.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#include "commands.h"
#include "poudriere.h"
#include "parseconf.h"

struct poudriere_conf conf;
static void usage(void);
static void usage_help(void);
static int exec_help(int, char **);

static struct commands {
	const char * const name;
	const char * const desc;
	int (*exec)(int argc, char **argv);
	void (*const usage)(void);
} cmd[] = {
	{ "bulk", "Run bulks", NULL, NULL },
	{ "help", "Displays help information", exec_help, usage_help},
	{ "jail", "Manipulate the jails", exec_jail, usage_jail },
	{ "ports", "Manipulate the ports trees", exec_ports, usage_ports },
	{ "test", "Test some ports", NULL, NULL },
};

const unsigned int cmd_len = (sizeof(cmd) / sizeof(cmd[0]));

static void
usage(void)
{
	unsigned int i;

	fprintf(stderr, "usage: poudriere [-v] <command> [<args>]\n\n");
	fprintf(stderr, "Global options supported:\n");
	fprintf(stderr, "\t%-15s%s\n\n", "-v", "Display poudriere(8) version");
	fprintf(stderr, "Commands supported:\n");

	for (i = 0; i < cmd_len; i++)
		fprintf(stderr, "\t%-15s%s\n", cmd[i].name, cmd[i].desc);

	fprintf(stderr, "\nFor more information on the different commands"
			" see 'poudriere help <command>'.\n");

	exit(EX_USAGE);
}

static void
usage_help(void)
{
	unsigned int i;

	fprintf(stderr, "usage: poudriere help <command>\n\n");
	fprintf(stderr, "Where <command> can be:\n");

	for (i = 0; i < cmd_len; i++)
		fprintf(stderr, "\t%s\n", cmd[i].name);
}

static int
exec_help(int argc, char **argv)
{
	char *manpage;

	if ((argc != 2) || (strcmp("help", argv[1]) == 0)) {
		usage_help();
		return(EX_USAGE);
	}

	for (unsigned int i = 0; i < cmd_len; i++) {
		if (strcmp(cmd[i].name, argv[1]) == 0) {
			if (asprintf(&manpage, "/usr/bin/man poudriere-%s", cmd[i].name) == -1)
				errx(1, "cannot allocate memory");

			system(manpage);
			free(manpage);

			return (0);
		}
	}

	if (strcmp(argv[1], "poudriere") == 0) {
		system("/usr/bin/man 8 poudriere");
		return (0);
	} else if (strcmp(argv[1], "poudriere.conf") == 0) {
		system("/usr/bin/man 5 poudriere.conf");
		return (0);
	}

	/* Command name not found */
	warnx("'%s' is not a valid command.\n", argv[1]);
	
	fprintf(stderr, "See 'poudriere help' for more information on the commands.\n");

	return (EX_USAGE);
}

int
main(int argc, char **argv)
{
	struct commands *command = NULL;
	unsigned int ambiguous = 0;
	unsigned int i;
	signed char ch;
	size_t len;
	int ret = EX_OK;

	if (argc < 2)
		usage();

	while ((ch = getopt(argc, argv, "v")) != -1) {
		switch (ch) {
		case 'v':
			printf("1.99\n");
			exit(EX_OK);
			break;
		}
	}

	argc -= optind;
	argv += optind;

	parse_config("/usr/local/etc/poudriere2.conf");

	/* reset getopt for the next call */
	optreset = 1;
	optind = 1;

	len = strlen(argv[0]);
	for (i = 0; i < cmd_len; i++) {
		if (strncmp(argv[0], cmd[i].name, len) == 0) {
			/* if we have the exact cmd */
			if (len == strlen(cmd[i].name)) {
				command = &cmd[i];
				ambiguous = 0;
				break;
			}

			/*
			 * we already found a partial match so `argv[0]' is
			 * an ambiguous shortcut
			 */
			ambiguous++;

			command = &cmd[i];
		}
	}

	if (command == NULL)
		usage();

	if (ambiguous <= 1) {
		assert(command->exec != NULL);
		ret = command->exec(argc, argv);
	} else {
		warnx("'%s' is not a valid command.\n", argv[0]);

		fprintf(stderr, "See 'poudriere help' for more information on the commands.\n\n");
		fprintf(stderr, "Command '%s' could be one of the following:\n", argv[0]);

		for (i = 0; i < cmd_len; i++)
			if (strncmp(argv[0], cmd[i].name, len) == 0)
				fprintf(stderr, "\t%s\n",cmd[i].name);
	}
	
	return (ret);
}
