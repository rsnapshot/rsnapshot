AC_INIT(rsnapshot, 1.0.7, nathan@rsnapshot.org)
AM_INIT_AUTOMAKE
AC_PROG_MAKE_SET
AC_PROG_INSTALL
AC_CONFIG_FILES(Makefile)
AC_PATH_PROG(PERL, perl)
dnl Combine the preamble with a normal, working script
AC_CONFIG_FILES(rsnapshot:rsnapshot-preamble.pl:rsnapshot-program.pl)
AC_OUTPUT

# this is kludgy, but it works
RSNAPSHOT_SYSCONFDIR=`eval echo ${sysconfdir}`

echo ""
echo "Now type \"make install\""
echo ""
echo "After rsnapshot is installed, don't forget to copy"
echo "$RSNAPSHOT_SYSCONFDIR/rsnapshot.conf.default to $RSNAPSHOT_SYSCONFDIR/rsnapshot.conf"
echo ""
