AC_INIT(rsnapshot, 1.0.7, nathan@rsnapshot.org)
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
