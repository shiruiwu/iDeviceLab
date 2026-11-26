#!/bin/sh
# Restore one verified app-data archive. Keychain/App Groups/system data are excluded.
set -eu
APP_ROOT='/var/mobile/Containers/Data/Application'
BUNDLE_ROOT='/var/containers/Bundle/Application'
BACKUP_ROOT='/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups'
ROLLBACK_ROOT="$BACKUP_ROOT/restore-snapshots"

fail() { echo "还原中止：$*" >&2; exit 1; }
if [ "$(id -u)" -ne 0 ]; then fail '请以 root 权限运行。'; fi
if [ "$#" -ne 3 ] || [ "$3" != '--confirm' ]; then
  echo '用法：mod-hw-app-restore <bundle.identifier> <archive-name.tar.gz> --confirm' >&2
  echo '执行前必须关闭目标 App；还原会替换该 App 的整个数据容器。' >&2
  exit 2
fi
BUNDLE_ID="$1"
NAME="$2"
case "$BUNDLE_ID" in ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) fail 'Bundle ID 格式无效。' ;; esac
case "$NAME" in ''|*/*|*..*|*.tmp*|*.tar.gz.tar.gz) fail '归档文件名无效。' ;; *.tar.gz) ;; *) fail '归档必须以 .tar.gz 结尾。' ;; esac

ARCHIVE="$BACKUP_ROOT/$NAME"
MANIFEST="${ARCHIVE%.tar.gz}.txt"
[ -d "$BACKUP_ROOT" ] && [ ! -L "$BACKUP_ROOT" ] || fail '备份目录不存在或不安全。'
[ -f "$ARCHIVE" ] && [ ! -L "$ARCHIVE" ] || fail '归档不存在或为符号链接。'
[ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || fail '清单不存在或为符号链接。'
[ -x /var/jb/usr/bin/mod-hw-app-backup-verify ] || fail '缺少 mod-hw-app-backup-verify。'
/var/jb/usr/bin/mod-hw-app-backup-verify "$NAME" >/dev/null || fail '备份完整性校验失败。'

manifest_value() {
  awk -F= -v key="$1" '
    $1 == key { count++; value=substr($0, index($0, "=")+1) }
    END { if (count != 1) exit 1; print value }
  ' "$MANIFEST"
}
SAVED_BUNDLE="$(manifest_value bundle_id)" || fail '清单 Bundle ID 字段缺失或重复。'
SAVED_CONTAINER="$(manifest_value container_id)" || fail '清单容器 ID 字段缺失或重复。'
[ "$SAVED_BUNDLE" = "$BUNDLE_ID" ] || fail '指定 Bundle ID 与备份清单不一致。'
case "$SAVED_CONTAINER" in ''|*[!A-Za-z0-9-]*) fail '清单容器 ID 格式无效。' ;; esac

MATCH=''
COUNT=0
for META in "$APP_ROOT"/*/.com.apple.mobile_container_manager.metadata.plist; do
  [ -f "$META" ] || continue
  IDENTIFIER="$(plutil -extract MCMMetadataIdentifier raw -o - "$META" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then MATCH="$(dirname "$META")"; COUNT=$((COUNT + 1)); fi
done
[ "$COUNT" -eq 1 ] || fail "目标 App 数据容器匹配数量为 $COUNT，不是唯一值。"
[ "$(basename "$MATCH")" = "$SAVED_CONTAINER" ] || fail '当前容器 ID 与备份时不同；为避免覆盖重装后的新容器，拒绝还原。'

APP_MATCH=''
APP_COUNT=0
for INFO in "$BUNDLE_ROOT"/*/*.app/Info.plist; do
  [ -f "$INFO" ] || continue
  IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$INFO" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then APP_MATCH="$INFO"; APP_COUNT=$((APP_COUNT + 1)); fi
done
[ "$APP_COUNT" -eq 1 ] || fail '无法唯一定位已安装 App 的 Info.plist。'
EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_MATCH" 2>/dev/null || true)"
[ -n "$EXECUTABLE" ] || fail '无法读取 App 可执行文件名称。'
command -v pgrep >/dev/null 2>&1 || fail '缺少 pgrep，无法确认 App 已退出。'
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
  fail '目标 App 仍在运行，请完全退出后重试。'
else
  PGP_STATUS=$?
  [ "$PGP_STATUS" -eq 1 ] || fail '无法可靠确认 App 进程状态。'
fi

# Only restore regular files and directories. Reject traversal, links, devices and FIFOs.
STAMP="$(date '+%Y%m%d-%H%M%S')"
STAGE="$BACKUP_ROOT/.restore-stage.$$"
LIST="$BACKUP_ROOT/.restore-list.$$"
DETAIL="$BACKUP_ROOT/.restore-detail.$$"
SNAPSHOT="$ROLLBACK_ROOT/$BUNDLE_ID.$STAMP.$SAVED_CONTAINER.pid-$PPID"
mkdir -p "$ROLLBACK_ROOT"
chmod 0700 "$ROLLBACK_ROOT"
mkdir "$STAGE"
chmod 0700 "$STAGE"
trap 'rm -rf "$STAGE"; rm -f "$LIST" "$DETAIL"' EXIT HUP INT TERM

tar -tzf "$ARCHIVE" > "$LIST" || fail '无法读取 tar 文件列表。'
awk '
  {
    p=$0
    sub(/^\.\//, "", p)
    sub(/\/$/, "", p)
    if (p == "" || p == ".") next
    if (substr(p,1,1) == "/") exit 1
    n=split(p, parts, "/")
    for (i=1; i<=n; i++) if (parts[i] == ".." || parts[i] == "") exit 1
  }
' "$LIST" || fail '归档包含绝对路径、空路径或目录穿越路径。'
tar -tvzf "$ARCHIVE" > "$DETAIL" || fail '无法读取 tar 文件类型清单。'
awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { exit 1 }' "$DETAIL" || fail '归档包含符号链接、硬链接或特殊文件；为防止越界写入，拒绝还原。'
tar -xzpf "$ARCHIVE" -C "$STAGE" || fail '归档解压到隔离暂存目录失败。'
STAGED_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$STAGE/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
[ "$STAGED_ID" = "$BUNDLE_ID" ] || fail '备份内的容器元数据与指定 Bundle ID 不匹配。'

# Preserve the current container as a same-filesystem rollback snapshot before replacement.
mkdir "$SNAPSHOT"
chmod 0700 "$SNAPSHOT"
cp -Rp "$MATCH/." "$SNAPSHOT/" || fail '还原前快照创建失败；原数据未更改。'
if ! find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} +; then
  find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
  cp -Rp "$SNAPSHOT/." "$MATCH/" || fail '清空失败且自动回滚失败；请保留快照目录。'
  fail '清空目标容器失败，已从快照回滚。'
fi
if ! cp -Rp "$STAGE/." "$MATCH/"; then
  find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
  cp -Rp "$SNAPSHOT/." "$MATCH/" || fail '严重错误：自动回滚失败，请保留快照目录并人工恢复。'
  fail '还原复制失败，已从快照回滚。'
fi
RESTORED_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$MATCH/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
if [ "$RESTORED_ID" != "$BUNDLE_ID" ]; then
  find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
  cp -Rp "$SNAPSHOT/." "$MATCH/" || fail '元数据校验失败且自动回滚失败；请保留快照目录。'
  fail '还原后容器元数据不匹配，已回滚。'
fi

echo "App 数据容器还原完成：$BUNDLE_ID"
echo "回滚快照：$SNAPSHOT"
echo '仅还原 App 数据容器；不包含 Keychain、App Groups、共享容器、系统数据库或服务端数据。'
echo '请先启动 App 验证数据，再决定是否保留回滚快照。'
