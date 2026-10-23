class Glidepath < Formula
  desc "PRs reviewed before you're back: scheduled Claude Code reviews for GitHub PRs, with a menu bar app"
  homepage "https://github.com/yznki/glidepath"
  url "https://github.com/yznki/glidepath/archive/refs/tags/v1.3.1.tar.gz"
  sha256 "7257d26ade859f6d0b1b5f0b9e81d8f98e0b3c5c4181262504641f79cd5b2d23"
  license "MIT"
  head "https://github.com/yznki/glidepath.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    system "./make-app.sh", "--no-build"
    bin.install ".build/release/glidepath"
    prefix.install "build/Glidepath.app"
    (share/"glidepath").install Dir["skill/glidepath/*"]
  end

  def caveats
    <<~EOS
      Set up the schedule, the Claude Code skill and the menu bar app:
        glidepath init

      Needs: claude (Claude Code, logged in), gh (signed in), git and the
      Xcode Command Line Tools. init checks these and prints the fix for each.

      init links the app into ~/Applications. To remove everything:
        glidepath uninstall && brew uninstall glidepath
    EOS
  end

  test do
    assert_match "glidepath", shell_output("#{bin}/glidepath --version")
  end
end
