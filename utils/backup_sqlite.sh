#!/bin/bash

##############################################################################
# backup_sqlite.sh
#
# http://www.rsnapshot.org/
#
# This is a simple shell script to backup a sqlite database with rsnapshot.
#
# This script simply needs to dump a file into the current working directory.
# rsnapshot handles everything else.
#
# The assumption is that this will be invoked from rsnapshot.
# See:
#	https://rsnapshot.org/rsnapshot/docs/docbook/rest.html#backup-script
#
#	Please remember that these backup scripts will be invoked as the user 
#	running rsnapshot. Make sure your backup scripts are owned by root, 
#	and not writable by anyone else. 
#	If you fail to do this, anyone with write access to these backup scripts
#	will be able to put commands in them that will be run as the root user. 
#	If they are malicious, they could take over your server.
#
#		chown root:root backup_sqlite.sh
#		chmod 700 backup_sqlite.sh
#
##############################################################################

umask 0077

# backup the database
/bin/find /var -type f -iname "*.db" -exec bash -c '/usr/bin/file {} | /bin/grep -q "SQLite 3" && /usr/bin/sqlite3 {} ".backup $(/usr/bin/basename {})" ' \;

# make the backup readable only by root
/bin/chmod 600 *.db

exit
