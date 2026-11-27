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
Name: mod_hw_for_ios V2 Config Tools
Version: 2.0.0~final6
Architecture: iphoneos-arm64
Description: Rootless config diagnostics, config backup/restore, and backup, guarded restore, and backup-first app-container cleanup tools.
Maintainer: mod_hw_for_ios contributors
Depends: coreutils
Section: Utilities
EOF
install -m 0755 "$ROOT/scripts/diagnose-config.sh" "$PKG/var/jb/usr/bin/mod-hw-diagnose"
install -m 0755 "$ROOT/scripts/backup-config.sh" "$PKG/var/jb/usr/bin/mod-hw-config-backup"
install -m 0755 "$ROOT/scripts/restore-config.sh" "$PKG/var/jb/usr/bin/mod-hw-config-restore"
install -m 0755 "$ROOT/scripts/backup-app-container.sh" "$PKG/var/jb/usr/bin/mod-hw-app-backup"
install -m 0755 "$ROOT/scripts/restore-app-container.sh" "$PKG/var/jb/usr/bin/mod-hw-app-restore"
install -m 0755 "$ROOT/scripts/cleanup-app-container.sh" "$PKG/var/jb/usr/bin/mod-hw-app-clean"
install -m 0755 "$ROOT/scripts/verify-app-container-backup.sh" "$PKG/var/jb/usr/bin/mod-hw-app-backup-verify"
install -m 0755 "$ROOT/scripts/selftest-device.sh" "$PKG/var/jb/usr/bin/mod-hw-selftest"
install -m 0755 "$ROOT/scripts/acceptance-iphone12.sh" "$PKG/var/jb/usr/bin/mod-hw-acceptance-iphone12"
install -m 0755 "$ROOT/scripts/diagnose-keychain-access.sh" "$PKG/var/jb/usr/bin/mod-hw-keychain-diagnose"
install -m 0755 "$ROOT/scripts/maintenance-dispatch.sh" "$PKG/var/jb/usr/bin/mod-hw-maintenance"
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
cp "$WORK/package.deb" "$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
test -s "$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
file "$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
