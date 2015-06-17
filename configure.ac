AC_INIT([rsnapshot],[m4_esyscmd_s([git describe --tags --always --dirty])],[rsnapshot-discuss@lists.sourceforge.net])
AM_INIT_AUTOMAKE([foreign])
AC_PROG_MAKE_SET
AC_CONFIG_FILES(Makefile)

dnl
dnl get the current working directory for the regression test suite
dnl
CWD=`eval echo \`pwd\``
AC_SUBST(CWD, "$CWD/")
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
m4_include(t/include.ac)


AC_OUTPUT

echo ""
echo "Now type  \"make test\"    to run the regression test suite."
echo "Then type \"make install\" to install the program."
echo ""

if test ! -e "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"; then
	echo "After rsnapshot is installed, don't forget to copy"
	echo "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf.default to $RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"
	echo ""
fi
