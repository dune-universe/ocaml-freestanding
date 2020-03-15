.PHONY: all clean install

include Makeconf

ifeq ($(OCAML_GTE_4_08_0),yes)
FREESTANDING_LIBS=build/openlibm/libopenlibm.a \
		  build/ocaml/runtime/libasmrun.a \
		  build/nolibc/libnolibc.a
else ifeq ($(OCAML_4_07_0),yes)
FREESTANDING_LIBS=build/openlibm/libopenlibm.a \
		  build/ocaml/asmrun/libasmrun.a \
		  build/nolibc/libnolibc.a
else
FREESTANDING_LIBS=build/openlibm/libopenlibm.a \
		  build/ocaml/asmrun/libasmrun.a \
		  build/ocaml/otherlibs/libotherlibs.a \
		  build/nolibc/libnolibc.a
endif

all:	$(FREESTANDING_LIBS) ocaml-freestanding.pc flags/libs flags/cflags flags/ld flags/libdir flags/ldflags

Makeconf:
	./configure.sh

TOP=$(abspath .)
FREESTANDING_CFLAGS+=-isystem $(TOP)/nolibc/include

build/openlibm/Makefile:
	mkdir -p build/openlibm
	cp -r openlibm build

build/openlibm/libopenlibm.a: build/openlibm/Makefile
	$(MAKE) -C build/openlibm "CFLAGS=$(FREESTANDING_CFLAGS)" libopenlibm.a

build/ocaml/Makefile:
	mkdir -p build
	cp -r `ocamlfind query ocaml-src` build/ocaml

ifeq ($(OCAML_GTE_4_08_0),yes)
# OCaml >= 4.08.0 uses an autotools-based build system. In this case we
# convince it to think it's using the Solo5 compiler as a cross compiler, and
# let the build system do its work with as little additional changes on our
# side as possible.
#
# Notes:
#
# - CPPFLAGS must be set for configure as well as CC, otherwise it complains
#   about headers due to differences of opinion between the preprocessor and
#   compiler.
# - ARCH must be overridden manually in Makefile.config due to the use of
#   hardcoded combinations in the OCaml configure.
# - HAS_XXX must be defined manually since our invocation of configure cannot
#   link against nolibc (which would need to produce complete Solo5 binaries).
# - We override OCAML_OS_TYPE since configure just hardcodes it to "Unix".
OCAML_CFLAGS=$(FREESTANDING_CFLAGS) -I$(TOP)/build/openlibm/include -I$(TOP)/build/openlibm/src

build/ocaml/Makefile.config: build/ocaml/Makefile
	cd build/ocaml && \
	    CC="cc $(OCAML_CFLAGS) -nostdlib" \
	    AS="as" \
	    ASPP="cc $(OCAML_CFLAGS) -c" \
	    LD="ld" \
	    CPPFLAGS="$(OCAML_CFLAGS)" \
	    ./configure --host=$(BUILD_ARCH)-unknown-none
	echo "ARCH=$(OCAML_BUILD_ARCH)" >> build/ocaml/Makefile.config
	echo '#define HAS_GETTIMEOFDAY' >> build/ocaml/runtime/caml/s.h
	echo '#define HAS_SECURE_GETENV' >> build/ocaml/runtime/caml/s.h
	echo '#define HAS_TIMES' >> build/ocaml/runtime/caml/s.h
	echo '#undef OCAML_OS_TYPE' >> build/ocaml/runtime/caml/s.h
	echo '#define OCAML_OS_TYPE "None"' >> build/ocaml/runtime/caml/s.h

build/ocaml/runtime/caml/version.h: build/ocaml/Makefile.config
	build/ocaml/tools/make-version-header.sh > $@

build/ocaml/runtime/libasmrun.a: build/ocaml/Makefile.config build/openlibm/Makefile build/ocaml/runtime/caml/version.h
	$(MAKE) -C build/ocaml/runtime libasmrun.a

else
# OCaml < 4.08.0 use the old build system, so just do what used to work here.
OCAML_CFLAGS=-O2 -fno-strict-aliasing -fwrapv -Wall -USYS_linux -DHAS_UNISTD $(FREESTANDING_CFLAGS)
OCAML_CFLAGS+=-I$(TOP)/build/openlibm/include -I$(TOP)/build/openlibm/src

build/ocaml/config/Makefile: build/ocaml/Makefile
	cp config/s.h build/ocaml/byterun/caml/s.h
	cp config/m.$(OCAML_BUILD_ARCH).h build/ocaml/byterun/caml/m.h
	cp config/Makefile.$(BUILD_OS).$(OCAML_BUILD_ARCH) build/ocaml/config/Makefile

build/ocaml/byterun/caml/version.h: build/ocaml/config/Makefile
	build/ocaml/tools/make-version-header.sh > $@

build/ocaml/asmrun/libasmrun.a: build/ocaml/config/Makefile build/openlibm/Makefile build/ocaml/byterun/caml/version.h
	$(MAKE) -C build/ocaml/asmrun \
	    CFLAGS="$(OCAML_CFLAGS)" \
	    libasmrun.a
endif

build/ocaml/otherlibs/libotherlibs.a: build/ocaml/config/Makefile
	$(MAKE) -C build/ocaml/otherlibs/bigarray \
	    OUTPUTOBJ=-o \
	    CFLAGS="$(FREESTANDING_CFLAGS) -DIN_OCAML_BIGARRAY -I../../byterun" \
	    bigarray_stubs.o mmap_ba.o mmap.o
	$(AR) rcs $@ \
	    build/ocaml/otherlibs/bigarray/bigarray_stubs.o \
	    build/ocaml/otherlibs/bigarray/mmap_ba.o \
	    build/ocaml/otherlibs/bigarray/mmap.o

build/nolibc/Makefile:
	mkdir -p build
	cp -r nolibc build
ifeq ($(OCAML_4_07_0),yes)
	echo '/* automatically added by configure.sh */' >> build/nolibc/stubs.c
	echo 'STUB_ABORT(caml_ba_map_file);' >> build/nolibc/stubs.c
endif

NOLIBC_CFLAGS=$(FREESTANDING_CFLAGS) -isystem $(TOP)/build/openlibm/src -isystem $(TOP)/build/openlibm/include
build/nolibc/libnolibc.a: build/nolibc/Makefile build/openlibm/Makefile
	$(MAKE) -C build/nolibc \
	    "FREESTANDING_CFLAGS=$(NOLIBC_CFLAGS)" \
	    "SYSDEP_OBJS=$(NOLIBC_SYSDEP_OBJS)"

ocaml-freestanding.pc: ocaml-freestanding.pc.in Makeconf
	sed -e 's!@@PKG_CONFIG_DEPS@@!$(PKG_CONFIG_DEPS)!' \
	    -e 's!@@PKG_CONFIG_EXTRA_LIBS@@!$(PKG_CONFIG_EXTRA_LIBS)!' \
	    ocaml-freestanding.pc.in > $@

flags/libs.tmp: flags/libs.tmp.in
	opam config subst $@

flags/libs: flags/libs.tmp Makeconf
	env PKG_CONFIG_PATH="$(shell opam config var prefix)/lib/pkgconfig" \
	    pkg-config $(PKG_CONFIG_DEPS) --libs >> $<
	awk -v RS= -- '{ \
	    sub("@@PKG_CONFIG_EXTRA_LIBS@@", "$(PKG_CONFIG_EXTRA_LIBS)", $$0); \
	    print "(", $$0, ")" \
	    }' $< >$@

flags/cflags.tmp: flags/cflags.tmp.in
	opam config subst $@

flags/cflags: flags/cflags.tmp Makeconf
	env PKG_CONFIG_PATH="$(shell opam config var prefix)/lib/pkgconfig" \
	    pkg-config $(PKG_CONFIG_DEPS) --cflags >> $<
	awk -v RS= -- '{ \
	    print "(", $$0, ")" \
	    }' $< >$@

flags/libdir: Makeconf
	env PKG_CONFIG_PATH="$(shell opam config var prefix)/lib/pkgconfig" \
	    pkg-config $(PKG_CONFIG_DEPS) --variable=libdir >> $@
	sed -i -e '1 s/$$/\/src/' $@

flags/ld: Makeconf
	env PKG_CONFIG_PATH="$(shell opam config var prefix)/lib/pkgconfig" \
	    pkg-config $(PKG_CONFIG_DEPS) --variable=ld >> $@
	sed -ni 's/\n/ /g' "$@"
	if [ ! -s $@ ]; then echo "ld" >> $@; fi

flags/ldflags: Makeconf
	env PKG_CONFIG_PATH="$(shell opam config var prefix)/lib/pkgconfig" \
	    pkg-config $(PKG_CONFIG_DEPS) --variable=ldflags >> $@
	sed -i "$@" -re 's/(\ )+/\n/g'


install: all
	./install.sh

uninstall:
	./uninstall.sh

clean:
	rm -rf build config Makeconf ocaml-freestanding.pc
	rm -rf flags/libs flags/libs.tmp
	rm -rf flags/cflags flags/cflags.tmp
