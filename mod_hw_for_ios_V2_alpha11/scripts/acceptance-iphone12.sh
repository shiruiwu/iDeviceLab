#!/bin/sh
# Final read-only acceptance gate for the requested iPhone 12 / iOS 16.2 target.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
check() {
  LABEL="$1"; shift
  if "$@"; then
    echo "PASS: $LABEL"
  else
    fail "$LABEL"
  fi
}
package_installed() {
  STATUS="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)"
  [ "$STATUS" = "install ok installed" ]
}

[ "$(id -u)" -eq 0 ] || fail '请以 root 权限运行。'
DEVICE_MODEL="$(sysctl -n hw.machine 2>/dev/null || true)"
IOS_VERSION="$(plutil -extract ProductVersion raw -o - /System/Library/CoreServices/SystemVersion.plist 2>/dev/null || true)"
check '设备为 iPhone 12（iPhone13,2）' test "$DEVICE_MODEL" = "iPhone13,2"
check '系统版本为 iOS 16.2' test "$IOS_VERSION" = "16.2"
check 'Rootless 越狱目录存在' test -d /var/jb
check 'Alpha11 Core DEB 已安装' package_installed com.idevelab.core.alpha11
check '诊断与维护工具 DEB 已安装' package_installed com.modhw.ios.diagnostics
check '原作者 Hook tweak DEB 已安装' package_installed com.modhw.ios
check 'Core 二进制存在' test -x /var/jb/usr/libexec/idevelab-core
check 'Root Helper 二进制存在' test -x /var/jb/usr/bin/mod-hw-maintenance-helper
check 'Manager 配对工具存在' test -x /var/jb/usr/bin/mod-hw-manager-pair
check '原作者 Hook 动态库存在' test -f /var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.dylib
check '原作者 Hook 过滤 plist 存在' test -f /var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist

APP_INFO="$(find /var/containers/Bundle/Application -path '*/ModHWManager.app/Info.plist' -print -quit 2>/dev/null || true)"
check 'TrollStore 管理器 App 已安装' test -n "$APP_INFO"
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_INFO" 2>/dev/null || true)"
check '管理器 Bundle ID 正确' test "$APP_BUNDLE_ID" = "com.modhw.manager"

PIN_PATH='/var/jb/var/root/Library/Preferences/com.idevelab.manager-cdhash'
check '管理器已完成 Root Helper 配对' test -s "$PIN_PATH"
PIN_META="$(stat -f '%u:%g:%Lp' "$PIN_PATH" 2>/dev/null || true)"
check '配对记录权限为 root:root 0600' test "$PIN_META" = "0:0:600"

check '设备只读自检通过' /var/jb/usr/bin/mod-hw-selftest
echo 'iPhone 12 / iOS 16.2 acceptance: PASS'
