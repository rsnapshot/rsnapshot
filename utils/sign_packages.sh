#!/bin/sh

##############################################################################
# sign_packages.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This is the script used to semi-automatically GPG sign rsnapshot releases
##############################################################################

for file in `/bin/ls *.tar.gz *.deb *.rpm | grep -v latest`; do
	# MD5
	if [ ! -e "$file.md5" ]; then
		md5sum $file > $file.md5;
		echo "Created MD5 Hash for $file";
	fi
	
	# PGP
	if [ ! -e "$file.asc" ]; then
		gpg --armor --detach-sign $file;
		echo "Created PGP Signature for $file";
	fi
done
