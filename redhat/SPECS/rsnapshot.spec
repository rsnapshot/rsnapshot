Name: rsnapshot
Summary: Local and remote filesystem snapshot utility
Version: 1.0.6
Release: 1
BuildArch: noarch
Copyright: GPL
Group: Applications/System
Source: http://www.rsnapshot.org/downloads/rsnapshot-1.0.6.tar.gz
Patch: rsnapshot.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-root
Requires: perl, rsync

%description
This is a remote backup program that uses rsync to take backup snapshots of filesystems. 
It uses hard links to save space on disk.

%prep

%setup 

%patch

# it's just perl, so no need to compile
%build

%install
install -d $RPM_BUILD_ROOT/%{_bindir}
install -m 755 rsnapshot $RPM_BUILD_ROOT/usr/bin/rsnapshot

install -d $RPM_BUILD_ROOT/%{_mandir}/man1
install -m 644 rsnapshot.1 $RPM_BUILD_ROOT/usr/share/man/man1/

install -d $RPM_BUILD_ROOT/%{_sysconfdir}
install -m 644 rsnapshot.conf $RPM_BUILD_ROOT/etc/rsnapshot.conf.default
install -m 600 rsnapshot.conf $RPM_BUILD_ROOT/etc/rsnapshot.conf

%post

%clean
rm -rf $RPM_BUILD_ROOT
rm -rf $RPM_BUILD_DIR/%{name}-%{version}/

%files
%defattr(-,root,root)
%verify(user group mode md5 size mtime) %doc COPYING README INSTALL TODO
%verify(user group mode md5 size mtime) %config %{_sysconfdir}/rsnapshot.conf.default
%verify(user group mode) %config(noreplace) %{_sysconfdir}/rsnapshot.conf
%verify(user group mode md5 size mtime) %{_bindir}/rsnapshot
%verify(user group mode md5 size mtime) %{_mandir}/man1/rsnapshot.1*

%changelog
* Wed Nov 05 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- Removed fileutils dependency, added verification info

* Tue Nov 04 2003 Nathan Rosenquist <rsnapshot@scubaninja.com>
- fixed anonymous rsync error

* Thu Oct 30 2003 Nathan Rosenquist <rsnapshot@scubaninja.com>
- update to 1.0.3

* Tue Oct 28 2003 Carl Wilhelm Soderstrom <chrome@real-time.com>
- created spec file
