# Local validation helpers. The real build and boot tests run in GitHub Actions.
SHELL := /bin/bash

.PHONY: check check-yaml check-json check-shell check-actions check-containerfile clean

check: check-yaml check-json check-shell check-actions check-containerfile

check-yaml:
	@python3 tools/check_workflows.py

check-json:
	@python3 -c 'import json; json.load(open("desktop/waybar/config")); print("OK   desktop/waybar/config")'

check-shell:
	@set -e; \
	for f in scripts/*; do \
	  [ -f "$$f" ] || continue; \
	  bash -n "$$f"; \
	  echo "OK   $$f"; \
	done

check-actions:
	@if command -v actionlint >/dev/null 2>&1; then \
	  actionlint; \
	else \
	  echo "SKIP actionlint (not installed)"; \
	fi

check-containerfile:
	@if command -v hadolint >/dev/null 2>&1; then \
	  hadolint Containerfile .github/iso/Containerfile; \
	else \
	  echo "SKIP hadolint (not installed)"; \
	fi

clean:
	rm -rf output artifacts
