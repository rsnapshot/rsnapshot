#!/bin/sh

##############################################################################
# debug_moving_files.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This is an abusive shell script designed to simulate users moving files
# while a backup is occuring. Hopefully your users aren't this abusive.
#
# The general idea is that you create an "abuse" directory, include it in your
# backup points, run this script in one terminal window and rsnapshot in the
# other.
#
# Most people will probably never need to use this unless they want to debug
# "vanishing file" problems with rsync.
##############################################################################

# change this path to your liking
DIRECTORY=/path/to/abuse/dir/

# be sure and create it or the script won't work
cd $DIRECTORY || exit 1;

# ready
touch 0 1 2 3 4 5 6 7 8 9
rm *.tmp 2>/dev/null

# set
echo "STARTING ABUSE NOW..."

# go
while true; do
	# move them
	for i in `echo 0 1 2 3 4 5 6 7 8 9`; do
		echo mv $i $i.tmp
		mv $i $i.tmp
	done
	
	# move them back
	for i in `echo 0 1 2 3 4 5 6 7 8 9`; do
		echo mv $i.tmp $i
		mv $i.tmp $i
	done
done
