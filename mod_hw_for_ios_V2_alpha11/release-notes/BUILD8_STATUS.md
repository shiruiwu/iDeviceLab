# V2 diagnostics build 8 audit

## Scope
This pass updates only the companion manager, read-only diagnostics, project validation, and documentation. It does not change the tweak runtime hooks or package payload.

## Changes
- Manager is a read-only plist inspector.
- It displays top-level key names and value types, but not values.
- It exports original imported bytes unchanged as a backup.
- Device-side diagnostic checks candidate file existence, readability, plist syntax, and root structure only.
- Xcode manager build number is 8.

## Validation
- Swift frontend syntax parse.
- Shell syntax parse for the read-only diagnostic.
- Static project and plist validation.

These checks do not replace an Xcode build, Theos package build, or Dopamine device test.

## Build limitations
The current execution environment does not contain xcodebuild, Apple's iOS SDK, or a configured Theos installation. No new IPA or DEB is claimed. The Alpha11 DEB remains a prior binary and was not rebuilt in this pass.
