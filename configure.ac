AC_INIT(rsnapshot, 1.1.4, nathan@rsnapshot.org)
AM_INIT_AUTOMAKE
AC_PROG_MAKE_SET
AC_PROG_INSTALL
AC_CONFIG_FILES(Makefile)

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
dnl if the user didn't specify a path, hunt for it
if test "$CP" != "no"; then
	if test "$CP" = ""; then
		AC_PATH_PROG(CP, cp, no)
	fi
fi
dnl if we couldn't find it, provide an example
if test "$CP" = "no"; then
	CP=/bin/cp
fi
dnl either way, set the cmd_ssh var
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
	if test "$RM" = ""; then
		AC_PATH_PROG(RM, rm, no)
	fi
fi
dnl if we couldn't find it, provide an example
if test "$RM" = "no"; then
	RM=/bin/rm
fi
dnl either way, set the cmd_ssh var
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
	if test "$SSH" = ""; then
		AC_PATH_PROG(SSH, ssh, no)
	fi
fi
dnl if we couldn't find it, provide an example
if test "$SSH" = "no"; then
	SSH=/path/to/ssh
fi
dnl either way, set the cmd_ssh var
AC_SUBST(CMD_SSH, "cmd_ssh	$SSH")



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
	if test "$LOGGER" = ""; then
		AC_PATH_PROG(LOGGER, logger, no)
	fi
fi
dnl if we couldn't find it, provide an example
if test "$LOGGER" = "no"; then
	SSH=/path/to/logger
fi
dnl either way, set the cmd_ssh var
AC_SUBST(CMD_LOGGER, "cmd_logger	$LOGGER")



dnl Combine the preamble with a normal, working script
AC_CONFIG_FILES(rsnapshot:rsnapshot-preamble.pl:rsnapshot-program.pl)

dnl try to find dependent programs for the config file
AC_CONFIG_FILES(rsnapshot.conf.default:rsnapshot.conf.default.in)

AC_OUTPUT

# this is kludgy, but it works
RSNAPSHOT_SYSCONFDIR=`eval echo ${sysconfdir}`

echo ""
echo "Now type \"make install\""
echo ""
echo "After rsnapshot is installed, don't forget to copy"
echo "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf.default to $RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"
echo ""

