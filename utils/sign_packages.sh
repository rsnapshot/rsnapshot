#!/bin/sh

##############################################################################
# sign_packages.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This is the script used to semi-automatically GPG sign rsnapshot releases
##############################################################################

# $Id: sign_packages.sh,v 1.3 2005/04/02 07:37:07 scubaninja Exp $

for file in `/bin/ls *.tar.gz *.deb *.rpm | grep -v latest`; do
	# MD5
	if [ ! -e "$file.md5" ]; then
		md5sum $file > $file.md5;
		echo "Created MD5 Hash for $file";
	fi
	
	# SHA1
	if [ ! -e "$file.sha1" ]; then
		sha1sum $file > $file.sha1;
		echo "Created SHA1 hash for $file";
	fi
	
	# PGP
	if [ ! -e "$file.asc" ]; then
		gpg --armor --detach-sign $file;
		echo "Created PGP Signature for $file";
	fi
done
