default:
	@echo "it's written in perl, just type make install"
	
man:
	pod2man rsnapshot > rsnapshot.1
	
html:
	pod2html rsnapshot > rsnapshot.html
	rm -f pod2htmd.x~~
	rm -f pod2htmi.x~~
	
clean:
	rm -f rsnapshot.1
	rm -rf rsnapshot-0.9.1/
	rm -f rsnapshot-0.9.1.tar.gz
	rm -f rsnapshot-0.9.1-1.deb
	rm -rf rsnapshot_dpkg
	
tar:
	make man
	mkdir rsnapshot-0.9.1
	rm -f rsnapshot-0.9.1.tar.gz
	cp rsnapshot rsnapshot.conf Makefile rsnapshot.1 GPL INSTALL README TODO rsnapshot-0.9.1/
	chown -R 0:0 rsnapshot-0.9.1/
	tar czf rsnapshot-0.9.1.tar.gz rsnapshot-0.9.1/
	rm -rf rsnapshot-0.9.1/
	rm -f rsnapshot.1
	
dpkg:
	mkdir -p rsnapshot_dpkg/{DEBIAN,usr/bin,etc,usr/share/man/man1}
	cp DEBIAN/{control,conffiles} rsnapshot_dpkg/DEBIAN/
	cat rsnapshot | sed 's/\/usr\/local\/bin/\/usr\/bin/g' > rsnapshot_dpkg/usr/bin/rsnapshot
	pod2man rsnapshot_dpkg/usr/bin/rsnapshot | gzip -9c > rsnapshot_dpkg/usr/share/man/man1/rsnapshot.1.gz
	cp rsnapshot.conf rsnapshot_dpkg/etc/
	chmod 600 rsnapshot_dpkg/etc/rsnapshot.conf
	chmod 755 rsnapshot_dpkg/usr/bin/rsnapshot
	chmod 644 rsnapshot_dpkg/usr/share/man/man1/rsnapshot.1.gz
	chown -R root:root rsnapshot_dpkg/
	dpkg -b rsnapshot_dpkg/ rsnapshot-0.9.1-1.deb
	
install:
	cp -f rsnapshot /usr/local/bin/rsnapshot
	chmod 755 /usr/local/bin/rsnapshot
	chown 0:0 /usr/local/bin/rsnapshot
	
	mkdir -p /usr/local/man/man1/
	cp -f rsnapshot.1 /usr/local/man/man1/rsnapshot.1
	chmod 644 /usr/local/man/man1/rsnapshot.1
	chown 0:0 /usr/local/man/man1/rsnapshot.1
	gzip -9 /usr/local/man/man1/rsnapshot.1
	
	@echo "if you already have a configuration file, you probably want to answer no here"
	cp -i rsnapshot.conf /etc/rsnapshot.conf
	chmod 600 /etc/rsnapshot.conf
	chown 0:0 /etc/rsnapshot.conf
