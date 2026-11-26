#!/bin/sh
# Create a timestamped, byte-preserving backup of the tweak configuration.
set -eu
CONFIG='/var/mobile/Library/Preferences/com.modhw.ios.devices.plist'
BACKUP_DIR='/var/mobile/Library/Preferences/mod_hw_for_ios_backups'
if [ "$(id -u)" -ne 0 ]; then
  echo '请以 root 权限运行。' >&2
  exit 1
fi
if [ ! -f "$CONFIG" ] || [ ! -r "$CONFIG" ]; then
  echo '配置文件不存在或不可读。' >&2
  exit 2
fi
if ! plutil -lint "$CONFIG" >/dev/null 2>&1; then
  echo '配置文件 plist 格式无效，未创建备份。' >&2
  exit 3
fi
mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
DEST="$BACKUP_DIR/com.modhw.ios.devices.$STAMP.plist"
if [ -e "$DEST" ]; then
  echo "备份目标已存在：$DEST" >&2
  exit 4
fi
cp -p "$CONFIG" "$DEST"
chmod 0600 "$DEST"
cmp -s "$CONFIG" "$DEST"
echo "配置备份完成：$DEST"
