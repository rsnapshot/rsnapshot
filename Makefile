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
	rm -rf rsnapshot-0.9.0/
	rm -f rsnapshot-0.9.0.tar.gz
	
tar:
	make man
	mkdir rsnapshot-0.9.0
	rm -f rsnapshot-0.9.0.tar.gz
	cp rsnapshot rsnapshot.conf Makefile rsnapshot.1 GPL INSTALL README rsnapshot-0.9.0/
	chown -R 0:0 rsnapshot-0.9.0/
	tar czf rsnapshot-0.9.0.tar.gz rsnapshot-0.9.0/
	rm -rf rsnapshot-0.9.0/
	rm -f rsnapshot.1
	
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
