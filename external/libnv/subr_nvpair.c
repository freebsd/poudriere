/*-
 * Copyright (c) 2009-2013 The FreeBSD Foundation
 * All rights reserved.
 *
 * This software was developed by Pawel Jakub Dawidek under sponsorship from
 * the FreeBSD Foundation.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <sys/cdefs.h>
__FBSDID("$FreeBSD: head/sys/kern/subr_nvpair.c 279439 2015-03-01 00:34:27Z rstone $");

#include <sys/param.h>
#include <sys/endian.h>
#include <sys/queue.h>

#ifdef _KERNEL

#include <sys/errno.h>
#include <sys/lock.h>
#include <sys/malloc.h>
#include <sys/systm.h>

#include <machine/stdarg.h>

#else
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "common_impl.h"
#endif

#ifdef HAVE_PJDLOG
#include <pjdlog.h>
#endif

#include <sys/nv.h>
#include <sys/nv_impl.h>
#include <sys/nvlist_impl.h>
#include <sys/nvpair_impl.h>

#ifndef	HAVE_PJDLOG
#ifdef _KERNEL
#define	PJDLOG_ASSERT(...)		MPASS(__VA_ARGS__)
#define	PJDLOG_RASSERT(expr, ...)	KASSERT(expr, (__VA_ARGS__))
#define	PJDLOG_ABORT(...)		panic(__VA_ARGS__)
#else
#include <assert.h>
#define	PJDLOG_ASSERT(...)		assert(__VA_ARGS__)
#define	PJDLOG_RASSERT(expr, ...)	assert(expr)
#define	PJDLOG_ABORT(...)		abort()
#endif
#endif

#define	NVPAIR_MAGIC	0x6e7670	/* "nvp" */
struct nvpair {
	int		 nvp_magic;
	char		*nvp_name;
	int		 nvp_type;
	uint64_t	 nvp_data;
	size_t		 nvp_datasize;
	nvlist_t	*nvp_list;
	TAILQ_ENTRY(nvpair) nvp_next;
};

#define	NVPAIR_ASSERT(nvp)	do {					\
	PJDLOG_ASSERT((nvp) != NULL);					\
	PJDLOG_ASSERT((nvp)->nvp_magic == NVPAIR_MAGIC);		\
} while (0)

struct nvpair_header {
	uint8_t		nvph_type;
	uint16_t	nvph_namesize;
	uint64_t	nvph_datasize;
} __packed;


void
nvpair_assert(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
}

nvlist_t *
nvpair_nvlist(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	return (nvp->nvp_list);
}

nvpair_t *
nvpair_next(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_list != NULL);

	return (TAILQ_NEXT(nvp, nvp_next));
}

nvpair_t *
nvpair_prev(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_list != NULL);

	return (TAILQ_PREV(nvp, nvl_head, nvp_next));
}

void
nvpair_insert(struct nvl_head *head, nvpair_t *nvp, nvlist_t *nvl)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_list == NULL);
	PJDLOG_ASSERT(!nvlist_exists(nvl, nvpair_name(nvp)));

	TAILQ_INSERT_TAIL(head, nvp, nvp_next);
	nvp->nvp_list = nvl;
}

static void
nvpair_remove_nvlist(nvpair_t *nvp)
{
	nvlist_t *nvl;

	/* XXX: DECONST is bad, mkay? */
	nvl = __DECONST(nvlist_t *, nvpair_get_nvlist(nvp));
	PJDLOG_ASSERT(nvl != NULL);
	nvlist_set_parent(nvl, NULL);
}

void
nvpair_remove(struct nvl_head *head, nvpair_t *nvp, const nvlist_t *nvl)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_list == nvl);

	if (nvpair_type(nvp) == NV_TYPE_NVLIST)
		nvpair_remove_nvlist(nvp);

	TAILQ_REMOVE(head, nvp, nvp_next);
	nvp->nvp_list = NULL;
}

nvpair_t *
nvpair_clone(const nvpair_t *nvp)
{
	nvpair_t *newnvp;
	const char *name;
	const void *data;
	size_t datasize;

	NVPAIR_ASSERT(nvp);

	name = nvpair_name(nvp);

	switch (nvpair_type(nvp)) {
	case NV_TYPE_NULL:
		newnvp = nvpair_create_null(name);
		break;
	case NV_TYPE_BOOL:
		newnvp = nvpair_create_bool(name, nvpair_get_bool(nvp));
		break;
	case NV_TYPE_NUMBER:
		newnvp = nvpair_create_number(name, nvpair_get_number(nvp));
		break;
	case NV_TYPE_STRING:
		newnvp = nvpair_create_string(name, nvpair_get_string(nvp));
		break;
	case NV_TYPE_NVLIST:
		newnvp = nvpair_create_nvlist(name, nvpair_get_nvlist(nvp));
		break;
#ifndef _KERNEL
	case NV_TYPE_DESCRIPTOR:
		newnvp = nvpair_create_descriptor(name,
		    nvpair_get_descriptor(nvp));
		break;
#endif
	case NV_TYPE_BINARY:
		data = nvpair_get_binary(nvp, &datasize);
		newnvp = nvpair_create_binary(name, data, datasize);
		break;
	default:
		PJDLOG_ABORT("Unknown type: %d.", nvpair_type(nvp));
	}

	return (newnvp);
}

size_t
nvpair_header_size(void)
{

	return (sizeof(struct nvpair_header));
}

size_t
nvpair_size(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	return (nvp->nvp_datasize);
}

unsigned char *
nvpair_pack_header(const nvpair_t *nvp, unsigned char *ptr, size_t *leftp)
{
	struct nvpair_header nvphdr;
	size_t namesize;

	NVPAIR_ASSERT(nvp);

	nvphdr.nvph_type = nvp->nvp_type;
	namesize = strlen(nvp->nvp_name) + 1;
	PJDLOG_ASSERT(namesize > 0 && namesize <= UINT16_MAX);
	nvphdr.nvph_namesize = namesize;
	nvphdr.nvph_datasize = nvp->nvp_datasize;
	PJDLOG_ASSERT(*leftp >= sizeof(nvphdr));
	memcpy(ptr, &nvphdr, sizeof(nvphdr));
	ptr += sizeof(nvphdr);
	*leftp -= sizeof(nvphdr);

	PJDLOG_ASSERT(*leftp >= namesize);
	memcpy(ptr, nvp->nvp_name, namesize);
	ptr += namesize;
	*leftp -= namesize;

	return (ptr);
}

unsigned char *
nvpair_pack_null(const nvpair_t *nvp, unsigned char *ptr,
    size_t *leftp __unused)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_NULL);

	return (ptr);
}

unsigned char *
nvpair_pack_bool(const nvpair_t *nvp, unsigned char *ptr, size_t *leftp)
{
	uint8_t value;

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_BOOL);

	value = (uint8_t)nvp->nvp_data;

	PJDLOG_ASSERT(*leftp >= sizeof(value));
	memcpy(ptr, &value, sizeof(value));
	ptr += sizeof(value);
	*leftp -= sizeof(value);

	return (ptr);
}

unsigned char *
nvpair_pack_number(const nvpair_t *nvp, unsigned char *ptr, size_t *leftp)
{
	uint64_t value;

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_NUMBER);

	value = (uint64_t)nvp->nvp_data;

	PJDLOG_ASSERT(*leftp >= sizeof(value));
	memcpy(ptr, &value, sizeof(value));
	ptr += sizeof(value);
	*leftp -= sizeof(value);

	return (ptr);
}

unsigned char *
nvpair_pack_string(const nvpair_t *nvp, unsigned char *ptr, size_t *leftp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_STRING);

	PJDLOG_ASSERT(*leftp >= nvp->nvp_datasize);
	memcpy(ptr, (const void *)(intptr_t)nvp->nvp_data, nvp->nvp_datasize);
	ptr += nvp->nvp_datasize;
	*leftp -= nvp->nvp_datasize;

	return (ptr);
}

unsigned char *
nvpair_pack_nvlist_up(unsigned char *ptr, size_t *leftp)
{
	struct nvpair_header nvphdr;
	size_t namesize;
	const char *name = "";

	namesize = 1;
	nvphdr.nvph_type = NV_TYPE_NVLIST_UP;
	nvphdr.nvph_namesize = namesize;
	nvphdr.nvph_datasize = 0;
	PJDLOG_ASSERT(*leftp >= sizeof(nvphdr));
	memcpy(ptr, &nvphdr, sizeof(nvphdr));
	ptr += sizeof(nvphdr);
	*leftp -= sizeof(nvphdr);

	PJDLOG_ASSERT(*leftp >= namesize);
	memcpy(ptr, name, namesize);
	ptr += namesize;
	*leftp -= namesize;

	return (ptr);
}

#ifndef _KERNEL
unsigned char *
nvpair_pack_descriptor(const nvpair_t *nvp, unsigned char *ptr, int64_t *fdidxp,
    size_t *leftp)
{
	int64_t value;

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_DESCRIPTOR);

	value = (int64_t)nvp->nvp_data;
	if (value != -1) {
		/*
		 * If there is a real descriptor here, we change its number
		 * to position in the array of descriptors send via control
		 * message.
		 */
		PJDLOG_ASSERT(fdidxp != NULL);

		value = *fdidxp;
		(*fdidxp)++;
	}

	PJDLOG_ASSERT(*leftp >= sizeof(value));
	memcpy(ptr, &value, sizeof(value));
	ptr += sizeof(value);
	*leftp -= sizeof(value);

	return (ptr);
}
#endif

unsigned char *
nvpair_pack_binary(const nvpair_t *nvp, unsigned char *ptr, size_t *leftp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_BINARY);

	PJDLOG_ASSERT(*leftp >= nvp->nvp_datasize);
	memcpy(ptr, (const void *)(intptr_t)nvp->nvp_data, nvp->nvp_datasize);
	ptr += nvp->nvp_datasize;
	*leftp -= nvp->nvp_datasize;

	return (ptr);
}

void
nvpair_init_datasize(nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	if (nvp->nvp_type == NV_TYPE_NVLIST) {
		if (nvp->nvp_data == 0) {
			nvp->nvp_datasize = 0;
		} else {
			nvp->nvp_datasize =
			    nvlist_size((const nvlist_t *)(intptr_t)nvp->nvp_data);
		}
	}
}

const unsigned char *
nvpair_unpack_header(bool isbe, nvpair_t *nvp, const unsigned char *ptr,
    size_t *leftp)
{
	struct nvpair_header nvphdr;

	if (*leftp < sizeof(nvphdr))
		goto failed;

	memcpy(&nvphdr, ptr, sizeof(nvphdr));
	ptr += sizeof(nvphdr);
	*leftp -= sizeof(nvphdr);

#if NV_TYPE_FIRST > 0
	if (nvphdr.nvph_type < NV_TYPE_FIRST)
		goto failed;
#endif
	if (nvphdr.nvph_type > NV_TYPE_LAST &&
	    nvphdr.nvph_type != NV_TYPE_NVLIST_UP) {
		goto failed;
	}

#if BYTE_ORDER == BIG_ENDIAN
	if (!isbe) {
		nvphdr.nvph_namesize = le16toh(nvphdr.nvph_namesize);
		nvphdr.nvph_datasize = le64toh(nvphdr.nvph_datasize);
	}
#else
	if (isbe) {
		nvphdr.nvph_namesize = be16toh(nvphdr.nvph_namesize);
		nvphdr.nvph_datasize = be64toh(nvphdr.nvph_datasize);
	}
#endif

	if (nvphdr.nvph_namesize > NV_NAME_MAX)
		goto failed;
	if (*leftp < nvphdr.nvph_namesize)
		goto failed;
	if (nvphdr.nvph_namesize < 1)
		goto failed;
	if (strnlen((const char *)ptr, nvphdr.nvph_namesize) !=
	    (size_t)(nvphdr.nvph_namesize - 1)) {
		goto failed;
	}

	memcpy(nvp->nvp_name, ptr, nvphdr.nvph_namesize);
	ptr += nvphdr.nvph_namesize;
	*leftp -= nvphdr.nvph_namesize;

	if (*leftp < nvphdr.nvph_datasize)
		goto failed;

	nvp->nvp_type = nvphdr.nvph_type;
	nvp->nvp_data = 0;
	nvp->nvp_datasize = nvphdr.nvph_datasize;

	return (ptr);
failed:
	RESTORE_ERRNO(EINVAL);
	return (NULL);
}

const unsigned char *
nvpair_unpack_null(bool isbe __unused, nvpair_t *nvp, const unsigned char *ptr,
    size_t *leftp __unused)
{

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_NULL);

	if (nvp->nvp_datasize != 0) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	return (ptr);
}

const unsigned char *
nvpair_unpack_bool(bool isbe __unused, nvpair_t *nvp, const unsigned char *ptr,
    size_t *leftp)
{
	uint8_t value;

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_BOOL);

	if (nvp->nvp_datasize != sizeof(value)) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}
	if (*leftp < sizeof(value)) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	memcpy(&value, ptr, sizeof(value));
	ptr += sizeof(value);
	*leftp -= sizeof(value);

	if (value != 0 && value != 1) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	nvp->nvp_data = (uint64_t)value;

	return (ptr);
}

const unsigned char *
nvpair_unpack_number(bool isbe, nvpair_t *nvp, const unsigned char *ptr,
     size_t *leftp)
{

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_NUMBER);

	if (nvp->nvp_datasize != sizeof(uint64_t)) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}
	if (*leftp < sizeof(uint64_t)) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	if (isbe)
		nvp->nvp_data = be64dec(ptr);
	else
		nvp->nvp_data = le64dec(ptr);
	ptr += sizeof(uint64_t);
	*leftp -= sizeof(uint64_t);

	return (ptr);
}

const unsigned char *
nvpair_unpack_string(bool isbe __unused, nvpair_t *nvp,
    const unsigned char *ptr, size_t *leftp)
{

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_STRING);

	if (*leftp < nvp->nvp_datasize || nvp->nvp_datasize == 0) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	if (strnlen((const char *)ptr, nvp->nvp_datasize) !=
	    nvp->nvp_datasize - 1) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	nvp->nvp_data = (uint64_t)(uintptr_t)nv_strdup((const char *)ptr);
	if (nvp->nvp_data == 0)
		return (NULL);

	ptr += nvp->nvp_datasize;
	*leftp -= nvp->nvp_datasize;

	return (ptr);
}

const unsigned char *
nvpair_unpack_nvlist(bool isbe __unused, nvpair_t *nvp,
    const unsigned char *ptr, size_t *leftp, size_t nfds, nvlist_t **child)
{
	nvlist_t *value;

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_NVLIST);

	if (*leftp < nvp->nvp_datasize || nvp->nvp_datasize == 0) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	value = nvlist_create(0);
	if (value == NULL)
		return (NULL);

	ptr = nvlist_unpack_header(value, ptr, nfds, NULL, leftp);
	if (ptr == NULL)
		return (NULL);

	nvp->nvp_data = (uint64_t)(uintptr_t)value;
	*child = value;

	return (ptr);
}

#ifndef _KERNEL
const unsigned char *
nvpair_unpack_descriptor(bool isbe, nvpair_t *nvp, const unsigned char *ptr,
    size_t *leftp, const int *fds, size_t nfds)
{
	int64_t idx;

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_DESCRIPTOR);

	if (nvp->nvp_datasize != sizeof(idx)) {
		errno = EINVAL;
		return (NULL);
	}
	if (*leftp < sizeof(idx)) {
		errno = EINVAL;
		return (NULL);
	}

	if (isbe)
		idx = be64dec(ptr);
	else
		idx = le64dec(ptr);

	if (idx < 0) {
		errno = EINVAL;
		return (NULL);
	}

	if ((size_t)idx >= nfds) {
		errno = EINVAL;
		return (NULL);
	}

	nvp->nvp_data = (uint64_t)fds[idx];

	ptr += sizeof(idx);
	*leftp -= sizeof(idx);

	return (ptr);
}
#endif

const unsigned char *
nvpair_unpack_binary(bool isbe __unused, nvpair_t *nvp,
    const unsigned char *ptr, size_t *leftp)
{
	void *value;

	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_BINARY);

	if (*leftp < nvp->nvp_datasize || nvp->nvp_datasize == 0) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	value = nv_malloc(nvp->nvp_datasize);
	if (value == NULL)
		return (NULL);

	memcpy(value, ptr, nvp->nvp_datasize);
	ptr += nvp->nvp_datasize;
	*leftp -= nvp->nvp_datasize;

	nvp->nvp_data = (uint64_t)(uintptr_t)value;

	return (ptr);
}

const unsigned char *
nvpair_unpack(bool isbe, const unsigned char *ptr, size_t *leftp,
    nvpair_t **nvpp)
{
	nvpair_t *nvp, *tmp;

	nvp = nv_calloc(1, sizeof(*nvp) + NV_NAME_MAX);
	if (nvp == NULL)
		return (NULL);
	nvp->nvp_name = (char *)(nvp + 1);

	ptr = nvpair_unpack_header(isbe, nvp, ptr, leftp);
	if (ptr == NULL)
		goto failed;
	tmp = nv_realloc(nvp, sizeof(*nvp) + strlen(nvp->nvp_name) + 1);
	if (tmp == NULL)
		goto failed;
	nvp = tmp;

	/* Update nvp_name after realloc(). */
	nvp->nvp_name = (char *)(nvp + 1);
	nvp->nvp_data = 0x00;
	nvp->nvp_magic = NVPAIR_MAGIC;
	*nvpp = nvp;
	return (ptr);
failed:
	nv_free(nvp);
	return (NULL);
}

int
nvpair_type(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	return (nvp->nvp_type);
}

const char *
nvpair_name(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	return (nvp->nvp_name);
}

static nvpair_t *
nvpair_allocv(int type, uint64_t data, size_t datasize, const char *namefmt,
    va_list nameap)
{
	nvpair_t *nvp;
	char *name;
	int namelen;

	PJDLOG_ASSERT(type >= NV_TYPE_FIRST && type <= NV_TYPE_LAST);

	namelen = nv_vasprintf(&name, namefmt, nameap);
	if (namelen < 0)
		return (NULL);

	PJDLOG_ASSERT(namelen > 0);
	if (namelen >= NV_NAME_MAX) {
		nv_free(name);
		RESTORE_ERRNO(ENAMETOOLONG);
		return (NULL);
	}

	nvp = nv_calloc(1, sizeof(*nvp) + namelen + 1);
	if (nvp != NULL) {
		nvp->nvp_name = (char *)(nvp + 1);
		memcpy(nvp->nvp_name, name, namelen + 1);
		nvp->nvp_type = type;
		nvp->nvp_data = data;
		nvp->nvp_datasize = datasize;
		nvp->nvp_magic = NVPAIR_MAGIC;
	}
	nv_free(name);

	return (nvp);
};

nvpair_t *
nvpair_create_null(const char *name)
{

	return (nvpair_createf_null("%s", name));
}

nvpair_t *
nvpair_create_bool(const char *name, bool value)
{

	return (nvpair_createf_bool(value, "%s", name));
}

nvpair_t *
nvpair_create_number(const char *name, uint64_t value)
{

	return (nvpair_createf_number(value, "%s", name));
}

nvpair_t *
nvpair_create_string(const char *name, const char *value)
{

	return (nvpair_createf_string(value, "%s", name));
}

nvpair_t *
nvpair_create_stringf(const char *name, const char *valuefmt, ...)
{
	va_list valueap;
	nvpair_t *nvp;

	va_start(valueap, valuefmt);
	nvp = nvpair_create_stringv(name, valuefmt, valueap);
	va_end(valueap);

	return (nvp);
}

nvpair_t *
nvpair_create_stringv(const char *name, const char *valuefmt, va_list valueap)
{
	nvpair_t *nvp;
	char *str;
	int len;

	len = nv_vasprintf(&str, valuefmt, valueap);
	if (len < 0)
		return (NULL);
	nvp = nvpair_create_string(name, str);
	if (nvp == NULL)
		nv_free(str);
	return (nvp);
}

nvpair_t *
nvpair_create_nvlist(const char *name, const nvlist_t *value)
{

	return (nvpair_createf_nvlist(value, "%s", name));
}

#ifndef _KERNEL
nvpair_t *
nvpair_create_descriptor(const char *name, int value)
{

	return (nvpair_createf_descriptor(value, "%s", name));
}
#endif

nvpair_t *
nvpair_create_binary(const char *name, const void *value, size_t size)
{

	return (nvpair_createf_binary(value, size, "%s", name));
}

nvpair_t *
nvpair_createf_null(const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_null(namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_createf_bool(bool value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_bool(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_createf_number(uint64_t value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_number(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_createf_string(const char *value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_string(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_createf_nvlist(const nvlist_t *value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_nvlist(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

#ifndef _KERNEL
nvpair_t *
nvpair_createf_descriptor(int value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_descriptor(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}
#endif

nvpair_t *
nvpair_createf_binary(const void *value, size_t size, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_createv_binary(value, size, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_createv_null(const char *namefmt, va_list nameap)
{

	return (nvpair_allocv(NV_TYPE_NULL, 0, 0, namefmt, nameap));
}

nvpair_t *
nvpair_createv_bool(bool value, const char *namefmt, va_list nameap)
{

	return (nvpair_allocv(NV_TYPE_BOOL, value ? 1 : 0, sizeof(uint8_t),
	    namefmt, nameap));
}

nvpair_t *
nvpair_createv_number(uint64_t value, const char *namefmt, va_list nameap)
{

	return (nvpair_allocv(NV_TYPE_NUMBER, value, sizeof(value), namefmt,
	    nameap));
}

nvpair_t *
nvpair_createv_string(const char *value, const char *namefmt, va_list nameap)
{
	nvpair_t *nvp;
	size_t size;
	char *data;

	if (value == NULL) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	data = nv_strdup(value);
	if (data == NULL)
		return (NULL);
	size = strlen(value) + 1;

	nvp = nvpair_allocv(NV_TYPE_STRING, (uint64_t)(uintptr_t)data, size,
	    namefmt, nameap);
	if (nvp == NULL)
		nv_free(data);

	return (nvp);
}

nvpair_t *
nvpair_createv_nvlist(const nvlist_t *value, const char *namefmt,
    va_list nameap)
{
	nvlist_t *nvl;
	nvpair_t *nvp;

	if (value == NULL) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	nvl = nvlist_clone(value);
	if (nvl == NULL)
		return (NULL);

	nvp = nvpair_allocv(NV_TYPE_NVLIST, (uint64_t)(uintptr_t)nvl, 0,
	    namefmt, nameap);
	if (nvp == NULL)
		nvlist_destroy(nvl);
	else
		nvlist_set_parent(nvl, nvp);

	return (nvp);
}

#ifndef _KERNEL
nvpair_t *
nvpair_createv_descriptor(int value, const char *namefmt, va_list nameap)
{
	nvpair_t *nvp;

	if (value < 0 || !fd_is_valid(value)) {
		errno = EBADF;
		return (NULL);
	}

	value = fcntl(value, F_DUPFD_CLOEXEC, 0);
	if (value < 0)
		return (NULL);

	nvp = nvpair_allocv(NV_TYPE_DESCRIPTOR, (uint64_t)value,
	    sizeof(int64_t), namefmt, nameap);
	if (nvp == NULL)
		close(value);

	return (nvp);
}
#endif

nvpair_t *
nvpair_createv_binary(const void *value, size_t size, const char *namefmt,
    va_list nameap)
{
	nvpair_t *nvp;
	void *data;

	if (value == NULL || size == 0) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	data = nv_malloc(size);
	if (data == NULL)
		return (NULL);
	memcpy(data, value, size);

	nvp = nvpair_allocv(NV_TYPE_BINARY, (uint64_t)(uintptr_t)data, size,
	    namefmt, nameap);
	if (nvp == NULL)
		nv_free(data);

	return (nvp);
}

nvpair_t *
nvpair_move_string(const char *name, char *value)
{

	return (nvpair_movef_string(value, "%s", name));
}

nvpair_t *
nvpair_move_nvlist(const char *name, nvlist_t *value)
{

	return (nvpair_movef_nvlist(value, "%s", name));
}

#ifndef _KERNEL
nvpair_t *
nvpair_move_descriptor(const char *name, int value)
{

	return (nvpair_movef_descriptor(value, "%s", name));
}
#endif

nvpair_t *
nvpair_move_binary(const char *name, void *value, size_t size)
{

	return (nvpair_movef_binary(value, size, "%s", name));
}

nvpair_t *
nvpair_movef_string(char *value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_movev_string(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_movef_nvlist(nvlist_t *value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_movev_nvlist(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

#ifndef _KERNEL
nvpair_t *
nvpair_movef_descriptor(int value, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_movev_descriptor(value, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}
#endif

nvpair_t *
nvpair_movef_binary(void *value, size_t size, const char *namefmt, ...)
{
	va_list nameap;
	nvpair_t *nvp;

	va_start(nameap, namefmt);
	nvp = nvpair_movev_binary(value, size, namefmt, nameap);
	va_end(nameap);

	return (nvp);
}

nvpair_t *
nvpair_movev_string(char *value, const char *namefmt, va_list nameap)
{
	nvpair_t *nvp;
	int serrno;

	if (value == NULL) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	nvp = nvpair_allocv(NV_TYPE_STRING, (uint64_t)(uintptr_t)value,
	    strlen(value) + 1, namefmt, nameap);
	if (nvp == NULL) {
		SAVE_ERRNO(serrno);
		nv_free(value);
		RESTORE_ERRNO(serrno);
	}

	return (nvp);
}

nvpair_t *
nvpair_movev_nvlist(nvlist_t *value, const char *namefmt, va_list nameap)
{
	nvpair_t *nvp;

	if (value == NULL || nvlist_get_nvpair_parent(value) != NULL) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	if (nvlist_error(value) != 0) {
		RESTORE_ERRNO(nvlist_error(value));
		nvlist_destroy(value);
		return (NULL);
	}

	nvp = nvpair_allocv(NV_TYPE_NVLIST, (uint64_t)(uintptr_t)value, 0,
	    namefmt, nameap);
	if (nvp == NULL)
		nvlist_destroy(value);
	else
		nvlist_set_parent(value, nvp);

	return (nvp);
}

#ifndef _KERNEL
nvpair_t *
nvpair_movev_descriptor(int value, const char *namefmt, va_list nameap)
{
	nvpair_t *nvp;
	int serrno;

	if (value < 0 || !fd_is_valid(value)) {
		errno = EBADF;
		return (NULL);
	}

	nvp = nvpair_allocv(NV_TYPE_DESCRIPTOR, (uint64_t)value,
	    sizeof(int64_t), namefmt, nameap);
	if (nvp == NULL) {
		serrno = errno;
		close(value);
		errno = serrno;
	}

	return (nvp);
}
#endif

nvpair_t *
nvpair_movev_binary(void *value, size_t size, const char *namefmt,
    va_list nameap)
{
	nvpair_t *nvp;
	int serrno;

	if (value == NULL || size == 0) {
		RESTORE_ERRNO(EINVAL);
		return (NULL);
	}

	nvp = nvpair_allocv(NV_TYPE_BINARY, (uint64_t)(uintptr_t)value, size,
	    namefmt, nameap);
	if (nvp == NULL) {
		SAVE_ERRNO(serrno);
		nv_free(value);
		RESTORE_ERRNO(serrno);
	}

	return (nvp);
}

bool
nvpair_get_bool(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	return (nvp->nvp_data == 1);
}

uint64_t
nvpair_get_number(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);

	return (nvp->nvp_data);
}

const char *
nvpair_get_string(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_STRING);

	return ((const char *)(intptr_t)nvp->nvp_data);
}

const nvlist_t *
nvpair_get_nvlist(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_NVLIST);

	return ((const nvlist_t *)(intptr_t)nvp->nvp_data);
}

#ifndef _KERNEL
int
nvpair_get_descriptor(const nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_DESCRIPTOR);

	return ((int)nvp->nvp_data);
}
#endif

const void *
nvpair_get_binary(const nvpair_t *nvp, size_t *sizep)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_type == NV_TYPE_BINARY);

	if (sizep != NULL)
		*sizep = nvp->nvp_datasize;
	return ((const void *)(intptr_t)nvp->nvp_data);
}

void
nvpair_free(nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_list == NULL);

	nvp->nvp_magic = 0;
	switch (nvp->nvp_type) {
#ifndef _KERNEL
	case NV_TYPE_DESCRIPTOR:
		close((int)nvp->nvp_data);
		break;
#endif
	case NV_TYPE_NVLIST:
		nvlist_destroy((nvlist_t *)(intptr_t)nvp->nvp_data);
		break;
	case NV_TYPE_STRING:
		nv_free((char *)(intptr_t)nvp->nvp_data);
		break;
	case NV_TYPE_BINARY:
		nv_free((void *)(intptr_t)nvp->nvp_data);
		break;
	}
	nv_free(nvp);
}

void
nvpair_free_structure(nvpair_t *nvp)
{

	NVPAIR_ASSERT(nvp);
	PJDLOG_ASSERT(nvp->nvp_list == NULL);

	nvp->nvp_magic = 0;
	nv_free(nvp);
}

const char *
nvpair_type_string(int type)
{

	switch (type) {
	case NV_TYPE_NULL:
		return ("NULL");
	case NV_TYPE_BOOL:
		return ("BOOL");
	case NV_TYPE_NUMBER:
		return ("NUMBER");
	case NV_TYPE_STRING:
		return ("STRING");
	case NV_TYPE_NVLIST:
		return ("NVLIST");
	case NV_TYPE_DESCRIPTOR:
		return ("DESCRIPTOR");
	case NV_TYPE_BINARY:
		return ("BINARY");
	default:
		return ("<UNKNOWN>");
	}
}
