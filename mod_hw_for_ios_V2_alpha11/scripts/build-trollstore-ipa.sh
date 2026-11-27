#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/manager/ModHWManager.xcodeproj"
SCHEME="ModHWManager"
BUILD_DIR="$ROOT/build/trollstore"
DERIVED="$BUILD_DIR/DerivedData"
PAYLOAD="$BUILD_DIR/Payload"
APP="$DERIVED/Build/Products/Release-iphoneos/ModHWManager.app"
OUT="$ROOT/release"
IPA="$OUT/mod_hw_manager_trollstore.ipa"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：需要 macOS + Xcode（包含 iOS SDK）才能编译 IPA。" >&2
  exit 2
fi
mkdir -p "$BUILD_DIR" "$OUT"
rm -rf "$DERIVED" "$PAYLOAD"
rm -f "$IPA"
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME" -configuration Release
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" ENABLE_BITCODE=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
if [[ ! -d "$APP" ]]; then echo "找不到构建产物：$APP" >&2; exit 3; fi
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/ModHWManager.app"
INFO="$PAYLOAD/ModHWManager.app/Info.plist"
BINARY="$PAYLOAD/ModHWManager.app/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
ENTITLEMENTS="$ROOT/manager/TrollStore.entitlements"
if ! command -v ldid >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install ldid
  else
    echo "错误：构建 TrollStore IPA 需要 ldid，以嵌入并签署受限的 no-sandbox entitlement。" >&2
    exit 10
  fi
fi
[[ -f "$ENTITLEMENTS" ]] || { echo "缺少 TrollStore entitlements 文件。" >&2; exit 11; }
ldid -S"$ENTITLEMENTS" "$BINARY"
ldid -e "$BINARY" > "$BUILD_DIR/embedded-entitlements.plist"
python3 - "$BUILD_DIR/embedded-entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as stream:
    entitlements = plistlib.load(stream)
assert entitlements.get("com.apple.private.security.no-sandbox") is True, entitlements
assert not entitlements.get("platform-application", False), entitlements
print("Manager entitlement verified: no-sandbox enabled; platform-application not granted")
PY
# Allow the manager to reach the jailbreak helper over loopback HTTP only.
# NSAllowsLocalNetworking is narrower than allowing arbitrary cleartext traffic.
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity dict' "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$INFO" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :NSAppTransportSecurity:NSAllowsLocalNetworking true' "$INFO"
/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsLocalNetworking' "$INFO" | grep -q true
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
[[ "$BUNDLE_ID" == "com.modhw.manager" ]] || { echo "Bundle ID 不匹配：$BUNDLE_ID" >&2; exit 4; }
[[ -x "$PAYLOAD/ModHWManager.app/$EXECUTABLE" ]] || { echo "缺少可执行文件：$EXECUTABLE" >&2; exit 5; }
file "$PAYLOAD/ModHWManager.app/$EXECUTABLE" | grep -q 'Mach-O' || { echo "应用主程序不是有效 Mach-O 文件。" >&2; exit 6; }
lipo "$PAYLOAD/ModHWManager.app/$EXECUTABLE" -verify_arch arm64 || { echo "应用主程序不包含 arm64 iOS 设备架构。" >&2; exit 8; }
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$INFO" >/dev/null || { echo "Info.plist 缺少 MinimumOSVersion。" >&2; exit 9; }
(cd "$BUILD_DIR" && /usr/bin/zip -qry "$IPA" Payload)
/usr/bin/unzip -t "$IPA" >/dev/null
/usr/bin/unzip -l "$IPA" | grep -q 'Payload/ModHWManager.app/Info.plist' || { echo "IPA 缺少 Info.plist。" >&2; exit 7; }
test -s "$IPA"
echo "IPA 已生成并通过结构检查：$IPA"
