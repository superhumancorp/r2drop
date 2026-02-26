SHELL := /bin/bash

.PHONY: help print-version rust-release fastlane-check testflight release release-patch release-minor release-major

# Pull the first MARKETING_VERSION from the XcodeGen spec (R2Drop target).
CURRENT_MARKETING_VERSION := $(shell awk -F'"' '/MARKETING_VERSION:/ { print $$2; exit }' R2Drop/project.yml)

# Allow callers to override, e.g. `make testflight BUILD_NUMBER=123`.
FASTLANE ?= bundle exec fastlane
VERSION_BUMP ?= patch

help:
	@echo "R2Drop local release automation"
	@echo ""
	@echo "Targets:"
	@echo "  make testflight        Build Rust (release) + upload to TestFlight"
	@echo "  make release           Build Rust (release) + submit App Store build (auto patch bump)"
	@echo "  make release-minor     Same as release with minor bump"
	@echo "  make release-major     Same as release with major bump"
	@echo "  make print-version     Show current/next version preview"
	@echo ""
	@echo "Overrides:"
	@echo "  BUILD_NUMBER=<n>       Override auto build number (default UTC timestamp)"
	@echo "  MARKETING_VERSION=x.y.z Override release/testflight version"
	@echo "  VERSION_BUMP=patch|minor|major (used by make release)"
	@echo "  XCODE_SCHEME='R2Drop Production' (passed through to Fastlane)"
	@echo ""
	@echo "Notes:"
	@echo "  - make testflight keeps MARKETING_VERSION at the current project version by default"
	@echo "  - make release auto-bumps MARKETING_VERSION (patch by default) without editing files"

print-version:
	@set -euo pipefail; \
	current="$(CURRENT_MARKETING_VERSION)"; \
	next_patch="$$(ruby -e 'v=ARGV[0].split(".").map(&:to_i); v[2]+=1; puts v.join(".")' "$$current")"; \
	next_minor="$$(ruby -e 'v=ARGV[0].split(".").map(&:to_i); v[1]+=1; v[2]=0; puts v.join(".")' "$$current")"; \
	next_major="$$(ruby -e 'v=ARGV[0].split(".").map(&:to_i); v[0]+=1; v[1]=0; v[2]=0; puts v.join(".")' "$$current")"; \
	echo "Current marketing version: $$current"; \
	echo "Next patch:               $$next_patch"; \
	echo "Next minor:               $$next_minor"; \
	echo "Next major:               $$next_major"; \
	echo "Default build number:     $$(date -u +%Y%m%d%H%M%S)"

rust-release:
	@./scripts/build-rust.sh --release

fastlane-check:
	@ruby -c fastlane/Fastfile >/dev/null && echo "Fastfile syntax OK"

testflight: rust-release fastlane-check
	@set -euo pipefail; \
	set -a; [[ -f .env ]] && source .env; set +a; \
	marketing_version="$${MARKETING_VERSION:-$(CURRENT_MARKETING_VERSION)}"; \
	build_number="$${BUILD_NUMBER:-$$(date -u +%Y%m%d%H%M%S)}"; \
	echo "Submitting to TestFlight"; \
	echo "  MARKETING_VERSION=$$marketing_version"; \
	echo "  BUILD_NUMBER=$$build_number"; \
	MARKETING_VERSION="$$marketing_version" BUILD_NUMBER="$$build_number" $(FASTLANE) upload_testflight

release: rust-release fastlane-check
	@set -euo pipefail; \
	set -a; [[ -f .env ]] && source .env; set +a; \
	current="$${MARKETING_VERSION:-$(CURRENT_MARKETING_VERSION)}"; \
	bump="$${VERSION_BUMP:-patch}"; \
	case "$$bump" in patch|minor|major) ;; *) echo "Invalid VERSION_BUMP=$$bump (expected patch|minor|major)" >&2; exit 1 ;; esac; \
	next_version="$$(ruby -e 'v=ARGV[0].split(".").map(&:to_i); b=ARGV[1]; case b; when "patch" then v[2]+=1; when "minor" then v[1]+=1; v[2]=0; when "major" then v[0]+=1; v[1]=0; v[2]=0; end; puts v.join(".")' "$$current" "$$bump")"; \
	build_number="$${BUILD_NUMBER:-$$(date -u +%Y%m%d%H%M%S)}"; \
	echo "Submitting App Store release"; \
	echo "  Base version:      $$current"; \
	echo "  Version bump:      $$bump"; \
	echo "  MARKETING_VERSION: $$next_version"; \
	echo "  BUILD_NUMBER:      $$build_number"; \
	MARKETING_VERSION="$$next_version" BUILD_NUMBER="$$build_number" $(FASTLANE) release_appstore

release-patch:
	@$(MAKE) release VERSION_BUMP=patch

release-minor:
	@$(MAKE) release VERSION_BUMP=minor

release-major:
	@$(MAKE) release VERSION_BUMP=major
