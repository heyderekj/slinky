cask "slinky" do
  version "2.0.0"
  sha256 "4f4b0a8f757d12dfc3da4f0d5820fdbcb1a7284cbff88f1f38853b984aef633d"

  url "https://github.com/heyderekj/slinky/releases/download/v#{version}/Slinky-#{version}.zip"
  name "Slinky"
  desc "Keeps secrets out of files: API keys, .env variables and recovery codes"
  homepage "https://slinkyfiles.com"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Slinky.app"
end
