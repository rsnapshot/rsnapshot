# $Id: rsnapshot.spec,v 1.42 2005/08/21 06:48:31 scubaninja Exp $

Name: rsnapshot
Summary: Local and remote filesystem snapshot utility
Version: 1.2.2
Release: 1
BuildArch: noarch
License: GPL
Group: Applications/System
Source: http://www.rsnapshot.org/downloads/rsnapshot-1.2.2.tar.gz
Patch: rsnapshot.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-root
Requires: perl, rsync
AutoReqProv: no

%description
This is a remote backup program that uses rsync to take backup snapshots of filesystems.
It uses hard links to save space on disk.

%prep

%setup 

%patch

%build
./configure \
	--prefix=/usr \
	--bindir=/usr/bin \
	--mandir=/usr/share/man \
	--sysconfdir=/etc \
	--with-perl=/usr/bin/perl \
	--with-rsync=/usr/bin/rsync \
	--with-ssh=/usr/bin/ssh \
	--with-logger=/usr/bin/logger \
	--with-du=/usr/bin/du

%install
install -d $RPM_BUILD_ROOT/%{_bindir}
install -m 755 rsnapshot $RPM_BUILD_ROOT/usr/bin/rsnapshot
install -m 755 rsnapshot-diff $RPM_BUILD_ROOT/usr/bin/rsnapshot-diff

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
%verify(user group mode md5 size mtime) %doc AUTHORS COPYING ChangeLog README INSTALL TODO
%verify(user group mode md5 size mtime) %config %{_sysconfdir}/rsnapshot.conf.default
%verify(user group mode) %config(noreplace) %{_sysconfdir}/rsnapshot.conf
%verify(user group mode md5 size mtime) %{_bindir}/rsnapshot
%verify(user group mode md5 size mtime) %{_mandir}/man1/rsnapshot.1*

%changelog
* Sat Apr 2 2005 Nathan Rosenquist <nathan@rsnapshot.org>
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
