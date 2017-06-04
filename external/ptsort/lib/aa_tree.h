/*-
 * Copyright (c) 2016 Universitetet i Oslo
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

#ifndef AA_TREE_H_INCLUDED
#define AA_TREE_H_INCLUDED

typedef int (*aa_comparator)(const void *, const void *);

typedef struct aa_tree {
	struct aa_node	*root;
	unsigned int	 size;
	aa_comparator	 compare;
} aa_tree;

typedef struct aa_node {
	struct aa_node	*up;
	struct aa_node	*left;
	struct aa_node	*right;
	unsigned int	 level;
	void		*data;
} aa_node;

typedef struct aa_iterator {
	struct aa_node	*cur;
} aa_iterator;

aa_tree *aa_init(aa_tree *, aa_comparator);
void aa_destroy(aa_tree *);
void *aa_insert(aa_tree *, void *);
void *aa_delete(aa_tree *, void *);
void *aa_find(const aa_tree *, const void *);

void *aa_first(const aa_tree *, aa_iterator **);
void *aa_next(aa_iterator **);
void aa_finish(aa_iterator **);

#endif
