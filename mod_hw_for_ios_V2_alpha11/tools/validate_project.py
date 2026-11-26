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
gestalt_source = (ROOT / "src/mobile_gestalt/mobile_gestalt.m").read_text()
project = (ROOT / "manager/ModHWManager.xcodeproj/project.pbxproj").read_text()
ipa = (ROOT / "scripts/build-trollstore-ipa.sh").read_text()
package_builder = (ROOT / "scripts/build-diagnostics-deb.sh").read_text()
core_package_builder_path = ROOT / "scripts/build-core-deb.sh"
core_package_builder = core_package_builder_path.read_text() if core_package_builder_path.is_file() else ""
core_source = ROOT / "core/main.m"
core_makefile = ROOT / "core/Makefile"
core_control = ROOT / "core/control"
core_control_text = core_control.read_text() if core_control.is_file() else ""
core_daemon = ROOT / "core/layout/Library/LaunchDaemons/com.idevelab.core.alpha11.plist"
if core_daemon.is_file():
    daemon = plistlib.loads(core_daemon.read_bytes())
    check(daemon.get("Label") == "com.idevelab.core.alpha11", "Alpha11 launchd plist uses a valid service label")
    check(daemon.get("ProgramArguments") == ["/var/jb/usr/libexec/idevelab-core"], "Alpha11 launchd starts the packaged Rootless Core binary")
    check(daemon.get("UserName") == "mobile" and daemon.get("GroupName") == "mobile", "Alpha11 Core runs as the unprivileged mobile user")

check("Version: 2.0.0~alpha11" in control, "Existing Alpha11 tweak package metadata retained")
check("THEOS_PACKAGE_SCHEME = rootless" in makefile, "Rootless Theos package scheme")
check("src/captain_hook/hook.mm" in makefile, "Original hook source remains in target")
hook_filter_path = ROOT / "layout/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist"
hook_filter = plistlib.loads(hook_filter_path.read_bytes())
hook_filter_config = hook_filter.get("Filter", {})
check(hook_filter_config.get("Mode") == "Any" and "com.apple.UIKit" in hook_filter_config.get("Bundles", []),
      "Substrate filter loads the Hook in UIKit apps while retaining explicit daemon targets")
check("IsHexStringOfLength(str, 12)" in gestalt_source and "IsHexStringOfLength(hex, 40)" in gestalt_source,
      "Hardware-address and UDID hex inputs require exact lengths and hexadecimal characters")
check(gestalt_source.count("if (data != nil) return CFDataCreate(NULL, [data bytes],[data length]);") == 6,
      "All six IOKit hardware-data conversions preserve the original value when hex parsing fails")
check("PreferenceBooleanIsTrue" in gestalt_source and "a == NULL" in gestalt_source,
      "Malformed plist booleans and invalid UDID bytes are rejected before use")
check('com.modhw.ios.profiles' in gestalt_source and 'bundleIdentifier' in gestalt_source and
      'rangeOfCharacterFromSet:invalidBundleChars' in gestalt_source and
      'per-app profile' in gestalt_source and 'global profile' in gestalt_source and
      'legacy fallback' in gestalt_source,
      "Original Hook selects a validated Bundle-ID-scoped profile before global and legacy fallback")
check('if (cf_device == nil || [cf_device count] == 0)' in gestalt_source and
      'skipping Hook installation' in gestalt_source,
      "Hook installation is skipped when the current process has no valid profile")
check("length == 0" in gestalt_source and "(length % 2) != 0" in gestalt_source and "index / 2" in gestalt_source,
      "Generic hex decoder rejects null, odd-length, invalid, and oversized input")
check("-fno-objc-arc" in makefile, "Manual-reference-counted build flag retained")
check("CURRENT_PROJECT_VERSION = 8;" in project, "Manager build number is 8")
check("fileImporter" in manager and "fileExporter" in manager, "Manager imports and exports plist files")
check("TabView" in manager and "设备总览" in manager and "配置管理" in manager and
      "备份与维护" in manager and "设备诊断" in manager,
      "Manager exposes the integrated dashboard, profiles, maintenance, and diagnostics navigation")
check("mod-hw-app-backup" in manager and "mod-hw-app-backup-verify" in manager and
      "mod-hw-app-restore" in manager and "mod-hw-app-clean" in manager,
      "Manager generates a target-specific maintenance command set without claiming in-app execution")
check("UIPasteboard.general.string = command" in manager,
      "Manager maintenance commands can be copied for execution in the jailbreak terminal")
check('Picker("已安装 App", selection: $maintenanceBundleID)' in manager and
      'TextField("Bundle ID' in manager and 'safeShellArgument(maintenanceBundleID)' in manager and
      'safeShellArgument(maintenanceArchiveName)' in manager,
      "Manager maintenance commands are parameterized by a selected or manually entered App and quoted archive name")
check("safeShellArgument" in manager and "replacingOccurrences" in manager and "请填写" in manager,
      "Manager safely quotes shell arguments and marks blank placeholders")

check("selectedProfileBundleID" in manager and "导出为所选 App 的独立配置" in manager and
      "com.modhw.ios.profiles" in manager and "exportAsPerAppProfile" in manager,
      "Manager can export the imported plist under a selected installed App's Bundle ID")
check("canExportPerAppProfile" in manager and '"UniqueDeviceID"' in manager and
      "udid.count == 40" in manager and "normalized.count == 12" in manager,
      "Manager validates the Hook-required UDID and enabled MAC address fields before per-app export")
check("PropertyListSerialization.propertyList" in manager, "Manager parses plist structure")
check("字段值未展示" in manager, "Manager does not display plist values")
check('http://127.0.0.1:18081/status' in manager and 'http://127.0.0.1:18081/apps' in manager and 'request.httpMethod = "GET"' in manager and 'payload["mode"] as? String == "read-only"' in manager,
      "Manager validates the read-only Alpha11 Core status response")
check('import UIKit' in manager and 'UIPasteboard.general.string = command' in manager,
      "Manager explicitly imports UIKit for native command-copy support")
check('http://127.0.0.1:18081/system' in manager and 'fetchSystemSummary()' in manager and
      'DeviceSummary' in manager and 'diskFreeBytes' in manager,
      "Manager reads the Core system summary and displays device and storage information")
check('http://127.0.0.1:18081/tools' in manager and 'fetchMaintenanceTools()' in manager and
      'MaintenanceTool' in manager and '已安装' in manager and '缺失' in manager,
      "Manager displays the live installed state of jailbreak maintenance tools")
check('http://127.0.0.1:18081/profiles' in manager and 'fetchAppProfiles()' in manager and
      'AppProfile' in manager and '越狱端已安装配置' in manager and '格式有效' in manager,
      "Manager displays read-only per-app Hook profile inventory and plist validity")


check('NSAllowsLocalNetworking' in ipa and 'grep -q true' in ipa,
      "TrollStore IPA permits local-network ATS exception for loopback Core status")
check("RawPlistDocument" in manager and "regularFileWithContents: data" in manager,
      "Manager exports original bytes unchanged")
check("ARCHS=arm64" in ipa and "unzip -t" in ipa, "IPA build targets arm64 and verifies archive")
check(core_source.is_file() and core_makefile.is_file() and core_control.is_file() and core_daemon.is_file(),
      "Alpha11 read-only Core source and Rootless package files exist")
check(core_package_builder_path.is_file() and
      'xcrun --sdk iphoneos clang' in core_package_builder and
      'var/jb/usr/libexec/idevelab-core' in core_package_builder and
      'var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist' in core_package_builder and
      'core/layout/DEBIAN/postinst' in core_package_builder and
      'core/layout/DEBIAN/prerm' in core_package_builder and
      'idevelab-core-alpha11.deb' in core_package_builder,
      "Core builder compiles and packages the rootless daemon, launchd plist, and lifecycle hooks")
postinst = ROOT / "core/layout/DEBIAN/postinst"
prerm = ROOT / "core/layout/DEBIAN/prerm"
if postinst.is_file() and prerm.is_file():
    post = postinst.read_text()
    pre = prerm.read_text()
    check("/var/jb/usr/libexec/launchctl" in post and "/var/jb/basebin/launchctl" in post and
          'find /var/jb -name launchctl -perm -111' in post and
          'bootstrap system "$PLIST"' in post,
          "Core installer searches common rootless launchctl locations and reports startup failure without aborting package installation")
    check("/var/jb/usr/libexec/launchctl" in pre and 'find /var/jb -name launchctl -perm -111' in pre,
          "Core removal script can locate launchctl in extended rootless paths")

if core_source.is_file():
    core = core_source.read_text()
    check('@"GET"' in core and '@"POST"' not in core and 'read-only endpoint' in core,
          "Alpha11 Core exposes read-only HTTP methods only")
    check("INADDR_LOOPBACK" in core and "kPort = 18081" in core,
          "Alpha11 Core binds only to loopback port 18081")
    check('@"tools"' in core and 'InstalledMaintenanceTools' in core and
          'access(path.fileSystemRepresentation, X_OK)' in core and
          '[path isEqualToString:@"/tools"]' in core,
          "Alpha11 Core reports only the fixed allowlisted maintenance tool inventory")
    check('@"profiles"' in core and 'InstalledProfiles' in core and
          'com.modhw.ios.profiles' in core and '[path isEqualToString:@"/profiles"]' in core and
          'NSPropertyListSerialization' in core,
          "Alpha11 Core reports only filenames and plist validity for installed per-app profiles")


    check('@"version": @"0.2.0-alpha11"' in core,
          "Alpha11 Core status reports its own version")
    check('validHash' in core and 'invalidIdentity' in core and
          'HasSecureBackupMetadata' in core and
          '[attrs[NSFileSize] unsignedLongLongValue] == 0' in core,
          "Backup inventory rejects non-hex hashes, malformed identities, public manifest permissions, and empty archives")
    check('HasSecureBackupMetadata' in core and 'lstat(path.fileSystemRepresentation, &st)' in core and
          'getpwnam("mobile")' in core and '(st.st_mode & 07777) == expectedMode' in core and
          'st.st_gid == mobileGID' in core,
          "Backup inventory rejects symlinks and requires exact root:mobile ownership and 0750/0640 modes")
if core_control.is_file():
    check("Architecture: iphoneos-arm64" in core_control_text and "Version: 0.2.0~alpha11" in core_control_text,
          "Alpha11 Core package metadata targets Rootless arm64")

diagnostic = ROOT / "scripts/diagnose-config.sh"
backup = ROOT / "scripts/backup-config.sh"
restore = ROOT / "scripts/restore-config.sh"
app_backup = ROOT / "scripts/backup-app-container.sh"
app_restore = ROOT / "scripts/restore-app-container.sh"
app_cleanup = ROOT / "scripts/cleanup-app-container.sh"
app_verify = ROOT / "scripts/verify-app-container-backup.sh"
keychain_diag = ROOT / "scripts/diagnose-keychain-access.sh"
selftest = ROOT / "scripts/selftest-device.sh"
for path, label in [
    (diagnostic, "Read-only config diagnostic"),
    (backup, "Timestamped config backup"),
    (restore, "Validated config restore with rollback snapshot"),
    (app_backup, "Scoped app-container backup"),
    (app_restore, "Guarded app-container restore with rollback"),
    (app_cleanup, "Backup-first scoped app-container cleanup"),
    (app_verify, "App-container backup integrity verifier"),
    (keychain_diag, "Read-only signed Keychain entitlement diagnostic"),
    (selftest, "Non-destructive on-device self-test"),
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
    check('[ ! -L "$BACKUP_ROOT" ]' in src and 'BACKUP_OWNER="$(stat -f' in src and
          'chown root:mobile "$BACKUP_ROOT"' in src and 'chmod 0750 "$BACKUP_ROOT"' in src and
          'chmod 0640 "$TMP"' in src and 'chmod 0640 "$MANIFEST_TMP"' in src,
          "App-container backup keeps root-only writes while granting the mobile Core read-only inventory access")
    check('MANIFEST_TMP="$MANIFEST.tmp.$$"' in src and 'mv "$MANIFEST_TMP" "$MANIFEST"' in src and 'COMMITTED=1' in src,
          "App-container backup commits manifest last and removes incomplete archive pairs")
    check("trap 'cleanup_backup' EXIT" in src and "trap 'exit 130' INT" in src and "trap 'exit 143' TERM" in src,
          "App-container backup exits on signals so EXIT cleanup removes incomplete archive pairs")
if selftest.is_file():
    src = selftest.read_text()
    check("127.0.0.1:18081/status" in src and "mod-hw-app-backup-verify" in src and "mod-hw-app-clean" in src and "rm -rf" not in src,
          "On-device self-test checks Core and tools without destructive operations")
    check("/var/jb/basebin/launchctl" in src and "system/com.idevelab.core.alpha11" in src,
          "On-device self-test locates the Dopamine rootless launchctl binary")
    check("http://127.0.0.1:18081/backups" in src and '"backups":' in src and
          "Backup directory is root-owned and mobile-group traversable (0750)" in src and "Archive is root:mobile read-only (0640)" in src and "Manifest is root:mobile read-only (0640)" in src and
          "Core runs as mobile (unprivileged)" in src,
          "On-device self-test covers backup inventory endpoint and mobile-readable private backup storage")
if app_cleanup.is_file():
    src = app_cleanup.read_text()
    check("mod-hw-app-backup" in src and "mod-hw-app-backup-verify" in src and "cleanup-snapshots" in src and "--confirm" in src and "tar -tvzf" in src,
          "App cleanup creates and verifies a backup and rollback snapshot before clearing data")
    check('if killall -0 "$EXECUTABLE"' in src and '[ "$KILLALL_STATUS" -eq 1 ]' in src,
          "App cleanup distinguishes a stopped process from a system killall execution error")
    check('tar -tvzf "$ARCHIVE_PATH" > "$DETAIL_LIST"' in src and "END { exit bad }" in src,
          "App cleanup propagates archive-listing failures instead of masking them in a pipeline")
    check('mktemp "$BACKUP_ROOT/.cleanup-archive-list.XXXXXX"' in src and "cleanup_on_exit()" in src,
          "App cleanup uses a unique temporary archive listing and a centralized exit handler")
    check("trap 'exit 130' INT" in src and "trap 'exit 143' TERM" in src and
          "DESTRUCTIVE_STARTED=1" in src and "SNAPSHOT_READY=1" in src and
          "cp -Rp \"$SNAPSHOT/.\" \"$MATCH/\"" in src,
          "App cleanup automatically restores its verified pre-clean snapshot after interruption or failure")
    check('[ ! -L "$SNAPSHOT_ROOT" ]' in src and 'stat -f \'%u\' "$SNAPSHOT_ROOT"' in src and
          'chmod 0700 "$SNAPSHOT_ROOT"' in src,
          "App cleanup rejects symlinked or non-root-owned snapshot storage")
    check("Keychain" in src and "App Groups" in src,
          "App cleanup documents Keychain and App Groups as excluded")
if app_restore.is_file():
    src = app_restore.read_text()
    check('chown root:mobile "$BACKUP_ROOT"' in src and 'chmod 0750 "$BACKUP_ROOT"' in src,
          "App restore preserves read-only mobile Core access to the backup inventory")
    check("--confirm" in src and "restore-snapshots" in src and "killall -0" in src,
          "App restore requires explicit confirmation, closed app, and rollback snapshot")
    check("cleanup_restore()" in src and "trap 'exit 130' INT" in src and
          "RESTORE_STARTED=1" in src and "SNAPSHOT_READY=1" in src and
          'cp -Rp "$SNAPSHOT/." "$MATCH/"' in src,
          "App restore automatically rolls back its snapshot after interruption or failure")
    check('[ ! -L "$ROLLBACK_ROOT" ]' in src and 'stat -f \'%u\' "$ROLLBACK_ROOT"' in src and
          'chmod 0700 "$ROLLBACK_ROOT"' in src,
          "App restore rejects symlinked or non-root-owned rollback storage")
    check("tar -tvzf" in src and "tar -tzf" in src and "符号链接" in src,
          "App restore rejects unsafe archive paths and link/special-file entries")
    check('if killall -0 "$EXECUTABLE"' in src and '[ "$KILLALL_STATUS" -eq 1 ]' in src,
          "App restore distinguishes a stopped process from a system killall execution error")
if keychain_diag.is_file():
    src = keychain_diag.read_text()
    check("ldid -e" in src and "codesign -d --entitlements" in src and "keychain-access-groups" in src,
          "Keychain diagnostic inspects signed access-group declarations with available signing tools")
    check("security" not in src and "security" not in package_builder,
          "Keychain diagnostic does not use broad Keychain command-line enumeration")
if app_verify.is_file():
    src = app_verify.read_text()
    check("sha256sum" in src and "tar -tzf" in src and "BACKUP_ROOT" in src,
          "App-container verifier checks checksum and archive readability in backup directory")
    check("length($2) != 64" in src and "[ ! -L \"$ARCHIVE\" ]" in src and
          "[ ! -L \"$MANIFEST\" ]" in src and "sha_count != 1" in src,
          "App-container verifier rejects malformed/duplicate manifests and symlink inputs")
    check("bundle_count != 1" in src and "container_count != 1" in src and "scope_count != 1" in src,
          "App-container verifier validates required identity and scope fields")

check('mod-hw-config-backup' in package_builder and 'mod-hw-config-restore' in package_builder,
      "Rootless utility DEB packages config backup and restore commands")
check('mod-hw-app-backup' in package_builder and 'mod-hw-app-restore' in package_builder and 'mod-hw-app-clean' in package_builder and 'mod-hw-app-backup-verify' in package_builder and 'mod-hw-selftest' in package_builder and 'mod-hw-keychain-diagnose' in package_builder,
      "Rootless utility DEB packages app-container backup and verification commands")
check("Depends: coreutils" in package_builder and "procps" not in package_builder, "Backup/restore tooling avoids an unavailable procps package dependency")

for rel in [
    "src/mobile_gestalt/mobile_gestalt.m",
    "src/cydia_substrate_hook/HookUtil.m",
    "src/captain_hook/hook.mm",
    "control",
    "layout/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist",
    "layout/usr/share/mod_hw_for_ios/com.modhw.ios.devices.plist.example",
    "manager/ModHWManager.xcodeproj/xcshareddata/xcschemes/ModHWManager.xcscheme",
    "core/layout/DEBIAN/postinst",
    "core/layout/DEBIAN/prerm",
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
