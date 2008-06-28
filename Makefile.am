# $Id: Makefile.am,v 1.88 2008/06/28 02:02:14 djk20 Exp $ #

# rsnapshot version
VERSION = 1.3.1

# Where RPM files are built on this system
RPM_BASE_DIR = /usr/src/redhat

# update of spec file, within this rsnapshot version
RPM_RELEASE = 1

doc: man html
	@echo "Documentation $(man_MANS) and rsnapshot.html are now up to date."
	@touch doc

man: $(man_MANS)
rsnapshot.1 : rsnapshot
	@# perl 5.8 for this
	/usr/bin/pod2man -c '' -n 'rsnapshot' -r '' rsnapshot > rsnapshot.1
	
rsnapshot-diff.1 : rsnapshot-diff
	@# perl 5.8 for this
	/usr/bin/pod2man -c '' -n 'rsnapshot-diff' -r '' rsnapshot-diff > rsnapshot-diff.1
	
html: rsnapshot.html
rsnapshot.html: rsnapshot
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	rm -f pod2htmd.*
	rm -f pod2htmi.*

upgrade:
	@echo ""
	${PERL} rsnapshot-program.pl -c ${sysconfdir}/rsnapshot.conf upgrade-config-file
	@echo ""

clean:
	rm -rf rsnapshot-$(VERSION)/
	rm -rf autom4te.cache
	rm -f rsnapshot-$(VERSION).tar.gz
	rm -f rsnapshot-$(VERSION)-$(RPM_RELEASE).noarch.rpm
	rm -f rsnapshot.conf.default
	rm -f rsnapshot.conf.default.in.redhat
	rm -f rsnapshot.html
	rm -f pod2htmd.*
	rm -f pod2htmi.*
	rm -f Makefile config.log config.status configure.lineno rsnapshot rsnapshot-diff
	-rm -f doc rpm-patch rpm tar
	rm -f t/*.t
	rm -f t/support/etc/*.conf
	rm -f t/support/files/a/{1,2}
	rm -rf t/support/snapshots/*.*
	
rpm-patch: redhat/SOURCES/rsnapshot.patch
	@echo
	@touch rpm-patch
redhat/SOURCES/rsnapshot.patch: rsnapshot.conf.default.in Makefile
	@echo building rpm config file patch $@
	cp -p rsnapshot.conf.default.in rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#\@CMD_CP\@/\@CMD_CP\@/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#\@CMD_DU\@/\@CMD_DU\@/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#logfile/logfile/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's/^\#lockfile/lockfile/' rsnapshot.conf.default.in.redhat
	perl -pi -e 's%^\#cmd_rsnapshot_diff	/usr/local/bin/rsnapshot-diff%cmd_rsnapshot_diff	/usr/bin/rsnapshot-diff%' rsnapshot.conf.default.in.redhat
	@# diff doesn't return 0
	diff -u rsnapshot.conf.default.in rsnapshot.conf.default.in.redhat > redhat/SOURCES/rsnapshot.patch || /bin/true
	rm -f rsnapshot.conf.default.in.redhat
	
rpm: rsnapshot-$(VERSION)-$(RPM_RELEASE).noarch.rpm
	@touch rpm
rsnapshot-$(VERSION)-$(RPM_RELEASE).noarch.rpm: tar redhat/SOURCES/rsnapshot.patch redhat/SPECS/rsnapshot.spec
	@echo building rpm file $@
	@# build rpm file
	cp rsnapshot-$(VERSION).tar.gz $(RPM_BASE_DIR)/SOURCES/
	cp redhat/SOURCES/rsnapshot.patch $(RPM_BASE_DIR)/SOURCES/
	cp redhat/SPECS/rsnapshot.spec $(RPM_BASE_DIR)/SPECS/
	rpmbuild -ba $(RPM_BASE_DIR)/SPECS/rsnapshot.spec
	cp -p $(RPM_BASE_DIR)/RPMS/noarch/rsnapshot-$(VERSION)-$(RPM_RELEASE).noarch.rpm .
	-cp -p $(RPM_BASE_DIR)/SRPMS/rsnapshot-$(VERSION)-$(RPM_RELEASE).src.rpm .
	@echo

tar: rsnapshot-$(VERSION).tar.gz
	@touch tar
rsnapshot-$(VERSION).tar.gz: $(man_MANS) rpm-patch Makefile $(bin_SCRIPTS) $(sysconf_DATA)
	@echo building tar file 
	@# recommended to run make tar as root for the chown
	rm -f rsnapshot-$(VERSION).tar.gz
	
	@# core files
	mkdir rsnapshot-$(VERSION)
	cp -p rsnapshot-preamble.pl rsnapshot-program.pl rsnapshot-diff.pl rsnapshot.conf.default.in \
		$(man_MANS) AUTHORS COPYING INSTALL README TODO NEWS ChangeLog \
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
	cp -p utils/{*.sh,*.pl,README} rsnapshot-$(VERSION)/utils/
	cp -p utils/{rsnaptar,rsnapshot-copy} rsnapshot-$(VERSION)/utils/
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
	@echo

test: rsnapshot
	@PERL@ -MTest::Harness -e 'runtests(glob "t/*.t")';

bin_SCRIPTS = rsnapshot rsnapshot-diff
man_MANS = rsnapshot.1 rsnapshot-diff.1
sysconf_DATA = rsnapshot.conf.default

