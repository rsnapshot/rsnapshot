#!/bin/bash

# $Id: rsnapshot_invert.sh,v 1.1 2007/04/12 16:51:58 drhyde Exp $

# This script takes one parameter, which should be your rsnapshot config
# file.  It will parse that file to find your snapshot_root, backup points,
# and interval/retain values, and will create from those an inverted
# directory structure of backup points containing daily.{0,1,2,3} etc
# symlinks.  Run it from a cron job to keep that structure up to date.
#
# There is minimal^Wno error checking, and the parsing is totally brain-
# dead.

SNAPSHOT_ROOT=`grep ^snapshot_root $1|awk '{print \$2}'`
BACKUPS=`grep ^backup $1|awk '{print \$3}'`
INTERVALS=`grep -E '^(interval|retain)' $1|awk '{print \$2}'`

cd $SNAPSHOT_ROOT
for i in $BACKUPS; do
    mkdir $i
    for j in $INTERVALS; do
	HOWMANY=`grep -E ^\(interval\|retain\).$j $1|awk '{print \$3}'`
	COUNT=0
	while [[ $COUNT != $HOWMANY ]]; do
	    ln -s $SNAPSHOT_ROOT/$j.$COUNT/$i $SNAPSHOT_ROOT/$i/$j.$COUNT
	    COUNT=$(($COUNT + 1))
	done
    done
done
