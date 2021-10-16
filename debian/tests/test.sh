#!/bin/bash

cleanup () {
	rm --recursive --force $data_dir $tmp_conf
}

backup_dir=$(mktemp --directory --suffix=.rsnapshot-backup)
backup_dest="localhost/"
retain_name="alpha"

# create fake content and keep sha1sum to test backup
data_dir=$(mktemp --directory --suffix=.rsnapshot-data)
data_file="${data_dir}/testfile.txt"
echo "This is a test file." > ${data_file}
data_file_sha1sum=$(sha1sum ${data_file} | awk '{print $1}')

# prepare conf and backup
tmp_conf=$(mktemp --suffix=.rsnapshot.conf)
cat << EOF > ${tmp_conf}
config_version	1.2
snapshot_root	${backup_dir}
cmd_rsync		/usr/bin/rsync
retain			${retain_name}	2
backup			${data_dir}	${backup_dest}
EOF
echo "Starting backup test session of ${data_dir}"
rsnapshot -c ${tmp_conf} alpha

# verify that the file is here and has the same sha1sum
if [ -r ${backup_dir}/${retain_name}.0/${backup_dest}/${data_file} ]
then
	backup_file_sha1sum=$(sha1sum ${backup_dir}/${retain_name}.0/${backup_dest}/${data_file} | awk '{print $1}')
else
	echo "ERROR: file $backup_dir/${retain_name}.0/${backup_dest}/${data_file} not found, backup fails ?"
	exit 1
fi

if [ "$backup_file_sha1sum" == "$data_file_sha1sum" ]
then
	echo "OK: file $backup_dir/${retain_name}.0/${backup_dest}/${data_file} has same sha1sum than before backup."
	cleanup
	exit 0
else
	echo "ERROR: file $backup_dir/${retain_name}.0/${backup_dest}/${data_file} has NOT same sha1sum than before backup !"
	exit 1
fi

cleanup
exit 1
