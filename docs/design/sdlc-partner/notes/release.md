# Release brief (per phase, X = minor)

Worktree `/Users/yznki/.t3/worktrees/glidepath/t3-63a6632c`, branch `sdlc-1.X`. No attribution lines anywhere.
Git network only as `git -c credential.helper= -c credential.helper='!gh auth git-credential' <cmd> https://github.com/yznki/<repo>.git <refspec>`. Never force-push main or tags.

0. Gate: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` all pass;
   `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build -c release` ok. Stop on failure.
a. Bump `Sources/Glidepath/Core/Version.swift` and `Resources/Info.plist` (CFBundleShortVersionString and
   CFBundleVersion) to `1.X.0`. Commit `glidepath 1.X.0`.
b. Push `sdlc-1.X` to yznki/glidepath. `gh pr create --repo yznki/glidepath --base main --head sdlc-1.X --title
   "1.X.0: <name>" --body "<bullets>"`, wait for its checks (`gh pr checks <n> --repo yznki/glidepath --watch`, all green), then `gh pr merge <n> --repo yznki/glidepath --rebase --delete-branch`.
c. Fetch main; find the merged `glidepath 1.X.0` commit on origin/main; `git tag -a v1.X.0 -m "Glidepath 1.X.0"
   <sha>`; push the tag (`refs/tags/v1.X.0`).
d. `curl -sL https://github.com/yznki/glidepath/archive/refs/tags/v1.X.0.tar.gz | shasum -a 256`. On a local
   branch at origin/main update `url` and `sha256` in `Formula/glidepath.rb`, commit `Formula: v1.X.0 url and
   sha256`, push to main (fast-forward).
e. Tap: `TAP=$(brew --repository yznki/tap)`; check its branch (`git -C $TAP branch --show-current`); pull it over
   HTTPS (https://github.com/yznki/homebrew-tap.git); copy `Formula/glidepath.rb` to `$TAP/Formula/glidepath.rb`;
   commit `glidepath 1.X.0`; push.
f. `gh release create v1.X.0 --repo yznki/glidepath --title "1.X.0" --notes "<CHANGELOG 1.X.0 section>"`.
g. `brew update && brew info yznki/tap/glidepath` shows 1.X.0; `brew fetch --build-from-source
   yznki/tap/glidepath` succeeds. Never `brew upgrade`.
Report: PR URL, merged sha, tag sha, tarball sha256, tap commit, release URL, brew info line.
