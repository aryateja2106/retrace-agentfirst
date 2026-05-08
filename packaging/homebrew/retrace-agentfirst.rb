cask "retrace-agentfirst" do
  version "0.8.7"
  sha256 "REPLACE_WITH_RELEASE_DMG_SHA256"

  url "https://github.com/OWNER/REPO/releases/download/v#{version}/Retrace-Agentfirst-#{version}-aarch64.dmg"
  name "Retrace Agentfirst"
  desc "Local-first screen memory, search, and agent context for macOS"
  homepage "https://github.com/OWNER/REPO"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Retrace Agentfirst.app"

  zap trash: [
    "~/Library/Preferences/io.retrace.app.plist",
  ]
end
