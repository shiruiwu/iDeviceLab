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
check '统一完整套件 DEB 已安装' package_installed com.idevelab.fullsuite.alpha11
PACKAGE_IDENTITY="$(dpkg-query -W -f='${Version}|${Architecture}' com.idevelab.fullsuite.alpha11 2>/dev/null || true)"
check '完整套件版本和架构正确（2.0.2~alpha11 / iphoneos-arm64）' test "$PACKAGE_IDENTITY" = '2.0.2~alpha11|iphoneos-arm64'
check 'Core 二进制存在' test -x /var/jb/usr/libexec/idevelab-core
check 'Root Helper 二进制存在' test -x /var/jb/usr/bin/mod-hw-maintenance-helper
check 'Manager 配对工具存在' test -x /var/jb/usr/bin/mod-hw-manager-pair
check '原作者 Hook 动态库存在' test -f /var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.dylib
check '原作者 Hook 过滤 plist 存在' test -f /var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist

APP_INFO=''
APP_COUNT=0
for candidate in /var/containers/Bundle/Application/*/ModHWManager.app/Info.plist; do
  [ -f "$candidate" ] || continue
  APP_INFO="$candidate"
  APP_COUNT=$((APP_COUNT + 1))
done
check 'TrollStore 管理器 App 唯一安装（避免误验收旧副本）' test "$APP_COUNT" -eq 1
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_INFO" 2>/dev/null || true)"
check '管理器 Bundle ID 正确' test "$APP_BUNDLE_ID" = "com.modhw.manager"
APP_BUILD_VERSION="$(plutil -extract CFBundleVersion raw -o - "$APP_INFO" 2>/dev/null || true)"
check '管理器 Build 版本为 9' test "$APP_BUILD_VERSION" = "9"
APP_MARKETING_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_INFO" 2>/dev/null || true)"
check '管理器市场版本为 2.0.0' test "$APP_MARKETING_VERSION" = "2.0.0"
APP_MINIMUM_OS="$(plutil -extract MinimumOSVersion raw -o - "$APP_INFO" 2>/dev/null || true)"
check '管理器最低系统版本为 16.0' test "$APP_MINIMUM_OS" = "16.0"
APP_LOCAL_NETWORKING="$(plutil -extract NSAppTransportSecurity.NSAllowsLocalNetworking raw -o - "$APP_INFO" 2>/dev/null || true)"
check '管理器允许访问本机 Loopback Core' test "$APP_LOCAL_NETWORKING" = "true"
APP_EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_INFO" 2>/dev/null || true)"
APP_BINARY="$(dirname "$APP_INFO")/$APP_EXECUTABLE"
check '管理器主程序存在' test -f "$APP_BINARY"
check '管理器主程序不是符号链接' test ! -L "$APP_BINARY"
check '管理器主程序可执行' test -x "$APP_BINARY"

PIN_PATH='/var/jb/var/root/Library/Preferences/com.idevelab.manager-cdhash'
check '管理器已完成 Root Helper 配对' test -s "$PIN_PATH"
PIN_HASH="$(cat "$PIN_PATH" 2>/dev/null || true)"
check '配对记录是 40 位十六进制 CDHash' sh -c 'printf "%s" "$1" | grep -Eq "^[0-9a-fA-F]{40}$"' sh "$PIN_HASH"
PIN_META="$(stat -f '%u:%g:%Lp' "$PIN_PATH" 2>/dev/null || true)"
check '配对记录权限为 root:root 0600' test "$PIN_META" = "0:0:600"

check '设备只读自检通过' /var/jb/usr/bin/mod-hw-selftest
echo 'iPhone 12 / iOS 16.2 acceptance: PASS'
