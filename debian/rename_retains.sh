#!/bin/bash
#
# Guillaume Delacour <gui@iroqwa.org> for the Debian project
# Script to help renaming of retains directories

# first get the snapshot_root value in the configuration
snapshot_root=$(awk '$0 ~ /^snapshot_root/ {print $2}' /etc/rsnapshot.conf)

if [ ! -d "$snapshot_root" ]
then
	echo "Unable to detect 'snapshot_root' in /etc/rsnapshot.conf, exiting."
	exit 1
fi

# then rename any directory inside
for dir in $snapshot_root/*
do
	new_dir=$(echo $dir | sed "s/hourly/alpha/;s/daily/beta/;s/weekly/gamma/;s/monthly/delta/")
	echo "mv $dir $new_dir"
	mv $dir $new_dir
done
