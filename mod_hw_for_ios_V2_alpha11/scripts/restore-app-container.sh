#!/bin/sh
# Restore one verified app-data archive. Keychain/App Groups/system data are excluded.
set -eu
APP_ROOT='/var/mobile/Containers/Data/Application'
BUNDLE_ROOT='/var/containers/Bundle/Application'
BACKUP_ROOT='/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups'
ROLLBACK_ROOT="$BACKUP_ROOT/restore-snapshots"
fail() { echo "还原中止：$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail '请以 root 权限运行。'
[ "$#" -eq 3 ] && [ "$3" = '--confirm' ] || { echo '用法：mod-hw-app-restore <bundle.identifier> <archive-name.tar.gz> --confirm' >&2; exit 2; }
BUNDLE_ID="$1"; NAME="$2"
case "$BUNDLE_ID" in ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) fail 'Bundle ID 格式无效。' ;; esac
case "$NAME" in ''|*/*|*..*|*.tmp*|*.tar.gz.tar.gz) fail '归档文件名无效。' ;; *.tar.gz) ;; *) fail '归档必须以 .tar.gz 结尾。' ;; esac
[ -d "$BACKUP_ROOT" ] && [ ! -L "$BACKUP_ROOT" ] || fail '备份目录不存在或不安全。'
[ "$(stat -f '%u' "$BACKUP_ROOT" 2>/dev/null || echo invalid)" = 0 ] || fail '备份目录必须由 root 拥有。'
chown root:mobile "$BACKUP_ROOT"
chmod 0750 "$BACKUP_ROOT"
ARCHIVE="$BACKUP_ROOT/$NAME"
MANIFEST="$BACKUP_ROOT/$(basename "$NAME" .tar.gz).txt"
[ -f "$ARCHIVE" ] && [ ! -L "$ARCHIVE" ] || fail '归档不存在或为符号链接。'
[ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || fail '清单不存在或为符号链接。'
[ -x /var/jb/usr/bin/mod-hw-app-backup-verify ] || fail '缺少 mod-hw-app-backup-verify。'
/var/jb/usr/bin/mod-hw-app-backup-verify "$NAME" >/dev/null || fail '备份完整性校验失败。'
manifest_value() {
  awk -F= -v key="$1" '$1 == key { count++; value=substr($0, index($0, "=")+1) } END { if (count != 1) exit 1; print value }' "$MANIFEST"
}
SAVED_BUNDLE="$(manifest_value bundle_id)" || fail '清单 Bundle ID 字段缺失或重复。'
SAVED_CONTAINER="$(manifest_value container_id)" || fail '清单容器 ID 字段缺失或重复。'
[ "$SAVED_BUNDLE" = "$BUNDLE_ID" ] || fail '指定 Bundle ID 与备份清单不一致。'
case "$SAVED_CONTAINER" in ''|*[!A-Za-z0-9-]*) fail '清单容器 ID 格式无效。' ;; esac
MATCH=''; COUNT=0
for META in "$APP_ROOT"/*/.com.apple.mobile_container_manager.metadata.plist; do
  [ -f "$META" ] && [ ! -L "$META" ] || continue
  IDENTIFIER="$(plutil -extract MCMMetadataIdentifier raw -o - "$META" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then MATCH="$(dirname "$META")"; COUNT=$((COUNT + 1)); fi
done
[ "$COUNT" -eq 1 ] || fail "目标 App 数据容器匹配数量为 $COUNT，不是唯一值。"
[ -d "$MATCH" ] && [ ! -L "$MATCH" ] || fail '目标容器路径不安全。'
[ "$(basename "$MATCH")" = "$SAVED_CONTAINER" ] || fail '当前容器 ID 与备份时不同；拒绝覆盖重装后的新容器。'
APP_MATCH=''; APP_COUNT=0
for INFO in "$BUNDLE_ROOT"/*/*.app/Info.plist; do
  [ -f "$INFO" ] || continue
  IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$INFO" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then APP_MATCH="$INFO"; APP_COUNT=$((APP_COUNT + 1)); fi
done
[ "$APP_COUNT" -eq 1 ] || fail '无法唯一定位已安装 App。'
EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_MATCH" 2>/dev/null || true)"
[ -n "$EXECUTABLE" ] || fail '无法读取 App 可执行文件名称。'
command -v killall >/dev/null 2>&1 || fail '缺少系统 killall。'
if killall -0 "$EXECUTABLE" >/dev/null 2>&1; then fail '目标 App 仍在运行。'; else KILLALL_STATUS=$?; [ "$KILLALL_STATUS" -eq 1 ] || fail '无法可靠确认 App 进程状态。'; fi
STAMP="$(date '+%Y%m%d-%H%M%S')"
STAGE="$BACKUP_ROOT/.restore-stage.$$"; LIST="$BACKUP_ROOT/.restore-list.$$"; DETAIL="$BACKUP_ROOT/.restore-detail.$$"
SNAPSHOT=''; SNAPSHOT_READY=0; RESTORE_STARTED=0; SUCCESS=0
cleanup_restore() {
  STATUS=$?
  trap - EXIT HUP INT TERM
  rm -rf "$STAGE"; rm -f "$LIST" "$DETAIL"
  if [ "$RESTORE_STARTED" -eq 1 ] && [ "$SNAPSHOT_READY" -eq 1 ] && [ "$SUCCESS" -ne 1 ]; then
    echo '还原未正常完成，正在自动回滚……' >&2
    if [ -d "$MATCH" ] && [ ! -L "$MATCH" ] &&
       find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + &&
       cp -Rp "$SNAPSHOT/." "$MATCH/"; then
      ROLLBACK_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$MATCH/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
      if [ "$ROLLBACK_ID" = "$BUNDLE_ID" ]; then echo "自动回滚成功；快照保留：$SNAPSHOT" >&2; else echo "回滚元数据校验失败；保留快照：$SNAPSHOT" >&2; STATUS=1; fi
    else
      echo "自动回滚失败；请保留快照：$SNAPSHOT" >&2; STATUS=1
    fi
  fi
  exit "$STATUS"
}
trap cleanup_restore EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
[ ! -e "$STAGE" ] && [ ! -L "$STAGE" ] || fail '还原暂存路径已存在。'
mkdir "$STAGE" || fail '无法创建隔离暂存目录。'
chmod 0700 "$STAGE"
tar -tzf "$ARCHIVE" > "$LIST" || fail '无法读取 tar 文件列表。'
awk '{ p=$0; sub(/^\.\//,"",p); sub(/\/$/,"",p); if(p==""||p==".")next; if(substr(p,1,1)=="/")exit 1; n=split(p,a,"/"); for(i=1;i<=n;i++)if(a[i]==".."||a[i]=="")exit 1 }' "$LIST" || fail '归档包含绝对路径或目录穿越路径。'
tar -tvzf "$ARCHIVE" > "$DETAIL" || fail '无法读取 tar 类型清单。'
awk 'substr($0,1,1)!="-" && substr($0,1,1)!="d"{exit 1}' "$DETAIL" || fail '归档包含链接或特殊文件，拒绝还原。'
tar -xzpf "$ARCHIVE" -C "$STAGE" || fail '隔离暂存解压失败。'
STAGED_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$STAGE/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
[ "$STAGED_ID" = "$BUNDLE_ID" ] || fail '备份内的容器元数据与指定 Bundle ID 不匹配。'
[ ! -L "$ROLLBACK_ROOT" ] || fail '还原快照目录不能是符号链接。'
mkdir -p "$ROLLBACK_ROOT"
[ -d "$ROLLBACK_ROOT" ] && [ ! -L "$ROLLBACK_ROOT" ] || fail '还原快照目录不安全。'
[ "$(stat -f '%u' "$ROLLBACK_ROOT" 2>/dev/null || echo invalid)" = 0 ] || fail '还原快照目录必须由 root 拥有。'
chmod 0700 "$ROLLBACK_ROOT"
SNAPSHOT="$ROLLBACK_ROOT/$BUNDLE_ID.$STAMP.$SAVED_CONTAINER.pid-$$"
mkdir "$SNAPSHOT" || fail '无法创建唯一的还原前快照目录。'
chmod 0700 "$SNAPSHOT"
cp -Rp "$MATCH/." "$SNAPSHOT/" || fail '还原前快照创建失败；原数据未更改。'
SNAPSHOT_READY=1
RESTORE_STARTED=1
find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || fail '清空目标容器失败；已触发自动回滚。'
cp -Rp "$STAGE/." "$MATCH/" || fail '还原复制失败；已触发自动回滚。'
RESTORED_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$MATCH/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
[ "$RESTORED_ID" = "$BUNDLE_ID" ] || fail '还原后容器元数据不匹配；已触发自动回滚。'
diff -qr "$STAGE" "$MATCH" >/dev/null || fail '还原后内容与已校验备份不一致；已触发自动回滚。'
SUCCESS=1
echo "App 数据容器还原完成：$BUNDLE_ID"
echo "回滚快照：$SNAPSHOT"
echo '仅还原 App 数据容器；不包含 Keychain、App Groups、共享容器、系统数据库或服务端数据。'
echo '请先启动 App 验证数据，再决定是否保留回滚快照。'
