PREFIX?=	/usr/local

install:
	install -m 755 -o root -g wheel src/poudriere.sh ${PREFIX}/bin/poudriere
	mkdir -p ${PREFIX}/share/poudriere
	install -m 644 -o root -g wheel src/poudriere.d/* ${PREFIX}/share/poudriere/
	install -m 644 -o root -g wheel conf/poudriere.conf.sample ${PREFIX}/etc/
