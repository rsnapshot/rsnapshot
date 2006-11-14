x := rsnapshot-HOWTO.en
xsldir := /usr/share/xml/docbook/stylesheet/nwalsh

## dependencies
all: $x.xhtml
all: $x.pdf
all: $x.info

## xsltproc / fop rules
%.xhtml: %.xml
	xsltproc $(xsldir)/xhtml/docbook.xsl '$<' >'$@'
%.fo: %.xml
	xsltproc $(xsldir)/fo/docbook.xsl '$<' >'$@'
%.pdf: %.fo
	fop -fo '$<' -pdf '$@'
%.txml: %.xml
	db2x_xsltproc -s texi '$<' -o '$@'
%.texi: %.txml
	db2x_texixml '$<'
%.info: %.texi
	makeinfo '$<'

### phony rules
clean:
	rm -f *~
	bash -c 'set -ex && rm -f *.{aux,cp,fn,ky,log,pg,toc,tp,vr,refs,txml,fo}'
distclean: clean
	bash -c 'set -ex && rm -f *.{texi,info,pdf,xhtml,html}'
test:
	xmllint --xinclude --valid --postvalid --noout $x.xml
.PHONY: all clean distclean test
