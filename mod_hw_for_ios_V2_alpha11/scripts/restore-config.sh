#!/bin/sh
# Restore the most recently created backup, keeping a pre-restore snapshot.
set -eu
CONFIG='/var/mobile/Library/Preferences/com.modhw.ios.devices.plist'
BACKUP_DIR='/var/mobile/Library/Preferences/mod_hw_for_ios_backups'
if [ "$(id -u)" -ne 0 ]; then
  echo '请以 root 权限运行。' >&2
  exit 1
fi
LATEST="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'com.modhw.ios.devices.*.plist' -print 2>/dev/null | sort | tail -n 1)"
if [ -z "$LATEST" ] || [ ! -r "$LATEST" ]; then
  echo '没有找到可用的时间戳配置备份。' >&2
  exit 2
fi
if ! plutil -lint "$LATEST" >/dev/null 2>&1; then
  echo '备份文件 plist 格式无效，未执行还原。' >&2
  exit 3
fi
if ! plutil -convert xml1 -o - "$LATEST" 2>/dev/null | grep -q '<dict>'; then
  echo '备份根对象不是 Dictionary，未执行还原。' >&2
  exit 4
fi
DIR="$(dirname "$CONFIG")"
mkdir -p "$DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
if [ -f "$CONFIG" ]; then
  cp -p "$CONFIG" "$BACKUP_DIR/com.modhw.ios.devices.pre-restore.$STAMP.plist"
fi
TMP="$DIR/.com.modhw.ios.devices.restore.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
cp "$LATEST" "$TMP"
plutil -lint "$TMP" >/dev/null
chown mobile:mobile "$TMP"
chmod 0644 "$TMP"
mv -f "$TMP" "$CONFIG"
trap - EXIT HUP INT TERM
echo "配置还原完成。来源：$(basename "$LATEST")"
echo '未重启 SpringBoard 或其他系统进程；请先检查配置，再按需手动重载。'
