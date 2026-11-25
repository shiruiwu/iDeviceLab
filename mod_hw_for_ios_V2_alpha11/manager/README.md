# mod_hw Manager — read-only iOS companion utility

SwiftUI companion-app source for inspecting a user-selected property-list file and exporting an unchanged backup.

## Current build

V2 diagnostics build 8. The app is intentionally read-only: it lists top-level field names and value types, does not show field values, and does not edit device identity or account-related values.

## Build

Open `ModHWManager.xcodeproj` in Xcode 15 or later. Select an iOS 16.0+ target and a signing team, then build. The Linux development environment used for this source pass does not contain Xcode or Apple's iOS SDK, so a real IPA build must be performed by the repository's macOS GitHub Actions workflow.

## Use

1. Export or copy the plist you want to inspect into the iOS Files app.
2. Open the manager and select **导入 plist**.
3. Review whether the file parses, its root object type, field names, and value types. Values are not displayed.
4. Use **导出原始备份** to export the exact original file bytes without rewriting the plist.

The app does not claim direct access to jailbreak-only paths. A standard iOS app sandbox cannot directly read or write `/var/mobile/Library/Preferences` or `/tmp`; use a file manager to select a copy manually.

## Diagnostics script

`scripts/diagnose-config.sh` is a read-only shell diagnostic for the two configuration candidate paths present in the upstream source. It reports only file existence, readability, plist syntax, and root-object structure. It does not display configuration values, inspect device identifiers, modify files, or restart processes.

Run on the jailbroken device:

```sh
sh /path/to/diagnose-config.sh
```

## Build an IPA

On macOS with Xcode 15 or later, run:

```sh
bash scripts/build-trollstore-ipa.sh
```

The script creates an unsigned TrollStore-compatible IPA. Install it through TrollStore. This Linux environment can only run source syntax and static checks; it cannot produce a genuine iOS IPA.
