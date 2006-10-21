# $Id: rsnapshot.spec,v 1.52 2006/10/21 06:42:38 djk20 Exp $

Name: rsnapshot
Summary: Local and remote filesystem snapshot utility
Version: 1.3.0
Release: 1
BuildArch: noarch
License: GPL
URL: http://www.rsnapshot.org/
Group: Applications/System
Source: http://www.rsnapshot.org/downloads/rsnapshot-%{version}.tar.gz
Patch: rsnapshot.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires: perl, rsync
AutoReqProv: no

%description
This is a remote backup program that uses rsync to take backup snapshots of
filesystems.  It uses hard links to save space on disk.
For more details see http://www.rsnapshot.org/.

%prep

%setup 

%patch

%build
%configure					\
	--with-perl="%{__perl}"			\
	--with-rsync="%{_bindir}/rsync"		\
	--with-ssh="%{_bindir}/ssh"		\
	--with-logger="%{_bindir}/logger"	\
	--with-du="%{_bindir}/du"

%install
install -d $RPM_BUILD_ROOT/%{_bindir}
install -m 755 rsnapshot $RPM_BUILD_ROOT/usr/bin/rsnapshot
install -m 755 rsnapshot-diff $RPM_BUILD_ROOT/usr/bin/rsnapshot-diff
install -m 755 utils/rsnapreport.pl $RPM_BUILD_ROOT/usr/bin/rsnapreport.pl

install -d $RPM_BUILD_ROOT/%{_mandir}/man1
install -m 644 rsnapshot.1 $RPM_BUILD_ROOT/usr/share/man/man1/

install -d $RPM_BUILD_ROOT/%{_sysconfdir}
install -m 644 rsnapshot.conf.default $RPM_BUILD_ROOT/etc/rsnapshot.conf.default
install -m 600 rsnapshot.conf.default $RPM_BUILD_ROOT/etc/rsnapshot.conf

%post
#
# upgrade rsnapshot config file
#
RSNAPSHOT_CONFIG_VERSION=`%{_bindir}/rsnapshot check-config-version`
if test $? != 0; then
	echo "Error upgrading %{_sysconfdir}/rsnapshot.conf"
fi

if test "$RSNAPSHOT_CONFIG_VERSION" = "1.2"; then
	# already latest version
	exit 0
fi

if test "$RSNAPSHOT_CONFIG_VERSION" = "unknown"; then
	%{_bindir}/rsnapshot upgrade-config-file
	RETVAL=$?
	exit $RETVAL
fi

echo "Error upgrading %{_sysconfdir}/rsnapshot.conf. Config format unknown!"
exit 1


%clean
rm -rf $RPM_BUILD_ROOT
rm -rf $RPM_BUILD_DIR/%{name}-%{version}/

%files
%defattr(-,root,root)
%doc AUTHORS COPYING ChangeLog README INSTALL TODO
%doc docs/Upgrading_from_1.1 docs/HOWTOs/rsnapshot-HOWTO.en.html
# rsnapshot.conf.default is replaceable - user is not supposed to edit it
%config %{_sysconfdir}/rsnapshot.conf.default
%config(noreplace) %verify(user group mode) %{_sysconfdir}/rsnapshot.conf
%{_bindir}/rsnapshot
%{_bindir}/rsnapshot-diff
%{_bindir}/rsnapreport.pl
%{_mandir}/man1/rsnapshot.1*

%changelog
* Tue Oct 10 2006 David Keegel <djk@cybersource.com.au> - 1.3.0-1
- Add docs: Upgrading_from_1.1 rsnapshot-HOWTO.en.html
- Add rsnapreport.pl to files and install.

* Sun Sep 24 2006 David Keegel <djk@cybersource.com.au> - 1.3.0-1
- Update version number to 1.3.0

* Thu Jun 22 2006 David Keegel <djk@cybersource.com.au> - 1.3.0-0
- Change BuildRoot to format recommended in Fedora Packaging Guidelines
- Reformat description to fit in 80 columns, and add URL.
- Add URL (www.rsnapshot.org)
- Remove %verify on %files (except rsnapshot.conf).  
- Change rsnapshot.conf to %config(noreplace).
- Add version numbers to my ChangeLog entries.

* Thu May 18 2006 David Keegel <djk@cybersource.com.au> - 1.2.9-1
- Update version number to 1.2.9

* Sun Feb  5 2006 David Keegel <djk@cybersource.com.au> - 1.2.4-1
- Added rsnapshot-diff to %files
- Update version number to 1.2.4

* Sat Apr  2 2005 Nathan Rosenquist <nathan@rsnapshot.org>
- Added rsnapshot-diff to install

* Sun Jan 29 2005 Nathan Rosenquist <nathan@rsnapshot.org>
- Added upgrade script

* Sat Jan 22 2005 Nathan Rosenquist <nathan@rsnapshot.org>
- Added --with-du option

* Thu Jan 15 2004 Nathan Rosenquist <nathan@rsnapshot.org>
- Added "AutoReqProv: no" for SuSE compatibility

* Fri Dec 26 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- Added util-linux dependency, and --with-logger= option

* Fri Dec 19 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- now fully support autoconf

* Tue Dec 16 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- changed rsnapshot.conf to rsnapshot.conf.default from the source tree

* Wed Nov 05 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- Removed fileutils dependency, added verification info

* Tue Nov 04 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- fixed anonymous rsync error

* Thu Oct 30 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- update to 1.0.3

* Tue Oct 28 2003 Carl Wilhelm Soderstrom <chrome@real-time.com>
- created spec file
