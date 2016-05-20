#ifndef _SH_COMPAT_COMPAT_H
#define _SH_COMPAT_COMPAT_H

#include "config.h"

#ifndef HAVE_STRCHRNUL
char	*strchrnul(const char*, int);
#endif
#endif
