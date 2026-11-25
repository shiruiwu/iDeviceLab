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

The intended Rootless preference location is `/var/mobile/Library/Preferences/com.modhw.ios.devices.plist`. Historical sample files remain under `txt/`; a blank template is packaged at `layout/var/mobile/Library/Preferences/com.modhw.ios.devices.plist.example`.

## Manager

The SwiftUI manager is in `manager/ModHWManager.xcodeproj`. It imports, edits, validates, and exports property lists. Transfer the exported file using an authorized file manager or SSH workflow.

## Validation

Run `python3 tools/validate_project.py` for static project and plist checks. These checks do not replace a Theos build or a real-device compatibility test.
