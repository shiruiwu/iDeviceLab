#!/usr/bin/env python3
"""Static validation for the iDeviceLab Rootless Core and safe Alpha11 plist bridge."""
from pathlib import Path
import re
import sys

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
check('@"version":@"0.1.9"' in MAIN and "Version: 0.1.8" in CONTROL, "Core API and Debian package versions match")
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
check("ClearDirectDirectoryContents" in MAIN and "lstat(" in MAIN, "App cleanup validates container paths and rejects symlink roots")
check('"runtimeInjectionVerified":@NO' in MAIN, "Hook status never falsely claims runtime injection is verified")
check("AppMaintenanceResponse" in MAINTENANCE and "clearSelectedAppCaches()" in MAINTENANCE, "Manager previews and executes selected app cache maintenance")
check("orphanedContainerCount" in MAINTENANCE and "疑似卸载残留容器" in MAINTENANCE, "Manager reports possible orphaned app containers")
check("Library/Caches" in MAINTENANCE and "Keychain" in MAINTENANCE, "Maintenance UI documents cleanup scope and credential exclusions")
check("HookInstallationStatus" in SWIFT and "refreshHookStatus()" in SWIFT, "Manager displays Hook installation diagnostics")
check('Label("同步当前配置档案"' in SWIFT, "Manager exposes selected-profile sync to Alpha11 local plist")
check('"HWModelStr": profile.deviceModel' in SWIFT and '"ProductVersion": profile.iosVersion' in SWIFT and '"RegionCode": profile.region' in SWIFT, "Profile sync maps only explicit safe profile fields")

print(f"Rootless validation: {len(passed)} passed, {len(errors)} failed")
for item in passed:
    print("[OK]", item)
for item in errors:
    print("[FAIL]", item)
sys.exit(1 if errors else 0)

