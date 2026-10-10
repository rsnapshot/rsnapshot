#!/bin/sh

[ -f Makefile ] && make distclean
rm -rf autom4te.cache/
rm -rf dist/
rm -f config.h.in
rm -f config.h
rm -f Makefile.in
rm -f config.status
rm -f configure
rm -f stamp*
rm -f aclocal.m4
rm -f compile
rm -f missing
rm -f install-sh
rm -f t/include.ac
rm -f *.1
