# TrollStore IPA build

The GitHub Actions workflow `.github/workflows/mod-hw-alpha11.yml` builds the SwiftUI manager on a macOS 15 runner with Xcode.

Open the repository's **Actions** tab, choose **Build mod_hw Alpha11 TrollStore IPA**, and run the workflow manually. On success, download the artifact named `mod-hw-manager-trollstore-ipa`.

The package is unsigned and intended for TrollStore installation. It is not an App Store package. A successful CI package check does not establish compatibility with every iOS release.
