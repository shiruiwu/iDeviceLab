# mod_hw_for_ios V2 Alpha11

## Current delivery status

The original Alpha11 source tree is retained for inspection. The standard iDeviceLab CI artifacts are the manager IPA and read-only diagnostics DEB. They do not contain a verified runtime Alpha11 tweak package.

The companion manager currently supports plist import, structural validation/inspection, and original-byte export. It does not edit hardware identity values and does not prove that a runtime tweak has loaded or consumed the imported file.

## Source modules retained

- `src/mobile_gestalt/mobile_gestalt.m`: MobileGestalt, IOKit, sysctlbyname, CoreTelephony and identifier API hook source.
- `src/cydia_substrate_hook/`: Substrate hook wrappers.
- `src/captain_hook/hook.mm`: optional CaptainHook response-hook source retained for source audit; excluded from the current Rootless Makefile.
- `src/third_party/`: upstream supporting headers and dependencies.
- `frida/`: upstream instrumentation scripts retained as source material.

## Important source audit findings

- `MGCopyMultipleAnswers` has an implementation, but its registration call is commented out.
- `hook_sysctl()` is not called by the constructor; its current replacement logs selected queries and delegates to the original implementation.
- The current Filter plist targets SpringBoard and Preferences only.
- The existence of hook source or a configured Filter does not establish successful injection into a process.

See [ALPHA11_RUNTIME_AUDIT.md](ALPHA11_RUNTIME_AUDIT.md) for the full source-to-build trace and outstanding verification matrix.

## Rootless source build metadata

The Theos Makefile describes an arm64 Rootless tweak recipe. The manual Alpha11 CI workflow is a static audit workflow and does not build or upload a runtime tweak package. A source recipe must not be confused with a tested installable release.

See [BUILD_ROOTLESS.md](BUILD_ROOTLESS.md) for the build metadata and configuration-path notes.
