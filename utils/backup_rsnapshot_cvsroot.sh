#!/bin/sh

# This is a simple shell script to backup the CVS tar/bz file from
# SourceForge.
#
# The assumption is that this will be invoked from rsnapshot. Also, since it
# will run unattended, the user that runs rsnapshot (probably root) should have
# a .pgpass file in their home directory that contains the password for the
# postgres user.
#
# This script simply needs to dump a file into the current working directory.
# rsnapshot handles everything else.

/usr/bin/wget http://cvs.sourceforge.net/cvstarballs/rsnapshot-cvsroot.tar.bz2 2>/dev/null
