# typed: false
# frozen_string_literal: true

# Casks/r2drop.rb
# Installs the R2Drop macOS menu bar app from a signed .dmg release.
# Users install with: brew install --cask superhumancorp/tap/r2drop
cask "r2drop" do
  arch arm: "aarch64", intel: "x86_64"

  version "0.1.0"
  sha256 arm:   "REPLACE_WITH_ARM64_SHA256",
         intel: "REPLACE_WITH_X86_64_SHA256"

  url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/R2Drop-#{version}-#{arch}.dmg"
  name "R2Drop"
  desc "Menu bar app for uploading files to Cloudflare R2"
  homepage "https://r2drop.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "R2Drop.app"

  zap trash: [
    "~/.r2drop",
    "~/Library/Application Support/com.superhumancorp.r2drop",
    "~/Library/Caches/com.superhumancorp.r2drop",
    "~/Library/Logs/R2Drop",
    "~/Library/Preferences/com.superhumancorp.r2drop.plist",
    "~/Library/Saved Application State/com.superhumancorp.r2drop.savedState",
  ]
end
