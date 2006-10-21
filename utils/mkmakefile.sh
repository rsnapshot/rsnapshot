#! /bin/sh -xe

# This mini script is to generate the Makefile for building rsnapshot.
#
# Usage: mkmakefile.sh [options to pass to ./configure]
#
# Example:	mkmakefile.sh
# Example:	mkmakefile.sh --sysconfdir=/etc
#
# You can just re-run ./configure after running mkmakefile.sh to change the
# options to ./configure.
#
# Inputs:	Makefile.am	configure.ac
# Outputs:	Makefile	Makefile.in	configure	aclocal.m4
#
# This script is executed with the sh -e flag, so that an error from 
# executing any command will cause the shell script to abort immediately.
#
trap "echo Previous command had error, mkmakefile.sh aborting." ERR
#
aclocal
autoconf
automake
./configure "$@"
