# mod_hw_for_ios V2 — Rootless build

The project keeps the upstream Objective-C/Objective-C++ implementation and provides a Rootless Theos build layout. The target test environment is iOS 16.2 with a Dopamine-style Rootless bootstrap.

## Build

Install Theos and an iOS SDK on macOS, then run:

```sh
export THEOS="$HOME/theos"
make clean package
```

The Debian package is emitted under `packages/`.

## Configuration

The tweak reads its active configuration from:

```
/var/mobile/Library/Preferences/com.modhw.ios.devices.plist
```

This is a real mobile-user preference location and must **not** be prefixed with `/var/jb`. The package therefore places only a blank example template at:

```
/var/jb/usr/share/mod_hw_for_ios/com.modhw.ios.devices.plist.example
```

Use the manager to export a plist, then transfer it to the active preference path above with a file manager that has the required permissions. Alternatively, copy the example template to that active path and edit it there. The tweak retains `/tmp/devices.plist` as a legacy fallback only when the primary file does not exist.

## Manager

The SwiftUI manager is in `manager/ModHWManager.xcodeproj`. It imports, edits, validates, and exports property lists. Transfer the exported file using an authorized file manager or SSH workflow.

## Validation

Run `python3 tools/validate_project.py` for static project and plist checks. These checks do not replace a Theos build or a real-device compatibility test.
