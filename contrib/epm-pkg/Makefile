# -*- mode: makefile; -*-
# contrib/epm-pkg/Makefile
# Build packages with epm program.
# All the config files are in: contrib/epm-pkg/

# --------------------
# Macros
SHELL=/bin/bash
mRsyncOpt=-azP
mPrefix=dist/usr/local
mShare=$(mPrefix)/share/doc/rsnapshot

include ver.mak

# --------------------
# Manual Targets

# 1
help :
	@echo -e "\nInitialize"
	@echo -e '\tmake config\n'
	@echo -e "Build the pseudo root dist/"
	@echo -e "\tmake build\n"
	@echo -e "Create the package. Put it in pkg/"
	@echo -e "\tmake package"

# 2
config : check-deps ../../configure ver.mak
	if [ "$$(whoami)" = 'root' ]; then exit 1; fi
	@echo -e '\nNow run "make build"'

# 3
build ../../dist/usr/local/bin/rsnapshot : ../../configure ../../dist ver.env
	if [ "$$(whoami)" = 'root' ]; then exit 1; fi
	-rm -rf ../../dist/*
	cd ../..; make
	cd ../..; make install
	cd ../..; make html
	-cd ../..; mkdir -p $(mShare)
	cd ../..; cp -r docs/* $(mShare)
	cd ../..; cp COPYING $(mShare)/LICENSE
	cd ../..; cp README.md $(mShare)
	cd ../..; cp rsnapshot.html $(mShare)
	grep PRETTY_NAME /etc/lsb-release >../../$(mShare)/build-os
	uname -a >>../../$(mShare)/build-os
	find ../../dist -type d -exec chmod a+rx {} \;
	find ../../dist -type f -exec chmod a+r {} \;
	cd ../..; mkepmlist -u root -g root --prefix / dist | patch-epm-list -f ./contrib/epm-pkg/epm.patch >contrib/epm-pkg/epm.list
	@echo -e '\nNow run "make test"'

# 4
test :
	cd ../..; make test
	@echo -e '\nIf OK run "sudo make package"'

# 5
package : ../../dist/usr/local/bin/rsnapshot ../../pkg ver.epm
	if [ "$$(whoami)" != 'root' ]; then exit 1; fi
	-rm -f ../../pkg/*
	cd ../..; epm -v -f native --output-dir pkg $(ProdName) contrib/epm-pkg/ver.epm
	cd ../..; epm -v -f portable --output-dir pkg -m $(ProdOSDist)-$(ProdArch) $(ProdName) contrib/epm-pkg/ver.epm
	chown -R $$SUDO_USER:$$SUDO_USER ../../*
	@echo -e '\nIf OK run "make release"'

# 6
release : save ver.env
	if [ "$$(whoami)" = 'root' ]; then exit 1; fi
	+. ./ver.env; echo ssh $$ProdRelServer mkdir -p $$ProdRelDir/$$ProdOS
	. ./ver.env; ssh $$ProdRelServer mkdir -p $$ProdRelDir/$$ProdOS
	+. ./ver.env; echo rsync -P ../../pkg/* $$ProdRelServer:$$ProdRelDir/$$ProdOS
	. ./ver.env; rsync -P ../../pkg/* $$ProdRelServer:$$ProdRelDir/$$ProdOS

# 7
save :
	if [ "$$(whoami)" = 'root' ]; then exit 1; fi
	git pull origin develop
	-git commit -am Updated
	-git push origin develop
	@echo -e '\nIf done type "make dist-clean"'

# 8
dist-clean : clean
	-cd ../..; make clean
	-cd ../..; rm -rf dist pkg configure rsnapshot.html
	-rm  epm.list ver.mak ver.env ver.epm

clean :
	-find . -type f -name '*~' -exec rm {} \;

# --------------------
# Rules

check-deps :
	command -v aclocal >/dev/null
	command -v autoreconf >/dev/null
	command -v epm >/dev/null
	command -v git >/dev/null
	command -v git >/dev/null
	command -v mkepmlist >/dev/null
	command -v mkver.pl >/dev/null
	command -v patch-epm-list >/dev/null
	command -v perl >/dev/null
	command -v rsync >/dev/null

../../configure : ../../autogen.sh
	cd ../..; ./autogen.sh
	cd ../..; ./configure --prefix=$$PWD/$(mPrefix)

../../dist ../../pkg :
	-mkdir $@

ver.mak ver.env ver.epm : ver.sh
	export RELEASE=1; mkver.pl -e 'mak env epm' -d $?
