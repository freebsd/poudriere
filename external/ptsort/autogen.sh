#!/bin/sh

mkdir -p m4
aclocal -I m4
autoheader
automake -a -c --foreign
autoconf
