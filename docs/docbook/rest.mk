RHFLAGS = --no-toc-backlinks \
          # --link-stylesheet \
	  # --stylesheet=http://twb.ath.cx/share/article.css \
	  # --trim-footnote-reference-space

RLFLAGS = --output-encoding=utf8:strict \
	  --use-latex-toc \
	  --table-style=booktabs \
#	  --hyperlink-color=0 \
#	  --documentclass=book

.txt.html:
	rst2html $(RHFLAGS) $< $@
.txt.tex:
	rst2latex $(RLFLAGS) $< $@
.tex.pdf:
	rubber --inplace --pdf $*
	rubber --inplace --clean $*

.SUFFIXES: .txt .html .tex .pdf

none:
all: $(patsubst %.txt,%.html,$(wildcard *.txt))
all: $(patsubst %.txt,%.pdf,$(wildcard *.txt))

clean:
	bash -c 'rm -f *.{aux,log,out}'

distclean: clean
	bash -c 'rm -f *.{html,pdf}'

.PHONY: none all clean distclean
