#!/usr/bin/env python3
"""Static checks for the Alpha11 tweak, manager, and config utility package."""
from pathlib import Path
import plistlib
import re
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
sandboxed_ipa = (ROOT / "scripts/build-manager-sandboxed-ipa.sh").read_text()
check("PRODUCT_BUNDLE_IDENTIFIER=com.modhw.manager.sandboxed" in sandboxed_ipa and
      "CURRENT_PROJECT_VERSION=17" in sandboxed_ipa and
      'assert not e.get("com.apple.private.security.no-sandbox"' in sandboxed_ipa and
      "NSAllowsLocalNetworking" in sandboxed_ipa,
      "Known-good sandboxed Manager Build16 keeps its Bundle ID and reaches Core over loopback HTTP")
check('ldid -S "$BINARY"' in sandboxed_ipa and 'ldid -e "$BINARY"' in sandboxed_ipa,
      "Sandboxed Manager is ad-hoc signed without privileged entitlements")
package_builder = (ROOT / "scripts/build-diagnostics-deb.sh").read_text()
theos_workflow_path = ROOT.parent / ".github/workflows/build-theos-tweak.yml"
theos_workflow = theos_workflow_path.read_text() if theos_workflow_path.is_file() else ""
check(not any(line.startswith(("dpkg-deb --contents", "test -x")) for line in theos_workflow.splitlines()),
      "Theos workflow shell commands remain inside their YAML run block")
check("bash scripts/build-diagnostics-deb.sh" in theos_workflow and
      "bash scripts/build-core-deb.sh" in theos_workflow and
      "release/*.deb" in theos_workflow and "mod-hw-maintenance-helper" in theos_workflow,
      "Theos workflow builds and uploads the same complete diagnostics and Root Helper Core DEBs as the TrollStore workflow")
core_package_builder_path = ROOT / "scripts/build-core-deb.sh"
core_package_builder = core_package_builder_path.read_text() if core_package_builder_path.is_file() else ""
check('(cd "$PKG" && tar --format=ustar -czf "$WORK/data.tar.gz" --owner=0 --group=0 ./var)' in package_builder and
      '(cd "$PKG" && tar --format=ustar -czf "$WORK/data.tar.gz" --owner=0 --group=0 ./var)' in core_package_builder,
      "Diagnostics and Core data archives exclude DEBIAN control metadata")
core_source = ROOT / "core/main.m"
core_makefile = ROOT / "core/Makefile"
core_control = ROOT / "core/control"
core_control_text = core_control.read_text() if core_control.is_file() else ""
core_daemon = ROOT / "core/layout/Library/LaunchDaemons/com.idevelab.core.alpha11.plist"

helper_source = ROOT / "core/maintenance_helper.m"
pair_source = ROOT / "core/manager_pair.m"
helper_daemon = ROOT / "core/layout/Library/LaunchDaemons/com.idevelab.maintenance.alpha11.plist"
if helper_daemon.is_file():
    helper_plist = plistlib.loads(helper_daemon.read_bytes())
    check(helper_plist.get("Label") == "com.idevelab.maintenance.alpha11" and
          helper_plist.get("ProgramArguments") == ["/var/jb/usr/bin/mod-hw-maintenance-helper"] and
          helper_plist.get("UserName") == "root" and helper_plist.get("GroupName") == "wheel" and
          helper_plist.get("KeepAlive") is True,
          "Root Helper is installed as a persistent root:wheel LaunchDaemon")
check(helper_source.is_file() and pair_source.is_file(),
      "Root Helper and explicit Manager pairing source files exist")
if helper_source.is_file():
    helper_text = helper_source.read_text()
    check("LOCAL_PEERPID" in helper_text and "getpeereid" in helper_text and
          "CS_OPS_CDHASH" in helper_text and "CS_VALID" in helper_text and
          "com.idevelab.manager-cdhash" in helper_text and "posix_spawn" in helper_text and
          "300.0" in helper_text and "kOutputLimit = 65536" in helper_text,
          "Root Helper checks peer UID/PID and pinned code signature, runs bounded fixed tools, and caps execution/output")
    check(all(token in helper_text for token in (
          '@"backup"', '@"verify"', '@"restore"', '@"clean"', '@"apply-profile"',
          '@"config-backup"', '@"config-restore"', '@"keychain-diagnose"',
          '@"diagnose-config"', '@"selftest"', '@"acceptance-iphone12"', '@"apply-global-profile"')),
          "Root Helper exposes only the declared maintenance allowlist")
if pair_source.is_file():
    pair_text = pair_source.read_text()
    check("KERN_PROCARGS2" in pair_text and "CS_OPS_CDHASH" in pair_text and
          'com.modhw.manager' in pair_text and 'ModHWManager.app' in pair_text and
          'strcmp(confirmation, "PAIR\\n")' in pair_text and "O_NOFOLLOW" in pair_text,
          "Pairing utility verifies the live Manager app identity and signature and requires root confirmation")

if core_daemon.is_file():
    daemon = plistlib.loads(core_daemon.read_bytes())
    check(daemon.get("Label") == "com.idevelab.core.alpha11", "Alpha11 launchd plist uses a valid service label")
    check(daemon.get("ProgramArguments") == ["/var/jb/usr/libexec/idevelab-core"], "Alpha11 launchd starts the packaged Rootless Core binary")
    check(daemon.get("UserName") == "mobile" and daemon.get("GroupName") == "mobile", "Alpha11 Core runs as the unprivileged mobile user")

check("Version: 2.0.2~alpha11" in control, "Existing Alpha11 tweak package metadata retained")
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
check("CURRENT_PROJECT_VERSION = 9;" in project, "Manager build number is 9")
check("fileImporter" in manager and "fileExporter" in manager, "Manager imports and exports plist files")
check("TabView" in manager and "homePage" in manager and "recordsPage" in manager and
      "settingsPage" in manager and "aboutPage" in manager and
      "备份中心" in manager and "还原中心" in manager and "清理中心" in manager and
      "改机管理" in manager and "分应用改机" in manager and "系统诊断" in manager and "IPA 多开" in manager,
      "Manager restores the blue dashboard, original feature modules, operation history, settings, and about navigation")
profile_view = (ROOT / "manager/ProfileManagerView.swift").read_text()
profile_store = (ROOT / "manager/ProfileStore.swift").read_text()
profile_models = (ROOT / "manager/DeviceProfileModels.swift").read_text()
app_entry = (ROOT / "manager/ModHWManager/ModHWManagerApp.swift").read_text()
check("ZIPFoundation" in project and "weichsel/ZIPFoundation.git" in project and "0.9.20" in project,
      "IPA editor ZIP archive dependency is pinned to the iOS 12+ compatible ZIPFoundation 0.9.20 package")
check("IPAEditorView()" in manager and "IPAEditorView.swift" in project and
      "IPAExporter.swift" in project and "IPABundleInfo.swift" in project and
      "FileBrowserView.swift" in project,
      "Original IPA multi-open editor and its bundled core, views, and support files are linked into the manager target")
check("hookConfiguration" in profile_models and "UniqueDeviceID" in profile_models and
      "InternationalMobileEquipmentIdentity" in profile_models and "WifiAddress" in profile_models and
      "BluetoothAddress" in profile_models and "IDFA" in profile_models and "IDFV" in profile_models and
      "randomizeHookIdentifiers" in profile_store,
      "Persistent profiles include the original Hook hardware fields and valid-format test identifier generation")
helper_source = (ROOT / "core/maintenance_helper.m").read_text()
check("apply-profile" in profile_view and "apply-global-profile" in profile_view and "onOperation" in profile_view and "recordOperation" in manager and
      "BOOL isGlobalProfile = [action isEqualToString:@" in helper_source and
      'ApplyHookProfile(isGlobalProfile ? nil : bundleID, request[@"profile"], isGlobalProfile' in helper_source and
      "com.modhw.ios.devices.plist" in helper_source and
      'isEqualToString:@"apply-profile", @"apply-global-profile"' not in helper_source and
      "MaintenanceClient.request" in profile_view and
      "确认写入并备份旧配置" in profile_view and "强制关闭并重新打开目标 App" in profile_view,
      "Profile manager dispatches validated per-App and global Hook profiles through Root Helper after explicit confirmation")
check("ProfileManagerView(" in manager and "availableApps:" in manager and "ProfileAppOption" in profile_models and "availableApps" in profile_view and "ProfileStore()" in app_entry and
      ".environmentObject(profileStore)" in app_entry and
      "应用选择与配置绑定" in profile_view and "全部参数一键随机" in profile_view and
      "配置备份" in profile_view and "struct DeviceProfile" in profile_models and
      "func importData" in profile_store,
      "Original profile manager, persistent profile store, app bindings, and JSON import/export are integrated")
check("\\\\(" not in profile_view,
      "Original profile manager interpolates profile names and app launch results correctly")
check('case "$ACTION" in' in (ROOT / "scripts/maintenance-dispatch.sh").read_text() and
      "必须在越狱终端以 root 身份运行" in (ROOT / "scripts/maintenance-dispatch.sh").read_text() and
      all(action in (ROOT / "scripts/maintenance-dispatch.sh").read_text() for action in ("backup)", "verify)", "restore)", "clean)")) and
      "未知操作" in (ROOT / "scripts/maintenance-dispatch.sh").read_text(),
      "Root-only maintenance dispatcher exposes only fixed backup, verify, restore, and clean actions")
check("mod-hw-maintenance" in package_builder and "maintenance-dispatch.sh" in package_builder,
      "Rootless utility DEB packages the fixed-command terminal fallback dispatcher")
check('acceptance-iphone12' in manager and "运行 iPhone 12 / iOS 16.2 最终验收" in manager,
      "Manager exposes the final read-only iPhone 12 acceptance gate")
check("MaintenanceClient.request" in manager and "managerPID" in manager and
      "127.0.0.1:18081/maintenance" in manager and
      "X-iDeviceLab-Manager-Token" in manager and "bridgeTokenName" in manager and
      "SecRandomCopyBytes" in manager and 'MaintenanceClient.request(action: "pair")' in manager and "func pairMaintenanceHelper()" in manager and
      "config-backup" in manager and "keychain-diagnose" in manager and "confirmationDialog" in manager and
      "helperPaired" in manager and "performMaintenance" in manager,
      "Manager authenticates to the Core bridge with a sandbox-private token and gates destructive actions behind explicit confirmation")
check("UIPasteboard.general.string = command" in manager,
      "Manager maintenance commands can be copied for execution in the jailbreak terminal")
check('Picker("已安装应用", selection: $maintenanceBundleID)' in manager and
      'TextField("Bundle ID' in manager and 'bundleID: bundleID.isEmpty ? nil : bundleID' in manager and
      'archive: archive.isEmpty ? nil : archive' in manager,
      "Manager sends the selected Bundle ID and backup filename to the Root Helper")
check("safeShellArgument" in manager and "replacingOccurrences" in manager and "请填写" in manager,
      "Manager safely quotes shell arguments and marks blank placeholders")
check("\\\\(" not in manager,
      "Manager maintenance command and backup-result strings use live Swift interpolation")

check("selectedProfileBundleID" in manager and "导出为所选应用的独立配置" in manager and
      "com.modhw.ios.profiles" in manager and "exportAsPerAppProfile" in manager,
      "Manager can export the imported plist under a selected installed App's Bundle ID")
check("canExportPerAppProfile" in manager and '"UniqueDeviceID"' in manager and
      "udid.count == 40" in manager and "normalized.count == 12" in manager,
      "Manager validates the Hook-required UDID and enabled MAC address fields before per-app export")
check("PropertyListSerialization.propertyList" in manager, "Manager parses plist structure")
check("字段值未展示" in manager, "Manager does not display plist values")
check('http://127.0.0.1:18081/status' in manager and 'http://127.0.0.1:18081/apps' in manager and 'request.httpMethod = "GET"' in manager and 'payload["mode"] as? String == "read-only"' in manager,
      "Manager validates the read-only Alpha11 Core status response")
check("POST to Core is rejected with HTTP 405" in (ROOT / "scripts/selftest-device.sh").read_text() and
      "for endpoint in system apps tools profiles backups" in (ROOT / "scripts/selftest-device.sh").read_text(),
      "On-device self-test verifies all read-only endpoints and rejects POST without changing device data")
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
helper_source = ROOT / "core/maintenance_helper.m"
pair_source = ROOT / "core/manager_pair.m"
helper_daemon = ROOT / "core/layout/Library/LaunchDaemons/com.idevelab.maintenance.alpha11.plist"
if helper_daemon.is_file():
    helper_plist = plistlib.loads(helper_daemon.read_bytes())
    check(helper_plist.get("Label") == "com.idevelab.maintenance.alpha11" and
          helper_plist.get("ProgramArguments") == ["/var/jb/usr/bin/mod-hw-maintenance-helper"] and
          helper_plist.get("UserName") == "root" and helper_plist.get("GroupName") == "wheel",
          "Root maintenance helper has a dedicated root-owned launchd service")
check('setenv("PATH", "/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin", 1)' in (ROOT / "core/maintenance_helper.m").read_text(),
      "Root helper gives fixed maintenance tools a deterministic rootless PATH")
check((ROOT / "core/CodeSignCompat.h").is_file() and
      "CS_OPS_CDHASH 5" in (ROOT / "core/CodeSignCompat.h").read_text() and
      "CS_KILLED 0x01000000" in (ROOT / "core/CodeSignCompat.h").read_text(),
      "Code-signature process hash compatibility declarations match XNU ABI constants")
check(helper_source.is_file() and pair_source.is_file(),
      "Pinned-signature maintenance helper and explicit Manager pairing utility exist")
if helper_source.is_file():
    src = helper_source.read_text()
    check("LOCAL_PEERPID" in src and "getpeereid" in src and "CS_OPS_CDHASH" in src and
          "CS_VALID" in src and "com.idevelab.manager-cdhash" in src and
          "posix_spawn" in src and "300.0" in src and "ApplyHookProfile" in src and "WriteSecureFile" in src and "UniqueDeviceID" in src and "UniqueDeviceIDData" in src and
          all(action in src for action in ('@"backup"', '@"verify"', '@"restore"', '@"clean"', '@"config-backup"', '@"config-restore"', '@"keychain-diagnose"', '@"diagnose-config"', '@"selftest"', '@"acceptance-iphone12"', '@"apply-profile"')),
          "Root helper authenticates the paired process signature and executes only bounded fixed maintenance commands")
if pair_source.is_file():
    src = pair_source.read_text()
    check("KERN_PROCARGS2" in src and "com.modhw.manager" in src and
          "CS_OPS_CDHASH" in src and 'strcmp(confirmation, "PAIR\\n")' in src,
          "Pairing utility requires root confirmation and pins the exact Manager app code hash")
check((ROOT / "core/layout/DEBIAN/postrm").is_file() and
      "com.idevelab.maintenance.alpha11.plist" in (ROOT / "core/layout/DEBIAN/postrm").read_text() and
      "com.idevelab.maintenance.sock" in (ROOT / "core/layout/DEBIAN/postrm").read_text(),
      "Core package has a helper shutdown and IPC cleanup post-removal hook")
unified_builder_path = ROOT / "scripts/build-unified-deb.sh"
unified_builder = unified_builder_path.read_text() if unified_builder_path.is_file() else ""
check(unified_builder_path.is_file() and "dpkg-deb --build --root-owner-group" in unified_builder and "com.idevelab.fullsuite.alpha11" in unified_builder and "mod_hw_for_ios_V2_FULL_SUITE_ALPHA11.deb" in unified_builder,
      "A self-contained unified Rootless DEB combines original tweak, diagnostics, Core, and Helper payloads")
check("bash scripts/build-unified-deb.sh" in theos_workflow and "FULL_PACKAGE" in theos_workflow,
      "Theos workflow builds and verifies the unified full-suite DEB")
check(core_package_builder_path.is_file() and
      "Depends: firmware (>= 15.0), com.modhw.ios.diagnostics" in core_package_builder and
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
    check("/var/jb/usr/bin/launchctl" in post and "/var/jb/basebin/launchctl" in post and
          'find /var/jb -name launchctl -perm -111' in post and
          'bootstrap system "$service_plist"' in post and 'ERROR: launchctl bootstrap failed' in post,
          "Core installer searches common rootless launchctl locations and reports startup failure without aborting package installation")
    check("/var/jb/usr/bin/launchctl" in pre and 'find /var/jb -name launchctl -perm -111' in pre,
          "Core removal script can locate launchctl in extended rootless paths")

if core_source.is_file():
    core = core_source.read_text()
    check('@"GET"' in core and 'ForwardMaintenanceRequest' in core and
          'com.idevelab.maintenance.sock' in core and '[path isEqualToString:@"/maintenance"]' in core and
          'ManagerBridgeTokenMatches' in core and 'MCMMetadataIdentifier' in core and
          'X-iDeviceLab-Manager-Token' in core,
          "Alpha11 Core verifies the Manager sandbox-private token before proxying to Root Helper")
    check("INADDR_LOOPBACK" in core and "kPort = 18081" in core,
          "Alpha11 Core binds only to loopback port 18081")
    check('@"tools"' in core and 'InstalledMaintenanceTools' in core and
          'access(path.fileSystemRepresentation, X_OK)' in core and
          '[path isEqualToString:@"/tools"]' in core,
          "Alpha11 Core reports only the fixed allowlisted maintenance tool inventory")
    check('@"mod-hw-maintenance"' in core and '@"mod-hw-maintenance-helper"' in core and '@"mod-hw-manager-pair"' in core and '@"mod-hw-acceptance-iphone12"' in core,
          "Core inventory includes the packaged fixed-command maintenance dispatcher")
    check('@"profiles"' in core and 'InstalledProfiles' in core and
          'com.modhw.ios.profiles' in core and '[path isEqualToString:@"/profiles"]' in core and
          'NSPropertyListSerialization' in core,
          "Alpha11 Core reports only filenames and plist validity for installed per-app profiles")


    check('@"version": @"0.3.5-alpha11"' in core,
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
    check("Architecture: iphoneos-arm64" in core_control_text and
          "Version: 0.3." in core_control_text and "~alpha11" in core_control_text,
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
config_backup_text = backup.read_text() if backup.is_file() else ""
config_restore_text = restore.read_text() if restore.is_file() else ""
check("com.modhw.ios.profiles" in config_backup_text and "tar -czpf" in config_backup_text and
      "sha256sum" in config_backup_text and "plutil -lint" in config_backup_text,
      "Configuration backup includes global and per-App Hook profiles with plist and SHA-256 verification")
check("tar -tzf" in config_restore_text and "tar -tvzf" in config_restore_text and
      "sha256sum -c" in config_restore_text and "profiles-before" in config_restore_text and
      "rollback-snapshots" in config_restore_text and "legacy" in config_restore_text,
      "Configuration restore validates archive paths and file types, then rolls back global and per-App profiles")

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

check("com.idevelab.maintenance.alpha11" in selftest.read_text() and
      "mod-hw-maintenance-helper" in selftest.read_text() and
      "mod-hw-manager-pair" in selftest.read_text() and "maintenance.sock" in selftest.read_text(),
      "On-device self-test verifies root helper installation, launchd service, and protected local socket")

acceptance_script = ROOT / "scripts/acceptance-iphone12.sh"
check(acceptance_script.is_file() and "com.idevelab.fullsuite.alpha11" in acceptance_script.read_text() and
      "2.0.2~alpha11|iphoneos-arm64" in acceptance_script.read_text() and
      "APP_COUNT" in acceptance_script.read_text() and "CFBundleVersion" in acceptance_script.read_text() and
      "NSAllowsLocalNetworking" in acceptance_script.read_text() and "MinimumOSVersion" in acceptance_script.read_text() and
      "test ! -L" in acceptance_script.read_text() and "CFBundleExecutable" in acceptance_script.read_text() and
      "iPhone13,2" in acceptance_script.read_text() and "16.2" in acceptance_script.read_text() and
      "mod-hw-selftest" in acceptance_script.read_text(),
      "Final acceptance validates exact full-suite package identity, unique Manager install/build, and iPhone 12 / iOS 16.2")

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
    check('PROFILE_NAME="${ENTRY#./com.modhw.ios.profiles/}"' in src and
          "*/*" in src and "*..*" in src and "uniq -d" in src and
          "tar -xzf \"$LATEST\" -C \"$STAGE\"" in src,
          "Config restore rejects traversal, malformed profile names, and duplicate archive paths before extraction")

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
    check("REMAINING=" in src and "清理后仍有未删除项目" in src,
          "App cleanup verifies the container is empty except for its required MCM registration marker")
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
    check('diff -qr "$STAGE" "$MATCH"' in src and "还原后内容与已校验备份不一致" in src,
          "App restore compares the restored tree with the verified staging tree before reporting success")
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
