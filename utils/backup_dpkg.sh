#!/bin/sh

##############################################################################
# backup_dpkg.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This script simply backs up a list of which Debian packages are installed.
# Naturally, this only works on a Debian system.
#
# This script simply needs to dump a file into the current working directory.
# rsnapshot handles everything else.
##############################################################################

/usr/bin/dpkg --get-selections > dpkg_selections
