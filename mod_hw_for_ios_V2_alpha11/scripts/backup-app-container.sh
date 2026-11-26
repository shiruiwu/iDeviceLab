#!/bin/sh
# Create a private, timestamped archive of one installed app's data container.
# This does not touch the app, Keychain, App Group containers, or system databases.
set -eu

APP_ROOT='/var/mobile/Containers/Data/Application'
BACKUP_ROOT='/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups'

if [ "$(id -u)" -ne 0 ]; then
  echo '请以 root 权限运行。' >&2
  exit 1
fi
if [ "$#" -ne 1 ]; then
  echo '用法：mod-hw-app-backup <bundle.identifier>' >&2
  exit 2
fi
BUNDLE_ID="$1"
case "$BUNDLE_ID" in
  ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) echo 'Bundle ID 格式无效。' >&2; exit 2 ;;
esac
if [ ! -d "$APP_ROOT" ]; then
  echo "未找到应用容器目录：$APP_ROOT" >&2
  exit 3
fi

MATCH=''
COUNT=0
for META in "$APP_ROOT"/*/.com.apple.mobile_container_manager.metadata.plist; do
  [ -f "$META" ] || continue
  IDENTIFIER="$(plutil -extract MCMMetadataIdentifier raw -o - "$META" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then
    MATCH="$(dirname "$META")"
    COUNT=$((COUNT + 1))
  fi
done
if [ "$COUNT" -eq 0 ]; then
  echo "没有找到 Bundle ID 对应的数据容器：$BUNDLE_ID" >&2
  exit 4
fi
if [ "$COUNT" -ne 1 ]; then
  echo "发现 $COUNT 个匹配容器，无法安全确定目标；未备份。" >&2
  exit 5
fi
if [ ! -r "$MATCH" ] || [ ! -x "$MATCH" ] || [ -L "$MATCH" ]; then
  echo '目标容器不可读、不可访问或为符号链接。' >&2
  exit 6
fi

mkdir -p "$BACKUP_ROOT"
[ -d "$BACKUP_ROOT" ] && [ ! -L "$BACKUP_ROOT" ] || {
  echo '备份目录不是安全的普通目录。' >&2
  exit 7
}
BACKUP_OWNER="$(stat -f '%u' "$BACKUP_ROOT" 2>/dev/null || echo invalid)"
[ "$BACKUP_OWNER" = 0 ] || {
  echo '备份目录必须由 root 拥有。' >&2
  exit 7
}
chown root:mobile "$BACKUP_ROOT"
chmod 0750 "$BACKUP_ROOT"
STAMP="$(date '+%Y%m%d-%H%M%S')"
CONTAINER_ID="$(basename "$MATCH")"
BASE="$BACKUP_ROOT/$BUNDLE_ID.$STAMP.$CONTAINER_ID"
ARCHIVE="$BASE.tar.gz"
TMP="$ARCHIVE.tmp.$$"
MANIFEST="$BASE.txt"
MANIFEST_TMP="$MANIFEST.tmp.$$"
COMMITTED=0
cleanup_backup() {
  rm -f "$TMP" "$MANIFEST_TMP"
  if [ "$COMMITTED" -ne 1 ]; then
    rm -f "$ARCHIVE" "$MANIFEST"
  fi
}
# EXIT performs cleanup; signal handlers exit so the EXIT trap always runs.
trap 'cleanup_backup' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -e "$ARCHIVE" ] || [ -e "$MANIFEST" ] || [ -e "$TMP" ] || [ -e "$MANIFEST_TMP" ]; then
  echo '备份目标已存在；未覆盖现有文件。' >&2
  exit 8
fi

tar -czpf "$TMP" -C "$MATCH" .
tar -tzf "$TMP" >/dev/null
chmod 0640 "$TMP"
chown root:mobile "$TMP"
mv "$TMP" "$ARCHIVE"
HASH="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
{
  echo "bundle_id=$BUNDLE_ID"
  echo "container_id=$CONTAINER_ID"
  echo "created_at=$STAMP"
  echo "archive=$(basename "$ARCHIVE")"
  echo "sha256=$HASH"
  echo 'scope=app-data-container-only'
  echo 'excluded=Keychain, App Groups, shared containers, system databases'
} > "$MANIFEST_TMP"
chmod 0640 "$MANIFEST_TMP"
chown root:mobile "$MANIFEST_TMP"
mv "$MANIFEST_TMP" "$MANIFEST"
COMMITTED=1
trap - EXIT HUP INT TERM
echo "应用数据容器备份完成：$ARCHIVE"
echo "SHA-256：$HASH"
echo '说明：此备份不包含 Keychain、App Groups 或系统级数据；尚未执行任何清理或还原。'
