class ReviewRadar < Formula
  desc "Scheduled Claude Code PR reviewer for GitHub repos, with a macOS menu bar radar"
  homepage "https://github.com/yznki/review-radar"
  url "https://github.com/yznki/review-radar/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/yznki/review-radar.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    system "./make-app.sh", "--no-build"
    bin.install ".build/release/review-radar"
    prefix.install "build/Review Radar.app"
    (share/"review-radar").install Dir["skill/review-radar/*"]
  end

  def caveats
    <<~EOS
      Set up the schedule, the Claude Code skill and the menu bar app:
        review-radar init

      Needs: claude (Claude Code, logged in), gh (signed in), git and the
      Xcode Command Line Tools. init checks these and prints the fix for each.

      init links the app into ~/Applications. To remove everything:
        review-radar uninstall && brew uninstall review-radar
    EOS
  end

  test do
    assert_match "review-radar", shell_output("#{bin}/review-radar --version")
  end
end
