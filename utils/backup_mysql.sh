#!/bin/sh

##############################################################################
# backup_mysql.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This is a simple shell script to backup a MySQL database with rsnapshot.
#
# The assumption is that this will be invoked from rsnapshot. Also, since it
# will run unattended, the user that runs rsnapshot (probably root) should have
# a .my.cnf file in their home directory that contains the password for the
# MySQL root user. For example:
#
# /root/.my.cnf (chmod 0600)
#   [client]
#   user = root
#   password = thepassword
#   host = localhost
#
# This script simply needs to dump a file into the current working directory.
# rsnapshot handles everything else.
##############################################################################

# $Id: backup_mysql.sh,v 1.6 2007/03/22 02:50:21 drhyde Exp $

umask 0077

# backup the database
/usr/bin/mysqldump --all-databases > mysqldump_all_databases.sql

# make the backup readable only by root
/bin/chmod 600 mysqldump_all_databases.sql
