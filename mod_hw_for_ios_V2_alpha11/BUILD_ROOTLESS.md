# mod_hw_for_ios V2 — Rootless source and companion

This directory retains the upstream Alpha11 Objective-C/Objective-C++ source. The current standard release workflow builds the iDeviceLab manager IPA and the read-only diagnostics DEB; it does **not** build or ship the Alpha11 runtime tweak.

## Source build recipe

The Theos Makefile describes a Rootless arm64 tweak build:

```sh
export THEOS="$HOME/theos"
make clean package
```

This recipe is source/build metadata, not a claim that the package has been validated on a device. The current manual Alpha11 workflow runs static checks only and does not upload a runtime tweak package.

## Configuration path

The retained upstream loader references:

```
/var/mobile/Library/Preferences/com.modhw.ios.devices.plist
```

It keeps `/tmp/devices.plist` as a legacy fallback. The manager companion currently imports a plist, validates its structure, displays limited diagnostics, and exports the original bytes. It is not an identity-profile editor, and successful file import/export does not prove runtime consumption by a tweak.

## Runtime audit

See [ALPHA11_RUNTIME_AUDIT.md](ALPHA11_RUNTIME_AUDIT.md) for the source-to-build trace, inactive hook registrations, Filter scope, package boundaries, and verification requirements.

## Hook utility compatibility notes

The retained `HookUtil.m` currently resolves CydiaSubstrate through the legacy absolute path `/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate`. Its availability under the target Rootless bootstrap has not been demonstrated. The Objective-C message-hook fallback also assumes the requested class and selector exist before calling `method_setImplementation`. See `ALPHA11_RUNTIME_AUDIT.md`; these are unresolved runtime compatibility risks, not successful runtime verification.

## Validation

Run:

```sh
python3 tools/validate_project.py
```

Static checks validate repository structure and plist syntax. They do not prove a Theos runtime build, injection, API compatibility, or behavior on iPhone 12 / iOS 16.2.
