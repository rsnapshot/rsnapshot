# $Id: Makefile.am,v 1.79 2006/10/16 21:22:40 djk20 Exp $ #

VERSION = 1.3.0

RPM_BASE_DIR = /usr/src/redhat

upgrade:
	@echo ""
	${PERL} rsnapshot-program.pl -c ${sysconfdir}/rsnapshot.conf upgrade-config-file
	@echo ""

doc: man html
	@echo "Documentation rsnapshot.1 and rsnapshot.html are now up to date."

man: rsnapshot.1
rsnapshot.1 : rsnapshot
	@# perl 5.8 for this
	/usr/bin/pod2man -c '' -n 'rsnapshot' -r '' rsnapshot > rsnapshot.1
	
html: rsnapshot.html
rsnapshot.html: rsnapshot
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
	
rpm-patch: redhat/SOURCES/rsnapshot.patch
redhat/SOURCES/rsnapshot.patch: rsnapshot.conf.default.in Makefile
	@# redhat config file patch
	cp -p rsnapshot.conf.default.in rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#\@CMD_CP\@/\@CMD_CP\@/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#\@CMD_DU\@/\@CMD_DU\@/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#logfile/logfile/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#lockfile/lockfile/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's%^\#cmd_rsnapshot_diff	/usr/local/bin/rsnapshot-diff%cmd_rsnapshot_diff	/usr/bin/rsnapshot-diff%' rsnapshot.conf.default.in.redhat
	@# diff doesn't return 0
	diff -u rsnapshot.conf.default.in rsnapshot.conf.default.in.redhat > redhat/SOURCES/rsnapshot.patch || /bin/true
	rm -f rsnapshot.conf.default.in.redhat
	
rpm: tar redhat/SOURCES/rsnapshot.patch
	cp rsnapshot-$(VERSION).tar.gz $(RPM_BASE_DIR)/SOURCES/
	cp redhat/SOURCES/rsnapshot.patch $(RPM_BASE_DIR)/SOURCES/
	cp redhat/SPECS/rsnapshot.spec $(RPM_BASE_DIR)/SPECS/
	rpmbuild -bb $(RPM_BASE_DIR)/SPECS/rsnapshot.spec
	cp $(RPM_BASE_DIR)/RPMS/noarch/rsnapshot-$(VERSION)-1.noarch.rpm .

tar: doc rpm-patch
	rm -f rsnapshot-$(VERSION).tar.gz
	
	@# core files
	mkdir rsnapshot-$(VERSION)
	cp -p rsnapshot-preamble.pl rsnapshot-program.pl rsnapshot-diff.pl rsnapshot.conf.default.in \
		rsnapshot.1 AUTHORS COPYING INSTALL README TODO NEWS ChangeLog \
		rsnapshot-$(VERSION)/

	@# documentation files
	cp -a docs rsnapshot-$(VERSION)/
	
	@# autoconf files
	cp -p Makefile.am Makefile.in aclocal.m4 configure configure.ac config.guess config.sub \
		install-sh missing mkinstalldirs rsnapshot-$(VERSION)/
	
	@# redhat
	mkdir rsnapshot-$(VERSION)/redhat/
	mkdir rsnapshot-$(VERSION)/redhat/SOURCES/
	mkdir rsnapshot-$(VERSION)/redhat/SPECS/
	cp -p redhat/README rsnapshot-$(VERSION)/redhat/
	cp -p redhat/SOURCES/rsnapshot.patch rsnapshot-$(VERSION)/redhat/SOURCES/
	cp -p redhat/SPECS/rsnapshot.spec rsnapshot-$(VERSION)/redhat/SPECS/
	
	@# utils
	mkdir rsnapshot-$(VERSION)/utils/
	cp -p utils/{rsnaptar,*.sh,*.pl,README} rsnapshot-$(VERSION)/utils/
	mkdir rsnapshot-$(VERSION)/utils/rsnapshotdb
	cp -p --parents utils/rsnapshotdb/*.* rsnapshot-$(VERSION)/
	
	@# t - testing
	mkdir -p rsnapshot-$(VERSION)/t/support/etc
	mkdir rsnapshot-$(VERSION)/t/support/files
	mkdir rsnapshot-$(VERSION)/t/support/snapshots
	cp -a --parents t/*.t.in t/support/etc/*.in t/support/files rsnapshot-$(VERSION)/
	@# remove CVS directories from t/support/files and docs.
	-find rsnapshot-$(VERSION)/ -depth -name CVS -exec rm -rf {} \;
	
	@# change ownership to root, and delete build dir
	-chown -R root:root rsnapshot-$(VERSION)/
	tar czf rsnapshot-$(VERSION).tar.gz rsnapshot-$(VERSION)/
	rm -rf rsnapshot-$(VERSION)/

test:
	@PERL@ -MTest::Harness -e 'runtests(glob "t/*.t")';

bin_SCRIPTS = rsnapshot rsnapshot-diff
man_MANS = rsnapshot.1
sysconf_DATA = rsnapshot.conf.default

