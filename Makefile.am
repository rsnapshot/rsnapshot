bin_SCRIPTS = rsnapshot
man_MANS = rsnapshot.1
sysconf_DATA = rsnapshot.conf.default

DEB_BUILD_DIR = deb_build_dir

man:
	pod2man rsnapshot-program.pl > rsnapshot.1

html:
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	/bin/rm -f pod2htmd.*
	/bin/rm -f pod2htmi.*

cleanup:
	/bin/rm -rf rsnapshot-$(VERSION)/
	/bin/rm -rf ${DEB_BUILD_DIR}/
	/bin/rm -f rsnapshot-$(VERSION).tar.gz
	/bin/rm -f rsnapshot-$(VERSION)-1.deb
	/bin/rm -f rsnapshot.html
	/bin/rm -f pod2htmd.*
	/bin/rm -f pod2htmi.*

debian:
	/bin/mkdir -p ${DEB_BUILD_DIR}/{DEBIAN,usr/bin,etc,usr/share/man/man1}
	/bin/cp DEBIAN/{control,conffiles} ${DEB_BUILD_DIR}/DEBIAN/
	
	/bin/cat rsnapshot | sed 's/\/usr\/local\/bin/\/usr\/bin/g' > ${DEB_BUILD_DIR}/usr/bin/rsnapshot
	/bin/chmod 755 ${DEB_BUILD_DIR}/usr/bin/rsnapshot
	
	pod2man ${DEB_BUILD_DIR}/usr/bin/rsnapshot | gzip -9c > ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	/bin/chmod 644 ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	
	/bin/cat rsnapshot.conf | sed 's/#cmd_cp/cmd_cp/' > ${DEB_BUILD_DIR}/etc/rsnapshot.conf
	/bin/cp ${DEB_BUILD_DIR}/etc/rsnapshot.conf ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	/bin/chmod 600 ${DEB_BUILD_DIR}/etc/rsnapshot.conf
	/bin/chmod 644 ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	
	/bin/chown -R root:root ${DEB_BUILD_DIR}/
	dpkg -b ${DEB_BUILD_DIR}/ rsnapshot-$(VERSION)-1.deb
	/bin/rm -rf ${DEB_BUILD_DIR}/

tar:
	/bin/rm -f rsnapshot-$(VERSION).tar.gz
	
	@# core files
	/bin/mkdir rsnapshot-$(VERSION)
	/bin/cp rsnapshot rsnapshot.conf Makefile COPYING INSTALL README TODO ChangeLog rsnapshot-$(VERSION)/
	pod2man rsnapshot > rsnapshot-$(VERSION)/rsnapshot.1
	
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
	/bin/cp utils/rsnaptar rsnapshot-$(VERSION)/utils/
	
	@# change ownership to root (or current user), and delete build dir
	/bin/chown -R root:root rsnapshot-$(VERSION)/
	/bin/tar czf rsnapshot-$(VERSION).tar.gz rsnapshot-$(VERSION)/
	/bin/rm -rf rsnapshot-$(VERSION)/
