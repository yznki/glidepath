# Contributing

Thanks for looking. Small, focused pull requests get reviewed fastest.

## Build and test

```sh
swift build                                                          # Command Line Tools are enough
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test  # XCTest needs Xcode
```

## No SwiftUI macros

Code must build with the Command Line Tools alone. Swift macros such as `#Preview` need plugins that Xcode ships and
the Command Line Tools do not, so one macro breaks `swift build` for anyone without Xcode. Write view code without
macros.

## Running the app

`./make-app.sh` builds the app bundle with the Command Line Tools. Pass `--no-build` to reuse an existing
`.build/release` binary.

For screenshots and the design states, run `glidepath --snapshot <dir>`. It renders from fixtures, in light and dark.

## Design

The design spec for v1.3 is in [docs/design/v1.3](docs/design/v1.3). Match it, or change the spec in the same pull
request.

## Pull requests

- Keep each PR to one change. Split a large refactor into steps.
- Update [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
- Describe what changed and how you checked it.
