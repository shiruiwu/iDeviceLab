#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/manager/StartupProbe/StartupProbe.xcodeproj"
BUILD_DIR="$ROOT/build/startup-probe"
DERIVED="$BUILD_DIR/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/StartupProbe.app"
OUT="$ROOT/release"
IPA="$OUT/mod_hw_manager_startup_probe_build12.ipa"
ENTITLEMENTS="$ROOT/manager/TrollStore.entitlements"

command -v xcodebuild >/dev/null 2>&1 || { echo "需要 macOS + Xcode。" >&2; exit 2; }
command -v ldid >/dev/null 2>&1 || { echo "需要 ldid。" >&2; exit 3; }
[[ -f "$ENTITLEMENTS" ]] || { echo "缺少 TrollStore entitlements。" >&2; exit 4; }
mkdir -p "$BUILD_DIR" "$OUT"
rm -rf "$DERIVED" "$BUILD_DIR/Payload"
rm -f "$IPA"

xcodebuild -project "$PROJECT" -scheme StartupProbe -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
[[ -d "$APP" ]] || { echo "找不到 StartupProbe.app。" >&2; exit 5; }
PAYLOAD="$BUILD_DIR/Payload"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/StartupProbe.app"
INFO="$PAYLOAD/StartupProbe.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 12' "$INFO"
BINARY="$PAYLOAD/StartupProbe.app/StartupProbe"
file "$BINARY" | grep -q 'Mach-O'
lipo "$BINARY" -verify_arch arm64
LINKS="$(otool -L "$BINARY")"
if grep -E 'SwiftUI\.framework|PhotosUI\.framework|Combine\.framework|libswiftPhotosUI|libswiftUniformTypeIdentifiers' <<< "$LINKS"; then
    echo "纯 UIKit 探针意外链接了高层 UI/媒体运行库。" >&2
    exit 6
fi
ldid -S"$ENTITLEMENTS" "$BINARY"
ldid -e "$BINARY" > "$BUILD_DIR/embedded-entitlements.plist"
python3 - "$BUILD_DIR/embedded-entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    e = plistlib.load(f)
assert e.get("com.apple.private.security.no-sandbox") is True, e
assert not e.get("platform-application", False), e
print("Probe entitlements verified")
PY
(cd "$BUILD_DIR" && /usr/bin/zip -qry "$IPA" Payload)
/usr/bin/unzip -t "$IPA" >/dev/null
echo "Pure UIKit startup probe built: $IPA"
