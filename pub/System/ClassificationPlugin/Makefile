FOSWIKI_ROOT?=~/foswiki/trunk/core
TARGET=\
  build \
  build/hierarchy.js \
  build/tageditor.js \
  build/styles.css

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

build:
	@mkdir build

build/%.css: src/%.css
	@echo generating $@; $(CAT) $^ | $(CSSMIN) $(CSSMIN_ARGS) > $@

build/%.js: src/%.js
	@echo generating $@; $(JSMIN) $^ > $@


clean:
	rm -f build/*
