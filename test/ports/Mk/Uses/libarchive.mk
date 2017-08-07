# $FreeBSD: head/Mk/Uses/libarchive.mk 423014 2016-09-30 19:24:30Z tijl $
#
# handle dependency on the libarchive port
#
# Feature:	libarchive
# Usage:	USES=libarchive
# Valid ARGS:	none
#
# MAINTAINER:	portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_LIBARCHIVE_MK)
_INCLUDE_USES_LIBARCHIVE_MK=	yes
_USES_POST+=	localbase

LIB_DEPENDS+=	libarchive.so.13:archivers/libarchive
.endif
