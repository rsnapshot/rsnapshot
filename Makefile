# GET THE VERSION NUMBER DIRECTLY FROM THE PROGRAM
VERSION=`./rsnapshot version_only`
DEB_BUILD_DIR="rsnapshot_deb"

default:
	@echo "it's written in perl, just type make install"
	
man:
	pod2man rsnapshot > rsnapshot.1
	
html:
	pod2html rsnapshot | grep -v 'link rev' > rsnapshot.html
	rm -f pod2htmd.x~~
	rm -f pod2htmi.x~~
	
clean:
	rm -rf rsnapshot-${VERSION}/
	rm -f rsnapshot-${VERSION}.tar.gz
	rm -f rsnapshot-${VERSION}-1.deb
	rm -f rsnapshot.html
	rm -rf ${DEB_BUILD_DIR}/
	
tar:
	rm -f rsnapshot-${VERSION}.tar.gz
	
	# core files
	mkdir rsnapshot-${VERSION}
	cp rsnapshot rsnapshot.conf Makefile COPYING INSTALL README TODO rsnapshot-${VERSION}/
	pod2man rsnapshot > rsnapshot-${VERSION}/rsnapshot.1
	
	# debian
	mkdir rsnapshot-${VERSION}/DEBIAN/
	cp DEBIAN/{control,conffiles} rsnapshot-${VERSION}/DEBIAN/
	
	# redhat
	mkdir rsnapshot-${VERSION}/redhat/
	mkdir rsnapshot-${VERSION}/redhat/SOURCES/
	mkdir rsnapshot-${VERSION}/redhat/SPECS/
	cp redhat/README rsnapshot-${VERSION}/redhat/
	cp redhat/SOURCES/rsnapshot.patch rsnapshot-${VERSION}/redhat/SOURCES/
	cp redhat/SPECS/rsnapshot.spec rsnapshot-${VERSION}/redhat/SPECS/
	
	chown -R 0:0 rsnapshot-${VERSION}/
	tar czf rsnapshot-${VERSION}.tar.gz rsnapshot-${VERSION}/
	rm -rf rsnapshot-${VERSION}/
	
debian:
	mkdir -p ${DEB_BUILD_DIR}/{DEBIAN,usr/bin,etc,usr/share/man/man1}
	cp DEBIAN/{control,conffiles} ${DEB_BUILD_DIR}/DEBIAN/
	
	cat rsnapshot | sed 's/\/usr\/local\/bin/\/usr\/bin/g' > ${DEB_BUILD_DIR}/usr/bin/rsnapshot
	chmod 755 ${DEB_BUILD_DIR}/usr/bin/rsnapshot
	
	pod2man ${DEB_BUILD_DIR}/usr/bin/rsnapshot | gzip -9c > ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	chmod 644 ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	
	cat rsnapshot.conf | sed s/#cmd_cp/cmd_cp/ > ${DEB_BUILD_DIR}/etc/rsnapshot.conf
	cp ${DEB_BUILD_DIR}/etc/rsnapshot.conf ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	chmod 600 ${DEB_BUILD_DIR}/etc/rsnapshot.conf ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	
	chown -R root:root ${DEB_BUILD_DIR}/
	dpkg -b ${DEB_BUILD_DIR}/ rsnapshot-${VERSION}-1.deb
	rm -rf ${DEB_BUILD_DIR}/
	
install:
	mkdir -p /usr/local/bin/
	cp -f rsnapshot /usr/local/bin/rsnapshot
	chmod 755 /usr/local/bin/rsnapshot
	chown 0:0 /usr/local/bin/rsnapshot
	
	mkdir -p /usr/local/man/man1/
	rm -f /usr/local/man/man1/rsnapshot.1.gz
	cp -f rsnapshot.1 /usr/local/man/man1/rsnapshot.1
	chmod 644 /usr/local/man/man1/rsnapshot.1
	chown 0:0 /usr/local/man/man1/rsnapshot.1
	
	cp -f rsnapshot.conf /etc/rsnapshot.conf.default
	chmod 600 /etc/rsnapshot.conf.default
	chown 0:0 /etc/rsnapshot.conf.default
	@echo
	@echo "+--------------------------------------------------------------------------+"
	@echo "| Example config file installed in /etc/rsnapshot.conf.default             |"
	@echo "| Copy this file to /etc/rsnapshot.conf, and modify it to suit your system |"
	@echo "+ -------------------------------------------------------------------------+"
	@echo
	
uninstall:
	rm -f /usr/local/bin/rsnapshot
	rm -f /usr/local/man/man1/rsnapshot.1
	rm -f /usr/local/man/man1/rsnapshot.1.gz
	rm -f /etc/rsnapshot.conf.default
	@echo
	@echo "Leaving /etc/rsnapshot.conf"
	@echo
