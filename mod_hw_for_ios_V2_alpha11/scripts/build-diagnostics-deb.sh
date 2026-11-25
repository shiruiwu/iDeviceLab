#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/diagnostics-deb"
PKG="$WORK/pkg"
OUT="$ROOT/release"
rm -rf "$WORK"
mkdir -p "$PKG/DEBIAN" "$PKG/var/jb/usr/bin" "$OUT"
cat > "$PKG/DEBIAN/control" <<'EOF'
Package: com.modhw.ios.diagnostics
Name: mod_hw_for_ios V2 Diagnostics
Version: 2.0.0~final1
Architecture: iphoneos-arm
Description: Read-only configuration plist diagnostics for rootless iOS.
Maintainer: mod_hw_for_ios contributors
Section: Utilities
EOF
install -m 0755 "$ROOT/scripts/diagnose-config.sh" "$PKG/var/jb/usr/bin/mod-hw-diagnose"
(
  cd "$PKG"
  tar --format=ustar -czf "$WORK/data.tar.gz" --owner=0 --group=0 .
)
(
  cd "$PKG/DEBIAN"
  tar --format=ustar -czf "$WORK/control.tar.gz" --owner=0 --group=0 .
)
printf '!<arch>\n' > "$WORK/package.deb"
(
  cd "$WORK"
  # Debian ar members require fixed-width headers and newline padding.
  python3 - "$WORK/package.deb" "$WORK/debian-binary" "$WORK/control.tar.gz" "$WORK/data.tar.gz" <<'PY'
import os, sys
out, *members = sys.argv[1:]
with open(out, "wb") as f:
    f.write(b"!<arch>\n")
    for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        path = os.path.join(os.path.dirname(out), name)
        data = open(path, "rb").read()
        header = (name + "/").ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + str(len(data)).ljust(10) + "`\n"
        f.write(header.encode("ascii"))
        f.write(data)
        if len(data) % 2:
            f.write(b"\n")
PY
)
printf '2.0\n' > "$WORK/debian-binary"
# Rebuild now that debian-binary exists.
python3 - "$WORK/package.deb" "$WORK" <<'PY'
import os, sys
out, root = sys.argv[1:]
with open(out, "wb") as f:
    f.write(b"!<arch>\n")
    for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        data = open(os.path.join(root, name), "rb").read()
        header = (name + "/").ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + str(len(data)).ljust(10) + "`\n"
        f.write(header.encode("ascii")); f.write(data)
        if len(data) % 2: f.write(b"\n")
PY
cp "$WORK/package.deb" "$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
test -s "$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
file "$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
