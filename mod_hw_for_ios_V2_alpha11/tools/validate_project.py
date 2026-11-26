#!/usr/bin/env python3
"""Static checks for the Alpha11 tweak, manager, and config utility package."""
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
package_builder = (ROOT / "scripts/build-diagnostics-deb.sh").read_text()

check("Version: 2.0.0~alpha11" in control, "Existing Alpha11 tweak package metadata retained")
check("THEOS_PACKAGE_SCHEME = rootless" in makefile, "Rootless Theos package scheme")
check("src/captain_hook/hook.mm" in makefile, "Original hook source remains in target")
check("-fno-objc-arc" in makefile, "Manual-reference-counted build flag retained")
check("CURRENT_PROJECT_VERSION = 8;" in project, "Manager build number is 8")
check("fileImporter" in manager and "fileExporter" in manager, "Manager imports and exports plist files")
check("PropertyListSerialization.propertyList" in manager, "Manager parses plist structure")
check("字段值未展示" in manager, "Manager does not display plist values")
check("RawPlistDocument" in manager and "regularFileWithContents: data" in manager,
      "Manager exports original bytes unchanged")
check("ARCHS=arm64" in ipa and "unzip -t" in ipa, "IPA build targets arm64 and verifies archive")

diagnostic = ROOT / "scripts/diagnose-config.sh"
backup = ROOT / "scripts/backup-config.sh"
restore = ROOT / "scripts/restore-config.sh"
app_backup = ROOT / "scripts/backup-app-container.sh"
app_verify = ROOT / "scripts/verify-app-container-backup.sh"
for path, label in [
    (diagnostic, "Read-only config diagnostic"),
    (backup, "Timestamped config backup"),
    (restore, "Validated config restore with rollback snapshot"),
    (app_backup, "Scoped app-container backup"),
    (app_verify, "App-container backup integrity verifier"),
]:
    check(path.is_file(), label + " script exists")

if diagnostic.is_file():
    diag = diagnostic.read_text()
    check("plutil -lint" in diag, "Device diagnostic validates plist syntax")
    check("UniqueDeviceID" not in diag, "Device diagnostic does not print or inspect identifier values")
if backup.is_file():
    src = backup.read_text()
    check("cmp -s" in src and "plutil -lint" in src, "Backup verifies byte equality and plist validity")
if restore.is_file():
    src = restore.read_text()
    check("plutil -lint" in src and "rollback-snapshots" in src and "mv -f" in src,
          "Restore validates backup, preserves pre-restore snapshot, and replaces atomically")

if app_backup.is_file():
    src = app_backup.read_text()
    check("MCMMetadataIdentifier" in src and "tar -czpf" in src and "sha256sum" in src,
          "App-container backup selects one bundle ID, archives data, and records SHA-256")
    check("Keychain" in src and "App Groups" in src,
          "App-container backup documents excluded system-managed stores")
if app_verify.is_file():
    src = app_verify.read_text()
    check("sha256sum" in src and "tar -tzf" in src and "BACKUP_ROOT" in src,
          "App-container verifier checks checksum and archive readability in backup directory")
    check("length($2) != 64" in src and "[ ! -L \"$ARCHIVE\" ]" in src and
          "[ ! -L \"$MANIFEST\" ]" in src and "sha_count != 1" in src,
          "App-container verifier rejects malformed/duplicate manifests and symlink inputs")

check('mod-hw-config-backup' in package_builder and 'mod-hw-config-restore' in package_builder,
      "Rootless utility DEB packages config backup and restore commands")
check('mod-hw-app-backup' in package_builder and 'mod-hw-app-backup-verify' in package_builder,
      "Rootless utility DEB packages app-container backup and verification commands")
check("Depends: coreutils" in package_builder, "Backup tooling declares its SHA-256 utility dependency")

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
