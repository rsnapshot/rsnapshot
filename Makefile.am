VERSION = 1.2.0

RPM_BASE_DIR  = /usr/src/redhat

man:
	@# perl 5.8 for this
	/usr/bin/pod2man -c '' -n 'rsnapshot' -r '' rsnapshot > rsnapshot.1
	
html:
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	/bin/rm -f pod2htmd.*
	/bin/rm -f pod2htmi.*

cleanup:
	/bin/rm -rf rsnapshot-$(VERSION)/
	/bin/rm -rf autom4te.cache
	/bin/rm -f rsnapshot-$(VERSION).tar.gz
	/bin/rm -f rsnapshot-$(VERSION)-1.deb
	/bin/rm -f rsnapshot-$(VERSION)-1.noarch.rpm
	/bin/rm -f rsnapshot.conf.default
	/bin/rm -f rsnapshot.html
	/bin/rm -f pod2htmd.*
	/bin/rm -f pod2htmi.*
	/bin/rm -f Makefile config.log config.status configure.lineno rsnapshot
	
rpm: tar
	/bin/cp rsnapshot-$(VERSION).tar.gz ${RPM_BASE_DIR}/SOURCES/
	/bin/cp redhat/SOURCES/rsnapshot.patch ${RPM_BASE_DIR}/SOURCES/
	/bin/cp redhat/SPECS/rsnapshot.spec ${RPM_BASE_DIR}/SPECS/
	/usr/bin/rpmbuild -bb ${RPM_BASE_DIR}/SPECS/rsnapshot.spec
	/bin/cp ${RPM_BASE_DIR}/RPMS/noarch/rsnapshot-$(VERSION)-1.noarch.rpm .

tar: man
	/bin/rm -f rsnapshot-$(VERSION).tar.gz
	
	@# core files
	/bin/mkdir rsnapshot-$(VERSION)
	/bin/cp rsnapshot-preamble.pl rsnapshot-program.pl rsnapshot.conf.default.in \
		rsnapshot.1 AUTHORS COPYING INSTALL README TODO NEWS ChangeLog rsnapshot-$(VERSION)/
	
	@# autoconf files
	/bin/cp Makefile.am Makefile.in aclocal.m4 configure configure.ac config.guess config.sub \
		install-sh missing mkinstalldirs rsnapshot-$(VERSION)/
	
	@# redhat
	/bin/mkdir rsnapshot-$(VERSION)/redhat/
	/bin/mkdir rsnapshot-$(VERSION)/redhat/SOURCES/
	/bin/mkdir rsnapshot-$(VERSION)/redhat/SPECS/
	/bin/cp redhat/README rsnapshot-$(VERSION)/redhat/
	/bin/cp redhat/SOURCES/rsnapshot.patch rsnapshot-$(VERSION)/redhat/SOURCES/
	/bin/cp redhat/SPECS/rsnapshot.spec rsnapshot-$(VERSION)/redhat/SPECS/
	
	@# utils
	/bin/mkdir rsnapshot-$(VERSION)/utils/
	/bin/cp utils/{rsnaptar,*.sh,*.pl,README} rsnapshot-$(VERSION)/utils/
	
	@# change ownership to root, and delete build dir
	chown -R root:root rsnapshot-$(VERSION)/
	/bin/tar czf rsnapshot-$(VERSION).tar.gz rsnapshot-$(VERSION)/
	/bin/rm -rf rsnapshot-$(VERSION)/

bin_SCRIPTS = rsnapshot
man_MANS = rsnapshot.1
sysconf_DATA = rsnapshot.conf.default

