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

1. **App-container restore:** a guarded restore command is now implemented. It requires explicit `--confirm`, checks the bundle/container identity, requires the app process to be stopped, validates tar paths and rejects links/special files, extracts to staging, snapshots the live container, and attempts rollback on copy/metadata failure. Device-side execution and rollback fault-injection tests remain pending.
2. **Deep cleanup:** a backup-first `mod-hw-app-clean` command now clears the selected app's local data container after verifying an automatic backup and preserving a rollback snapshot. This is a scoped local-data reset only, not factory-reset equivalence; Keychain, App Groups, shared/system stores, and server-side state remain untouched.
3. **Keychain handling:** no Keychain export, wipe, or restore is implemented. The app-container archive explicitly excludes Keychain. No credentials or tokens are read or printed.
4. **Manager/Core integration:** first implementation step added to the Alpha11 manager: a user-triggered, read-only GET to `127.0.0.1:18080/status`, with a three-second timeout and response-shape validation. The IPA build script adds the narrow `NSAllowsLocalNetworking` ATS setting. This only detects the legacy Core; it does not yet package/start it or prove end-to-end installation on-device.
5. **Per-app configuration:** the manager now reads an installed-App inventory (name, Bundle ID, version) from the read-only Core, providing reliable per-app targets for backup/restore/cleanup. Independent per-app Hook configuration and proof that the tweak consumes it are still not implemented; the inventory is not an active profile.
6. **Real-device validation:** a non-destructive `mod-hw-selftest` command is now included in the diagnostics package plan. It checks Rootless paths, Core launchd state, helper commands, and loopback status when curl is available. It has not yet been run on the iPhone 12 / iOS 16.2; hook injection and restore behavior still require device logs and tests.

The manager/Core status probe is a concrete integration milestone, not a claim that the six workstreams are complete. Continue with separately testable changes and keep device-only checks marked pending until device evidence is available.


## Core packaging milestone (2026-11-26)

- Added an Alpha11-specific Rootless companion Core under `core/`, built from the existing local-diagnostics approach but isolated from the legacy profile-writing API.
- The new service exposes only GET endpoints (`/status`, `/system`, `/apps`), binds to loopback only, and uses port 18081 to avoid colliding with the legacy service on 18080.
- Added a Rootless Theos package, LaunchDaemon plist, install/uninstall scripts, and CI packaging checks. The workflow makes maintainer scripts executable before packaging and checks they remain executable in the DEB.
- The manager now validates the Alpha11 status response, including the explicit `read-only` mode marker. It does not create/select profiles or write hook configuration.
- This is still a build/integration milestone. It is not proof that launchd starts the service or that the TrollStore app can reach it on iOS 16.2; those checks remain pending on the physical device.


## App restore and device smoke-test milestone (2026-11-26)

- Added `scripts/restore-app-container.sh` and packaged it as `mod-hw-app-restore`.
- Restore is opt-in with `--confirm`; it refuses a mismatched bundle/container ID, refuses a running app, rejects absolute/traversal paths and archive entries other than regular files/directories, stages extraction, and snapshots the current container before replacement.
- The restore command excludes Keychain, App Groups, shared containers, system databases, and server-side state. It is not a "factory reset" and does not claim to remove every app trace.
- Added `scripts/selftest-device.sh`, packaged as `mod-hw-selftest`, for non-destructive on-device checks.
- Diagnostics package version advanced to `2.0.0~final6`; package now declares `coreutils, procps`.
- Static validation and CI packaging are pending for the current HEAD. No physical-device result is claimed.


## Scoped local cleanup milestone (2026-11-26)

- Added `scripts/cleanup-app-container.sh`, packaged as `mod-hw-app-clean`.
- It requires explicit `--confirm`, verifies the target app is not running, creates and verifies an app-container backup, snapshots the current container, and clears only the container's contents while retaining the MCM metadata marker.
- It rolls back from the snapshot if the operation or metadata validation fails.
- Keychain, App Groups, shared containers, system databases, notification services, and server-side state are outside its scope. This is not a full deep-clean / fresh-flash equivalent.
- Device-side destructive-operation tests and rollback fault-injection remain pending.


## Per-app target inventory milestone (2026-11-26)

- Added a manager view that retrieves installed App names, Bundle IDs, and versions through Core `GET /apps`.
- This gives the maintenance tools a concrete Bundle ID selection source. It is read-only and does not claim per-app device profile or Hook isolation is complete.


## Configuration parser hardening (2026-11-26)

- Hardened the original MobileGestalt configuration parsing helpers without changing their Hook targets or adding new identifier rewriting behavior.
- MAC-address hex input now requires exactly 12 hexadecimal characters; malformed input returns no data instead of being partially decoded.
- UDID hex input now requires exactly 40 hexadecimal characters and is checked before CFData access; invalid values cause the loaded configuration to be discarded.
- Plist flags controlling binary-data interpretation are accepted only when the stored value is an actual Boolean, not an arbitrary string or number.
- The generic hex decoder now rejects null, empty, odd-length, non-hex, and over-capacity input before reading bytes.
- Corrected a string-count helper to inspect each character rather than repeatedly inspecting the first character.
- Added static regression assertions for these guards. Compilation and on-device config-load behavior still require the latest CI build and iPhone 12 / iOS 16.2 verification.


## Consolidated status correction (2026-11-26, latest Alpha11 branch review)

This section supersedes any earlier checkpoint above where the same feature is described as not yet implemented. Earlier checkpoint text is retained as historical progress.

| Workstream | Current source state | Still required before delivery |
|---|---|---|
| App-container backup | Implemented: one Bundle ID, unique MCM container match, private archive, SHA-256 manifest | Device backup/restore round-trip |
| App-container restore | Implemented: manifest verification, Bundle ID + container ID match, stopped-process check, path/type checks, staging, pre-restore snapshot, rollback attempts | Fault-injection and iOS 16.2 runtime validation |
| App local-data cleanup | Implemented: backup + verifier + same-container snapshot before clearing contents; retains MCM metadata and attempts rollback | Device validation; verify process matching and ownership/metadata behavior |
| Keychain | Not implemented | Determine supported app-scoped behavior and platform constraints; no blanket keychain wipe is claimed |
| Manager ↔ Alpha11 Core | Source integration implemented: manager calls GET /status and GET /apps on 127.0.0.1:18081; Core is packaged as a Rootless LaunchDaemon | IPA/DEB install and localhost reachability test on target device |
| Per-app Hook profiles | Not implemented. Manager currently displays installed-app inventory only; the original tweak still loads one global preference plist | Define and implement a per-app configuration schema and demonstrate actual process-scoped consumption |
| Device validation | Self-test command exists and is packaged by the diagnostics builder | Run on iPhone 12 / iOS 16.2; capture launchd, injection, config-load and backup/restore evidence |

### Latest source review notes

- Alpha11 Core exposes read-only GET /status, /system, and /apps endpoints and binds to loopback port 18081.
- The manager validates the Core status response and renders the installed-app inventory. It does not yet edit or apply profiles.
- The original tweak's preference loader still reads the global com.modhw.ios.devices.plist path (with a legacy fallback); no per-bundle profile lookup is present in the reviewed source.
- The cleanup and restore scripts are source-implemented but have not been executed on the target device. Their rollback paths are not a substitute for fault-injection testing.
- The latest observed Theos and IPA Actions runs were pending/queued or in progress during this source review; check the branch's Actions page for their final conclusion before treating the latest source revision as built.

## Per-app Hook profile resolution — source implementation

- The original MobileGestalt configuration loader now resolves the current process Bundle ID and checks `/var/mobile/Library/Preferences/com.modhw.ios.profiles/<Bundle-ID>.plist` first.
- If no valid per-app path is present, it preserves compatibility by falling back to the global `com.modhw.ios.devices.plist`, then the legacy `/tmp/devices.plist`.
- Bundle IDs are restricted to alphanumeric characters, dot, underscore, and hyphen; leading dots, trailing dots, and consecutive dots are rejected before constructing the profile path.
- The tweak logs only which source class was selected (per-app/global/legacy), not profile contents.
- The selected plist is read during tweak initialization. This is not hot reload; restart the target process after changing its profile.
- Static regression checks now assert that per-app lookup precedes global/legacy fallback. Build and target-device process-isolation tests are pending.
- The manager still does not have a privileged profile-write API. Profile files must currently be placed in the Rootless preference directory through an authorized device file-management workflow.

## Manager per-app export flow — source implementation

- The manager now offers a Bundle ID picker populated from the Core `GET /apps` inventory.
- After importing a plist, the user can export a copy using the selected Bundle ID as the filename. The output is intended for the matching file under `com.modhw.ios.profiles`.
- The manager does not write directly into the jailbreak preference directory. Moving the exported file into place remains an explicit device file-management step.
- The static validator checks that the selection/export controls and profile directory reference remain present.
- The per-app loader and manager export are source-level milestones; the IPA/DEB build and iPhone 12 / iOS 16.2 process-isolation test are still required.
