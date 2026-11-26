# Alpha11 source compatibility audit

Audited source: `mod_hw_for_ios_V2_alpha11`.

## Build composition

- The original Makefile compiles `src/mobile_gestalt/mobile_gestalt.m` and `src/cydia_substrate_hook/HookUtil.m`.
- `src/captain_hook/hook.mm` exists but is not part of the Makefile source list.
- The installed filter declares only `SpringBoard` and `com.apple.Preferences`; it is not a per-third-party-app filter generator.
- The Alpha11 runtime tweak is not part of the iDeviceLab Manager / Rootless Core release workflow. This project therefore does not claim that Alpha11 is installed or active.

## Source call graph observations

- The constructor calls `initPrefFile()`, `initGlobalSysCtl()`, `MobileGestaltHooker()`, `hook_sysctlbyname()`, `CTMobileEquipmentInfo_setIMEI()`, `CTMobileEquipmentInfo_setMEID()`, `HOOK_IDFA()`, and `HOOK_IDFV()`.
- `MobileGestaltHooker()` calls `HookerForMGCopyAnswer()`; its `HookerForMGCopyMultipleAnswers()` call is commented out.
- `hook_sysctl()` is defined, but the constructor does not call it. `replace_sysctl()` delegates to the original implementation and logs selected keys; it does not provide a configured replacement.
- CoreTelephony setter hooks and IDFA / IDFV hooks are present in source and registered from the constructor, but source presence is not runtime evidence.
- IOKit wrappers use the source's `HOOK_FUNCTION` macro, which generates constructor-time registration when the tweak library is loaded. The filter still limits eligible processes to its declared targets, and runtime loading / behavior are not verified by the Manager.

## Manager capability boundary

- The Manager can inspect tweak and filter file presence, parse the filter, list declared targets, and report library size.
- The Manager can synchronize the explicitly allowlisted local plist fields and inspect the local plist schema.
- App-to-profile binding is Manager metadata. It does not configure a third-party process, prove injection, or prove that a target process reads a plist.
- `runtimeInjectionVerified` intentionally remains false until separate device-side process-level verification is implemented and observed.

## Acceptance evidence still required

A successful CI build proves compilation and packaging only. Device acceptance must separately confirm package installation, LaunchDaemon state, loopback API health, Manager installation, and observed process-level Hook loading. No device acceptance is implied by this static audit.
