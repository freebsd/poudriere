/*-
 * Copyright (c) 2016 Dag-Erling Smørgrav
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote
 *    products derived from this software without specific prior written
 *    permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fline.h"

struct fline_buf {
	FILE *curf;
	char *buf, *line, *next, *end;
	size_t len, size;
};

/*
 * Allocate and initialize a fline buffer
 */
struct fline_buf *
fline_new(void)
{

	return (calloc(1, sizeof(struct fline_buf)));
}

/*
 * Free a fline buffer
 */
void
fline_free(struct fline_buf *lb)
{

	free(lb->buf);
	memset(lb, 0, sizeof *lb);
	free(lb);
}

/*
 * Read a full line of text from a stream
 */
const char *
fline_read(FILE *f, struct fline_buf *lb)
{
	char *p, *q;
	char *tmpbuf;
	size_t r;

	if (lb->buf == NULL) {
		/* first call, allocate buffer */
		lb->size = 1024;
		if ((lb->buf = malloc(lb->size)) == NULL)
			return (NULL);
	}
	if (f != lb->curf) {
		/* first call for new file, reset pointers */
		lb->next = lb->line = lb->end = lb->buf;
		lb->len = 0;
		lb->curf = f;
	}

	/*
	 * See if we already have a full line waiting.
	 */
	for (p = q = lb->next; q < lb->end; ++q) {
		if (*q == '\n') {
			lb->next = q + 1;
			*q = '\0';
			return (p);
		}
	}

	/*
	 * Either our buffer is empty, or it only contains a partial line.
	 * We need to read more data into it, and possibly expand it.
	 * Start by moving the partial line (if any) up to the front.
	 */
	if (lb->next > lb->buf) {
		/* shift everything up by next - buf */
		lb->len = lb->end - lb->next;
		memmove(lb->buf, lb->next, lb->len);
		lb->next = lb->buf;
		lb->end = lb->buf + lb->len;
	}
	for (;;) {
		if (lb->len == lb->size) {
			/* expand the buffer */
			lb->size = lb->size * 2;
			if ((tmpbuf = realloc(lb->buf, lb->size)) == NULL)
				return (NULL);
			lb->buf = tmpbuf;
			lb->end = lb->buf + lb->len;
		}
		if ((r = fread(lb->end, 1, lb->size - lb->len, f)) == 0) {
			/* either EOF or error */
			if (lb->len == 0) {
				/* we got nothing */
				return (NULL);
			}
			/* whatever is left */
			lb->next = lb->end + 1;
			*lb->end = '\0';
			return (lb->buf);
		}
		/* we got something, let's look for EOL */
		lb->len += r;
		lb->end += r;
		for (p = q = lb->next; q < lb->end; ++q) {
			if (*q == '\n') {
				lb->next = q + 1;
				*q = '\0';
				return (p);
			}
		}
		/* nothing, loop around */
	}
}
