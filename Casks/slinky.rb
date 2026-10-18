cask "slinky" do
  version "1.0.0"
  sha256 "2c8fd4424efaaf90523bd8f57d57be58e61b795a018fbfd65c567dd8c16aad48"

  url "https://github.com/heyderekj/slinky/releases/download/v#{version}/Slinky-#{version}.zip"
  name "Slinky"
  desc "Keeps secrets out of files: API keys, .env variables and recovery codes"
  homepage "https://slinkyfiles.com"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Slinky.app"
end
