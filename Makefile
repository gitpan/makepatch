VERSION	= 1.10
BINDIR	= /usr/local/bin
MANEXT	= 1
MANDIR	= /usr/local/man/man$(MANEXT)

INSTALL_PROGRAM	= install -c -m 0555
INSTALL_DATA	= install -c -m 0444

all:
	@echo "Edit the Makefile and issue"
	@echo "'make install' to install makepatch"

install:
	$(INSTALL_PROGRAM) makepatch.pl $(BINDIR)/makepatch
	$(INSTALL_DATA) makepatch.man $(MANDIR)/makepatch.$(MANEXT)

dist:
	ln -s . makepatch-$(VERSION)
	makepatch -quiet -filelist -prefix makepatch-$(VERSION)/ MANIFEST |\
		gtar -Zcvf makepatch-$(VERSION).tar.Z -T -
	rm -f makepatch-$(VERSION)

shar:
	makepatch -quiet -filelist -nosort MANIFEST |\
		shar -f -F -S > makepatch-$(VERSION).shar
