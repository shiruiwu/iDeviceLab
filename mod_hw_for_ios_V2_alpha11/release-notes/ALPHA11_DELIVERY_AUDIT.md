# Alpha11 delivery audit (2026-11-26)

## Baseline
- Repository: `shiruiwu/iDeviceLab`
- Development branch: `mod-hw-alpha11`
- Audit baseline: `11b211816beaef5f4f4136c990604b0bde7c3488`; follow-up changes are recorded in branch history.
- The `main` branch is outside this change scope.

## Verified source inventory

| Area | Current repository evidence | Delivery status |
|---|---|---|
| Original tweak hooks | `src/mobile_gestalt/mobile_gestalt.m`, `src/cydia_substrate_hook/HookUtil.m`, `src/captain_hook/hook.mm` are included in the Theos target | Source present; runtime behavior not verified on device |
| Rootless packaging | Theos Makefile sets `THEOS_PACKAGE_SCHEME = rootless`; package workflow builds and inspects a DEB | Cloud build previously passed; install/load not verified |
| Configuration file | Example plist and read-only `diagnose-config.sh` exist; hook reads the primary preference path with a legacy fallback | Basic config path exists; end-to-end apply not verified |
| TrollStore manager | SwiftUI app imports plist, validates plist syntax, lists top-level keys/types, and exports the original bytes | Read-only utility, not a full manager |
| Backup / restore | Timestamped config backup/restore plus explicit-bundle-ID app-container backup with SHA-256 manifest | Config backup/restore and app-container backup implemented; app-container restore not implemented |
| Deep app cleanup | No Alpha11 app-data/keychain cleanup implementation found in the audited tree | Not implemented |
| Profile manager | Older `iDeviceLab-2.0-source-v2` has local profile storage/API | Separate legacy code; not wired to Alpha11 tweak configuration |
| Manager ↔ Core bridge | No integrated authenticated bridge between the Alpha11 manager, a privileged helper, and the tweak config path found | Not implemented |
| Diagnostics | Read-only config path/plist checks, static project validator, and backup metadata/checksum | Basic diagnostics plus backup integrity metadata |
| Device verification | No device test results are part of this source audit | Requires iPhone 12 / iOS 16.2 test session |

## Important technical distinction
A profile stored by the legacy Core is not automatically consumed by the Alpha11 tweak. The Alpha11 manager's file importer/exporter does not grant access to jailbreak system paths. A successful IPA/DEB build proves packaging and compilation only; it does not prove injection, hook coverage, config parsing on-device, or effects in target processes.

## Consolidated work still required
1. Define one versioned configuration schema and validate key names/types without exposing stored values in diagnostics.
2. Add safe configuration backup/restore with atomic writes, pre-restore backup, validation, rollback, and an audit log.
3. Implement a supported manager-to-device transport and privileged helper with explicit authorization, request validation, and bounded operations.
4. Separate per-app configuration selection from global configuration and prove process filtering with on-device tests.
5. Add safe app-container restore for explicitly selected containers, with hostile-archive validation, pre-restore snapshot, rollback, and restore verification.
6. Treat cleanup as a reversible, scoped operation. Report protected/unavailable data rather than claiming a factory-reset-equivalent wipe; keychain and system-managed data require separate platform-level handling.
7. Add integration tests for config parsing, process filtering, package layout, upgrade/uninstall behavior, and rollback.
8. Run the Rootless DEB and TrollStore IPA workflows, install on the target device, inspect logs, and record observed results.

## Work completed after the initial audit
- Added `scripts/backup-config.sh` for timestamped, byte-preserving backups of the tweak plist.
- Added `scripts/restore-config.sh` for plist validation, atomic restore, and a separate pre-restore rollback snapshot.
- Included both config commands in the Rootless config-tools DEB and added CI syntax/static checks.
- Added `scripts/backup-app-container.sh`: backs up one explicitly named app data container, writes a SHA-256 manifest, and documents that Keychain, App Groups, and system-managed data are excluded.
- Added `scripts/verify-app-container-backup.sh`: verifies the manifest filename, SHA-256 digest, and archive readability without extracting or changing app data.
- Included the app-container backup and verification commands in the Rootless tools DEB; no app data is deleted or modified by these commands.
- Corrected the tweak source control metadata architecture to `iphoneos-arm64`, matching the Theos-produced package.

## Not claimed
This audit does not claim that deep cleanup, keychain erasure, app-container restoration, full manager/Core integration, or real-device runtime validation is complete. No new device-side operation was performed by this audit.
