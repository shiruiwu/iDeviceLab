#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/core-deb"
PKG="$WORK/pkg"
OUT="$ROOT/release"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$PKG/DEBIAN" "$PKG/var/jb/usr/libexec" "$PKG/var/jb/usr/bin" "$PKG/var/jb/Library/LaunchDaemons" "$OUT"
rm -rf "$WORK"
mkdir -p "$PKG/DEBIAN" "$PKG/var/jb/usr/libexec" "$PKG/var/jb/usr/bin" "$PKG/var/jb/Library/LaunchDaemons"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$SDK" -fobjc-arc -Wall -Wextra -framework Foundation "$ROOT/core/main.m" -o "$PKG/var/jb/usr/libexec/idevelab-core"
chmod 0755 "$PKG/var/jb/usr/libexec/idevelab-core"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$SDK" -fobjc-arc -Wall -Wextra -framework Foundation "$ROOT/core/maintenance_helper.m" -o "$PKG/var/jb/usr/bin/mod-hw-maintenance-helper"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$SDK" -fobjc-arc -Wall -Wextra -framework Foundation "$ROOT/core/manager_pair.m" -o "$PKG/var/jb/usr/bin/mod-hw-manager-pair"
chmod 0755 "$PKG/var/jb/usr/bin/mod-hw-maintenance-helper" "$PKG/var/jb/usr/bin/mod-hw-manager-pair"
# Rootless launchd jobs are native iOS executables and must carry an ad-hoc
# code signature. Unsigned Mach-O files can be present in a DEB yet fail exec.
for binary in \
  "$PKG/var/jb/usr/libexec/idevelab-core" \
  "$PKG/var/jb/usr/bin/mod-hw-maintenance-helper" \
  "$PKG/var/jb/usr/bin/mod-hw-manager-pair"; do
  ldid -S "$binary"
  ldid -e "$binary" >/dev/null
  file "$binary" | grep -q "Mach-O" || { echo "签名后文件不是 Mach-O：$binary" >&2; exit 4; }
done
install -m 0644 "$ROOT/core/layout/Library/LaunchDaemons/com.idevelab.core.alpha11.plist" "$PKG/var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist"
install -m 0644 "$ROOT/core/layout/Library/LaunchDaemons/com.idevelab.maintenance.alpha11.plist" "$PKG/var/jb/Library/LaunchDaemons/com.idevelab.maintenance.alpha11.plist"
install -m 0755 "$ROOT/core/layout/DEBIAN/postinst" "$PKG/DEBIAN/postinst"
install -m 0755 "$ROOT/core/layout/DEBIAN/prerm" "$PKG/DEBIAN/prerm"
install -m 0755 "$ROOT/core/layout/DEBIAN/postrm" "$PKG/DEBIAN/postrm"
cat > "$PKG/DEBIAN/control" <<'EOF'
Package: com.idevelab.core.alpha11
Name: iDeviceLab Alpha11 Core
Version: 0.3.7~alpha11
Architecture: iphoneos-arm64
Description: Rootless diagnostics Core with sandbox-private authenticated Manager maintenance bridge.
Maintainer: iDeviceLab contributors
Depends: firmware (>= 15.0), com.modhw.ios.diagnostics
Section: Utilities
EOF
printf '2.0\n' > "$WORK/debian-binary"
(cd "$PKG" && tar --format=ustar -czf "$WORK/data.tar.gz" --owner=0 --group=0 ./var)
(cd "$PKG/DEBIAN" && tar --format=ustar -czf "$WORK/control.tar.gz" --owner=0 --group=0 .)
python3 - "$WORK/package.deb" "$WORK" <<'PY'
import os, sys
out, root = sys.argv[1:]
with open(out, "wb") as f:
    f.write(b"!<arch>\n")
    for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        data = open(os.path.join(root, name), "rb").read()
        header = (name + "/").ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + str(len(data)).ljust(10) + "`\n"
        f.write(header.encode("ascii"))
        f.write(data)
        if len(data) % 2:
            f.write(b"\n")
PY
cp "$WORK/package.deb" "$OUT/idevelab-core-alpha11.deb"
test -s "$OUT/idevelab-core-alpha11.deb"
echo "Core DEB generated: $OUT/idevelab-core-alpha11.deb"
