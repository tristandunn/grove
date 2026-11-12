BATS ?= test/bats/bin/bats

# bats waits a full second whenever every job slot is busy, so give it plenty of
# slots. The tests are short and spend most of their time starting processes.
BATS_JOBS ?= 64

# Run the tests within each file in parallel, but the files one at a time. This
# needs no GNU parallel, and running the files at the same time as well was
# slower on 4 CPUs, as each extra file adds bats overhead.
BATS_PARALLEL_FLAGS ?= --jobs $(BATS_JOBS) --no-parallelize-across-files

install:
	mkdir -p $(HOME)/.local/bin
	ln -sfnv $(CURDIR)/bin/grove $(HOME)/.local/bin/grove

uninstall:
	rm -f $(HOME)/.local/bin/grove

test:
	$(BATS) $(BATS_PARALLEL_FLAGS) $(BATS_FLAGS) test/*.bats

# Run a single file, for example `make test-rename` runs test/rename.bats.
test-%:
	$(BATS) $(BATS_PARALLEL_FLAGS) $(BATS_FLAGS) test/$*.bats

.PHONY: install uninstall test
