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


## Additional source-level findings (not runtime-verified)

The original hook implementation was reviewed for call-site coverage and hard-coded behavior. The following are concrete source findings that should be resolved or explicitly accepted before a production release:

- `HookerForMGCopyMultipleAnswers()` exists, but the constructor currently calls only `HookerForMGCopyAnswer()`; the multi-answer path is not activated by the current initializer.
- `hook_sysctl()` is defined, but the constructor calls only `hook_sysctlbyname()`. The current `replace_sysctl` body delegates to the original function and logs selected queries; it does not replace those values.
- Three CoreTelephony hooks return fixed SIM/phone-state values in source (`_CTSettingCopyMyPhoneNumber`, `_CTSIMSupportGetSIMStatus`, and `_CTSIMSupportGetSIMTrayStatus`) instead of reading a validated configuration. These hard-coded responses can produce inconsistent device state and must not be treated as configurable or verified behavior.
- Hex decoding helpers contain comments acknowledging missing input validation. Malformed configuration strings may cause invalid reads or inconsistent data; validate configuration before the tweak consumes it.
- The CI Theos build completes with compiler warnings, including deprecated property-list APIs and unused hook/helper functions. Warnings are recorded; they are not proof of runtime correctness.

These findings are intentionally documented rather than silently changing the upstream hook semantics during this maintenance pass. The current work adds management and backup tooling, not new identifier-rewriting behavior.

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


## Follow-up hardening (2026-11-26)
- Tightened the app-container backup verifier: the manifest must contain exactly one valid lowercase 64-character SHA-256 field and exactly one matching archive filename field.
- The verifier rejects archive/manifest symlink inputs and refuses to proceed if the backup root itself is a symlink.
- Verification remains non-destructive: it checks the checksum and tar readability only. It does not extract archives or establish restore safety.
- Manager/Core integration remains unimplemented in this change. The legacy Core is a separate component and its profile store is not consumed by the Alpha11 tweak; connecting the manager to it without a supported, packaged, authenticated helper would create a misleading "connected" state.


## Six outstanding workstreams — progress checkpoint (2026-11-26)

1. **App-container restore:** not implemented yet. The current archive is verified but has not been proven safe to extract into a live iOS container. Restore remains blocked on path/link validation, app-process quiescence, ownership/permission preservation, pre-restore snapshot, and rollback tests.
2. **Deep cleanup:** not implemented. The current project does not claim a factory-reset-equivalent result. A cleanup design must distinguish the app data container from App Groups, Keychain, caches owned by other services, and server-side state.
3. **Keychain handling:** no Keychain export, wipe, or restore is implemented. The app-container archive explicitly excludes Keychain. No credentials or tokens are read or printed.
4. **Manager/Core integration:** first implementation step added to the Alpha11 manager: a user-triggered, read-only GET to `127.0.0.1:18080/status`, with a three-second timeout and response-shape validation. The IPA build script adds the narrow `NSAllowsLocalNetworking` ATS setting. This only detects the legacy Core; it does not yet package/start it or prove end-to-end installation on-device.
5. **Per-app configuration:** not implemented. The legacy Core profile store is not consumed by the Alpha11 tweak. No profile is represented as active until there is an explicit, tested app-scoped configuration path. Runtime rewriting of hardware/account identifiers is not part of this integration step.
6. **Real-device validation:** not completed. CI syntax/package checks cannot validate injection, launch daemon startup, loopback reachability, data restore, or cleanup on an iPhone 12 running iOS 16.2. A device-side test run and logs are still required.

The manager/Core status probe is a concrete integration milestone, not a claim that the six workstreams are complete. Continue with separately testable changes and keep device-only checks marked pending until device evidence is available.


## Core packaging milestone (2026-11-26)

- Added an Alpha11-specific Rootless companion Core under `core/`, built from the existing local-diagnostics approach but isolated from the legacy profile-writing API.
- The new service exposes only GET endpoints (`/status`, `/system`, `/apps`), binds to loopback only, and uses port 18081 to avoid colliding with the legacy service on 18080.
- Added a Rootless Theos package, LaunchDaemon plist, install/uninstall scripts, and CI packaging checks. The workflow makes maintainer scripts executable before packaging and checks they remain executable in the DEB.
- The manager now validates the Alpha11 status response, including the explicit `read-only` mode marker. It does not create/select profiles or write hook configuration.
- This is still a build/integration milestone. It is not proof that launchd starts the service or that the TrollStore app can reach it on iOS 16.2; those checks remain pending on the physical device.
