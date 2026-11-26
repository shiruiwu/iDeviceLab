# Alpha11 Runtime Source Audit

Audit target: `device-manager-pro-full` at the current source revision.
Scope: static source and packaging inspection only. This report does not claim device-side runtime behavior.

## Executive result

The upstream Alpha11 implementation is retained, but the current installable deliverables do not include a verified runtime tweak. The manager app is a plist inspection/import/export companion; it does not expose a profile editor or prove that a third-party process has loaded a tweak.

## Source-to-build trace

| Area | Source evidence | Build / activation state |
|---|---|---|
| Configuration load | `mobile_gestalt.m:initPrefFile()` reads the shared mobile preference path and has a legacy `/tmp/devices.plist` fallback | Constructor calls the loader; no device-side test recorded |
| MobileGestalt | `HookerForMGCopyAnswer()` resolves `MGCopyAnswer`; `DeviceDataFilter()` maps configured keys | Constructor calls the hooker; actual symbol resolution and process load unverified |
| IOKit | `IORegistryEntrySearchCFProperty` and `IORegistryEntryCreateCFProperty` wrappers are declared through `HOOK_IOKIT` | Compile-time hook declarations present; runtime unverified |
| Multiple MobileGestalt answers | `MGCopyMultipleAnswers` implementation exists | Registration call is commented out |
| `sysctlbyname` | replacement function handles `hw.model` and `hw.machine` | Constructor calls registration function; runtime unverified |
| `sysctl` | replacement and registration functions exist | Constructor does not call `hook_sysctl()`; function currently logs selected queries rather than returning replacement values |
| CoreTelephony | late class hooks for IMEI/MEID setters exist | Constructor calls registration functions; class availability and runtime behavior unverified |
| IDFA / IDFV | method-hook functions exist | Constructor calls registration functions; runtime behavior unverified |
| CaptainHook response module | `src/captain_hook/hook.mm` retained | Excluded from the current Makefile source list and current package recipe |
| Injection filter | Filter targets SpringBoard and Preferences only | Does not establish loading into arbitrary third-party apps |

## Packaging findings

- The Rootless Theos Makefile currently compiles `src/mobile_gestalt/mobile_gestalt.m` and `src/cydia_substrate_hook/HookUtil.m`.
- `src/captain_hook/hook.mm` is not included in that source list.
- The normal delivery workflow currently builds the manager IPA and read-only diagnostics DEB. It does not produce a runtime Alpha11 tweak package.
- The standalone Alpha11 audit workflow is intentionally static-only and does not build or upload a runtime tweak.
- The Filter plist lists `SpringBoard` and `com.apple.Preferences`; this is not a per-third-party-app deployment matrix.

## Hook utility and Rootless compatibility review

- `HookUtil.m` resolves the Substrate entry points dynamically with `dlsym`, but it currently opens the literal path `/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate`.
- That is a legacy absolute framework path. The repository does not contain a device-side proof that this path resolves under the intended Rootless bootstrap on iOS 16.2. The Theos package scheme and `-lsubstrate` link flag do not, by themselves, prove that this runtime `dlopen` succeeds.
- The `_HookMessage` fallback calls `method_setImplementation(class_getInstanceMethod(cls, sel), hook)` without first checking that the class and method exist. If the late-loaded class or selector is unavailable, this fallback is unsafe.
- These are compatibility and crash-risk findings, not evidence that the tweak loaded. They must remain explicit in the runtime checklist; no Rootless path rewrite should be claimed successful without validating it against the actual bootstrap and package environment.

## Manager capability boundary

The current SwiftUI manager imports a plist, parses/validates its structure, displays diagnostic metadata, and exports the original bytes. It does not provide editable identity fields. Import/export success only confirms file handling; it does not confirm that a tweak consumed the file.

## Required verification before any runtime claim

1. Build reproducibility against the intended Rootless Theos / iOS SDK toolchain.
2. Package inspection: dylib architecture, install paths, dependency metadata, Filter plist and file permissions.
3. On-device installation and bootstrap compatibility on the stated iPhone 12 / iOS 16.2 target.
4. Read-only process diagnostics showing whether the library is loaded in the intended process, without treating file presence as proof.
5. Crash/log review and rollback verification.

## Known source-level caveats

- `MGCopyMultipleAnswers` hook registration is commented out.
- `hook_sysctl()` is not invoked by the constructor.
- `replace_sysctl()` currently calls the original function and logs selected hardware queries; it does not provide configured replacements.
- `HookUtil.m` uses a hard-coded legacy CydiaSubstrate framework path; Rootless resolution is unverified.
- The `_HookMessage` fallback does not guard a missing Objective-C class or selector before calling `method_setImplementation`.
- The legacy README describes editing/deployment capabilities that do not match the current read-only manager and current CI outputs. The project documentation should follow the actual implementation.
- Static checks and successful IPA/diagnostics-DEB builds are not substitutes for the runtime test matrix above.
