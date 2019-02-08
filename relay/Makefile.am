AUTOMAKE_OPTIONS = foreign

ACLOCAL_AMFLAGS = -I m4

AM_CPPFLAGS = $(DEFAULT_CPPFLAGS)
AM_CFLAGS = $(DEFAULT_CFLAGS)

EXTRA_DIST = version.sh configure.ac $(srcdir)/m4 config.rpath

MAINTAINERCLEANFILES = autom4te.cache aclocal.m4 compile config.* configure \
 depcomp install-sh ltmain.sh Makefile.in missing $(PACKAGE)-*.gz

maintainer-clean-local:
	rm -rf m4

bin_PROGRAMS = tci-relay

tci_relay_DEPENDENCIES = Makefile
tci_relay_SOURCES = \
 admin.c admin.h \
 checkout.c checkout.h \
 list.c list.h \
 log.c log.h \
 main.c \
 msg.h \
 relay.c relay.h \
 resource.c resource.h \
 timer.c timer.h \
 util.c util.h

.PHONY: help

help:
	@echo "Targets:"
	@echo "  make install"
	@echo "  make dist"
	@echo "  make distcheck"
	@echo "  make distclean"
	@echo "  make maintainer-clean"
