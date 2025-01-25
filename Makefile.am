# rsnapshot version
VERSION = @VERSION@

doc: man html
	@echo "Documentation $(man_MANS) and rsnapshot.html are now up to date."
	@touch doc

man: $(man_MANS)
rsnapshot.1 : rsnapshot
	@# perl 5.8 for this
	pod2man -c 'rsnapshot-tools' -n 'rsnapshot' -r 'rsnapshot-tools' rsnapshot > rsnapshot.1

rsnapshot-diff.1 : rsnapshot-diff
	@# perl 5.8 for this
	pod2man -c 'rsnapshot-tools' -n 'rsnapshot-diff' -r 'rsnapshot-tools' rsnapshot-diff > rsnapshot-diff.1

html: rsnapshot.html
rsnapshot.html: rsnapshot
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	rm -f pod2htmd.*
	rm -f pod2htmi.*

clean:
	rm -rf rsnapshot-$(VERSION)/
	rm -f  $(man_MANS)
	rm -rf autom4te.cache
	rm -f rsnapshot-$(VERSION).tar.gz
	rm -f $(sysconf_DATA)
	rm -f rsnapshot.html
	rm -f pod2htmd.*
	rm -f pod2htmi.*
	rm -f Makefile config.log config.status configure.lineno rsnapshot rsnapshot-diff
	rm -f t/*.t
	rm -f t/*.pm
	rm -f t/support/etc/*.conf
	rm -f t/support/files/a/{1,2}
	rm -rf t/support/snapshots/*.*

tar: dist/rsnapshot-$(VERSION).tar.gz

dist/rsnapshot-$(VERSION).tar.gz: $(man_MANS) Makefile $(bin_SCRIPTS) $(sysconf_DATA)
	@echo building tar file
	mkdir -p dist/rsnapshot-$(VERSION)/
	@# core files
	cp -a AUTHORS ChangeLog COPYING INSTALL.md Makefile.am README.md \
 		rsnapshot.conf.default.in rsnapshot-diff.pl rsnapshot-program.pl \
 		dist/rsnapshot-$(VERSION)
	@# autoconf files
	cp -a configure.ac Makefile.am \
		aclocal.m4 autom4te.cache configure install-sh Makefile.in missing \
		dist/rsnapshot-$(VERSION)/
	@# documentation files
	cp -a docs \
		dist/rsnapshot-$(VERSION)/
	@# utils
	cp -a utils/ \
		dist/rsnapshot-$(VERSION)/
	@# testsuite
	cp -a t/ \
		dist/rsnapshot-$(VERSION)/
	@# remove git-files
	find dist/rsnapshot-$(VERSION)/ -depth -name .gitignore -exec rm -rf {} \;
	@# change ownership to root, and delete build dir
	fakeroot chown -R root:root dist/rsnapshot-$(VERSION)/
	rm -f dist/rsnapshot-$(VERSION).tar.gz
	tar czf dist/rsnapshot-$(VERSION).tar.gz dist/rsnapshot-$(VERSION)/
	rm -rf dist/rsnapshot-$(VERSION)/
	@echo

# If you lack GNU make, you could use "test_cases = t/*.t" as an approximation.
test_cases_in := $(wildcard t/*/*.t.in)
test_cases := $(test_cases_in:%.in=%)
test_configs_in := $(wildcard t/*/conf/*.conf.in)
test_configs := $(test_configs_in:%.in=%)
test_modules_in = $(wildcard t/*.pm.in)
test_modules = $(test_modules_in:%.in=%)
test: rsnapshot $(test_cases) $(test_configs) $(test_modules)
	@PERL@ -MTest::Harness -It -e 'runtests($(test_cases:%="%",))'

bin_SCRIPTS = rsnapshot rsnapshot-diff
man_MANS = rsnapshot.1 rsnapshot-diff.1
sysconf_DATA = rsnapshot.conf.default
