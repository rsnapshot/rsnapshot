#!/bin/sh

##############################################################################
# backup_pgsql.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This is a simple shell script to backup a PostgreSQL database with rsnapshot.
#
# The assumption is that this will be invoked from rsnapshot. Also, since it
# will run unattended, the user that runs rsnapshot (probably root) should have
# a .pgpass file in their home directory that contains the password for the
# postgres user. For example:
#
# /root/.pgpass (chmod 0600)
#   *:*:*:postgres:thepassword
#
# This script simply needs to dump a file into the current working directory.
# rsnapshot handles everything else.
##############################################################################

# $Id: backup_pgsql.sh,v 1.6 2007/03/22 02:50:21 drhyde Exp $

umask 0077

# backup the database
/usr/local/pgsql/bin/pg_dumpall -Upostgres > pg_dumpall.sql

# make the backup readable only by root
/bin/chmod 600 pg_dumpall.sql
