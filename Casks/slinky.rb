cask "slinky" do
  version "1.0.0"
  sha256 "214c7c3c06b20456f91888def0095c6a0c0f0a47e6d423247e29e3d2d29036f5"

  url "https://github.com/heyderekj/slinky/releases/download/v#{version}/Slinky-#{version}.zip"
  name "Slinky"
  desc "Keeps secrets out of files: API keys, .env variables and recovery codes"
  homepage "https://slinkyfiles.com"

  depends_on macos: :tahoe

  app "Slinky.app"
end
