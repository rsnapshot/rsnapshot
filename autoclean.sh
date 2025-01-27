#!/bin/sh

[ -f Makefile ] && make clean
rm -rf autom4te.cache
rm -f {config.h.in,config.h}
rm -f {Makefile.in,Makefile}
rm -f config.status
rm -f configure
rm -f stamp*
rm -f aclocal.m4
rm -f compile
rm -f missing
rm -f install-sh
rm -rf dist/
