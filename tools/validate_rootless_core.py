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
check('@"version":@"0.1.8"' in MAIN and "Version: 0.1.8" in CONTROL, "Core API and Debian package versions match")
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

print(f"Rootless validation: {len(passed)} passed, {len(errors)} failed")
for item in passed:
    print("[OK]", item)
for item in errors:
    print("[FAIL]", item)
sys.exit(1 if errors else 0)
