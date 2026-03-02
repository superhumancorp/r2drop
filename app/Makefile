SHELL := /bin/bash

.PHONY: help print-version rust-release fastlane-check testflight release release-patch release-minor release-major dmg-release dmg-release-no-notary release-tools release-public-key release-check-key release-sign-dmg release-verify-update-feed sparkle-tools sparkle-public-key sparkle-check-key sparkle-sign-dmg sparkle-verify-appcast

# Pull the first MARKETING_VERSION from the XcodeGen spec (R2Drop target).
CURRENT_MARKETING_VERSION := $(shell awk -F'"' '/MARKETING_VERSION:/ { print $$2; exit }' R2Drop/project.yml)

# Allow callers to override, e.g. `make testflight BUILD_NUMBER=123`.
FASTLANE ?= bundle exec fastlane
VERSION_BUMP ?= patch
SIGNING_TOOLS_VERSION ?= 2.9.0
RELEASE_PUBLIC_KEY ?= NWlOpvs7+ccCaW6557MqyCO94w3KVziS7uAOOxR8gQk=
SIGNING_TOOLS_DIR ?= /tmp/sparkle-$(SIGNING_TOOLS_VERSION)
SIGNING_TOOLS_ARCHIVE ?= /tmp/sparkle-$(SIGNING_TOOLS_VERSION).tar.xz
SIGNING_BIN_DIR ?= $(SIGNING_TOOLS_DIR)/bin
UPDATE_FEED_URL ?= https://github.com/superhumancorp/r2drop/releases/latest/download/appcast.xml

help:
	@echo "R2Drop local release automation"
	@echo ""
	@echo "Targets:"
	@echo "  make testflight        Build Rust (release) + upload to TestFlight"
	@echo "  make release           Build Rust (release) + submit App Store build (auto patch bump)"
	@echo "  make release-minor     Same as release with minor bump"
	@echo "  make release-major     Same as release with major bump"
	@echo "  make dmg-release       Build local DMGs (arm64 + x86_64), sign + notarize by default"
	@echo "  make dmg-release-no-notary  Same as dmg-release but skips notarization"
	@echo "  make release-tools     Download update-signing tools"
	@echo "  make release-public-key Print local release-signing public key"
	@echo "  make release-check-key Verify local release-signing key matches app key"
	@echo "  make release-sign-dmg DMG=<path> [SIGNING_PRIVATE_KEY_FILE=<path>]"
	@echo "  make release-verify-update-feed [UPDATE_FEED_URL=<url>]"
	@echo "  make print-version     Show current/next version preview"
	@echo ""
	@echo "Overrides:"
	@echo "  BUILD_NUMBER=<n>       Override auto build number (default UTC timestamp)"
	@echo "  MARKETING_VERSION=x.y.z Override release/testflight version"
	@echo "  VERSION_BUMP=patch|minor|major (used by make release)"
	@echo "  XCODE_SCHEME='R2Drop Production' (passed through to Fastlane)"
	@echo "  DMG_SIGN=0|1           Toggle DMG app signing (default 1)"
	@echo "  DMG_NOTARIZE=0|1       Toggle DMG notarization (default 1 for make dmg-release)"
	@echo "  DMG_SIGN_IDENTITY='Developer ID Application: Paul Pierre (A89MU37ZLB)'"
	@echo "  SIGNING_TOOLS_VERSION=2.9.0  Update-signing tool version"
	@echo "  RELEASE_PUBLIC_KEY=<base64> Expected app release public key"
	@echo "  UPDATE_FEED_URL=<url>  Update feed URL used by release-verify-update-feed"
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

dmg-release: rust-release fastlane-check
	@set -euo pipefail; \
	set -a; [[ -f .env ]] && source .env; set +a; \
	marketing_version="$${MARKETING_VERSION:-$(CURRENT_MARKETING_VERSION)}"; \
	build_number="$${BUILD_NUMBER:-$$(date -u +%Y%m%d%H%M%S)}"; \
	dmg_sign="$${DMG_SIGN:-1}"; \
	dmg_notarize="$${DMG_NOTARIZE:-1}"; \
	echo "Building local DMG release artifacts"; \
	echo "  MARKETING_VERSION=$$marketing_version"; \
	echo "  BUILD_NUMBER=$$build_number"; \
	echo "  DMG_SIGN=$$dmg_sign"; \
	echo "  DMG_NOTARIZE=$$dmg_notarize"; \
	MARKETING_VERSION="$$marketing_version" BUILD_NUMBER="$$build_number" \
	DMG_SIGN="$$dmg_sign" DMG_NOTARIZE="$$dmg_notarize" \
	DMG_SIGN_IDENTITY="$${DMG_SIGN_IDENTITY:-}" \
	$(FASTLANE) build_local_dmg

dmg-release-no-notary:
	@$(MAKE) dmg-release DMG_NOTARIZE=0

release-tools:
	@set -euo pipefail; \
	echo "Installing release-signing tools $(SIGNING_TOOLS_VERSION) into $(SIGNING_TOOLS_DIR)"; \
	curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$(SIGNING_TOOLS_VERSION)/Sparkle-$(SIGNING_TOOLS_VERSION).tar.xz" \
	  -o "$(SIGNING_TOOLS_ARCHIVE)"; \
	rm -rf "$(SIGNING_TOOLS_DIR)"; \
	mkdir -p "$(SIGNING_TOOLS_DIR)"; \
	tar -xf "$(SIGNING_TOOLS_ARCHIVE)" -C "$(SIGNING_TOOLS_DIR)"; \
	test -x "$(SIGNING_BIN_DIR)/sign_update"; \
	test -x "$(SIGNING_BIN_DIR)/generate_appcast"; \
	test -x "$(SIGNING_BIN_DIR)/generate_keys"; \
	ls -1 "$(SIGNING_BIN_DIR)"

release-public-key: release-tools
	@$(SIGNING_BIN_DIR)/generate_keys -p

release-check-key: release-tools
	@set -euo pipefail; \
	actual="$$( $(SIGNING_BIN_DIR)/generate_keys -p )"; \
	expected="$(RELEASE_PUBLIC_KEY)"; \
	echo "Expected: $$expected"; \
	echo "Actual:   $$actual"; \
	if [ "$$actual" != "$$expected" ]; then \
	  echo "Release signing public key mismatch" >&2; \
	  exit 1; \
	fi; \
	echo "Release signing public key matches SUPublicEDKey"

release-sign-dmg: release-tools
	@set -euo pipefail; \
	if [ -z "$${DMG:-}" ]; then \
	  echo "Usage: make release-sign-dmg DMG=/path/to/R2Drop-<version>-<arch>.dmg [SIGNING_PRIVATE_KEY_FILE=/path/to/key.txt]" >&2; \
	  exit 1; \
	fi; \
	if [ ! -f "$$DMG" ]; then \
	  echo "DMG not found: $$DMG" >&2; \
	  exit 1; \
	fi; \
	if [ -n "$${SIGNING_PRIVATE_KEY_FILE:-}" ]; then \
	  if [ ! -f "$$SIGNING_PRIVATE_KEY_FILE" ]; then \
	    echo "Key file not found: $$SIGNING_PRIVATE_KEY_FILE" >&2; \
	    exit 1; \
	  fi; \
	  "$(SIGNING_BIN_DIR)/sign_update" "$$DMG" -f "$$SIGNING_PRIVATE_KEY_FILE"; \
	else \
	  "$(SIGNING_BIN_DIR)/sign_update" "$$DMG"; \
	fi

release-verify-update-feed:
	@set -euo pipefail; \
	tmp="$$(mktemp)"; \
	curl -fsSL "$(UPDATE_FEED_URL)" -o "$$tmp"; \
	sig_count="$$(rg -c 'sparkle:edSignature=' "$$tmp" || true)"; \
	echo "Update feed URL: $(UPDATE_FEED_URL)"; \
	echo "Signature count: $$sig_count"; \
	if [ "$$sig_count" -lt 1 ]; then \
	  echo "No update signatures found in update feed" >&2; \
	  cat "$$tmp"; \
	  rm -f "$$tmp"; \
	  exit 1; \
	fi; \
	echo "Update signatures present in feed"; \
	rm -f "$$tmp"

# Backward-compatible aliases.
sparkle-tools: release-tools
sparkle-public-key: release-public-key
sparkle-check-key: release-check-key
sparkle-sign-dmg: release-sign-dmg
sparkle-verify-appcast: release-verify-update-feed
