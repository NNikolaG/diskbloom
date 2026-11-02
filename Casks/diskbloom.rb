# Homebrew cask for Diskbloom, served from this repository as a tap:
#   brew tap nnikolag/diskbloom https://github.com/NNikolaG/diskbloom
#   brew install --cask nnikolag/diskbloom/diskbloom
# `version` and `sha256` are rewritten by .github/workflows/release.yml after each release.
cask "diskbloom" do
  version "0.3.0"
  sha256 "0832c5f46c15ef533897cef2a4a6ffa3df89d99b1756371ac6c012892e3ddd41"

  url "https://github.com/NNikolaG/diskbloom/releases/download/v#{version}/Diskbloom-#{version}.zip"
  name "Diskbloom"
  desc "Disk usage map and cleaner for developer junk"
  homepage "https://github.com/NNikolaG/diskbloom"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Diskbloom.app"

  # Diskbloom is signed ad hoc and not notarized (no paid Apple Developer account), so
  # Gatekeeper would refuse to open it. Drop the quarantine flag on the staged app before
  # Homebrew moves it to /Applications.
  preflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{staged_path}}/Diskbloom.app"],
        must_succeed: false
  end

  uninstall quit: "io.github.nnikolag.diskbloom"

  zap trash: [
    "~/Library/Caches/io.github.nnikolag.diskbloom",
    "~/Library/HTTPStorages/io.github.nnikolag.diskbloom",
    "~/Library/Preferences/io.github.nnikolag.diskbloom.plist",
    "~/Library/Saved Application State/io.github.nnikolag.diskbloom.savedState",
  ]

  caveats <<~EOS
    Diskbloom is not notarized by Apple. This cask removes the quarantine flag
    (com.apple.quarantine) so macOS opens it without a Gatekeeper prompt.

    For a complete scan, allow Full Disk Access in
      System Settings > Privacy & Security > Full Disk Access
    Each release is signed ad hoc, so macOS may ask for it again after an upgrade.
  EOS
end
