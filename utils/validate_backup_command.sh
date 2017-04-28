#!/bin/bash
#
# This protects the integrity (but not the confidentiality) of the remote server if the backup server's
# ssh key is compromised.
#
# This is used as part of the forced_command in .ssh/authorized_keys on the machine to be backed up
# The script ensures that only the rsync command of rsnapshot.conf is executed by being strict about the
# executed command. The backup directory needs to exist. This can be the same on all hosts and doesn't
# need to change per server. This also prevent a ssh rsync pushed the host.
#
# In /root/.ssh/authorized_keys you can have the following followed by the rest or your backup ssh key
# Here the command refers to this script, and the from refers to the backup server.
# See ssh documentation for more information on authorized_keys files and their format.
#
# command="/usr/local/bin/validate_backup_command.sh",from="192.168.1.1",no-port-forwarding,no-X11-forwarding,no-pty ssh-rsa ....
#
# Contributed by Daniel Black of Open Query (openquery.com)
#
if [[ "$SSH_ORIGINAL_COMMAND" =~ (rsync --server --sender -(v?)logDtprRe([\.iLsf]*) --numeric-ids \. (/.*)) ]]; then
        D=${BASH_REMATCH[4]}
        if [ -d "$D" ]; then
                rsync --server --sender -"${BASH_REMATCH[2]}logDtprRe${BASH_REMATCH[3]}" --numeric-ids . -- "${D}"
                logger -- 'backup running: '  rsync --server --sender -"${BASH_REMATCH[2]}logDtprRe${BASH_REMATCH[3]}" --numeric-ids . -- "${D}"
        else
                logger -- 'backup failed: '  ${D} does not exist
        fi
else
        logger -- 'backup failed: '  $SSH_ORIGINAL_COMMAND

fi
