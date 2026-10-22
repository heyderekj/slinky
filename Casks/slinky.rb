cask "slinky" do
  version "1.1.0"
  sha256 "69367b7f56be5a91f6082d7a822d1dd9e66668d4453b0be29c6867a39f960dd8"

  url "https://github.com/heyderekj/slinky/releases/download/v#{version}/Slinky-#{version}.zip"
  name "Slinky"
  desc "Keeps secrets out of files: API keys, .env variables and recovery codes"
  homepage "https://slinkyfiles.com"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Slinky.app"
end
