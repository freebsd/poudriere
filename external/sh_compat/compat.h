#ifndef _SH_COMPAT_COMPAT_H
#define _SH_COMPAT_COMPAT_H

#include "config.h"

#ifndef HAVE_UTIMENSAT
#include <sys/stat.h>
#endif /* !HAVE_UTIMENSAT */

#ifndef HAVE_STRCHRNUL
char	*strchrnul(const char*, int);
#endif /* !HAVE_STRCHRNUL */
#ifndef HAVE_UTIMENSAT
#ifndef	UTIME_NOW
#define	UTIME_NOW	-1
#define	UTIME_OMIT	-2
#endif /* !UTIME_NOW */
int utimensat(int, const char *, const struct timespec *, int);
#endif /* !HAVE_UTIMENSAT */
#endif /* !_SH_COMPAT_COMPAT_H */
