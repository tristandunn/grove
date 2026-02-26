install:
	mkdir -p $(HOME)/.local/bin
	ln -sfnv $(CURDIR)/bin/grove $(HOME)/.local/bin/grove

uninstall:
	rm -f $(HOME)/.local/bin/grove

.PHONY: install uninstall
