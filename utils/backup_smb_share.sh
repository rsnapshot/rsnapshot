#!/bin/sh

# This is a simple shell script to backup an SMB share with rsnapshot.
#
# The assumption is that this will be invoked from rsnapshot. Also, for
# security reasons, the authfile should be stored in a place where it is not
# accessible by anyone other than the user running rsnapshot (probably root).
#
# This script simply needs to dump the contents of the SMB share into the
# current working directory. rsnapshot handles everything else.

# IP or hostname to backup over SMB
SERVER=192.168.1.10

# The name of the share
SHARE=home

# The authfile is a file that contains the username and password to connect
# with. man smbclient(1) for details on how this works. It's much more secure
# than specifying the password on the command line directly.
AUTHFILE=/path/to/authfile

# connect to the SMB share using the authfile
/usr/local/samba/bin/smbclient -A ${AUTHFILE} //${SERVER}/${SHARE} -Tc - | tar xf -

