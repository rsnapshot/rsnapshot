# GET THE VERSION NUMBER DIRECTLY FROM THE PROGRAM
VERSION=`./rsnapshot version_only`
DPKG_BUILD_DIR="rsnapshot_dpkg"

default:
	@echo "it's written in perl, just type make install"
	
man:
	pod2man rsnapshot > rsnapshot.1
	
html:
	pod2html rsnapshot > rsnapshot.html
	/bin/rm -f pod2htmd.x~~
	/bin/rm -f pod2htmi.x~~
	
clean:
	/bin/rm -rf rsnapshot-${VERSION}/
	/bin/rm -f rsnapshot-${VERSION}.tar.gz
	/bin/rm -f rsnapshot-${VERSION}-1.deb
	/bin/rm -f rsnapshot.html
	
tar:
	/bin/rm -f rsnapshot-${VERSION}.tar.gz
	
	mkdir rsnapshot-${VERSION}
	mkdir rsnapshot-${VERSION}/DEBIAN/
	
	/bin/cp rsnapshot rsnapshot.conf Makefile GPL INSTALL README TODO rsnapshot-${VERSION}/
	/bin/cp DEBIAN/{control,conffiles} rsnapshot-${VERSION}/DEBIAN/
	
	pod2man rsnapshot > rsnapshot-${VERSION}/rsnapshot.1
	
	chown -R 0:0 rsnapshot-${VERSION}/
	tar czf rsnapshot-${VERSION}.tar.gz rsnapshot-${VERSION}/
	rm -rf rsnapshot-${VERSION}/
	
debian:
	mkdir -p ${DPKG_BUILD_DIR}/{DEBIAN,usr/bin,etc,usr/share/man/man1}
	/bin/cp DEBIAN/{control,conffiles} ${DPKG_BUILD_DIR}/DEBIAN/
	
	cat rsnapshot | sed 's/\/usr\/local\/bin/\/usr\/bin/g' > ${DPKG_BUILD_DIR}/usr/bin/rsnapshot
	chmod 755 ${DPKG_BUILD_DIR}/usr/bin/rsnapshot
	
	pod2man ${DPKG_BUILD_DIR}/usr/bin/rsnapshot | gzip -9c > ${DPKG_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	chmod 644 ${DPKG_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	
	/bin/cp rsnapshot.conf ${DPKG_BUILD_DIR}/etc/rsnapshot.conf
	/bin/cp rsnapshot.conf ${DPKG_BUILD_DIR}/etc/rsnapshot.conf.default
	chmod 600 ${DPKG_BUILD_DIR}/etc/rsnapshot.conf
	chmod 600 ${DPKG_BUILD_DIR}/etc/rsnapshot.conf.default
	
	chown -R root:root ${DPKG_BUILD_DIR}/
	dpkg -b ${DPKG_BUILD_DIR}/ rsnapshot-${VERSION}-1.deb
	/bin/rm -rf ${DPKG_BUILD_DIR}/
	
install:
	/bin/cp -f rsnapshot /usr/local/bin/rsnapshot
	chmod 755 /usr/local/bin/rsnapshot
	chown 0:0 /usr/local/bin/rsnapshot
	
	mkdir -p /usr/local/man/man1/
	cat rsnapshot.1 | gzip -9c > /usr/local/man/man1/rsnapshot.1.gz
	chmod 644 /usr/local/man/man1/rsnapshot.1.gz
	chown 0:0 /usr/local/man/man1/rsnapshot.1.gz
	
	/bin/cp -f rsnapshot.conf /etc/rsnapshot.conf.default
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
	rm -f /usr/local/man/man1/rsnapshot.1.gz
	rm -f /etc/rsnapshot.conf.default
	
