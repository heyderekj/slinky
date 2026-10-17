cask "slinky" do
  version "1.0.0"
  sha256 "371ed4068cefd12d43fff39870b6d9677411fdf75fdba4abf788c0058bfdc1f5"

  url "https://github.com/heyderekj/slinky/releases/download/v#{version}/Slinky-#{version}.zip"
  name "Slinky"
  desc "Keeps secrets out of files: API keys, .env variables and recovery codes"
  homepage "https://slinkyfiles.com"

  depends_on macos: :tahoe

  app "Slinky.app"
end
