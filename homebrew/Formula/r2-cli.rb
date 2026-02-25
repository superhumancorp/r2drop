# typed: false
# frozen_string_literal: true

# Formula/r2-cli.rb
# Installs the r2-cli binary from pre-compiled GitHub Release assets.
# Users install with: brew install superhumancorp/tap/r2-cli
class R2Cli < Formula
  desc "CLI for uploading files to Cloudflare R2 storage"
  homepage "https://r2drop.com"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/r2-cli-aarch64-apple-darwin.tar.gz"
      sha256 "REPLACE_WITH_MACOS_ARM64_SHA256"

      def install
        bin.install "r2-cli"
      end
    end

    if Hardware::CPU.intel?
      url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/r2-cli-x86_64-apple-darwin.tar.gz"
      sha256 "REPLACE_WITH_MACOS_X86_64_SHA256"

      def install
        bin.install "r2-cli"
      end
    end
  end

  on_linux do
    if Hardware::CPU.intel? && Hardware::CPU.is_64_bit?
      url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/r2-cli-x86_64-unknown-linux-musl.tar.gz"
      sha256 "REPLACE_WITH_LINUX_X86_64_SHA256"

      def install
        bin.install "r2-cli"
      end
    end

    if Hardware::CPU.arm? && Hardware::CPU.is_64_bit?
      url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/r2-cli-aarch64-unknown-linux-musl.tar.gz"
      sha256 "REPLACE_WITH_LINUX_ARM64_SHA256"

      def install
        bin.install "r2-cli"
      end
    end
  end

  livecheck do
    url :stable
    strategy :github_latest
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/r2-cli --version")
  end
end
