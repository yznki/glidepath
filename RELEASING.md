# Releasing glidepath

This is the checklist for v1.0.0 and later releases. Each remote step is marked. Do not run a remote step without
the go-ahead for that release.

## 1. Check the tree

- `main` is green in CI (`swift build` and `swift test` on macOS).
- Release build with the Command Line Tools: `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build -c release`.
- Tests with Xcode: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- `docs/shots/*.png` and `docs/media/hero.gif` match the current design. Re-render with `glidepath --snapshot docs/shots`
  and `glidepath --hero-gif docs/media/hero.gif` if the popover changed.

## 2. Tag (remote)

```sh
git tag -a v1.0.0 -m "Glidepath 1.0.0"
git push origin v1.0.0                                  # remote
```

## 3. Tarball hash

Homebrew downloads GitHub's generated archive for the tag, so the hash must come from that file, not from a local
`git archive`:

```sh
curl -sL https://github.com/yznki/glidepath/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
```

The repo's `Formula/glidepath.rb` has `sha256` set to a placeholder of zeros. Replace it with that hash.

## 4. Tap (remote)

The tap is a separate repo, `yznki/homebrew-tap`, with the formula at `Formula/glidepath.rb`. Copy the repo's
`Formula/glidepath.rb` there, with the hash from step 3, and commit it to the tap.

Create the tap repo once: `gh repo create yznki/homebrew-tap --public`.                            # remote

## 5. Social preview (remote, manual)

In the glidepath repo settings, set `assets/brand/social.png` (1280 x 640) as the social preview image.
GitHub has no command-line path for this step.                                                    # remote

## 6. Smoke test (remote)

On a Mac with a clean Homebrew:

```sh
brew install yznki/tap/glidepath
glidepath --version
glidepath doctor
brew uninstall glidepath
```

`doctor` reports each requirement. Anything it marks as missing has a fix command next to it.

## 7. After release

- Update the README's Limits section: remove the line about the tap and the placeholder hash.
- Keep `Formula/glidepath.rb` in this repo in step with the tap.
