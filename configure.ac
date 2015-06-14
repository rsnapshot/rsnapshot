AC_INIT(rsnapshot, [m4_esyscmd_s([git describe --tags --always])], rsnapshot-discuss@lists.sourceforge.net)
AM_INIT_AUTOMAKE([foreign])
AC_PROG_MAKE_SET
AC_PROG_INSTALL
AC_PROG_LIBTOOL
AC_CONFIG_FILES(Makefile)

dnl
dnl get the current working directory for the regression test suite
dnl
CWD=`eval echo \`pwd\``
dnl general test-directory
AC_SUBST(TEST, "$CWD/t/")
dnl snapshot_root in conf-files
AC_SUBST(SNAP, "$CWD/t/support/snapshots")
dnl template-source to backup
AC_SUBST(TEMP, "$CWD/t/support/files/template")


dnl
dnl PERL CHECK (required program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(perl,
	[  --with-perl=PATH	  Specify the path to perl ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				PERL=$withval
			else
				AC_MSG_ERROR(perl not found)
			fi
		else
			AC_MSG_ERROR(perl is required)
		fi
	]
)
dnl if the user didn't specify a path, hunt for it
if test "$PERL" = ""; then
	AC_PATH_PROG(PERL, perl, no)
fi
dnl bail out if we can't find it
if test "$PERL" = "no"; then
	AC_MSG_ERROR(perl is required)
fi


dnl
dnl RSYNC CHECK (required program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(rsync,
	[  --with-rsync=PATH       Specify the path to rsync ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				RSYNC=$withval
				AC_SUBST(CMD_RSYNC, "cmd_rsync	$RSYNC")
			else
				AC_MSG_ERROR(rsync not found)
			fi
		else
			AC_MSG_ERROR(rsync is required)
		fi
	]
)
dnl if the user didn't specify a path, hunt for it
if test "$RSYNC" = ""; then
	AC_PATH_PROG(RSYNC, rsync, no)
	AC_SUBST(RSYNC, "$RSYNC")
	AC_SUBST(CMD_RSYNC, "cmd_rsync	$RSYNC")
fi
dnl bail out if we can't find it
if test "$RSYNC" = "no"; then
	AC_MSG_ERROR(rsync is required)
fi



dnl
dnl CP CHECK (optional program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(cp,
	[  --with-cp=PATH          Specify the path to cp ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				CP=$withval
			else
				AC_MSG_ERROR(cp not found)
			fi
		else
			CP=no
		fi
	]
)
dnl save the program for testing
AC_SUBST(TEST_CP, "$CP")
dnl if the user didn't specify a path, hunt for it
if test "$CP" != "no"; then
	AC_PATH_PROG(CP, cp, no)
fi
dnl if we couldn't find it, provide an example
if test "$CP" = "no"; then
	CP=/bin/cp
fi
dnl either way, set the cmd_cp var
AC_SUBST(CMD_CP, "cmd_cp		$CP")



dnl
dnl RM CHECK (optional program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(rm,
	[  --with-rm=PATH          Specify the path to rm ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				RM=$withval
			else
				AC_MSG_ERROR(rm not found)
			fi
		else
			RM=no
		fi
	]
)
dnl if the user didn't specify a path, hunt for it
if test "$RM" != "no"; then
	AC_PATH_PROG(RM, rm, no)
fi
dnl save the program for testing
AC_SUBST(TEST_RM, "$RM")
dnl if we couldn't find it, provide an example
if test "$RM" = "no"; then
	RM=/bin/rm
fi
dnl either way, set the cmd_rm var
AC_SUBST(CMD_RM, "cmd_rm		$RM")



dnl
dnl SSH CHECK (optional program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(ssh,
	[  --with-ssh=PATH         Specify the path to ssh ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				SSH=$withval
			else
				AC_MSG_ERROR(ssh not found)
			fi
		else
			SSH=no
		fi
	]
)
dnl if the user didn't specify a path, hunt for it
if test "$SSH" != "no"; then
	AC_PATH_PROG(SSH, ssh, no)
fi
dnl save the program for testing
AC_SUBST(TEST_SSH, "$SSH")
dnl if we couldn't find it, provide an example
if test "$SSH" = "no"; then
	SSH=/path/to/ssh
fi
dnl either way, set the cmd_ssh var
AC_SUBST(CMD_SSH, "cmd_ssh	$SSH")


dnl
dnl LVM COMMANDS CHECK (optional programs)
dnl
dnl lvcreate
AC_PATH_PROG(LVCREATE, lvcreate, no)
if test "$LVCREATE" = "no"; then
	LVCREATE=/path/to/lvcreate
fi
AC_SUBST(CMD_LVCREATE, "$LVCREATE")

dnl lvremove
AC_PATH_PROG(LVREMOVE, lvremove, no)
if test "$LVREMOVE" = "no"; then
	LVREMOVE=/path/to/lvremove
fi
AC_SUBST(CMD_LVREMOVE, "$LVREMOVE")

dnl mount
AC_PATH_PROG(MOUNT, mount, no)
if test "$MOUNT" = "no"; then
	MOUNT=/path/to/mount
fi
AC_SUBST(CMD_MOUNT, "$MOUNT")

dnl umount
AC_PATH_PROG(UMOUNT, umount, no)
if test "$UMOUNT" = "no"; then
	UMOUNT=/path/to/umount
fi
AC_SUBST(CMD_UMOUNT, "$UMOUNT")


dnl
dnl LOGGER CHECK (optional program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(logger,
	[  --with-logger=PATH      Specify the path to logger ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				LOGGER=$withval
			else
				AC_MSG_ERROR(logger not found)
			fi
		else
			LOGGER=no
		fi
	]
)
dnl if the user didn't specify a path, hunt for it
if test "$LOGGER" != "no"; then
	AC_PATH_PROG(LOGGER, logger, no)
fi
dnl save the program for testing
AC_SUBST(TEST_LOGGER, "$LOGGER")
dnl if we couldn't find it, provide an example
if test "$LOGGER" = "no"; then
	LOGGER=/path/to/logger
fi
dnl either way, set the cmd_logger var
AC_SUBST(CMD_LOGGER, "cmd_logger	$LOGGER")



dnl
dnl DU CHECK (optional program)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(du,
	[  --with-du=PATH          Specify the path to du ],
	[
		if test "x$withval" != "xno"; then
			if test -x "$withval"; then
				DU=$withval
			else
				AC_MSG_ERROR(du not found)
			fi
		else
			DU=no
		fi
	]
)
dnl if the user didn't specify a path, hunt for it
if test "$DU" != "no"; then
	AC_PATH_PROG(DU, du, no)
fi
dnl save the program for testing
AC_SUBST(TEST_DU, "$DU")
dnl if we couldn't find it, provide an example
if test "$DU" = "no"; then
	DU=/path/to/du
fi
dnl either way, set the cmd_du var
AC_SUBST(CMD_DU, "cmd_du		$DU")


dnl
dnl TEST_SSH_USER CHECK (optional param)
dnl
dnl if the user specified a path, try that first
AC_ARG_WITH(test-ssh-user,
	[  --with-test-ssh-user=USER       Specify the path to rsync ],
	[
		if test "x$withval" != "xno"; then
			TEST_SSH_USER="$withval"
			AC_SUBST(TEST_SSH_USER, "$TEST_SSH_USER")
		fi
	]
)
dnl if the user didn't specify a test ssh user use current user
if test "$TEST_SSH_USER" = ""; then
	AC_SUBST(TEST_SSH_USER, "$USER")
fi


# replace perl paths
AC_CONFIG_FILES(rsnapshot:rsnapshot-program.pl)
AC_CONFIG_FILES(rsnapshot-diff:rsnapshot-diff.pl)

dnl try to find dependent programs for the config file
AC_CONFIG_FILES(rsnapshot.conf.default:rsnapshot.conf.default.in)

dnl testsuite-files are following
AC_CONFIG_FILES(t/backup_exec/backup_exec.t:t/backup_exec/backup_exec.t.in)
AC_CONFIG_FILES(t/backup_exec/conf/backup_exec.conf:t/backup_exec/conf/backup_exec.conf.in)
AC_CONFIG_FILES(t/backup_exec/conf/backup_exec_fail.conf:t/backup_exec/conf/backup_exec_fail.conf.in)

AC_CONFIG_FILES(t/cmd-post_pre-exec/cmd-post_pre-exec.t:t/cmd-post_pre-exec/cmd-post_pre-exec.t.in)
AC_CONFIG_FILES(t/cmd-post_pre-exec/conf/pre-false-post-false.conf:t/cmd-post_pre-exec/conf/pre-false-post-false.conf.in)
AC_CONFIG_FILES(t/cmd-post_pre-exec/conf/pre-false-post-true.conf:t/cmd-post_pre-exec/conf/pre-false-post-true.conf.in)
AC_CONFIG_FILES(t/cmd-post_pre-exec/conf/pre-true-post-false.conf:t/cmd-post_pre-exec/conf/pre-true-post-false.conf.in)
AC_CONFIG_FILES(t/cmd-post_pre-exec/conf/pre-true-post-true.conf:t/cmd-post_pre-exec/conf/pre-true-post-true.conf.in)

AC_CONFIG_FILES(t/configtest/conf/configtest.conf:t/configtest/conf/configtest.conf.in)
AC_CONFIG_FILES(t/configtest/configtest.t:t/configtest/configtest.t.in)

AC_CONFIG_FILES(t/gnu_cp/conf/gnu_cp.conf:t/gnu_cp/conf/gnu_cp.conf.in)
AC_CONFIG_FILES(t/gnu_cp/gnu_cp.t:t/gnu_cp/gnu_cp.t.in)

AC_CONFIG_FILES(t/link-dest_-t_when_only_one_snapshot/conf/link-dest_-t_when_only_one_snapshot.conf:t/link-dest_-t_when_only_one_snapshot/conf/link-dest_-t_when_only_one_snapshot.conf.in)
AC_CONFIG_FILES(t/link-dest_-t_when_only_one_snapshot/link-dest_-t_when_only_one_snapshot.t:t/link-dest_-t_when_only_one_snapshot/link-dest_-t_when_only_one_snapshot.t.in)

AC_CONFIG_FILES(t/relative_delete_bugfix/conf/relative_delete_bugfix.conf:t/relative_delete_bugfix/conf/relative_delete_bugfix.conf.in)
AC_CONFIG_FILES(t/relative_delete_bugfix/relative_delete_bugfix.t:t/relative_delete_bugfix/relative_delete_bugfix.t.in)

AC_CONFIG_FILES(t/rsync/conf/rsync.conf:t/rsync/conf/rsync.conf.in)
AC_CONFIG_FILES(t/rsync/rsync.t:t/rsync/rsync.t.in)

AC_CONFIG_FILES(t/snapshot_root_with_space/conf/snapshot_root_with_space.conf:t/snapshot_root_with_space/conf/snapshot_root_with_space.conf.in)
AC_CONFIG_FILES(t/snapshot_root_with_space/snapshot_root_with_space.t:t/snapshot_root_with_space/snapshot_root_with_space.t.in)

AC_CONFIG_FILES(t/ssh_args/conf/ssh_args.conf:t/ssh_args/conf/ssh_args.conf.in)
AC_CONFIG_FILES(t/ssh_args/ssh_args.t:t/ssh_args/ssh_args.t.in)

dnl Perl modules for regression test scripts
AC_CONFIG_FILES(t/SysWrap.pm)

AC_OUTPUT

# this is kludgy, but it works
RSNAPSHOT_SYSCONFDIR=`eval echo ${sysconfdir}`

if test -e "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"; then
	RSNAPSHOT_OLD_VERSION=`$PERL rsnapshot-program.pl -c $RSNAPSHOT_SYSCONFDIR/rsnapshot.conf check-config-version`

	# figure out if this is a fresh install or an upgrade
	# advise the user accordingly
	if test "$RSNAPSHOT_OLD_VERSION" = "unknown"; then
		echo ""
		echo "+----------------------------------------------------------------------------+"
		echo "| A previous version of rsnapshot was detected.                              |"
		echo "|                                                                            |"
		echo "| If you have not already done so, it is HIGHLY recommended that you upgrade |"
		echo "| your config file for compatibility with this release.                      |"
		echo "|                                                                            |"
		echo "| If you don't upgrade your config file, rsnapshot will appear to work, but  |"
		echo "| rearrange the relative paths to your backup files when you aren't looking. |"
		echo "| It would be a nasty surprise, which is why we're telling you about it now. |"
		echo "|                                                                            |"
		echo "| If you would like to automatically upgrade your config file, just type:    |"
		echo "|                                                                            |"
		echo "|     \"make upgrade\"                                                         |"
		echo "|                                                                            |"
		echo "| After you have upgraded your config file, type \"make install\".             |"
		echo "|                                                                            |"
		echo "| For more information on the upgrade, read the INSTALL file that came with  |"
		echo "| the program.                                                               |"
		echo "+----------------------------------------------------------------------------+"
		exit 0
	fi

	# this is already the latest version.
	if test "$RSNAPSHOT_OLD_VERSION" = "1.2"; then
		echo "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf found, and is up to date."
	else
		echo ""
		echo "ERROR: $RSNAPSHOT_SYSCONFDIR/rsnapshot.conf is an unknown version."
		echo "Upgrading is not recommended until you figure out what's wrong."
		echo ""
		exit 1
	fi
fi

echo ""
echo "Now type  \"make test\"    to run the regression test suite."
echo "Then type \"make install\" to install the program."
echo ""

if test ! -e "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"; then
	echo "After rsnapshot is installed, don't forget to copy"
	echo "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf.default to $RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"
	echo ""
fi
