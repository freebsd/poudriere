# $FreeBSD: head/Mk/Uses/libedit.mk 423014 2016-09-30 19:24:30Z tijl $
#
# handle dependency on the libedit port
#
# Feature:	libedit
# Usage:	USES=libedit
# Valid ARGS:	none
#
# MAINTAINER:	portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_LIBEDIT_MK)
_INCLUDE_USES_LIBEDIT_MK=	yes
_USES_POST+=	localbase

LIB_DEPENDS+=	libedit.so.0:devel/libedit
.endif
