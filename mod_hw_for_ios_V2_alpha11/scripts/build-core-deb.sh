#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/core-deb"
PKG="$WORK/pkg"
OUT="$ROOT/release"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$PKG/DEBIAN" "$PKG/var/jb/usr/libexec" "$PKG/var/jb/Library/LaunchDaemons" "$OUT"
rm -rf "$WORK"
mkdir -p "$PKG/DEBIAN" "$PKG/var/jb/usr/libexec" "$PKG/var/jb/Library/LaunchDaemons"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$SDK" -fobjc-arc -Wall -Wextra -framework Foundation "$ROOT/core/main.m" -o "$PKG/var/jb/usr/libexec/idevelab-core"
chmod 0755 "$PKG/var/jb/usr/libexec/idevelab-core"
install -m 0644 "$ROOT/core/layout/Library/LaunchDaemons/com.idevelab.core.alpha11.plist" "$PKG/var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist"
cat > "$PKG/DEBIAN/control" <<'EOF'
Package: com.idevelab.core.alpha11
Name: iDeviceLab Alpha11 Core
Version: 0.2.1~alpha11
Architecture: iphoneos-arm64
Description: Rootless loopback-only read-only diagnostics Core for the Alpha11 manager.
Maintainer: iDeviceLab contributors
Depends: firmware (>= 15.0)
Section: Utilities
EOF
printf '2.0\n' > "$WORK/debian-binary"
(cd "$PKG" && tar --format=ustar -czf "$WORK/data.tar.gz" --owner=0 --group=0 .)
(cd "$PKG/DEBIAN" && tar --format=ustar -czf "$WORK/control.tar.gz" --owner=0 --group=0 .)
python3 - "$WORK/package.deb" "$WORK" <<'PY'
import os, sys
out, root = sys.argv[1:]
with open(out, "wb") as f:
    f.write(b"!<arch>\\n")
    for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        data = open(os.path.join(root, name), "rb").read()
        header = (name + "/").ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + str(len(data)).ljust(10) + "`\\n"
        f.write(header.encode("ascii"))
        f.write(data)
        if len(data) % 2:
            f.write(b"\\n")
PY
cp "$WORK/package.deb" "$OUT/idevelab-core-alpha11.deb"
test -s "$OUT/idevelab-core-alpha11.deb"
echo "Core DEB generated: $OUT/idevelab-core-alpha11.deb"
