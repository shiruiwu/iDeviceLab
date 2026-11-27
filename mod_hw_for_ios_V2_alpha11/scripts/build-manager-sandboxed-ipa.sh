#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/manager/ModHWManager.xcodeproj"
BUILD_DIR="$ROOT/build/manager-sandboxed"
DERIVED="$BUILD_DIR/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/ModHWManager.app"
OUT="$ROOT/release"
IPA="$OUT/mod_hw_manager_sandboxed_build15.ipa"

command -v xcodebuild >/dev/null 2>&1 || { echo "需要 macOS + Xcode。" >&2; exit 2; }
command -v ldid >/dev/null 2>&1 || { echo "需要 ldid。" >&2; exit 3; }
mkdir -p "$BUILD_DIR" "$OUT"
rm -rf "$DERIVED" "$BUILD_DIR/Payload"
rm -f "$IPA"

xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme ModHWManager
xcodebuild -project "$PROJECT" -scheme ModHWManager -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" PRODUCT_BUNDLE_IDENTIFIER=com.modhw.manager.sandboxed CURRENT_PROJECT_VERSION=15 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" ENABLE_BITCODE=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

[[ -d "$APP" ]] || { echo "找不到 Manager.app。" >&2; exit 4; }
PAYLOAD="$BUILD_DIR/Payload"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/ModHWManager.app"
INFO="$PAYLOAD/ModHWManager.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 15' "$INFO"
BINARY="$PAYLOAD/ModHWManager.app/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
[[ "$BUNDLE_ID" == "com.modhw.manager.sandboxed" ]] || { echo "Bundle ID 不匹配：$BUNDLE_ID" >&2; exit 5; }
file "$BINARY" | grep -q Mach-O
lipo "$BINARY" -verify_arch arm64
ldid -S "$BINARY"
ldid -e "$BINARY" > "$BUILD_DIR/embedded-entitlements.plist"
if [[ -s "$BUILD_DIR/embedded-entitlements.plist" ]]; then
  python3 - "$BUILD_DIR/embedded-entitlements.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],"rb") as f: e=plistlib.load(f)
assert not e.get("com.apple.private.security.no-sandbox",False),e
assert not e.get("platform-application",False),e
print("Manager sandboxed entitlements verified")
PY
else
  echo "Manager sandboxed entitlements verified (none embedded)"
fi
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity dict' "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$INFO" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :NSAppTransportSecurity:NSAllowsLocalNetworking true' "$INFO"
(cd "$BUILD_DIR" && /usr/bin/zip -qry "$IPA" Payload)
/usr/bin/unzip -t "$IPA" >/dev/null
echo "Sandboxed Manager IPA built: $IPA"
