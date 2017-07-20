# Build OVM App Bundles (Python code with a statically-linked CPython
# interpreter.)
#
# We can also build a tarball that allows the end user to build an app bundle.
# They need GNU Make, bash, and a C compiler.  (And xargs, chmod, etc.)
#
# Tarball layout (see build/compile.sh for details):
#
# oil.tar/
#   configure
#   install
#   Makefile
#   _build/                 # Intermediate files
#     oil/                  # The app name
#       bytecode.zip        # Arch-independent
#       main_name.c
#       module_init.c       # Python module initializer
#       c-module-srcs.txt   # List of Modules/ etc.
#   native/                 # App-specific modules
#     libc.c
#   build/
#     static-c-modules.txt  # From Python interpreter
#     compile.sh ...
#     detect-cc.c ...
#   Python-2.7.13/
#     pyconfig.h            # A frozen version
#     Python/
#     Objects/
#     Modules/
#     Include/
#
#
# Intermediate layout:
#
# _build/
#   cpython-full/           # Full CPython build, for dynamically
#                           # discovering Python/C dependencies
#   c-module-toc.txt        # What files each module is in
#   oil/                    # App-specific dir
#     all-deps-c.txt        # App deps plus CPython platform deps
#     app-deps-c.txt
#     app-deps-py.txt
#     bytecode.zip
#     c-module-srcs.txt
#     main_name.c
#     module_init.c
#     ovm.d                 # Make fragment
#     ovm, ovm-dbg          # OVM executables (without bytecode)
# _release/
#   oil.tar                 # See tarball layout above
# _bin/                     # Concatenated App Bundles
#   oil.ovm
#   oil.ovm-dbg
#   hello.ovm
#   hello.ovm-dbg

# Needed for rules with '> $@'.  Does this always work?
.DELETE_ON_ERROR:

# Intermediate targets aren't automatically deleted.
.SECONDARY:

# Don't use the built-in rules database.  This makes the 'make -d' output
# easier to read.
.SUFFIXES:

# Do this before every build.  There should be a nicer way of handling
# directories but I don't know it.
$(shell mkdir -p _bin _release _build/hello _build/oil)

ACTIONS_SH := build/actions.sh
COMPILE_SH := build/compile.sh

# For faster tesing of builds
default: _bin/oil.ovm-dbg

# What the end user should build when they type 'make'.
#default: _bin/oil.ovm

# Debug bundles and release tarballs.
all: \
	_bin/hello.ovm _bin/oil.ovm \
	_bin/hello.ovm-dbg _bin/oil.ovm-dbg \
	_release/hello.tar _release/oil.tar

clean:
	rm -r -f _build/hello _build/oil
	rm -f _bin/oil.* _bin/hello.* _release/*.tar \
		_build/runpy-deps-*.txt _build/c-module-toc.txt
	$(ACTIONS_SH) clean-pyc

.PHONY: default all clean install

# NOTES:
# - Manually rm this file to generate a new build timestamp.
# - This messes up reproducible builds.
# - It's not marked .PHONY because that would mess up the end user build.
#   bytecode.zip should NOT be built by the user.
_build/release-date.txt:
	$(ACTIONS_SH) write-release-date

# The Makesfiles generated by autoconf don't call configure, but Linux/toybox
# config system does.  This can be overridden.
_build/detected-config.sh:
	./configure

# .PHONY alias for compatibility
install:
	@./install

# What files correspond to each C module.
# TODO:
# - Where to put -l z?  (Done in Modules/Setup.dist)
_build/c-module-toc.txt: build/c_module_toc.py
	$(ACTIONS_SH) c-module-toc > $@

# Python and C dependencies of runpy.
# NOTE: This is done with a pattern rule because of the "multiple outputs"
# problem in Make.
_build/runpy-deps-%.txt: build/runpy_deps.py
	$(ACTIONS_SH) runpy-deps _build

#
# Hello App.  Everything below here is app-specific.
#

# C module dependencies
-include _build/hello/ovm.d

# What Python module to run.
_build/hello/main_name.c:
	$(ACTIONS_SH) main-name hello hello.ovm > $@

# Dependencies calculated by importing main.  The guard is because ovm.d
# depends on it.  Is that correct?  We'll skip it before 'make dirs'.
_build/hello/app-deps-%.txt: $(HELLO_SRCS) _build/detected-config.sh \
	                           build/app_deps.py
	test -d _build/hello && \
		$(ACTIONS_SH) app-deps hello build/testdata hello

# NOTE: We could use src/dest paths pattern instead of _build/app?
#
# TODO:
# - Deps need to be better.  Depend on .pyc and .py.    I guess
#   app-deps hello will compile the .pyc files.  Don't need a separate action.
#   %.pyc : %py
_build/hello/bytecode.zip: $(HELLO_SRCS) \
                           build/testdata/hello-version.txt \
                           _build/release-date.txt \
                           _build/hello/app-deps-py.txt \
                           _build/runpy-deps-py.txt \
                           build/testdata/hello-manifest.txt
	{ echo 'build/testdata/hello-version.txt hello-version.txt'; \
	  echo '_build/release-date.txt release-date.txt'; \
	  cat build/testdata/hello-manifest.txt \
	      _build/hello/app-deps-py.txt \
	      _build/runpy-deps-py.txt; \
	} | build/make_zip.py $@

#
# Oil
#

# C module dependencies
-include _build/oil/ovm.d

_build/oil/main_name.c:
	$(ACTIONS_SH) main-name bin.oil oil.ovm > $@

# Dependencies calculated by importing main.
# NOTE: The list of files is used both to compile and to make a tarball.
# - For compiling, we should respect _HAVE_READLINE in detected_config
# - For the tarball, we should ALWAYS include readline.
_build/oil/app-deps-%.txt: _build/detected-config.sh build/app_deps.py
	test -d _build/oil && \
		$(ACTIONS_SH) app-deps oil ~/git/oil bin.oil

# TODO: Need $(OIL_SRCS) here?
# NOTES:
# - _build/osh_help.py is a minor hack to depend on the entire
# _build/osh-quick-ref dir, since they both get generated by the same build
# action.
# - release-date is at a different location on purpose, so we don't show it in
#   dev mode.
_build/oil/bytecode.zip: oil-version.txt \
                         _build/release-date.txt \
                         _build/oil/app-deps-py.txt \
                         _build/runpy-deps-py.txt \
                         build/oil-manifest.txt \
                         _build/osh_help.py \
                         doc/osh-quick-ref-toc.txt
	{ echo '_build/release-date.txt release-date.txt'; \
  	$(ACTIONS_SH) files-manifest oil-version.txt \
	                             doc/osh-quick-ref-toc.txt; \
	  cat build/oil-manifest.txt \
	      _build/oil/app-deps-py.txt \
	      _build/runpy-deps-py.txt; \
	  $(ACTIONS_SH) quick-ref-manifest _build/osh-quick-ref; \
	} | build/make_zip.py $@ 

#
# App-Independent Pattern Rules.
#

# Regenerate dependencies.  But only if we made the app dirs.
_build/%/ovm.d: _build/%/app-deps-c.txt
	$(ACTIONS_SH) make-dotd $* $^ > $@

# Source paths of all C modules the app depends on.  For the tarball.
# A trick: remove the first dep to form the lists.  You can't just use $^
# because './c_module_srcs.py' is rewritten to 'c_module_srcs.py'.
_build/%/c-module-srcs.txt: \
	build/c_module_srcs.py _build/c-module-toc.txt _build/%/app-deps-c.txt
	build/c_module_srcs.py $(filter-out $<,$^) > $@

_build/%/all-deps-c.txt: build/static-c-modules.txt _build/%/app-deps-c.txt
	$(ACTIONS_SH) join-modules $^ > $@

PY27 := Python-2.7.13

# Per-app extension module initialization.
_build/%/module_init.c: $(PY27)/Modules/config.c.in _build/%/all-deps-c.txt
	# NOTE: Using xargs < input.txt style because it will fail if input.txt
	# doesn't exist!  'cat' errors will be swallowed.
	xargs $(ACTIONS_SH) gen-module-init < _build/$*/all-deps-c.txt > $@


# 
# Tarballs
#
# Contain Makefile and associated shell scripts, discovered .c and .py deps,
# app source.

_release/%.tar: _build/%/bytecode.zip \
                _build/%/module_init.c \
                _build/%/main_name.c \
                _build/%/c-module-srcs.txt
	$(COMPILE_SH) make-tar $* $@

#
# Native Builds
#

# Release build.
# This depends on the static modules
_build/%/ovm: _build/%/module_init.c _build/%/main_name.c \
              _build/%/c-module-srcs.txt $(COMPILE_SH)
	$(COMPILE_SH) build-opt $@ $(filter-out $(COMPILE_SH),$^)

# Fast build, with symbols for debugging.
_build/%/ovm-dbg: _build/%/module_init.c _build/%/main_name.c \
                  _build/%/c-module-srcs.txt $(COMPILE_SH)
	$(COMPILE_SH) build-dbg $@ $(filter-out $(COMPILE_SH),$^)

# Coverage, for paring down the files that we build.
# TODO: Hook this up.
_build/%/ovm-cov: _build/%/module_init.c _build/%/main_name.c \
                  _build/%/c-module-srcs.txt $(COMPILE_SH)
	$(COMPILE_SH) build $@ $(filter-out $(COMPILE_SH),$^)

# Make bundles quickly.
_bin/%.ovm-dbg: _build/%/ovm-dbg _build/%/bytecode.zip
	cat $^ > $@
	chmod +x $@

_bin/%.ovm: _build/%/ovm _build/%/bytecode.zip
	cat $^ > $@
	chmod +x $@

# For debugging
print-%:
	@echo $*=$($*)
