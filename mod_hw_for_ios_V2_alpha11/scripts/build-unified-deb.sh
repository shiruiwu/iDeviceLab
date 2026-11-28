#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/unified-deb"
PKG="$WORK/pkg"
OUT="$ROOT/release"
shopt -s nullglob
TWEAK_PACKAGES=("$ROOT"/packages/*.deb)
DIAGNOSTICS_PACKAGE="$OUT/mod_hw_for_ios_V2_diagnostics_FINAL.deb"
CORE_PACKAGE="$OUT/idevelab-core-alpha11.deb"

[ "${#TWEAK_PACKAGES[@]}" -eq 1 ] || {
  echo "Theos packages/ 必须且只能有一个当前构建的 .deb，实际为 ${#TWEAK_PACKAGES[@]} 个。" >&2
  exit 2
}
TWEAK_PACKAGE="${TWEAK_PACKAGES[0]}"
[ -s "$TWEAK_PACKAGE" ] || { echo "Theos tweak 包为空。" >&2; exit 2; }
[ -s "$DIAGNOSTICS_PACKAGE" ] || { echo "缺少 diagnostics DEB。" >&2; exit 2; }
[ -s "$CORE_PACKAGE" ] || { echo "缺少 Core DEB。" >&2; exit 2; }
command -v dpkg-deb >/dev/null 2>&1 || { echo "缺少 dpkg-deb。" >&2; exit 3; }

assert_package_field() {
  local package_path="$1"
  local field_name="$2"
  local expected_value="$3"
  local got_value
  got_value="$(dpkg-deb -f "$package_path" "$field_name")" || {
    echo "无法读取包字段 $field_name：$package_path" >&2
    exit 3
  }
  if [ "$got_value" != "$expected_value" ]; then
    echo "包身份校验失败：$package_path 的 $field_name=$got_value，预期 $expected_value" >&2
    exit 3
  fi
}
assert_package_field "$TWEAK_PACKAGE" Package com.modhw.ios
assert_package_field "$TWEAK_PACKAGE" Version '2.0.3~alpha11'
assert_package_field "$TWEAK_PACKAGE" Architecture iphoneos-arm64
assert_package_field "$DIAGNOSTICS_PACKAGE" Package com.modhw.ios.diagnostics
assert_package_field "$DIAGNOSTICS_PACKAGE" Version '2.0.0~final6'
assert_package_field "$DIAGNOSTICS_PACKAGE" Architecture iphoneos-arm64
assert_package_field "$CORE_PACKAGE" Package com.idevelab.core.alpha11
assert_package_field "$CORE_PACKAGE" Version '0.3.10~alpha11'
assert_package_field "$CORE_PACKAGE" Architecture iphoneos-arm64

rm -rf "$WORK"
mkdir -p "$PKG/DEBIAN" "$WORK/tweak" "$WORK/diagnostics" "$WORK/core"
dpkg-deb -x "$TWEAK_PACKAGE" "$WORK/tweak"
dpkg-deb -x "$DIAGNOSTICS_PACKAGE" "$WORK/diagnostics"
dpkg-deb -x "$CORE_PACKAGE" "$WORK/core"
for component in tweak diagnostics core; do
  [ ! -e "$WORK/$component/DEBIAN" ] || {
    echo "$component 数据载荷错误地包含 DEBIAN 控制目录；拒绝合并。" >&2
    exit 4
  }
done
dpkg-deb -e "$TWEAK_PACKAGE" "$WORK/control-tweak"
dpkg-deb -e "$DIAGNOSTICS_PACKAGE" "$WORK/control-diagnostics"
dpkg-deb -e "$CORE_PACKAGE" "$WORK/control-core"

for component in tweak diagnostics core; do
  for hook in preinst postinst prerm postrm; do
    if [ -e "$WORK/control-$component/$hook" ]; then
      if [ "$component" = core ] && [ "$hook" != preinst ]; then
        continue
      fi
      echo "发现 $component 的 $hook；必须先显式合并生命周期脚本，拒绝打包。" >&2
      exit 4
    fi
  done
done
for hook in postinst prerm postrm; do
  [ -s "$WORK/control-core/$hook" ] || {
    echo "Core lifecycle hook missing or empty: $hook" >&2
    exit 5
  }
done

python3 - "$WORK" "$PKG" <<'PY'
import os, shutil, stat, sys
work, destination = sys.argv[1:]
for component in ("tweak", "diagnostics", "core"):
    source = os.path.join(work, component)
    for root, dirs, files in os.walk(source):
        relative = os.path.relpath(root, source)
        target_root = destination if relative == "." else os.path.join(destination, relative)
        os.makedirs(target_root, exist_ok=True)
        if any(os.path.islink(os.path.join(root, name)) for name in dirs):
            raise SystemExit("Symlinked package directories are not accepted: " + component)
        for name in files:
            src = os.path.join(root, name)
            dst = os.path.join(target_root, name)
            if os.path.lexists(dst):
                if os.path.islink(src):
                    same = os.path.islink(dst) and os.readlink(dst) == os.readlink(src)
                else:
                    same = not os.path.islink(dst) and os.path.isfile(dst) and os.path.isfile(src)
                    if same:
                        with open(dst, "rb") as left, open(src, "rb") as right:
                            same = left.read() == right.read()
                if not same:
                    raise SystemExit("Conflicting payload path: " + os.path.relpath(dst, destination))
                continue
            if os.path.islink(src):
                os.symlink(os.readlink(src), dst)
            else:
                shutil.copy2(src, dst)
                os.chmod(dst, stat.S_IMODE(os.stat(src).st_mode))
PY

for hook in postinst prerm postrm; do
  [ -f "$WORK/control-core/$hook" ] || { echo "Core lifecycle hook missing: $hook" >&2; exit 5; }
  install -m 0755 "$WORK/control-core/$hook" "$PKG/DEBIAN/$hook"
done
for hook in postinst prerm postrm; do
  sh -n "$PKG/DEBIAN/$hook" || { echo "Invalid shell syntax in lifecycle hook: $hook" >&2; exit 5; }
done
grep -Fq 'Package payload is configured; service startup requires follow-up diagnosis.' "$PKG/DEBIAN/postinst" || {
  echo "postinst must keep daemon startup failures from interrupting dpkg configuration." >&2
  exit 5
}
cat > "$PKG/DEBIAN/control" <<'EOF'
Package: com.idevelab.fullsuite.alpha11
Name: mod_hw_for_ios V2 + iDeviceLab Alpha11 Full Suite
Version: 2.0.3~alpha11
Architecture: iphoneos-arm64
Description: Unified Rootless package containing the original mod_hw Hook, configuration and app-container maintenance tools, read-only Core, and authenticated Manager Root Helper.
Maintainer: iDeviceLab contributors
Author: Original mod_hw authors and iDeviceLab contributors
Depends: firmware (>= 15.0), mobilesubstrate, coreutils
Replaces: com.modhw.ios, com.modhw.ios.diagnostics, com.idevelab.core.alpha11
Conflicts: com.modhw.ios, com.modhw.ios.diagnostics, com.idevelab.core.alpha11
Section: Utilities
EOF

FULL_PACKAGE="$OUT/mod_hw_for_ios_V2_FULL_SUITE_ALPHA11.deb"
dpkg-deb --build --root-owner-group "$PKG" "$FULL_PACKAGE"
assert_package_field "$FULL_PACKAGE" Package com.idevelab.fullsuite.alpha11
assert_package_field "$FULL_PACKAGE" Version '2.0.3~alpha11'
assert_package_field "$FULL_PACKAGE" Architecture iphoneos-arm64
assert_package_field "$FULL_PACKAGE" Depends 'firmware (>= 15.0), mobilesubstrate, coreutils'
assert_package_field "$FULL_PACKAGE" Replaces 'com.modhw.ios, com.modhw.ios.diagnostics, com.idevelab.core.alpha11'
assert_package_field "$FULL_PACKAGE" Conflicts 'com.modhw.ios, com.modhw.ios.diagnostics, com.idevelab.core.alpha11'
dpkg-deb --info "$FULL_PACKAGE"
CONTENTS="$(dpkg-deb --contents "$FULL_PACKAGE")"
for expected in \
  'var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.dylib' \
  'var/jb/usr/bin/mod-hw-app-backup' \
  'var/jb/usr/bin/mod-hw-app-backup-verify' \
  'var/jb/usr/bin/mod-hw-app-restore' \
  'var/jb/usr/bin/mod-hw-app-clean' \
  'var/jb/usr/bin/mod-hw-acceptance-iphone12' \
  'var/jb/usr/libexec/idevelab-core' \
  'var/jb/usr/bin/mod-hw-maintenance-helper' \
  'var/jb/usr/bin/mod-hw-manager-pair' \
  'var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist' \
  'var/jb/Library/LaunchDaemons/com.idevelab.maintenance.alpha11.plist'; do
  printf '%s\n' "$CONTENTS" | grep -Fq "$expected" || { echo "Unified DEB 缺少文件：$expected" >&2; exit 6; }
done
echo "Unified Rootless DEB verified: $FULL_PACKAGE"
