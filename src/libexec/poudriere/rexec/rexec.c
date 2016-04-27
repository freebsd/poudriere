/*-
 * Copyright (c) 2014 Baptiste Daroussin <bapt@FreeBSD.org>
 * All rights reserved.
 *~
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *~
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

#include <sys/types.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <libgen.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <err.h>
#include <nv.h>

int
main(int argc, char **argv)
{
	struct sockaddr_un un;
	int ch;
	int fd;
	int i;
	char *sock = NULL;
	char *user = NULL;
	nvlist_t *nv, *arguments;
	char key[4];

	while ((ch = getopt(argc, argv, "s:u:")) != -1) {
		switch (ch) {
		case 's':
			sock = optarg;
			break;
		case 'u':
			user = optarg;
		}
	}
	argc -= optind;
	argv += optind;

	if (!sock)
		errx(EXIT_FAILURE, "rexec -s <socketpath> [-u user] <cmd>");

	if ((fd = socket(AF_UNIX, SOCK_STREAM, 0)) < 0)
		err(EXIT_FAILURE, "socket()");

	memset(&un, 0, sizeof(struct sockaddr_un));
	un.sun_family = AF_UNIX;
	if (chdir(dirname(sock)))
		err(EXIT_FAILURE, "chdir()");
	strlcpy(un.sun_path, basename(sock), sizeof(un.sun_path));

	if (connect(fd, (struct sockaddr *) &un, sizeof(struct sockaddr_un)) == -1)
		err(EXIT_FAILURE, "connect(%s)", sock);

	nv = nvlist_create(0);
	arguments = nvlist_create(0);

	if (user)
		nvlist_add_string(nv, "user", user);

	nvlist_add_string(nv, "command", argv[0]);
	for (i = 0; i < argc; i++) {
		snprintf(key, sizeof(key), "%d", i);
		nvlist_add_string(arguments, key, argv[i]);
	}
	nvlist_add_nvlist(nv, "arguments", arguments);
	nvlist_add_descriptor(nv, "stdout", STDOUT_FILENO);
	nvlist_add_descriptor(nv, "stderr", STDERR_FILENO);
	nvlist_add_descriptor(nv, "stdin", STDIN_FILENO);

	if (nvlist_send(fd, nv) < 0) {
		nvlist_destroy(nv);
		err(EXIT_FAILURE, "nvlist_send() failed");
	}
	nvlist_destroy(nv);

	nv = nvlist_recv(fd, 0);
	if (nv == NULL)
		err(1, "nvlist_recv() failed");

	i = nvlist_get_number(nv, "return");

	return (i);
}
