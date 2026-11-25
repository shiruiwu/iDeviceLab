# Alpha11

- Add a SwiftUI plist configuration manager project.
- Add a shared Xcode scheme for reproducible command-line builds.
- Add a macOS GitHub Actions workflow for unsigned arm64 TrollStore IPA packaging.
- Add package and archive structure checks.
- Preserve the original plist object types and unknown keys when importing and exporting.
- Add input validation for hexadecimal fields and MAC-address formatting.

The manager CI workflow validates the manager source and package structure only; it does not compile or validate the jailbreak tweak.
