# typed: false
# frozen_string_literal: true

# Casks/r2drop.rb
# Installs the R2Drop macOS menu bar app from a signed .dmg release.
# Users install with: brew install --cask superhumancorp/tap/r2drop
cask "r2drop" do
  arch arm: "aarch64", intel: "x86_64"

  version "0.1.0"
  # Replace with real SHA256 values when publishing a new app release.
  sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
         intel: "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/R2Drop-#{version}-#{arch}.dmg",
      verified: "github.com/superhumancorp/r2drop/"
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
