.DEFAULT_GOAL := check
.DELETE_ON_ERROR:
.SUFFIXES:

MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

SHELL := /usr/bin/bash
.SHELLFLAGS := -euo pipefail -c

TOFU ?= tofu
SHELLCHECK ?= shellcheck
CRSTLINT ?= crstlint
RSTCHECK ?= rstcheck
RST2HTML ?= rst2html
ANSIBLE_LINT ?= ansible-lint
PYTHON ?= python3
TF_PLUGIN_CACHE_DIR ?= $(HOME)/.cache/opentofu/plugin-cache

RST_FILES := $(sort $(wildcard README.rst CHANGELOG.rst 0[1-9]-*/README.rst 10-*/README.rst))
BASH_SCRIPTS := $(sort $(wildcard 0[1-9]-*/scripts/*.bash 10-*/scripts/*.bash))
TOFU_DIRS := $(sort $(patsubst %/main.tf,%,$(shell find . -maxdepth 4 -path '*/tofu/main.tf' -not -path '*/.terraform/*' | sort)))
ANSIBLE_PLAYBOOKS := $(sort $(shell find . -maxdepth 4 -name 'playbook.yaml' -not -path '*/.terraform/*' | sort))

define HYGIENE_PY
import pathlib, re, struct, sys

root = pathlib.Path(".")
errors = []

for mod_dir in sorted(p for p in root.glob("[01][0-9]-*") if p.is_dir()):
    for md in sorted(mod_dir.rglob("*.md")):
        if ".terraform" not in md.parts:
            errors.append(f"Forbidden Markdown in module: {md}")

rst_paths = sorted(
    list(root.glob("README.rst"))
    + list(root.glob("CHANGELOG.rst"))
    + list(root.glob("[01][0-9]-*/README.rst"))
)
for p in rst_paths:
    lines = p.read_text(encoding="utf-8").splitlines()
    in_code = False
    code_indent = 0
    for idx, line in enumerate(lines, 1):
        if re.match(r"^\s*\.\.\s+code-block::", line):
            in_code = True
            code_indent = len(line) - len(line.lstrip(" "))
            continue
        if in_code and line.strip() and (len(line) - len(line.lstrip(" "))) <= code_indent:
            in_code = False
        if "file://" in line:
            errors.append(f"{p}:{idx}: forbidden file:// link")
        if "git checkout 0" in line:
            errors.append(f"{p}:{idx}: nonexistent branch checkout reference")
        if "\u2014" in line:
            errors.append(f"{p}:{idx}: forbidden em-dash")
        if not in_code:
            stripped = re.sub(r"``[^`]+``", "", line)
            stripped = re.sub(r"<https?://[^>]+>|<[^>]+\.[a-z0-9]+/?[^>]*>", "", stripped)
            if " / " in stripped:
                errors.append(f"{p}:{idx}: forbidden spaced forward slash")
            if "(" in stripped or ")" in stripped:
                errors.append(f"{p}:{idx}: parentheses forbidden in RST prose/headings: {line}")

pngs = sorted(root.glob("[01][0-9]-*/assets/*.png"))
for p in pngs:
    data = p.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data) < 24:
        errors.append(f"{p}: not a valid PNG file")
        continue
    w, h = struct.unpack(">II", data[16:24])
    if h == 0 or abs((w / h) - (16.0 / 9.0)) > 0.06:
        errors.append(f"{p}: aspect ratio {w}x{h} is not 16:9")

if errors:
    sys.exit("\n".join(errors))
print(f"Hygiene OK: {len(rst_paths)} RST files, {len(pngs)} PNG assets verified.")
endef
export HYGIENE_PY

.PHONY: all check fmt fmt-check lint-rst lint-bash lint-ansible lint-hygiene validate-tofu verify-clean-state help

all: check

fmt: ## Format OpenTofu manifests and fix RST formatting
	@for dir in $(TOFU_DIRS); do \
		printf 'Formatting OpenTofu in %s\n' "$$dir"; \
		$(TOFU) -chdir="$$dir" fmt -recursive; \
	done
	@if [[ -n "$(RST_FILES)" ]]; then \
		printf 'Formatting RST files...\n'; \
		$(CRSTLINT) -f $(RST_FILES); \
	fi

fmt-check: ## Verify OpenTofu formatting without modifying files
	@for dir in $(TOFU_DIRS); do \
		$(TOFU) -chdir="$$dir" fmt -check -recursive; \
	done

lint-rst: ## Lint all public reStructuredText files with crstlint, rstcheck, and rst2html --strict
	@if [[ -n "$(RST_FILES)" ]]; then \
		$(CRSTLINT) $(RST_FILES); \
		$(RSTCHECK) --report-level warning $(RST_FILES); \
		for f in $(RST_FILES); do \
			$(RST2HTML) --strict "$$f" >/dev/null; \
		done; \
	fi

lint-bash: ## Run bash -n and ShellCheck on all module bootstrap scripts
	@for script in $(BASH_SCRIPTS); do \
		printf 'Checking Bash script %s\n' "$$script"; \
		bash -n "$$script"; \
		$(SHELLCHECK) -s bash "$$script"; \
	done

lint-ansible: ## Run ansible-lint on module playbooks
	@for pb in $(ANSIBLE_PLAYBOOKS); do \
		dir="$${pb%/*}"; \
		file="$${pb##*/}"; \
		printf 'Linting Ansible playbook %s\n' "$$pb"; \
		(cd "$$dir" && $(PYTHON) -c 'import os, subprocess, sys; [os.set_blocking(fd, True) for fd in (0, 1, 2)]; sys.exit(subprocess.call(sys.argv[1:]))' $(ANSIBLE_LINT) "$$file"); \
	done

validate-tofu: ## Initialize cached plugins and validate all OpenTofu modules
	@mkdir -p "$(TF_PLUGIN_CACHE_DIR)"
	@export TF_PLUGIN_CACHE_DIR="$(TF_PLUGIN_CACHE_DIR)"; \
	for dir in $(TOFU_DIRS); do \
		printf 'Validating OpenTofu module %s\n' "$$dir"; \
		if [[ ! -d "$$dir/.terraform" || "$$dir/provider.tf" -nt "$$dir/.terraform" ]]; then \
			$(TOFU) -chdir="$$dir" init -backend=false -input=false -no-color >/dev/null; \
		fi; \
		$(TOFU) -chdir="$$dir" validate -no-color; \
	done

verify-clean-state: ## Fail if any local terraform.tfstate contains active cloud resources
	@$(PYTHON) -c 'import json, pathlib, sys; bad=[]; [bad.append((str(p), len(json.loads(p.read_text(encoding="utf-8")).get("resources", [])))) for p in sorted(pathlib.Path(".").rglob("terraform.tfstate")) if ".terraform" not in p.parts and len(json.loads(p.read_text(encoding="utf-8")).get("resources", [])) > 0]; sys.exit("\n".join(f"Active state in {p}: {n} resources" for p, n in bad)) if bad else print("All terraform.tfstate files are clean (0 resources).")'

lint-hygiene: ## Enforce repository hygiene: no .md in modules, no file:// links, valid PNGs, typography
	@$(PYTHON) -c "$$HYGIENE_PY"

check: fmt-check lint-rst lint-bash lint-ansible lint-hygiene validate-tofu verify-clean-state ## Run all deterministic quality gates

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "%-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
