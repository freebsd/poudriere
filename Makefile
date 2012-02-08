PREFIX?=	/usr/local
MAN8DIR?=	${PREFIX}/man/man8

all:
	/usr/bin/true

install:
.if exists(${PREFIX}/bin/zsh)
	install -m 755 -o root -g wheel zsh-completions ${PREFIX}/share/zsh/site-functions/_poudriere
.endif
	install -m 755 -o root -g wheel src/poudriere.sh ${PREFIX}/bin/poudriere
	mkdir -p ${PREFIX}/share/poudriere
	install -m 755 -o root -g wheel src/poudriere.d/* ${PREFIX}/share/poudriere/
	install -m 644 -o root -g wheel conf/poudriere.conf.sample ${PREFIX}/etc/
	if [ -f poudriere.8.gz ]; then rm -f poudriere.8.gz; fi
	gzip -k -9 poudriere.8
	install -m 644 poudriere.8.gz ${MAN8DIR}
