# typed: false
# frozen_string_literal: true

# Formula/r2drop.rb
# Installs the r2drop CLI binary from pre-compiled GitHub Release assets.
# Users install with: brew install superhumancorp/tap/r2drop
#
# SHA-256 hashes are updated automatically by the bump workflow
# when a new cli-v* tag is pushed.
class R2drop < Formula
  desc "CLI for uploading files to Cloudflare R2 storage"
  homepage "https://r2drop.com"
  version "0.1.7"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/superhumancorp/r2drop/releases/download/cli-v#{version}/r2drop-macos-arm64.tar.gz"
      sha256 "PLACEHOLDER_ARM64_SHA256"

      def install
        bin.install "r2drop"
      end
    end

    if Hardware::CPU.intel?
      url "https://github.com/superhumancorp/r2drop/releases/download/cli-v#{version}/r2drop-macos-x86_64.tar.gz"
      sha256 "PLACEHOLDER_X86_64_SHA256"

      def install
        bin.install "r2drop"
      end
    end
  end

  livecheck do
    url "https://github.com/superhumancorp/r2drop/releases"
    regex(/^cli-v(\d+(?:\.\d+)+)$/i)
    strategy :github_releases
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/r2drop --version")
  end
end
