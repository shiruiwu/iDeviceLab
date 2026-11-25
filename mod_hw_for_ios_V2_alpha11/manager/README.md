# mod_hw Manager — iOS companion app

SwiftUI source for importing, editing, validating, and exporting the tweak's property-list configuration.

## Build

Open `ModHWManager.xcodeproj` in Xcode 15 or later. The project targets iOS 16.0 and builds an arm64 iOS app. For an unsigned TrollStore package, use the repository GitHub Actions workflow or run `scripts/build-trollstore-ipa.sh` on macOS with Xcode installed.

## Configuration

The editor exposes the known fields used by the current MobileGestalt/IOKit implementation, including `ProductId` and `UniqueChipId`, and the `*Data` format switches. Unknown plist keys are retained when importing and exporting. Unchanged known fields preserve their original plist values and object types.

## Use

1. Create a blank configuration or import an existing plist.
2. Edit fields and choose **检查并导出**.
3. Correct validation errors and export the plist to Files.
4. Back up the active configuration on the jailbroken device.
5. Transfer the exported file to `/var/mobile/Library/Preferences/com.modhw.ios.devices.plist` using a file manager with the required permissions.

The app does not install the tweak or restart SpringBoard by itself.
