#!/bin/sh

##############################################################################
# backup_smb_share.sh
#
# by Nathan Rosenquist <nathan@rsnapshot.org>
# http://www.rsnapshot.org/
#
# This is a simple shell script to backup an SMB share with rsnapshot.
#
# The assumption is that this will be invoked from rsnapshot. Also, for
# security reasons, the authfile should be stored in a place where it is not
# accessible by anyone other than the user running rsnapshot (probably root).
#
# This script simply needs to dump the contents of the SMB share into the
# current working directory. rsnapshot handles everything else.
#
# Please note that because of cross-platform issues, the files archived will
# be owned by the user running rsnapshot to make the backup, not by the
# original owner of the files. Also, any ACL permissions that may have been
# on the Windows machine will be lost. However, the data in the files will
# be archived safely.
##############################################################################

# $Id: backup_smb_share.sh,v 1.6 2005/04/02 07:37:07 scubaninja Exp $

# IP or hostname to backup over SMB
SERVER=192.168.1.10

# The name of the share
SHARE=home

# The authfile is a file that contains the username and password to connect
# with. man smbclient(1) for details on how this works. It's much more secure
# than specifying the password on the command line directly.
AUTHFILE=/path/to/authfile

# connect to the SMB share using the authfile
/usr/local/samba/bin/smbclient //${SERVER}/${SHARE} -A ${AUTHFILE} -Tc - 2>/dev/null | tar xf -

