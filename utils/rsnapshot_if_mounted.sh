#!/bin/sh

##############################################################################
# rsnapshot_if_mounted.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
##############################################################################
##############################################################################
##############################################################################
#
# NOTE: THIS SCRIPT HAS BEEN SUPERCEDED BY THE "no_create_root" OPTION IN
# rsnapshot. IT IS LEFT HERE JUST IN CASE ANYONE WANTS TO USE IT.
#
##############################################################################
##############################################################################
##############################################################################
#
# This is a simple shell script to run rsnapshot only if the backup drive
# is mounted. It is intended to be used when backups are made to removable
# devices (such as FireWire drives).
#
# Usage: /path/to/rsnapshot_if_mounted.sh [options] interval
#
# Edit this script so it points to your rsnapshot program and snapshot root.
# Then simply call this script instead of rsnapshot.
#
# Example: /usr/local/bin/rsnapshot_if_mounted.sh -v daily
##############################################################################

# $Id: rsnapshot_if_mounted.sh,v 1.4 2005/04/02 07:37:07 scubaninja Exp $

# path to rsnapshot
RSNAPSHOT=/usr/local/bin/rsnapshot

# snapshot_root
SNAPSHOT_ROOT=/.snapshots/;

# external programs
LS=/bin/ls
HEAD=/usr/bin/head

# check to see if the drive is mounted
IS_MOUNTED=`$LS $SNAPSHOT_ROOT/ | $HEAD -1` > /dev/null 2>&1;

# if the drive is mounted, run rsnapshot
# otherwise refuse to run
if [ $IS_MOUNTED ]; then
	$RSNAPSHOT $@
else
	echo "$SNAPSHOT_ROOT is not mounted, rsnapshot will not be run"
fi
