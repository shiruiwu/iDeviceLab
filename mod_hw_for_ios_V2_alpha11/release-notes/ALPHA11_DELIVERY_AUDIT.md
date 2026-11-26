# Alpha11 delivery audit (2026-11-26)

## Baseline
- Repository: `shiruiwu/iDeviceLab`
- Development branch: `mod-hw-alpha11`
- Audited HEAD: `11b211816beaef5f4f4136c990604b0bde7c3488`
- The `main` branch is outside this change scope.

## Verified source inventory

| Area | Current repository evidence | Delivery status |
|---|---|---|
| Original tweak hooks | `src/mobile_gestalt/mobile_gestalt.m`, `src/cydia_substrate_hook/HookUtil.m`, `src/captain_hook/hook.mm` are included in the Theos target | Source present; runtime behavior not verified on device |
| Rootless packaging | Theos Makefile sets `THEOS_PACKAGE_SCHEME = rootless`; package workflow builds and inspects a DEB | Cloud build previously passed; install/load not verified |
| Configuration file | Example plist and read-only `diagnose-config.sh` exist; hook reads the primary preference path with a legacy fallback | Basic config path exists; end-to-end apply not verified |
| TrollStore manager | SwiftUI app imports plist, validates plist syntax, lists top-level keys/types, and exports the original bytes | Read-only utility, not a full manager |
| Backup / restore | Manager exports imported plist bytes; Rootless tools now include timestamped config backup and validated atomic config restore with pre-restore snapshot | Config-file backup/restore implemented; no app-container backup/restore |
| Deep app cleanup | No Alpha11 app-data/keychain cleanup implementation found in the audited tree | Not implemented |
| Profile manager | Older `iDeviceLab-2.0-source-v2` has local profile storage/API | Separate legacy code; not wired to Alpha11 tweak configuration |
| Manager ↔ Core bridge | No integrated authenticated bridge between the Alpha11 manager, a privileged helper, and the tweak config path found | Not implemented |
| Diagnostics | Read-only config path/plist checks and static project validator exist | Basic diagnostics only |
| Device verification | No device test results are part of this source audit | Requires iPhone 12 / iOS 16.2 test session |

## Important technical distinction
A profile stored by the legacy Core is not automatically consumed by the Alpha11 tweak. The Alpha11 manager's file importer/exporter does not grant access to jailbreak system paths. A successful IPA/DEB build proves packaging and compilation only; it does not prove injection, hook coverage, config parsing on-device, or effects in target processes.

## Consolidated work still required
1. Define one versioned configuration schema and validate key names/types without exposing stored values in diagnostics.
2. Add safe configuration backup/restore with atomic writes, pre-restore backup, validation, rollback, and an audit log.
3. Implement a supported manager-to-device transport and privileged helper with explicit authorization, request validation, and bounded operations.
4. Separate per-app configuration selection from global configuration and prove process filtering with on-device tests.
5. Add app-data backup/restore only for explicitly selected, accessible app containers, with clear exclusions and restore verification.
6. Treat cleanup as a reversible, scoped operation. Report protected/unavailable data rather than claiming a factory-reset-equivalent wipe; keychain and system-managed data require separate platform-level handling.
7. Add integration tests for config parsing, process filtering, package layout, upgrade/uninstall behavior, and rollback.
8. Run the Rootless DEB and TrollStore IPA workflows, install on the target device, inspect logs, and record observed results.

## Work completed after the initial audit
- Added `scripts/backup-config.sh` for timestamped, byte-preserving backups of the tweak plist.
- Added `scripts/restore-config.sh` for plist validation, atomic restore, and a separate pre-restore rollback snapshot.
- Included both commands in the Rootless config-tools DEB and added CI syntax/static checks.

## Not claimed
This audit does not claim that deep cleanup, keychain erasure, app-data restoration, full manager/Core integration, or real-device spoofing validation is complete. No new device-side operation was performed by this audit.
