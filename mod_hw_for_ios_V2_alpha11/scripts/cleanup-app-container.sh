#!/bin/sh
# Clear one installed app's local data container after making a verified backup.
# Keychain, App Groups, shared containers and server-side data are not touched.
set -eu
APP_ROOT='/var/mobile/Containers/Data/Application'
BUNDLE_ROOT='/var/containers/Bundle/Application'
BACKUP_ROOT='/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups'
SNAPSHOT_ROOT="$BACKUP_ROOT/cleanup-snapshots"

fail() { echo "清理中止：$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail '请以 root 权限运行。'
[ "$#" -eq 2 ] && [ "$2" = '--confirm' ] || {
  echo '用法：mod-hw-app-clean <bundle.identifier> --confirm' >&2
  echo '此操作会清空指定 App 的整个本地数据容器；执行前自动备份。' >&2
  exit 2
}
BUNDLE_ID="$1"
case "$BUNDLE_ID" in ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) fail 'Bundle ID 格式无效。' ;; esac
command -v pgrep >/dev/null 2>&1 || fail '缺少 pgrep，无法确认 App 已退出。'
command -v mod-hw-app-backup >/dev/null 2>&1 || fail '缺少 mod-hw-app-backup。'
command -v mod-hw-app-backup-verify >/dev/null 2>&1 || fail '缺少 mod-hw-app-backup-verify。'

APP_MATCH=''
APP_COUNT=0
for INFO in "$BUNDLE_ROOT"/*/*.app/Info.plist; do
  [ -f "$INFO" ] || continue
  IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$INFO" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then APP_MATCH="$INFO"; APP_COUNT=$((APP_COUNT + 1)); fi
done
[ "$APP_COUNT" -eq 1 ] || fail '无法唯一定位已安装 App。'
EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_MATCH" 2>/dev/null || true)"
[ -n "$EXECUTABLE" ] || fail '无法读取 App 可执行文件名称。'
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
  fail '目标 App 仍在运行，请完全退出后重试。'
else
  PGP_STATUS=$?
  [ "$PGP_STATUS" -eq 1 ] || fail '无法可靠确认 App 进程状态。'
fi

MATCH=''
COUNT=0
for META in "$APP_ROOT"/*/.com.apple.mobile_container_manager.metadata.plist; do
  [ -f "$META" ] || continue
  IDENTIFIER="$(plutil -extract MCMMetadataIdentifier raw -o - "$META" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then MATCH="$(dirname "$META")"; COUNT=$((COUNT + 1)); fi
done
[ "$COUNT" -eq 1 ] || fail "目标数据容器匹配数量为 $COUNT，不是唯一值。"
[ -d "$MATCH" ] && [ ! -L "$MATCH" ] || fail "目标数据容器路径不安全。"

# Create and verify an archive before changing anything.
BACKUP_OUTPUT="$(mod-hw-app-backup "$BUNDLE_ID")" || fail '自动备份失败；未清理数据。'
ARCHIVE_PATH="$(printf '%s\n' "$BACKUP_OUTPUT" | sed -n 's/^应用数据容器备份完成：//p' | tail -n 1)"
[ -n "$ARCHIVE_PATH" ] || fail '无法从备份工具结果中定位归档；未清理数据。'
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
mod-hw-app-backup-verify "$ARCHIVE_NAME" >/dev/null || fail '自动备份校验失败；未清理数据。'

STAMP="$(date '+%Y%m%d-%H%M%S')"
SNAPSHOT="$SNAPSHOT_ROOT/$BUNDLE_ID.$STAMP.pid-$PPID"
mkdir -p "$SNAPSHOT_ROOT"
chmod 0700 "$SNAPSHOT_ROOT"
mkdir "$SNAPSHOT"
chmod 0700 "$SNAPSHOT"
cp -Rp "$MATCH/." "$SNAPSHOT/" || fail '清理前快照创建失败；未清理数据。'

# Keep the MCM metadata marker so iOS retains the current container registration.
if ! find "$MATCH" -mindepth 1 -maxdepth 1 ! -name '.com.apple.mobile_container_manager.metadata.plist' -exec rm -rf {} +; then
  find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
  cp -Rp "$SNAPSHOT/." "$MATCH/" || fail '清理失败且自动回滚失败；请保留快照目录。'
  fail '清理过程中发生错误，已回滚。'
fi
CURRENT_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$MATCH/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
if [ "$CURRENT_ID" != "$BUNDLE_ID" ]; then
  find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
  cp -Rp "$SNAPSHOT/." "$MATCH/" || fail '元数据校验失败且自动回滚失败；请保留快照目录。'
  fail '容器元数据校验失败，已回滚。'
fi

echo "App 本地数据容器清理完成：$BUNDLE_ID"
echo "自动备份：$ARCHIVE_NAME"
echo "回滚快照：$SNAPSHOT"
echo '此操作不清除 Keychain、App Groups、共享容器、系统数据库、通知/云端记录或服务端数据。'
