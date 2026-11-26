#!/usr/bin/env python3
"""Static checks for the V2 read-only diagnostics companion project."""
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
errors, checks = [], []

def check(ok, message):
    (checks if ok else errors).append(message)

makefile = (ROOT / "Makefile").read_text()
control = (ROOT / "control").read_text()
manager = (ROOT / "manager/ModHWManager/ModHWManagerApp.swift").read_text()
project = (ROOT / "manager/ModHWManager.xcodeproj/project.pbxproj").read_text()
ipa = (ROOT / "scripts/build-trollstore-ipa.sh").read_text()
check("Version: 2.0.0~alpha11" in control, "Existing Alpha11 package metadata retained")
check("THEOS_PACKAGE_SCHEME = rootless" in makefile, "Rootless Theos package scheme")
check((ROOT / "src/captain_hook/hook.mm").is_file() and "src/captain_hook/hook.mm" not in makefile,
      "Optional cloud hook source retained but excluded from Rootless build")
check("-fno-objc-arc" in makefile, "Manual-reference-counted build flag retained")
check("CURRENT_PROJECT_VERSION = 8;" in project, "Manager build number is 8")
check("fileImporter" in manager and "fileExporter" in manager, "Manager imports and exports plist files")
check("PropertyListSerialization.propertyList" in manager, "Manager parses plist structure")
check("字段值未展示" in manager, "Manager does not display plist values")
check("RawPlistDocument" in manager and "regularFileWithContents: data" in manager,
      "Manager exports original bytes unchanged")
check("TextField(" not in manager and "Toggle(" not in manager,
      "Manager has no configuration identity editing controls")
check("ARCHS=arm64" in ipa and "unzip -t" in ipa, "IPA build targets arm64 and verifies archive")
filter_path = ROOT / "layout/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist"
if filter_path.is_file():
    try:
        filter_data = plistlib.loads(filter_path.read_bytes())
        filter_root = filter_data.get("Filter", {})
        executables = filter_root.get("Executables", [])
        bundles = filter_root.get("Bundles", [])
        check(executables == ["SpringBoard"] and bundles == ["com.apple.Preferences"],
              "Tweak injection limited to SpringBoard and Settings; cloud daemons excluded")
    except Exception as exc:
        errors.append("Invalid tweak injection filter: " + str(exc))

hook_util = (ROOT / "src/cydia_substrate_hook/HookUtil.m").read_text()
check('dlopen("/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"' in hook_util,
      "Substrate helper still uses the legacy absolute framework path; Rootless resolution remains unverified")
check("method_setImplementation(class_getInstanceMethod(cls, sel), hook)" in hook_util,
      "HookMessage fallback implementation is present and requires class/selector availability")

source = (ROOT / "src/mobile_gestalt/mobile_gestalt.m").read_text()
constructor_start = source.find("__attribute__((__constructor__))")
constructor = source[constructor_start:] if constructor_start >= 0 else ""
mobile_gestalt_hooker_start = source.find("void MobileGestaltHooker()")
mobile_gestalt_hooker_end = source.find("\n}", mobile_gestalt_hooker_start)
mobile_gestalt_hooker = source[mobile_gestalt_hooker_start:mobile_gestalt_hooker_end] if mobile_gestalt_hooker_start >= 0 and mobile_gestalt_hooker_end >= 0 else ""
check("MobileGestaltHooker();" in constructor and "HookerForMGCopyAnswer();" in mobile_gestalt_hooker,
      "Constructor reaches the MobileGestalt answer hook through MobileGestaltHooker")
check("hook_sysctlbyname();" in constructor and "hook_sysctl();" not in constructor,
      "Constructor registers sysctlbyname but not the separate sysctl hook")
check("// HookerForMGCopyMultipleAnswers();" in source,
      "MGCopyMultipleAnswers registration remains explicitly inactive")
sysctl_body = source[source.find("int replace_sysctl("):source.find("static void hook_sysctl()")]
check("NSLog(" in sysctl_body and "orig_sysctl(name" in sysctl_body,
      "Separate sysctl replacement currently delegates and logs; no configured replacement")
check((ROOT / "ALPHA11_RUNTIME_AUDIT.md").is_file(),
      "Runtime source audit report is present")
check("src/captain_hook/hook.mm" not in makefile,
      "CaptainHook response module remains excluded from package source list")

diagnostic = ROOT / "scripts/diagnose-config.sh"
check(diagnostic.is_file(), "Read-only device diagnostic exists")
if diagnostic.is_file():
    diag = diagnostic.read_text()
    check("plutil -lint" in diag, "Device diagnostic validates plist syntax")
    check("UniqueDeviceID" not in diag, "Device diagnostic does not inspect identity fields")

for rel in [
    "src/mobile_gestalt/mobile_gestalt.m",
    "src/cydia_substrate_hook/HookUtil.m",
    "src/captain_hook/hook.mm",
    "control",
    "layout/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist",
    "layout/usr/share/mod_hw_for_ios/com.modhw.ios.devices.plist.example",
    "manager/ModHWManager.xcodeproj/xcshareddata/xcschemes/ModHWManager.xcscheme",
]:
    check((ROOT / rel).is_file(), "Required file: " + rel)

for path in ROOT.rglob("*.plist"):
    if any(part in {".git", ".theos"} for part in path.parts):
        continue
    try:
        plistlib.loads(path.read_bytes())
        checks.append("Valid plist: " + str(path.relative_to(ROOT)))
    except Exception as exc:
        errors.append("Invalid plist " + str(path.relative_to(ROOT)) + ": " + str(exc))

print("Static checks: %d passed, %d failed" % (len(checks), len(errors)))
for item in checks:
    print("[OK]", item)
for item in errors:
    print("[FAIL]", item)
sys.exit(1 if errors else 0)
