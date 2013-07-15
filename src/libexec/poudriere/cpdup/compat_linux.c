/*
 * linux compatibility
 */
#include <sys/types.h>
#include <string.h>

size_t
strlcpy(char *dst, const char *src, size_t size)
{
	size_t i;

	for (i = 0; i < size; ++i) {
		dst[i] = src[i];
		if (src[i] == 0)
			return(i);
	}
	if (i)
		dst[i - 1] = 0;
	return(strlen(src));
}

