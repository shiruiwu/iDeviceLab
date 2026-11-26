#!/usr/bin/env python3
"""Static validation for the iDeviceLab Rootless Core and safe Alpha11 plist bridge."""
from pathlib import Path
import re
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/JailbreakCore"
VIEW = ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/iDeviceLab/RootlessCoreView.swift"
MAIN = (CORE / "main.m").read_text()
SWIFT = VIEW.read_text()
MAINTENANCE = (ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/iDeviceLab/MaintenanceView.swift").read_text()
CONTROL = (CORE / "control").read_text()
LAUNCHD = (CORE / "layout/Library/LaunchDaemons/com.idevelab.core.plist").read_text()
POSTINST = (CORE / "layout/DEBIAN/postinst").read_text()
PRERM = (CORE / "layout/DEBIAN/prerm").read_text()
ALPHA11 = ROOT / "mod_hw_for_ios_V2_alpha11"
ALPHA11_MAKEFILE = (ALPHA11 / "Makefile").read_text()
ALPHA11_SOURCE = (ALPHA11 / "src/mobile_gestalt/mobile_gestalt.m").read_text()
ALPHA11_FILTER = (ALPHA11 / "layout/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist").read_text()

errors, passed = [], []
def check(ok, message):
    (passed if ok else errors).append(message)

match = re.search(r'NSSet \*allowed = \[NSSet setWithArray:@\[(.*?)\]\];', MAIN, re.S)
keys = re.findall(r'@"([^"]+)"', match.group(1)) if match else []
expected = {
    "HWModelStr", "ProductVersion", "BuildVersion", "HardwarePlatform",
    "ModelNumber", "RegionInfo", "RegionCode", "ProductType"
}
check(set(keys) == expected and len(keys) == len(expected), "Core write allowlist contains exactly eight non-unique test fields")
check('@"UniqueDeviceID"] isKindOfClass:NSString.class' in MAIN, "Core requires existing Alpha11 plist schema before updates")
check("lstat(path.fileSystemRepresentation" in MAIN and "S_ISREG(pathInfo.st_mode)" in MAIN, "Core rejects symlink and non-regular plist targets")
check("NSDataWritingAtomic" in MAIN, "Core writes plist atomically")
check("body.length > 32768" in MAIN, "Core caps config update request size")
check('@"POST"] && [path isEqualToString:@"/config/update"' in MAIN, "Core exposes local POST config update route")
check('@"GET"] && [path isEqualToString:@"/config/status"' in MAIN, "Core exposes local read-only status route")
check('@"version":@"0.1.9"' in MAIN and "Version: 0.1.9" in CONTROL, "Core API and Debian package versions match")
check("config/update" in SWIFT and "URLRequest" in SWIFT and 'request.httpMethod = "POST"' in SWIFT, "Manager posts imported plist fields to local Core")
check("fileImporter" in SWIFT and "allowed: Set<String>" in SWIFT, "Manager uses file import and matching safe-field allowlist")
check("schemaCompatible" in SWIFT and "refreshAlpha11Config()" in SWIFT, "Manager refreshes plist compatibility after import")
check("127.0.0.1:18080" in SWIFT, "Manager connects to loopback Core only")
check("/var/jb/usr/libexec/idevelab-core" in LAUNCHD, "LaunchDaemon points to Rootless Core executable")
check("UserName</key><string>mobile" in LAUNCHD, "Core runs as mobile user for preference access")
check("launchctl bootstrap system" in POSTINST and "launchctl kickstart -k" in POSTINST, "Package postinst bootstraps and starts Core")
check("launchctl bootout system" in PRERM, "Package prerm stops Core cleanly")


check("htonl(INADDR_LOOPBACK)" in MAIN, "Core HTTP listener is loopback-only")
check('@"keys":safeKeys' in MAIN and '@"UniqueDeviceID":' not in MAIN, "Config diagnostics return field names only")
check("value.length > 64" in MAIN and "SELF MATCHES" in MAIN, "Safe fields have length and character validation")
check("applied.count == 0" in MAIN, "Core rejects updates with no valid allowlisted values")
check('Label("导入安全字段"' in SWIFT, "Manager exposes safe plist import")
check("await refreshAlpha11Config()" in SWIFT, "Manager refreshes plist status after import")
check("NSAllowsLocalNetworking: true" in (ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/project.yml").read_text(), "App transport security permits local Core connection")
check('stringByAppendingString:@".idevelab-backup"' in MAIN, "Core backs up original plist before changes")
check("RestoreAlpha11ConfigBackup" in MAIN and 'backupPlist[@"UniqueDeviceID"]' in MAIN, "Core validates rollback backup schema")
check('@"POST"] && [path isEqualToString:@"/config/restore"' in MAIN, "Core exposes local restore route")
check("confirmationDialog" in SWIFT and "restoreAlpha11Backup()" in SWIFT, "Manager confirms local rollback restore")
check("backupParseable" in SWIFT, "Manager shows local rollback backup status")

check('@"GET"] && [path isEqualToString:@"/maintenance/apps"' in MAIN, "Core exposes per-app maintenance inventory")
check('@"POST"] && [path isEqualToString:@"/maintenance/clear"' in MAIN, "Core exposes confirmed per-app cache cleanup")
check('@"GET"] && [path isEqualToString:@"/hooks/status"' in MAIN, "Core exposes read-only Hook installation diagnostics")
check('@"Library/Caches"' in MAIN and '@"tmp"' in MAIN and '@"Documents"' in MAIN, "App cleanup is limited to caches and tmp; documents are excluded")
check("AppDataContainerIndex" in MAIN and "MCMMetadataIdentifier" in MAIN, "App containers are matched by system metadata bundle identifier")
check('ambiguousBundleIDs' in MAIN and 'removeObjectForKey:bundleID' in MAIN, "Core refuses ambiguous duplicate bundle-ID container mappings")
check("ClearDirectDirectoryContents" in MAIN and "lstat(" in MAIN, "App cleanup validates container paths and rejects symlink roots")
check('stringByDeletingLastPathComponent isEqualToString:root' in MAIN and 'relativePath isEqualToString:@"Library/Caches"' in MAIN and 'target.stringByResolvingSymlinksInPath' in MAIN, "App cleanup is restricted to direct app-container children and rejects intermediate symlink escapes")
check('initWithUUIDString:child' in MAIN and 'initWithUUIDString:canonicalContainer.lastPathComponent' in MAIN, "App cleanup inventory and deletion require UUID-named app containers")
check('BOOL dryRun' in MAIN and 'cache cleanup preflight failed' in MAIN and 'NULL, YES' in MAIN, "App cleanup preflights both cache locations before deleting either")
check('"runtimeInjectionVerified":@NO' in MAIN, "Hook status never falsely claims runtime injection is verified")
check("SafeDirectoryMetrics" in MAIN and 'cachesMetrics[@"fileCount"]' in MAIN and 'temporaryMetrics[@"fileCount"]' in MAIN, "Core reports per-directory file counts for cleanup preview")
check("SafeDirectoryMetrics" in MAIN and '"cachesScanStatus"' in MAIN and '"temporaryScanStatus"' in MAIN, "Core distinguishes complete, partial, missing and inaccessible directory scans")
check("scanStatusLabel" in MAINTENANCE and "部分扫描" in MAINTENANCE and "权限不足 / 不可访问" in MAINTENANCE, "Manager displays scan completeness and access failures")
check('"removedItems"' in MAIN and '"failedArea"' in MAIN and '"partial"' in MAIN, "Core reports partial cleanup item counts and failure location")
check(MAIN.index("static void SetMaintenanceError") < MAIN.index("static BOOL ValidateRemovalTree") < MAIN.index("static BOOL ClearDirectDirectoryContents"), "Cleanup validation helpers are declared before first use")
check('"removedItems"' in MAINTENANCE and '"failedArea"' in MAINTENANCE, "Manager persists partial cleanup details in maintenance history")
check("cachesFileCount" in MAINTENANCE and "temporaryFileCount" in MAINTENANCE, "Manager displays per-directory cleanup preview counts")
check("AppMaintenanceResponse" in MAINTENANCE and "clearSelectedAppCaches()" in MAINTENANCE, "Manager previews and executes selected app cache maintenance")
check("orphanedContainerCount" in MAINTENANCE and "疑似卸载残留容器" in MAINTENANCE, "Manager reports possible orphaned app containers")
check("Library/Caches" in MAINTENANCE and "Keychain" in MAINTENANCE, "Maintenance UI documents cleanup scope and credential exclusions")
check("HookInstallationStatus" in SWIFT and "refreshHookStatus()" in SWIFT, "Manager displays Hook installation diagnostics")
check('@"orphanedContainers":orphans' in MAIN and '"containerUUID"' in MAIN, "Core returns per-container orphan diagnostics with UUID and bundle identifier")
check('@"installedAppScanStatus":(installedScanError ? @"partial" : @"complete")' in MAIN and '@"containerIndexScanStatus":(containerScanError ? @"partial" : @"complete")' in MAIN and '@"orphanScanStatus":(!orphanScanComplete ? @"unavailable" : (orphanMetricsComplete ? @"complete" : @"partial"))' in MAIN, "Core emits scan status strings as Objective-C objects without invalid boxed expressions")
check('"filterParseable"' in MAIN and '"filterTargets"' in MAIN and '"runtimeInjectionVerified":@NO' in MAIN, "Hook diagnostics parse filter rules without claiming runtime injection")
check('"installedAppInventory": appInventory' in MAINTENANCE and '"orphanedContainers": orphanInventory' in MAINTENANCE, "Maintenance report includes last app inventory and orphan container details")
check("OrphanedContainerItem" in (ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/iDeviceLab/Models.swift").read_text(), "Manager has typed orphan container response model")
check('"diagnosticReason"' in MAIN and '"containerScanStatus"' in MAIN, "Core explains orphan candidate evidence and scan completeness")
check("diagnosticReason" in MAINTENANCE and "containerScanStatus" in MAINTENANCE, "Manager displays orphan evidence and scan completeness")
check("InstalledApplications(NSError **scanError)" in MAIN and "AppDataContainerIndex(NSError **scanError)" in MAIN, "Core propagates installed-app and app-container enumeration errors")
check('"orphanScanStatus"' in MAIN and "if (orphanScanComplete)" in MAIN, "Core suppresses orphan claims when either inventory scan is incomplete")
check("installed app inventory is incomplete; cleanup refused" in MAIN and "app container inventory is incomplete; cleanup refused" in MAIN, "Core refuses destructive cleanup when inventory integrity is uncertain")
check("installedAppScanStatus" in MAINTENANCE and "containerIndexScanStatus" in MAINTENANCE and "无法可靠判断" in MAINTENANCE, "Manager distinguishes incomplete inventory from a zero-orphan result")
check("decodeIfPresent(String.self, forKey: .cachesScanStatus)" in (ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/iDeviceLab/Models.swift").read_text(), "Manager decodes maintenance inventory from older Core versions")
check("inventoryFresh" in MAINTENANCE and "inventoryScanError" in MAINTENANCE, "Maintenance report marks stale inventory when refresh fails")
check("nilIfEmpty" not in MAINTENANCE and MAINTENANCE.count('"inventoryScanError": inventoryLastError ?? ""') == 1, "Maintenance report uses one portable optional scan-error field without duplicate dictionary keys")
check('Section("最近一次 App 清理记录")' in MAINTENANCE and '"result": partial ? "partial" : "failed"' in MAINTENANCE, "Manager displays success, partial and failed cleanup history")

check('Label("同步当前配置档案"' in SWIFT, "Manager exposes selected-profile sync to Alpha11 local plist")
check('"HWModelStr": profile.deviceModel' in SWIFT and '"ProductVersion": profile.iosVersion' in SWIFT and '"RegionCode": profile.region' in SWIFT, "Profile sync maps only explicit safe profile fields")

check("SO_RCVTIMEO" in MAIN and "SO_SNDTIMEO" in MAIN and "struct timeval timeout = {5, 0}" in MAIN, "Core applies bounded socket read and write timeouts")
check("maximumHeaderBytes = 16 * 1024" in MAIN and "maximumBodyBytes = 1024 * 1024" in MAIN, "Core enforces bounded HTTP header and body sizes")
check("hasContentLength || value.length == 0" in MAIN and "Transfer-Encoding is not supported" in MAIN, "Core rejects duplicate or malformed Content-Length and unsupported transfer encodings")
check("request body is incomplete or timed out" in MAIN and "request line must be GET or POST" in MAIN, "Core validates request line and rejects incomplete bodies")
check("static BOOL SendAll" in MAIN and "remaining -= (size_t)sent" in MAIN, "Core handles partial socket writes")
check("container %@ metadata is unavailable" in MAIN and "multiple app data containers claim Bundle ID" in MAIN, "Core marks missing metadata and duplicate container mappings as incomplete scans")
check("multiple installed app bundles claim Bundle ID" in MAIN and "ambiguousBundleIDs" in MAIN, "Core refuses duplicate installed-app Bundle ID selection")
check("static BOOL ValidateRemovalTree" in MAIN and "access(path.fileSystemRepresentation, W_OK | X_OK)" in MAIN, "Cleanup preflight recursively checks nested directory access before deletion")
check('@"orphanScanStatus":(!orphanScanComplete ? @"unavailable" : (orphanMetricsComplete ? @"complete" : @"partial"))' in MAIN, "Orphan diagnostics distinguish incomplete container-size scans")
 
check("inventoryScanStatus" in SWIFT and "inventoryScanError" in SWIFT and "installedAppScanStatus" in SWIFT, "Manager surfaces installed-app inventory completeness and scan errors")
check("installed app bundle root is not a real directory" in MAIN and "app data container root is not a real directory" in MAIN, "Core reports wrong root file types without relying on stale errno")

check("#import <dirent.h>" in MAIN and "#import <fcntl.h>" in MAIN, "Core imports POSIX directory-descriptor APIs for race-resistant cleanup")
check("OpenCleanupTargetDirectory" in MAIN and "openat(" in MAIN and "O_NOFOLLOW" in MAIN, "Cleanup opens app-container paths with descriptor-relative no-follow traversal")
check("RemoveDirectoryContentsAt" in MAIN and "fstatat(" in MAIN and "unlinkat(" in MAIN, "Cleanup removes entries relative to pinned directory descriptors without following symlinks")
check('"beforeBytes"' in MAIN and '"afterBytes"' in MAIN and '"beforeFileCount"' in MAIN and '"afterFileCount"' in MAIN, "Core reports before/after cleanup bytes and file counts")
check('"elapsedMilliseconds"' in MAIN and '"startedAt"' in MAIN and '"finishedAt"' in MAIN, "Core reports cleanup duration and timestamps")
check('"beforeBytes"' in MAINTENANCE and '"afterBytes"' in MAINTENANCE and '"elapsedMilliseconds"' in MAINTENANCE, "Manager persists and displays cleanup before/after metrics and duration")
check("hook.mm" in (ROOT / "docs/ALPHA11_COMPATIBILITY_AUDIT.md").read_text() and "HookerForMGCopyMultipleAnswers" in (ROOT / "docs/ALPHA11_COMPATIBILITY_AUDIT.md").read_text(), "Alpha11 audit documents source/Makefile and inactive call paths")
check("App 绑定只表示管理器中的档案关联" in (ROOT / "iDeviceLab-2.0-source-v2/iDeviceLab-2.0/iDeviceLab/RootlessCoreView.swift").read_text(), "Manager distinguishes App metadata binding from runtime Hook state")
check("runtimeInjectionVerified" in (ROOT / "docs/ALPHA11_COMPATIBILITY_AUDIT.md").read_text(), "Hook audit separates static diagnostics from runtime verification")
check("maintenance/apps" in (ROOT / "scripts/device_acceptance.sh").read_text() and "launchctl print system/com.idevelab.core" in (ROOT / "scripts/device_acceptance.sh").read_text(), "Device acceptance script checks installed service and loopback API health")


constructor_match = re.search(r'__attribute__\(\(__constructor__\)\)\s*static void _MSInitialize\(void\)\s*\{(.*?)\n\}', ALPHA11_SOURCE, re.S)
constructor_body = constructor_match.group(1) if constructor_match else ""
mobile_gestalt_match = re.search(r'void MobileGestaltHooker\(\)\s*\{(.*?)\n\}', ALPHA11_SOURCE, re.S)
mobile_gestalt_body = mobile_gestalt_match.group(1) if mobile_gestalt_match else ""
check("src/mobile_gestalt/mobile_gestalt.m" in ALPHA11_MAKEFILE and "src/cydia_substrate_hook/HookUtil.m" in ALPHA11_MAKEFILE, "Alpha11 Makefile includes its declared MobileGestalt and substrate utility sources")
check("src/captain_hook/hook.mm" not in ALPHA11_MAKEFILE and (ALPHA11 / "src/captain_hook/hook.mm").is_file(), "Alpha11 CaptainHook source exists but is excluded from the Makefile")
check("<string>SpringBoard</string>" in ALPHA11_FILTER and "<string>com.apple.Preferences</string>" in ALPHA11_FILTER, "Alpha11 filter declares SpringBoard and Preferences only")
check("HookerForMGCopyAnswer();" in mobile_gestalt_body and re.search(r"^\s*HookerForMGCopyMultipleAnswers\(\);", mobile_gestalt_body, re.M) is None, "Alpha11 MobileGestalt constructor path enables MGCopyAnswer but not MGCopyMultipleAnswers")
check("hook_sysctlbyname();" in constructor_body and "hook_sysctl();" not in constructor_body, "Alpha11 constructor registers sysctlbyname but not sysctl")
check("CTMobileEquipmentInfo_setIMEI();" in constructor_body and "CTMobileEquipmentInfo_setMEID();" in constructor_body and "HOOK_IDFA();" in constructor_body and "HOOK_IDFV();" in constructor_body, "Alpha11 constructor registers CoreTelephony setter and advertising/vendor ID hook entry points")

check("removeItemAtPath:candidate" not in MAIN and "unlinkat(" in MAIN, "App cleanup has no pathname-based recursive deletion fallback")
check("iDeviceLabAppCleanupHistoryV1" in MAINTENANCE and "persistAppCleanupRecord" in MAINTENANCE and "appCleanupHistory" in MAINTENANCE, "Manager persists and exports the latest 20 App cleanup records")
check('request.timeoutInterval = 15' in MAINTENANCE, "Manager bounds per-app cleanup request wait time")
check('"result": "unknown"' in MAINTENANCE and '"operationMayHaveCompleted": true' in MAINTENANCE, "Manager records an explicit unknown result when the cleanup response is lost")
check('result == "unknown" ? "结果未知' in MAINTENANCE, "Manager distinguishes unknown cleanup outcomes in the UI")
device_script = ROOT / "scripts/device_acceptance.sh"
shell_syntax = subprocess.run(["sh", "-n", str(device_script)], capture_output=True, text=True)
check(shell_syntax.returncode == 0, "Device acceptance script passes POSIX shell syntax validation")
check("manager_installed" in device_script.read_text() and "package_installed" in device_script.read_text(), "Device acceptance script verifies both Manager IPA and Rootless package installation")

print(f"Rootless validation: {len(passed)} passed, {len(errors)} failed")
for item in passed:
    print("[OK]", item)
for item in errors:
    print("[FAIL]", item)
sys.exit(1 if errors else 0)

