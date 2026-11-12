BATS ?= test/bats/bin/bats

install:
	mkdir -p $(HOME)/.local/bin
	ln -sfnv $(CURDIR)/bin/grove $(HOME)/.local/bin/grove

uninstall:
	rm -f $(HOME)/.local/bin/grove

test:
	$(BATS) $(BATS_FLAGS) test/*.bats

# Run a single file, for example `make test-rename` runs test/rename.bats.
test-%:
	$(BATS) $(BATS_FLAGS) test/$*.bats

.PHONY: install uninstall test
