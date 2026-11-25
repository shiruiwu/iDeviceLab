# Alpha11

- Add a SwiftUI plist configuration manager project.
- Add a shared Xcode scheme for reproducible command-line builds.
- Add a macOS GitHub Actions workflow for unsigned arm64 TrollStore IPA packaging.
- Add package and archive structure checks.
- Preserve the original plist object types and unknown keys when importing and exporting.
- Add input validation for hexadecimal fields and MAC-address formatting.

The manager CI workflow validates the manager source and package structure only; it does not compile or validate the jailbreak tweak.


## V2 diagnostics build 8 — read-only manager pass

1. Replaced the editable identity-field form with a read-only plist inspector.
2. The manager reports the plist root type, top-level field names, and value types without displaying field values.
3. Export preserves the exact original plist bytes as a backup rather than serializing edited fields.
4. Removed identity-field editing controls and configuration mutation from the companion app.
5. Added a read-only device-side diagnostic for candidate file existence, readability, plist syntax, and root-object structure.
6. Updated the Xcode build number to 8.

Status: Swift syntax parsing and static project checks are available. A full iOS build still requires macOS + Xcode; no IPA or real-device success is claimed.
