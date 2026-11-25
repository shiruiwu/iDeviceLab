#!/usr/bin/env python3
from pathlib import Path
import plistlib
import sys
root = Path(__file__).resolve().parents[1]
errors, checks = [], []
def check(ok, message):
    (checks if ok else errors).append(message)
makefile = (root / "Makefile").read_text()
control = (root / "control").read_text()
manager = (root / "manager/ModHWManager/ModHWManagerApp.swift").read_text()
project = (root / "manager/ModHWManager.xcodeproj/project.pbxproj").read_text()
ipa = (root / "scripts/build-trollstore-ipa.sh").read_text()
check("Version: 2.0.0~alpha11" in control, "Alpha11 package metadata")
check("THEOS_PACKAGE_SCHEME = rootless" in makefile, "Rootless Theos package")
check("src/captain_hook/hook.mm" in makefile, "CaptainHook source included")
check("-fno-objc-arc" in makefile, "Manual-reference-counted source flags")
check("CURRENT_PROJECT_VERSION = 7;" in project, "Manager build number")
check("fileImporter" in manager and "fileExporter" in manager, "Manager plist import/export")
check("extraValues = dictionary.filter" in manager, "Manager preserves unknown plist keys")
check("ARCHS=arm64" in ipa and "unzip -t" in ipa, "arm64 IPA and archive checks")
for rel in ["src/mobile_gestalt/mobile_gestalt.m", "src/cydia_substrate_hook/HookUtil.m",
            "src/captain_hook/hook.mm", "control",
            "layout/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist",
            "layout/usr/share/mod_hw_for_ios/com.modhw.ios.devices.plist.example"]:
    check((root / rel).is_file(), "Required file: " + rel)
for path in root.rglob("*.plist"):
    try:
        plistlib.loads(path.read_bytes())
        checks.append("Valid plist: " + str(path.relative_to(root)))
    except Exception as exc:
        errors.append("Invalid plist " + str(path.relative_to(root)) + ": " + str(exc))
print("Static checks: %d passed, %d failed" % (len(checks), len(errors)))
for item in errors:
    print("[FAIL]", item)
sys.exit(1 if errors else 0)
