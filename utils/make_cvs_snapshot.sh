#!/bin/sh

##############################################################################
# make_cvs_snapshot.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# this script just does a find/replace in the source tree to change
# the version number to CVS-$DATE
#
# this was done before manually, now it's automatic
##############################################################################

if [ $PWD = "$HOME/projects/rsnapshot" ]; then
	echo "This is not where you want to be. cp -r to a different directory first!"
	echo "Quitting now!"
	exit 1
fi

VERSION=`./rsnapshot-program.pl version-only | sed s/\\\./\\\\\\\./g`
DATE=`date +"%Y%m%d"`

perl -pi -e s/$VERSION/CVS-$DATE/g `find . -type f`
