# the classics
CP=/bin/cp
RM=/bin/rm
CAT=/bin/cat
CHMOD=/bin/chmod
CHOWN=/bin/chown
MKDIR=/bin/mkdir

# variable locations
ID=id
SED=sed
GREP=grep
GNU_TAR=tar
INSTALL=install
DPKG=dpkg
POD2MAN=pod2man
POD2HTML=pod2html

# execute programs to populate variables
VERSION = `./rsnapshot version_only`
INSTALL_UID = `${ID} -u`
INSTALL_GID = `${ID} -g`

# directory paths
INSTALL_DIR=/usr/local
BIN_DIR=${INSTALL_DIR}/bin
MAN_DIR=${INSTALL_DIR}/man
SYSCONF_DIR=/etc
DEB_BUILD_DIR=rsnapshot_deb

default:
	@echo "it's written in perl, just type make install"
	
man:
	${POD2MAN} rsnapshot > rsnapshot.1
	
html:
	${POD2HTML} rsnapshot | ${GREP} -v 'link rev' > rsnapshot.html
	${RM} -f pod2htmd.*
	${RM} -f pod2htmi.*
	
clean:
	${RM} -rf rsnapshot-${VERSION}/
	${RM} -rf ${DEB_BUILD_DIR}/
	${RM} -f rsnapshot-${VERSION}.tar.gz
	${RM} -f rsnapshot-${VERSION}-1.deb
	${RM} -f rsnapshot.html
	${RM} -f pod2htmd.*
	${RM} -f pod2htmi.*
	
tar:
	${RM} -f rsnapshot-${VERSION}.tar.gz
	
	@# core files
	${MKDIR} rsnapshot-${VERSION}
	${CP} rsnapshot rsnapshot.conf Makefile COPYING INSTALL README TODO ChangeLog rsnapshot-${VERSION}/
	${POD2MAN} rsnapshot > rsnapshot-${VERSION}/rsnapshot.1
	
	@# debian
	${MKDIR} rsnapshot-${VERSION}/DEBIAN/
	${CP} DEBIAN/{control,conffiles} rsnapshot-${VERSION}/DEBIAN/
	
	@# redhat
	${MKDIR} rsnapshot-${VERSION}/redhat/
	${MKDIR} rsnapshot-${VERSION}/redhat/SOURCES/
	${MKDIR} rsnapshot-${VERSION}/redhat/SPECS/
	${CP} redhat/README rsnapshot-${VERSION}/redhat/
	${CP} redhat/SOURCES/rsnapshot.patch rsnapshot-${VERSION}/redhat/SOURCES/
	${CP} redhat/SPECS/rsnapshot.spec rsnapshot-${VERSION}/redhat/SPECS/
	
	@# utils
	${MKDIR} rsnapshot-${VERSION}/utils/
	${CP} utils/rsnaptar rsnapshot-${VERSION}/utils/
	
	@# change ownership to root (or current user), and delete build dir
	${CHOWN} -R ${INSTALL_UID}:${INSTALL_GID} rsnapshot-${VERSION}/
	${GNU_TAR} czf rsnapshot-${VERSION}.tar.gz rsnapshot-${VERSION}/
	${RM} -rf rsnapshot-${VERSION}/
	
debian:
	${MKDIR} -p ${DEB_BUILD_DIR}/{DEBIAN,usr/bin,etc,usr/share/man/man1}
	${CP} DEBIAN/{control,conffiles} ${DEB_BUILD_DIR}/DEBIAN/
	
	${CAT} rsnapshot | ${SED} 's/\/usr\/local\/bin/\/usr\/bin/g' > ${DEB_BUILD_DIR}/usr/bin/rsnapshot
	${CHMOD} 755 ${DEB_BUILD_DIR}/usr/bin/rsnapshot
	
	${POD2MAN} ${DEB_BUILD_DIR}/usr/bin/rsnapshot | gzip -9c > ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	${CHMOD} 644 ${DEB_BUILD_DIR}/usr/share/man/man1/rsnapshot.1.gz
	
	${CAT} rsnapshot.conf | ${SED} 's/#cmd_cp/cmd_cp/' > ${DEB_BUILD_DIR}/etc/rsnapshot.conf
	${CP} ${DEB_BUILD_DIR}/etc/rsnapshot.conf ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	${CHMOD} 600 ${DEB_BUILD_DIR}/etc/rsnapshot.conf
	${CHMOD} 644 ${DEB_BUILD_DIR}/etc/rsnapshot.conf.default
	
	${CHOWN} -R ${INSTALL_UID}:${INSTALL_GID} ${DEB_BUILD_DIR}/
	${DPKG} -b ${DEB_BUILD_DIR}/ rsnapshot-${VERSION}-1.deb
	${RM} -rf ${DEB_BUILD_DIR}/
	
# workaround for Mac OS X, possibly others with case insensitive filenames
# this prevents make from looking at "INSTALL" instead of this target
install: install-all

install-all:
	${INSTALL} -d ${BIN_DIR}/
	${INSTALL} -d ${MAN_DIR}/man1/
	${INSTALL} -d ${SYSCONF_DIR}/
	${INSTALL} -m 755 -o ${INSTALL_UID} -g ${INSTALL_GID} rsnapshot ${BIN_DIR}/rsnapshot
	${INSTALL} -m 644 -o ${INSTALL_UID} -g ${INSTALL_GID} rsnapshot.conf ${SYSCONF_DIR}/rsnapshot.conf.default
	${INSTALL} -m 644 -o ${INSTALL_UID} -g ${INSTALL_GID} rsnapshot.1 ${MAN_DIR}/man1/rsnapshot.1
	${RM} -f ${MAN_DIR}/man1/rsnapshot.1.gz
	@echo
	@echo "---------------------------------------------------------------------"
	@echo "Example config file installed in ${SYSCONF_DIR}/rsnapshot.conf.default."
	@echo "Copy this file to ${SYSCONF_DIR}/rsnapshot.conf, and modify it for your system."
	@echo "---------------------------------------------------------------------"
	@echo
	
uninstall:
	${RM} -f ${BIN_DIR}/rsnapshot
	${RM} -f ${MAN_DIR}/man1/rsnapshot.1
	${RM} -f ${MAN_DIR}/man1/rsnapshot.1.gz
	${RM} -f ${SYSCONF_DIR}/rsnapshot.conf.default
	@echo
	@echo "Leaving /etc/rsnapshot.conf"
	@echo
