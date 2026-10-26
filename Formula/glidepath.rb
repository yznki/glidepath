class Glidepath < Formula
  desc "PRs reviewed before you're back: scheduled Claude Code reviews for GitHub PRs, with a menu bar app"
  homepage "https://github.com/yznki/glidepath"
  url "https://github.com/yznki/glidepath/archive/refs/tags/v1.10.0.tar.gz"
  sha256 "cefe50a2ca83cd5a9cd6a119e69cd13f96385c3222260343743c0d5d8208185a"
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

      If the build stops on Xcode: update Xcode to match your macOS and run
      `sudo xcodebuild -license accept`. Command Line Tools only: `xcode-select --install`.

      init links the app into ~/Applications. To remove everything:
        glidepath uninstall && brew uninstall glidepath
    EOS
  end

  test do
    assert_match "glidepath", shell_output("#{bin}/glidepath --version")
  end
end
