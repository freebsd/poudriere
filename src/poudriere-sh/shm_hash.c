/*-
 * SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Baptiste Daroussin <bapt@FreeBSD.org>
 */

/*
 * Lock-free hash table in POSIX shared memory.
 *
 * Layout of a segment:
 *   [shm_hash_header][entry_table[nbuckets]][string_pool[pool_size]]
 */

#include <sys/types.h>
#include <sys/mman.h>

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#ifndef SHELL
#error Only supported as a builtin
#endif

#include "bltin/bltin.h"
#include "helpers.h"
#include "var.h"

static unsigned long
shm_get_ulong(const char *str, const char *desc)
{
	char *endp = NULL;
	unsigned long val;

	errno = 0;
	val = strtoul(str, &endp, 10);
	if (*endp != '\0' || errno != 0)
		err(EX_USAGE, "Invalid %s", desc);
	return (val);
}

#define SHM_HASH_MAGIC	0x53484D02U

struct shm_hash_header {
	uint32_t	magic;
	uint32_t	nbuckets;
	_Atomic uint32_t count;
	uint32_t	pool_size;
	_Atomic uint32_t pool_used;
};

struct shm_hash_entry {
	_Atomic uint32_t hash;		/* 0 = empty, 1 = BUSY */
	uint16_t	key_len;	/* immutable after insert */
	uint16_t	_pad;
	uint32_t	key_off;	/* immutable after insert */
	uint32_t	_pad2;
	_Atomic uint64_t value_desc;	/* atomic: (off << 32) | len */
};	/* 24 bytes */

#define VDESC_MAKE(off, len)	(((uint64_t)(off) << 32) | (uint32_t)(len))
#define VDESC_OFF(vd)		((uint32_t)((vd) >> 32))
#define VDESC_LEN(vd)		((uint32_t)((vd) & 0xFFFFFFFFU))

/*
 * Slot states:
 *   0              — empty
 *   SHM_HASH_BUSY  — claimed by a writer, metadata not yet valid
 *   anything else  — occupied, metadata valid (the real hash)
 */
#define SHM_HASH_BUSY	1U

/* FNV-1a 32-bit */
static uint32_t
fnv1a(const char *key, size_t len)
{
	uint32_t h = 2166136261U;
	const unsigned char *p = (const unsigned char *)key;

	for (size_t i = 0; i < len; i++) {
		h ^= p[i];
		h *= 16777619U;
	}
	/* Never return 0 (empty) or SHM_HASH_BUSY (reserved). */
	if (h == 0 || h == SHM_HASH_BUSY)
		h = 2;
	return (h);
}

static size_t
next_prime(size_t n)
{
	size_t i;

	if (n <= 2)
		return (2);
	if ((n & 1) == 0)
		n++;
	for (;; n += 2) {
		for (i = 3; i * i <= n; i += 2) {
			if (n % i == 0)
				break;
		}
		if (i * i > n)
			return (n);
	}
}

static size_t
segment_size(uint32_t nbuckets, uint32_t pool_size)
{

	return (sizeof(struct shm_hash_header) +
	    (size_t)nbuckets * sizeof(struct shm_hash_entry) +
	    pool_size);
}

static struct shm_hash_entry *
entry_table(struct shm_hash_header *hdr)
{

	return ((struct shm_hash_entry *)(hdr + 1));
}

static char *
string_pool(struct shm_hash_header *hdr)
{

	return ((char *)(entry_table(hdr) + hdr->nbuckets));
}

/*
 * Create or open a shm segment.  Called with INTOFF.
 * Returns the mapped header (caller must munmap) or NULL on error.
 * On success *out_size is set to the mapped size.
 *
 * If excl is true, any existing segment is removed first (explicit create).
 * If excl is false, an existing segment is opened or created, with CAS
 * on magic to arbitrate which process initializes the header.
 */
static struct shm_hash_header *
shm_hash_do_create(const char *name, size_t capacity, size_t avg_data,
    int excl, size_t *out_size)
{
	struct shm_hash_header *hdr;
	size_t total;
	uint32_t nbuckets, pool_size, expected;
	int fd;

	/* Table size: ~150% of capacity, rounded up to a prime. */
	nbuckets = (uint32_t)next_prime(capacity + capacity / 2 + 1);
	pool_size = (uint32_t)(capacity * avg_data);
	total = segment_size(nbuckets, pool_size);

	if (excl)
		shm_unlink(name);

	fd = shm_open(name, O_RDWR | O_CREAT | (excl ? O_EXCL : 0), 0600);
	if (fd == -1)
		return (NULL);
	if (ftruncate(fd, (off_t)total) == -1) {
		close(fd);
		if (excl)
			shm_unlink(name);
		return (NULL);
	}
	hdr = mmap(NULL, total, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	close(fd);
	if (hdr == MAP_FAILED) {
		if (excl)
			shm_unlink(name);
		return (NULL);
	}

	/*
	 * CAS on magic to arbitrate initialization.
	 * Winner writes 1 (initializing), sets header fields,
	 * then publishes SHM_HASH_MAGIC.
	 * Losers spin until magic == SHM_HASH_MAGIC.
	 */
	expected = 0;
	if (atomic_compare_exchange_strong_explicit(
	    (_Atomic uint32_t *)&hdr->magic, &expected, 1U,
	    memory_order_acq_rel, memory_order_acquire)) {
		/* We won — initialize the header. */
		hdr->nbuckets = nbuckets;
		hdr->pool_size = pool_size;
		atomic_store_explicit(&hdr->count, 0,
		    memory_order_relaxed);
		atomic_store_explicit(&hdr->pool_used, 0,
		    memory_order_relaxed);
		/* Publish: magic last. */
		atomic_store_explicit((_Atomic uint32_t *)&hdr->magic,
		    SHM_HASH_MAGIC, memory_order_release);
	} else if (expected == 1U) {
		/* Another process is initializing — wait. */
		while (atomic_load_explicit(
		    (_Atomic uint32_t *)&hdr->magic,
		    memory_order_acquire) != SHM_HASH_MAGIC)
			;
	} else if (expected != SHM_HASH_MAGIC) {
		/*
		 * Stale segment from an old version (different magic).
		 * Destroy and recreate.
		 */
		munmap(hdr, total);
		shm_unlink(name);
		fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd == -1) {
			/* Lost the race — another process recreated it. */
			fd = shm_open(name, O_RDWR | O_CREAT, 0600);
			if (fd == -1)
				return (NULL);
		}
		if (ftruncate(fd, (off_t)total) == -1) {
			close(fd);
			return (NULL);
		}
		hdr = mmap(NULL, total, PROT_READ | PROT_WRITE,
		    MAP_SHARED, fd, 0);
		close(fd);
		if (hdr == MAP_FAILED)
			return (NULL);
		/* Re-attempt initialization. */
		expected = 0;
		if (atomic_compare_exchange_strong_explicit(
		    (_Atomic uint32_t *)&hdr->magic, &expected, 1U,
		    memory_order_acq_rel, memory_order_acquire)) {
			hdr->nbuckets = nbuckets;
			hdr->pool_size = pool_size;
			atomic_store_explicit(&hdr->count, 0,
			    memory_order_relaxed);
			atomic_store_explicit(&hdr->pool_used, 0,
			    memory_order_relaxed);
			atomic_store_explicit(
			    (_Atomic uint32_t *)&hdr->magic,
			    SHM_HASH_MAGIC, memory_order_release);
		} else {
			while (atomic_load_explicit(
			    (_Atomic uint32_t *)&hdr->magic,
			    memory_order_acquire) != SHM_HASH_MAGIC)
				;
		}
	}

	*out_size = total;
	return (hdr);
}

/*
 * shm_hash_create name capacity [data_size]
 *
 * Create a POSIX shm segment with an empty hash table sized for
 * `capacity` entries.  Optional `data_size` is the average expected
 * bytes per entry for the string pool (default 200).
 */
int
shm_hash_createcmd(int argc, char **argv)
{
	struct shm_hash_header *hdr;
	const char *name;
	size_t total, capacity, avg_data;

	if (argc < 3 || argc > 4)
		errx(EX_USAGE, "Usage: shm_hash_create name capacity "
		    "[data_size]");

	name = argv[1];
	capacity = (size_t)shm_get_ulong(argv[2], "capacity");
	avg_data = (argc == 4) ? (size_t)shm_get_ulong(argv[3], "data_size") : 200;

	INTOFF;
	hdr = shm_hash_do_create(name, capacity, avg_data, 1, &total);
	if (hdr == NULL) {
		INTON;
		err(EXIT_FAILURE, "shm_hash_create(%s)", name);
	}
	munmap(hdr, total);
	INTON;
	return (0);
}

/*
 * Auto-create a segment when shm_hash_set finds it missing.
 * Uses SHASH_SHM_CAPACITY from the environment (default 131072).
 * Called with INTOFF.
 */
static struct shm_hash_header *
shm_hash_autocreate(const char *name, size_t *out_size)
{
	const char *cap_str;
	size_t capacity;

	cap_str = getenv("SHASH_SHM_CAPACITY");
	capacity = (cap_str != NULL) ? strtoul(cap_str, NULL, 10) : 131072;
	if (capacity == 0)
		capacity = 131072;
	return (shm_hash_do_create(name, capacity, 200, 0, out_size));
}

/*
 * Map an existing shm segment.  Returns the header pointer and sets
 * *out_size to the mapped size.  Caller must munmap().
 */
static struct shm_hash_header *
shm_hash_map(const char *name, size_t *out_size)
{
	struct shm_hash_header probe;
	struct shm_hash_header *hdr;
	size_t total;
	int fd;

	fd = shm_open(name, O_RDWR, 0);
	if (fd == -1)
		return (NULL);

	/* First map just the header to learn the real size. */
	if (read(fd, &probe, sizeof(probe)) != (ssize_t)sizeof(probe)) {
		close(fd);
		return (NULL);
	}
	if (atomic_load_explicit((_Atomic uint32_t *)&probe.magic,
	    memory_order_acquire) != SHM_HASH_MAGIC) {
		close(fd);
		return (NULL);
	}

	total = segment_size(probe.nbuckets, probe.pool_size);
	hdr = mmap(NULL, total, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	close(fd);
	if (hdr == MAP_FAILED)
		return (NULL);

	*out_size = total;
	return (hdr);
}

/*
 * shm_hash_set [-n] name key value
 *
 * Insert key=value.  Returns 0 on success, 2 if the table or pool
 * is full.  With -n (noclobber): returns 1 if the key already exists.
 * Without -n: updates the value if the key exists (last writer wins).
 */
int
shm_hash_setcmd(int argc, char **argv)
{
	struct shm_hash_header *hdr;
	struct shm_hash_entry *ent;
	const char *name, *key, *value;
	char *pool;
	size_t map_size;
	uint32_t h, idx, klen, vlen, off, expect;
	int ret, noclobber;

	noclobber = 0;
	if (argc >= 2 && strcmp(argv[1], "-n") == 0) {
		noclobber = 1;
		argv++;
		argc--;
	}
	if (argc != 4)
		errx(EX_USAGE, "Usage: shm_hash_set [-n] name key value");

	name = argv[1];
	key = argv[2];
	value = argv[3];
	klen = (uint32_t)strlen(key);
	vlen = (uint32_t)strlen(value);

	INTOFF;
	hdr = shm_hash_autocreate(name, &map_size);
	if (hdr == NULL) {
		INTON;
		err(EXIT_FAILURE, "shm_hash_set: cannot create %s", name);
	}

	h = fnv1a(key, klen);
	idx = h % hdr->nbuckets;
	ent = entry_table(hdr);
	pool = string_pool(hdr);
	ret = 0;

	for (uint32_t i = 0; i < hdr->nbuckets; i++) {
		uint32_t slot = (idx + i) % hdr->nbuckets;
		uint32_t slot_hash = atomic_load_explicit(&ent[slot].hash,
		    memory_order_acquire);

		if (slot_hash == h) {
			/* Potential match — verify key. */
			if (ent[slot].key_len == klen &&
			    memcmp(pool + ent[slot].key_off, key, klen) == 0) {
				if (noclobber) {
					ret = 1;
					goto out;
				}
				/*
				 * Key exists — update value (last writer
				 * wins, matching write_atomic semantics).
				 * Allocate new pool space for the value;
				 * old space is leaked but the pool is
				 * append-only.
				 */
				off = atomic_fetch_add_explicit(
				    &hdr->pool_used, vlen + 1,
				    memory_order_relaxed);
				if (off + vlen + 1 > hdr->pool_size) {
					ret = 2;
					goto out;
				}
				memcpy(pool + off, value, vlen);
				pool[off + vlen] = '\0';
				atomic_store_explicit(
				    &ent[slot].value_desc,
				    VDESC_MAKE(off, vlen),
				    memory_order_release);
				goto out;
			}
			/* Hash collision, different key — keep probing. */
			continue;
		}
		if (slot_hash == SHM_HASH_BUSY) {
			/*
			 * Another writer is setting up this slot.
			 * Spin until it publishes the real hash.
			 */
			while ((slot_hash = atomic_load_explicit(
			    &ent[slot].hash,
			    memory_order_acquire)) == SHM_HASH_BUSY)
				;
			/* Re-evaluate this slot with the real hash. */
			i--;
			continue;
		}
		if (slot_hash != 0) {
			/* Occupied by a different hash — keep probing. */
			continue;
		}

		/* Empty slot — try to claim it with CAS 0 → BUSY. */
		expect = 0;
		if (!atomic_compare_exchange_strong_explicit(
		    &ent[slot].hash, &expect, SHM_HASH_BUSY,
		    memory_order_acq_rel, memory_order_acquire)) {
			/*
			 * Someone else claimed it.  Re-check this slot.
			 */
			i--;
			continue;
		}

		/* Slot is ours.  Allocate from the string pool. */
		off = atomic_fetch_add_explicit(&hdr->pool_used,
		    klen + vlen + 2, memory_order_relaxed);
		if (off + klen + vlen + 2 > hdr->pool_size) {
			/*
			 * Pool is full.  Release the slot as empty
			 * so probing still works.
			 */
			atomic_store_explicit(&ent[slot].hash, 0,
			    memory_order_release);
			ret = 2;
			goto out;
		}

		memcpy(pool + off, key, klen);
		pool[off + klen] = '\0';
		memcpy(pool + off + klen + 1, value, vlen);
		pool[off + klen + 1 + vlen] = '\0';

		ent[slot].key_off = off;
		ent[slot].key_len = (uint16_t)klen;
		atomic_store_explicit(&ent[slot].value_desc,
		    VDESC_MAKE(off + klen + 1, vlen),
		    memory_order_relaxed);

		/*
		 * Publish the real hash — readers will now see
		 * both the hash and all metadata fields.
		 */
		atomic_store_explicit(&ent[slot].hash, h,
		    memory_order_release);
		atomic_fetch_add_explicit(&hdr->count, 1,
		    memory_order_relaxed);
		goto out;
	}

	/* Table is full. */
	ret = 2;
out:
	munmap(hdr, map_size);
	INTON;
	return (ret);
}

/*
 * shm_hash_get name key variable
 *
 * Lookup key and set the shell variable.  Returns 0 if found, 1 if
 * not found.
 */
int
shm_hash_getcmd(int argc, char **argv)
{
	struct shm_hash_header *hdr;
	struct shm_hash_entry *ent;
	const char *name, *key, *var_return;
	char *pool;
	size_t map_size;
	uint32_t h, idx, klen;
	int ret;

	if (argc != 4)
		errx(EX_USAGE, "Usage: shm_hash_get name key variable");

	name = argv[1];
	key = argv[2];
	var_return = argv[3];
	klen = (uint32_t)strlen(key);

	INTOFF;
	hdr = shm_hash_map(name, &map_size);
	if (hdr == NULL) {
		INTON;
		return (1);
	}

	h = fnv1a(key, klen);
	idx = h % hdr->nbuckets;
	ent = entry_table(hdr);
	pool = string_pool(hdr);
	ret = 1;

	for (uint32_t i = 0; i < hdr->nbuckets; i++) {
		uint32_t slot = (idx + i) % hdr->nbuckets;
		uint32_t slot_hash = atomic_load_explicit(&ent[slot].hash,
		    memory_order_acquire);

		if (slot_hash == 0)
			break;	/* Empty — key not in table. */

		if (slot_hash == SHM_HASH_BUSY) {
			/* Writer in progress — spin then re-check. */
			while ((slot_hash = atomic_load_explicit(
			    &ent[slot].hash,
			    memory_order_acquire)) == SHM_HASH_BUSY)
				;
			if (slot_hash == 0)
				break;
		}

		if (slot_hash != h)
			continue;

		/* Hash matches — verify key. */
		if (ent[slot].key_len == klen &&
		    memcmp(pool + ent[slot].key_off, key, klen) == 0) {
			/* Found it — read value atomically. */
			uint64_t vd = atomic_load_explicit(
			    &ent[slot].value_desc,
			    memory_order_acquire);
			uint32_t voff = VDESC_OFF(vd);
			uint32_t vlen = VDESC_LEN(vd);

			if (strcmp(var_return, "-") == 0) {
				printf("%.*s\n", (int)vlen,
				    pool + voff);
			} else {
				char vbuf[vlen + 1];
				memcpy(vbuf, pool + voff, vlen);
				vbuf[vlen] = '\0';
				if (setvarsafe(var_return, vbuf, 0)) {
					munmap(hdr, map_size);
					INTON;
					return (1);
				}
			}
			ret = 0;
			break;
		}
	}

	munmap(hdr, map_size);
	INTON;
	return (ret);
}

/*
 * shm_hash_exists name key
 *
 * Returns 0 if key exists, 1 otherwise.
 */
int
shm_hash_existscmd(int argc, char **argv)
{
	struct shm_hash_header *hdr;
	struct shm_hash_entry *ent;
	const char *name, *key;
	char *pool;
	size_t map_size;
	uint32_t h, idx, klen;
	int ret;

	if (argc != 3)
		errx(EX_USAGE, "Usage: shm_hash_exists name key");

	name = argv[1];
	key = argv[2];
	klen = (uint32_t)strlen(key);

	INTOFF;
	hdr = shm_hash_map(name, &map_size);
	if (hdr == NULL) {
		INTON;
		return (1);
	}

	h = fnv1a(key, klen);
	idx = h % hdr->nbuckets;
	ent = entry_table(hdr);
	pool = string_pool(hdr);
	ret = 1;

	for (uint32_t i = 0; i < hdr->nbuckets; i++) {
		uint32_t slot = (idx + i) % hdr->nbuckets;
		uint32_t slot_hash = atomic_load_explicit(&ent[slot].hash,
		    memory_order_acquire);

		if (slot_hash == 0)
			break;

		if (slot_hash == SHM_HASH_BUSY) {
			while ((slot_hash = atomic_load_explicit(
			    &ent[slot].hash,
			    memory_order_acquire)) == SHM_HASH_BUSY)
				;
			if (slot_hash == 0)
				break;
		}

		if (slot_hash != h)
			continue;

		if (ent[slot].key_len == klen &&
		    memcmp(pool + ent[slot].key_off, key, klen) == 0) {
			ret = 0;
			break;
		}
	}

	munmap(hdr, map_size);
	INTON;
	return (ret);
}

/*
 * shm_hash_destroy name
 *
 * Unlink the shm segment.
 */
int
shm_hash_destroycmd(int argc, char **argv)
{

	if (argc != 2)
		errx(EX_USAGE, "Usage: shm_hash_destroy name");

	if (shm_unlink(argv[1]) == -1 && errno != ENOENT)
		err(EXIT_FAILURE, "shm_unlink(%s)", argv[1]);

	return (0);
}
