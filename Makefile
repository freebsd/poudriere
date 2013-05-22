PREFIX?=	/usr/local
MAN8DIR?=	${PREFIX}/man/man8

all:
	${MAKE} -C src/libexec/poudriere
	sed -e "s,/usr/local,${PREFIX},g" src/etc/rc.d/poudriere.in > src/etc/rc.d/poudriere

install:
	install -m 755 -o root -g wheel src/bin/poudriere.sh ${PREFIX}/bin/poudriere
	mkdir -p ${PREFIX}/etc/poudriere.d/hooks
	mkdir -p ${PREFIX}/share/poudriere
	mkdir -p ${PREFIX}/share/poudriere/awk
	mkdir -p ${PREFIX}/share/poudriere/html
	install -m 755 -o root -g wheel src/share/poudriere/*.sh ${PREFIX}/share/poudriere/
	install -m 644 -o root -g wheel src/share/poudriere/awk/* ${PREFIX}/share/poudriere/awk/
	install -m 644 -o root -g wheel src/share/poudriere/html/* ${PREFIX}/share/poudriere/html/
	install -m 644 -o root -g wheel conf/poudriere.conf.sample ${PREFIX}/etc/
	install -m 644 -o root -g wheel src/etc/poudriere.d/hooks/pkgbuild.sh.sample ${PREFIX}/etc/poudriere.d/hooks
	install -m 555 -o root -g wheel src/etc/rc.d/poudriere ${PREFIX}/etc/rc.d
	if [ -f poudriere.8.gz ]; then rm -f poudriere.8.gz; fi
	gzip -k -9 poudriere.8
	install -m 644 poudriere.8.gz ${MAN8DIR}
	${MAKE} -C src/libexec/poudriere install

clean:
	${MAKE} -C src/libexec/poudriere clean
	if [ -f poudriere.8.gz ]; then rm -f poudriere.8.gz; fi
	rm -f src/etc/rc.d/poudriere
