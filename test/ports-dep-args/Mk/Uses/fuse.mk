# $FreeBSD: head/Mk/Uses/fuse.mk 431541 2017-01-15 09:52:47Z rene $
#
# handle dependency on the fuse port
#
# Feature:	fuse
# Usage:	USES=fuse
# Valid ARGS:	does not require args
#
# MAINTAINER: portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_FUSE_MK)
_INCLUDE_USES_FUSE_MK=	yes

.if !empty(fuse_ARGS)
IGNORE=	USES=fuse does not require args
.endif

LIB_DEPENDS+=	libfuse.so:sysutils/fusefs-libs

.endif
