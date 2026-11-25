# mod_hw_for_ios V2 Alpha11 — Manager build

This directory contains the iOS configuration manager project and the GitHub Actions workflow used to produce an unsigned arm64 TrollStore IPA.

## Build

The workflow runs on GitHub Actions using a macOS 15 runner with Xcode. Open **Actions → Build TrollStore IPA → Run workflow** to start a build. On success, download the artifact named \`mod-hw-manager-trollstore-ipa\`.

The IPA is unsigned and intended for installation with TrollStore. It is not an App Store distribution package.

## Local build

Requirements: macOS, Xcode with the iOS SDK, and command-line tools.

\`\`\`sh
bash scripts/build-trollstore-ipa.sh
\`\`\`

The output is \`release/mod_hw_manager_trollstore.ipa\`.

## Manager

The SwiftUI manager imports and exports property-list configuration files, retains unknown keys, and performs basic format checks. Exported files must be transferred to the appropriate location on the target device using a file manager or another authorized workflow.

## Scope

This manager/build subset is maintained separately from the upstream tweak implementation. No claim is made that the tweak or a cloud-connected identity workflow has been built or validated by this manager-only CI job.
