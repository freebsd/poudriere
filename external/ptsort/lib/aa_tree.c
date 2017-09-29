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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include "aa_tree.h"

static aa_node aa_nil = {
	.up = &aa_nil,
	.left = &aa_nil,
	.right = &aa_nil,
	.level = 0,
	.data = NULL,
};

#if AA_SLAB_ALLOCATOR

typedef struct aa_slab aa_slab;

struct aa_slab {
	unsigned int	 size;
	unsigned int	 free;
	unsigned int	 lastused;
	aa_slab		*next;
	aa_node		*firstfree;
	aa_node		 nodes[];
};

#define INITIAL_SLAB_SIZE 1048576
static aa_slab *slabs;

static aa_node *
aa_alloc(aa_node *parent, void *data)
{
	aa_node *node;
	aa_slab *slab;
	unsigned int size;

	/* search for a slab with free space */
	for (slab = slabs; slab != NULL; slab = slab->next)
		if (slab->free > 0)
			break;
	/* none?  create new slab */
	if (slab == NULL) {
		size = /* slabs ? slabs->size * 2 : */ INITIAL_SLAB_SIZE;
		slab = malloc(sizeof *slab + size * sizeof slab->nodes[0]);
		if (slab == NULL)
			return (NULL);
		slab->size = slab->free = size;
		slab->lastused = 0;
		slab->next = slabs;
		slab->firstfree = NULL;
		slabs = slab;
	}
	/* get first free node off slab */
	if (slab->firstfree != NULL) {
		/* previously returned */
		node = slab->firstfree;
		slab->firstfree = node->right;
	} else {
		/* never used before */
		assert(slab->lastused < slab->size);
		node = &slab->nodes[slab->lastused++];
	}
	slab->free--;
	node->up = parent;
	node->left = node->right = &aa_nil;
	node->level = 1;
	node->data = data;
	return (node);
}

static void
aa_free(aa_node *node)
{
	aa_slab *slab;

	/* search for slab from which node was allocated */
	for (slab = slabs; slab != NULL; slab = slab->next)
		if (node >= slab->nodes && node < slab->nodes + slab->size)
			break;
	assert(slab != NULL);
	/* clear node and prepend it to the free list */
	node->up = NULL;
	node->left = NULL;
	node->right = slab->firstfree;
	node->level = 0;
	node->data = NULL;
	slab->firstfree = node;
	slab->free++;
	if (slab->free == slab->size) {
		/* XXX free the slab! */
	}
}

#else

static aa_node *
aa_alloc(aa_node *parent, void *data)
{
	aa_node *node;

	if ((node = calloc(1, sizeof *node)) == NULL)
		return (NULL);
	node->up = parent;
	node->left = node->right = &aa_nil;
	node->level = 1;
	node->data = data;
	return (node);
}

static void
aa_free(aa_node *node)
{

	free(node);
}

#endif

aa_tree *
aa_init(aa_tree *tree, aa_comparator compare)
{

	if (tree == NULL && (tree = calloc(1, sizeof *tree)) == NULL)
		return (NULL);
	tree->compare = compare;
	tree->root = &aa_nil;
	tree->size = 0;
	return (tree);
}

static aa_node *
aa_skew(aa_node *node)
{
	aa_node *lc;

	if (node != &aa_nil &&
	    (lc = node->left) != &aa_nil &&
	    node->level == lc->level) {
		node->left = lc->right;
		if (node->left != &aa_nil)
			node->left->up = node;
		lc->right = node;
		lc->up = node->up;
		node->up = lc;
		node = lc;
	}
	return (node);
}

static aa_node *
aa_split(aa_node *node)
{
	aa_node *rc;

	if (node != &aa_nil &&
	    (rc = node->right) != &aa_nil &&
	    rc->right != &aa_nil &&
	    node->level == rc->right->level) {
		node->right = rc->left;
		if (node->right != &aa_nil)
			node->right->up = node;
		rc->left = node;
		rc->up = node->up;
		node->up = rc;
		rc->level++;
		node = rc;
	}
	return (node);
}

static void *
aa_insert_r(aa_tree *tree, aa_node *parent, aa_node **nodep, void *data)
{
	aa_node *node;
	void *ret;
	int cmp;

	ret = NULL;
	if ((node = *nodep) == &aa_nil) {
		if ((node = aa_alloc(parent, data)) == NULL)
			return (NULL);
		tree->size++;
		*nodep = node;
		return (node->data);
	} else if ((cmp = tree->compare(data, node->data)) == 0) {
		return (node->data);
	} else if (cmp < 0) {
		ret = aa_insert_r(tree, node, &node->left, data);
	} else /* (cmp > 0) */ {
		ret = aa_insert_r(tree, node, &node->right, data);
	}
	node = aa_split(aa_skew(node));
	*nodep = node;
	return (ret);
}

void *
aa_insert(aa_tree *tree, void *data)
{

	assert(data != NULL);
	return (aa_insert_r(tree, &aa_nil, &tree->root, data));
}

static aa_node *
aa_delete_r(aa_tree *tree, aa_node **nodep, void *key)
{
	aa_node *node, *pred, *succ;
	void *ret;
	int cmp;

	ret = NULL;
	if ((node = *nodep) == &aa_nil) {
		return (NULL);
	} else if ((cmp = tree->compare(key, node->data)) == 0) {
		if (node->left == &aa_nil && node->right == &aa_nil) {
			ret = node->data;
			aa_free(node);
			*nodep = &aa_nil;
			tree->size--;
			return (ret);
		} else if (node->left == &aa_nil) {
			succ = node->right;
			while (succ->left != &aa_nil)
				succ = succ->left;
			node->data = succ->data;
			ret = aa_delete_r(tree, &node->right, succ->data);
		} else {
			pred = node->left;
			while (pred->right != &aa_nil)
				pred = pred->right;
			node->data = pred->data;
			ret = aa_delete_r(tree, &node->left, pred->data);
		}
	} else if (cmp < 0) {
		ret = aa_delete_r(tree, &node->left, key);
	} else /* (cmp > 0) */ {
		ret = aa_delete_r(tree, &node->right, key);
	}
	if (node->left->level < node->level - 1 ||
	    node->right->level < node->level - 1)
		node->level = node->level - 1;
	node = aa_skew(node);
	node->right = aa_skew(node->right);
	node->right->right = aa_skew(node->right->right);
	node = aa_split(node);
	node->right = aa_split(node->right);
	*nodep = node;
	return (ret);
}

void *
aa_delete(aa_tree *tree, void *key)
{

	assert(key != NULL);
	return (aa_delete_r(tree, &tree->root, key));
}

void
aa_destroy(aa_tree *tree)
{

	while (tree->root != &aa_nil)
		aa_delete_r(tree, &tree->root, tree->root->data);
}

static void *
aa_find_r(const aa_node *node, const void *key, aa_comparator compare)
{
	aa_node *ret;
	int cmp;

	ret = NULL;
	if (node == &aa_nil)
		ret = NULL;
	else if ((cmp = compare(key, node->data)) == 0)
		ret = node->data;
	else if (cmp < 0)
		ret = aa_find_r(node->left, key, compare);
	else /* (cmp > 0) */
		ret = aa_find_r(node->right, key, compare);
	return (ret);
}

void *
aa_find(const aa_tree *tree, const void *key)
{

	assert(key != NULL);
	return (aa_find_r(tree->root, key, tree->compare));
}

void *
aa_first(const aa_tree *tree, aa_iterator **iterp)
{
	aa_iterator *iter;
	aa_node *node;

	if ((*iterp = iter = calloc(1, sizeof *iter)) == NULL)
		return (NULL);
	node = tree->root;
	while (node->left != &aa_nil)
		node = node->left;
	iter->cur = node;
	return (iter->cur->data);
}

void *
aa_next(aa_iterator **iterp)
{
	aa_iterator *iter = *iterp;

	if (iter == NULL || iter->cur == &aa_nil)
		return (NULL);

	if (iter->cur->left != &aa_nil) {
		/*
		 * If this node has a left subtree, we have already
		 * visited it, and we now need to go as far down the right
		 * subtree as possible.
		 */
		iter->cur = iter->cur->right;
		while (iter->cur->left != &aa_nil)
			iter->cur = iter->cur->left;
	} else if (iter->cur->right != &aa_nil) {
		/*
		 * If this node only has a right subtree, we have not yet
		 * visited it, and we now need to go as far down the right
		 * subtree as possible.
		 */
		iter->cur = iter->cur->right;
		while (iter->cur->left != &aa_nil)
			iter->cur = iter->cur->left;
	} else if (iter->cur == iter->cur->up->left) {
		/*
		 * This node is its parent's left child; visit the parent.
		 */
		iter->cur = iter->cur->up;
	} else if (iter->cur == iter->cur->up->right) {
		/*
		 * This node is its parent's right child; go up until we
		 * reach a node which is its parent left child, then up
		 * again.  This is also the path back to the root after
		 * having visited the last node.
		 */
		iter->cur = iter->cur->up;
		while (iter->cur != iter->cur->up->left)
			iter->cur = iter->cur->up;
		iter->cur = iter->cur->up;
	} else {
		/*
		 * This is the only node in the tree; it has neither
		 * children nor a parent, and we are done.
		 */
		iter->cur = &aa_nil;
	}
	return (iter->cur->data);
}

void
aa_finish(aa_iterator **iterp)
{
	aa_iterator *iter = *iterp;

	free(iter);
	*iterp = NULL;
}
