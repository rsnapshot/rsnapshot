#!/bin/bash

##############################################################################
# random_file_verify.sh
#
# by Sherman Boyd <sherman.boyd AT gmail.com>
# http://www.rsnapshot.org/
#
# This script generates a random test file to be backed up and
# then tests it after the backup.  It's a paranoid sanity check, I
# suppose.  The script then emails the results of the backup and check
# to the admin.
#
# As it is currently implemented, it is a wrapper around an "rsnapshot daily"
# command. It could probably be broken out into seperate preexec annd
# postexec commands as well.
#
# Feel free to use and improve ...
#
##############################################################################

#Initialize 

echo "Started backup script on `date`"> /var/log/localbackup.log
msubject="Local Backup SUCCESSFUL!"

#Create random 100 byte file

echo "Generating random test file.">> /var/log/localbackup.log
dd if=/dev/urandom of=/path/to/files/you/are/backing/up/randomtestfile
bs=1 count=100

if [ $? -eq 0 ]
then
  echo "SUCCESS:  Randomly generated test file created." >>
/var/log/localbackup.log
else
  echo "FAILED:  Randomly generated test file not created." >>
/var/log/localbackup.log
  msubject="Local Backup has ERRORS!"
fi

#Run Backup
echo "Running rsnapshot backup.">> /var/log/localbackup.log
rsnapshot daily

if [ $? -eq 0 ]
then
  echo "SUCCESS:  Backup completed with no errors." >> /var/log/localbackup.log
else
  echo "FAILED:  Backup completed with some errors." >> /var/log/localbackup.log
  msubject="Local Backup has ERRORS!"
fi

#Test Random File

echo "Comparing random file with the backup.">> /var/log/localbackup.log
diff /path/to/files/you/are/backing/up/randomtestfile
/path/to/your/rsnapshots/daily.0/localhost/randomtestfile  > /dev/null

if [ $? -eq 0 ]
then
  echo "PASSED:  Randomly generated test file is the same." >>
/var/log/localbackup.log
else
  echo "FAILED:  Randomly generated test file differs." >>
/var/log/localbackup.log
  msubject="Local Backup has ERRORS!"
fi

#Mail results
mail -s "$msubject" your@email.com < /var/log/localbackup.log

exit 0
