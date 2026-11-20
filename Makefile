SCRIPTS := install.sh tests/test_install.sh $(wildcard claude/skills/*/scripts/*.sh)

.PHONY: check syntax shellcheck test privacy install

check: syntax shellcheck privacy test

# Every shell script must parse under the bash it runs with (macOS ships 3.2); /usr/bin/python3 is checked where it exists.
syntax:
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	@for py in /usr/bin/python3 python3; do command -v $$py >/dev/null 2>&1 || continue; $$py -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' lib/settings_merge.py || exit 1; done
	@echo "syntax ok"

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck --severity=warning $(SCRIPTS); \
	else echo "shellcheck not installed; skipped (brew or apt install shellcheck)"; fi

# Shared config must not carry personal paths or secrets (README → What never goes in this repo).
privacy:
	@if git grep -nIE '/(Users|home)/[a-z][a-z0-9_-]+/|[A-Za-z]:\\Users\\[^\\]+\\|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|sk-(ant-)?[A-Za-z0-9_-]{20,}|BEGIN [A-Z ]*PRIVATE KEY|[A-Za-z0-9._%+-]+@(gmail|googlemail|yahoo|hotmail|outlook|live|icloud|me|proton|protonmail)\.[a-z]{2,}' \
	  -- . ':!Makefile' ':!tests/'; then echo "privacy: remove the lines above"; exit 1; fi
	@echo "privacy ok"

# install.sh against a throwaway $HOME; never touches your real home directory.
test:
	bash tests/test_install.sh

install:
	./install.sh --with-claude-md
