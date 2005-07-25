# $Id: Makefile.am,v 1.65 2005/07/25 06:49:40 scubaninja Exp $ #

VERSION = 1.2.2

RPM_BASE_DIR = /usr/src/redhat

upgrade:
	@echo ""
	${PERL} rsnapshot-program.pl -c ${sysconfdir}/rsnapshot.conf upgrade-config-file
	@echo ""

man:
	@# perl 5.8 for this
	/usr/bin/pod2man -c '' -n 'rsnapshot' -r '' rsnapshot > rsnapshot.1
	
html:
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	rm -f pod2htmd.*
	rm -f pod2htmi.*

clean:
	rm -rf rsnapshot-$(VERSION)/
	rm -rf autom4te.cache
	rm -f rsnapshot-$(VERSION).tar.gz
	rm -f rsnapshot-$(VERSION)-1.noarch.rpm
	rm -f rsnapshot.conf.default
	rm -f rsnapshot.conf.default.in.redhat
	rm -f rsnapshot.html
	rm -f pod2htmd.*
	rm -f pod2htmi.*
	rm -f Makefile config.log config.status configure.lineno rsnapshot rsnapshot-diff
	rm -f t/*.t
	rm -f t/support/etc/*.conf
	rm -f t/support/files/a/{1,2}
	rm -rf t/support/snapshots/*.*
	
rpm-patch:
	@# redhat config file patch
	cp rsnapshot.conf.default.in rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#\@CMD_CP\@/\@CMD_CP\@/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#\@CMD_DU\@/\@CMD_DU\@/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#logfile/logfile/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#lockfile/lockfile/' rsnapshot.conf.default.in.redhat
	@# diff doesn't return 0
	diff -u rsnapshot.conf.default.in rsnapshot.conf.default.in.redhat > redhat/SOURCES/rsnapshot.patch || /bin/true
	rm -f rsnapshot.conf.default.in.redhat
	
rpm: tar
	cp rsnapshot-$(VERSION).tar.gz $(RPM_BASE_DIR)/SOURCES/
	cp redhat/SOURCES/rsnapshot.patch $(RPM_BASE_DIR)/SOURCES/
	cp redhat/SPECS/rsnapshot.spec $(RPM_BASE_DIR)/SPECS/
	rpmbuild -bb $(RPM_BASE_DIR)/SPECS/rsnapshot.spec
	cp $(RPM_BASE_DIR)/RPMS/noarch/rsnapshot-$(VERSION)-1.noarch.rpm .

tar: man rpm-patch
	rm -f rsnapshot-$(VERSION).tar.gz
	
	@# core files
	mkdir rsnapshot-$(VERSION)
	cp rsnapshot-preamble.pl rsnapshot-program.pl rsnapshot-diff.pl rsnapshot.conf.default.in \
		rsnapshot.1 AUTHORS COPYING INSTALL README TODO NEWS ChangeLog rsnapshot-$(VERSION)/
	
	@# autoconf files
	cp Makefile.am Makefile.in aclocal.m4 configure configure.ac config.guess config.sub \
		install-sh missing mkinstalldirs rsnapshot-$(VERSION)/
	
	@# redhat
	mkdir rsnapshot-$(VERSION)/redhat/
	mkdir rsnapshot-$(VERSION)/redhat/SOURCES/
	mkdir rsnapshot-$(VERSION)/redhat/SPECS/
	cp redhat/README rsnapshot-$(VERSION)/redhat/
	cp redhat/SOURCES/rsnapshot.patch rsnapshot-$(VERSION)/redhat/SOURCES/
	cp redhat/SPECS/rsnapshot.spec rsnapshot-$(VERSION)/redhat/SPECS/
	
	@# utils
	mkdir rsnapshot-$(VERSION)/utils/
	cp utils/{rsnaptar,*.sh,*.pl,README} rsnapshot-$(VERSION)/utils/
	
	@# change ownership to root, and delete build dir
	chown -R root:root rsnapshot-$(VERSION)/
	tar czf rsnapshot-$(VERSION).tar.gz rsnapshot-$(VERSION)/
	rm -rf rsnapshot-$(VERSION)/

test:
	@PERL@ -MTest::Harness -e 'runtests(glob "t/*.t")';

bin_SCRIPTS = rsnapshot rsnapshot-diff
man_MANS = rsnapshot.1
sysconf_DATA = rsnapshot.conf.default

