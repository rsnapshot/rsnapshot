VERSION = 1.0.8

DEB_BUILD_DIR = fakeroot
RPM_BASE_DIR  = /usr/src/redhat

man:
	pod2man rsnapshot-program.pl > rsnapshot.1

html:
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	/bin/rm -f pod2htmd.*
	/bin/rm -f pod2htmi.*

cleanup:
	/bin/rm -rf rsnapshot-$(VERSION)/
	/bin/rm -rf ${DEB_BUILD_DIR}/
	/bin/rm -rf autom4te.cache
	/bin/rm -f rsnapshot-$(VERSION).tar.gz
	/bin/rm -f rsnapshot-$(VERSION)-1.deb
	/bin/rm -f rsnapshot-$(VERSION)-1.noarch.rpm
	/bin/rm -f rsnapshot.conf.default
	/bin/rm -f rsnapshot.html
	/bin/rm -f pod2htmd.*
	/bin/rm -f pod2htmi.*
	/bin/rm -f Makefile config.log config.status configure.lineno rsnapshot
	
debian:
	./configure --prefix=/usr --sysconfdir=/etc --mandir=/usr/share/man
	make DESTDIR=${DEB_BUILD_DIR} install
	
	/bin/mkdir ${DEB_BUILD_DIR}/DEBIAN/
	/bin/cp DEBIAN/{control,conffiles} ${DEB_BUILD_DIR}/DEBIAN/
	
	/bin/mkdir -p ${DEB_BUILD_DIR}/{DEBIAN,usr/bin,etc,usr/share/man/man1}
	/bin/cp DEBIAN/{control,conffiles} ${DEB_BUILD_DIR}/DEBIAN/
	
	gzip -9 ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1
	
	/bin/cat ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default | sed 's/#cmd_cp/cmd_cp/' | sed 's/#cmd_ssh/cmd_ssh	/' > ${DEB_BUILD_DIR}/etc/rsnapshot.conf
	/bin/rm ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	/bin/cp ${DEB_BUILD_DIR}/etc/rsnapshot.conf ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	
	chown -R root:root ${DEB_BUILD_DIR}/
	dpkg -b ${DEB_BUILD_DIR}/ rsnapshot-$(VERSION)-1.deb
	/bin/rm -rf ${DEB_BUILD_DIR}/

rpm: tar
	/bin/cp rsnapshot-$(VERSION).tar.gz ${RPM_BASE_DIR}/SOURCES/
	/bin/cp redhat/SOURCES/rsnapshot.patch ${RPM_BASE_DIR}/SOURCES/
	/bin/cp redhat/SPECS/rsnapshot.spec ${RPM_BASE_DIR}/SPECS/
	/usr/bin/rpmbuild -bb ${RPM_BASE_DIR}/SPECS/rsnapshot.spec
	/bin/cp ${RPM_BASE_DIR}/RPMS/noarch/rsnapshot-$(VERSION)-1.noarch.rpm .

tar:
	/bin/rm -f rsnapshot-$(VERSION).tar.gz
	
	@# core files
	/bin/mkdir rsnapshot-$(VERSION)
	/bin/cp rsnapshot-preamble.pl rsnapshot-program.pl rsnapshot.conf.default.in \
		AUTHORS COPYING INSTALL README TODO NEWS ChangeLog rsnapshot-$(VERSION)/
	pod2man rsnapshot > rsnapshot-$(VERSION)/rsnapshot.1
	
	@# autoconf files
	/bin/cp Makefile.am Makefile.in aclocal.m4 configure configure.ac install-sh \
		missing mkinstalldirs rsnapshot-$(VERSION)/
	
	@# debian
	/bin/mkdir rsnapshot-$(VERSION)/DEBIAN/
	/bin/cp DEBIAN/{control,conffiles} rsnapshot-$(VERSION)/DEBIAN/
	
	@# redhat
	/bin/mkdir rsnapshot-$(VERSION)/redhat/
	/bin/mkdir rsnapshot-$(VERSION)/redhat/SOURCES/
	/bin/mkdir rsnapshot-$(VERSION)/redhat/SPECS/
	/bin/cp redhat/README rsnapshot-$(VERSION)/redhat/
	/bin/cp redhat/SOURCES/rsnapshot.patch rsnapshot-$(VERSION)/redhat/SOURCES/
	/bin/cp redhat/SPECS/rsnapshot.spec rsnapshot-$(VERSION)/redhat/SPECS/
	
	@# utils
	/bin/mkdir rsnapshot-$(VERSION)/utils/
	/bin/cp utils/rsnaptar utils/backup_pgsql.sh utils/backup_rsnapshot_cvsroot.sh rsnapshot-$(VERSION)/utils/
	
	@# change ownership to root, and delete build dir
	chown -R root:root rsnapshot-$(VERSION)/
	/bin/tar czf rsnapshot-$(VERSION).tar.gz rsnapshot-$(VERSION)/
	/bin/rm -rf rsnapshot-$(VERSION)/

bin_SCRIPTS = rsnapshot
man_MANS = rsnapshot.1
sysconf_DATA = rsnapshot.conf.default

