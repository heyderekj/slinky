cask "slinky" do
  version "1.0.0"
  sha256 "858b5b314447486a7993f67efbaad55ced4e1d6fbb835fa07e244b985443a869"

  url "https://github.com/heyderekj/slinky/releases/download/v#{version}/Slinky-#{version}.zip"
  name "Slinky"
  desc "Keeps secrets out of files: API keys, .env variables and recovery codes"
  homepage "https://slinkyfiles.com"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Slinky.app"
end
