SHELL := /bin/bash
SCRIPTS := skills/claude-egress-guard/scripts
SHELLCHECK ?= shellcheck
SHELLCHECK_FLAGS ?= -x -S warning

.PHONY: help lint test scan check install skill

help:
	@printf '%s\n' \
		'make check   shellcheck + self-tests + leak scan (what CI runs)' \
		'make lint    shellcheck on every script' \
		'make test    42 sandboxed assertions, no root and no network' \
		'make scan    privacy/secret scan' \
		'make skill   copy the skill into ~/.hermes/skills'

lint:
	$(SHELLCHECK) $(SHELLCHECK_FLAGS) install.sh $(wildcard $(SCRIPTS)/*)

test:
	@bash $(SCRIPTS)/selftest.sh

scan:
	@python3 tools/leak-scan.py

check: lint test scan

install:
	@sudo ./install.sh --help >/dev/null && echo 'run: sudo ./install.sh --proxy URL --exit-ip ADDR'

skill:
	@./install.sh --skill-only --dest "$${DEST:-$$HOME/.hermes/skills}"
