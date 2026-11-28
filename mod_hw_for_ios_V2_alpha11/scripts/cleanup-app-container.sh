#!/var/jb/bin/sh
# Clear one installed app's local data container after making a verified backup.
# Keychain, App Groups, shared containers and server-side data are not touched.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
BIN_DIR="$SCRIPT_DIR"
JBROOT=$(CDPATH= cd -- "$BIN_DIR/../.." && pwd -P) || exit 1
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
command -v killall >/dev/null 2>&1 || fail '缺少系统 killall，无法确认 App 已退出。'
[ -x "$BIN_DIR/mod-hw-app-backup" ] || fail '缺少 mod-hw-app-backup。'
[ -x ""$BIN_DIR/mod-hw-app-backup"-verify" ] || fail '缺少 mod-hw-app-backup-verify。'

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
if killall -0 "$EXECUTABLE" >/dev/null 2>&1; then
  fail '目标 App 仍在运行，请完全退出后重试。'
else
  KILLALL_STATUS=$?
  [ "$KILLALL_STATUS" -eq 1 ] || fail '无法可靠确认 App 进程状态。'
fi

MATCH=''
COUNT=0
for META in "$APP_ROOT"/*/.com.apple.mobile_container_manager.metadata.plist; do
  [ -f "$META" ] && [ ! -L "$META" ] || continue
  IDENTIFIER="$(plutil -extract MCMMetadataIdentifier raw -o - "$META" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then MATCH="$(dirname "$META")"; COUNT=$((COUNT + 1)); fi
done
[ "$COUNT" -eq 1 ] || fail "目标数据容器匹配数量为 $COUNT，不是唯一值。"
[ -d "$MATCH" ] && [ ! -L "$MATCH" ] || fail '目标数据容器路径不安全。'

# Create and verify an archive before changing anything.
BACKUP_OUTPUT="$(""$BIN_DIR/mod-hw-app-backup"" "$BUNDLE_ID")" || fail '自动备份失败；未清理数据。'
ARCHIVE_PATH="$(printf '%s\n' "$BACKUP_OUTPUT" | sed -n 's/^应用数据容器备份完成：//p' | tail -n 1)"
[ -n "$ARCHIVE_PATH" ] || fail '无法从备份工具结果中定位归档；未清理数据。'
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
"""$BIN_DIR/mod-hw-app-backup"-verify"" "$ARCHIVE_NAME" >/dev/null || fail '自动备份校验失败；未清理数据。'

[ -d "$BACKUP_ROOT" ] && [ ! -L "$BACKUP_ROOT" ] || fail '备份目录不存在或不安全。'
[ "$(/usr/bin/stat -f '%u' "$BACKUP_ROOT" 2>/dev/null || echo invalid)" = 0 ] || fail '备份目录必须由 root 拥有。'
chown root:mobile "$BACKUP_ROOT"
chmod 0750 "$BACKUP_ROOT"
DETAIL_LIST="$(mktemp "$BACKUP_ROOT/.cleanup-archive-list.XXXXXX")" || fail '无法创建归档检查临时文件。'
SNAPSHOT_READY=0
DESTRUCTIVE_STARTED=0
SUCCESS=0
SNAPSHOT=''
cleanup_on_exit() {
  STATUS=$?
  trap - EXIT HUP INT TERM
  [ -n "$DETAIL_LIST" ] && rm -f "$DETAIL_LIST"
  if [ "$DESTRUCTIVE_STARTED" -eq 1 ] && [ "$SNAPSHOT_READY" -eq 1 ] && [ "$SUCCESS" -ne 1 ]; then
    echo '检测到清理未正常完成，正在从清理前快照自动回滚……' >&2
    if [ -d "$MATCH" ] && [ ! -L "$MATCH" ] &&
       find "$MATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + &&
       cp -Rp "$SNAPSHOT/." "$MATCH/" &&
       diff -qr "$SNAPSHOT" "$MATCH" >/dev/null; then
      ROLLBACK_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$MATCH/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
      if [ "$ROLLBACK_ID" = "$BUNDLE_ID" ]; then
        echo "自动回滚成功；快照保留：$SNAPSHOT" >&2
      else
        echo "自动回滚后的容器元数据校验失败；请保留快照：$SNAPSHOT" >&2
        STATUS=1
      fi
    else
      echo "自动回滚失败；请保留快照并人工恢复：$SNAPSHOT" >&2
      STATUS=1
    fi
  fi
  exit "$STATUS"
}
trap 'cleanup_on_exit' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! tar -tvzf "$ARCHIVE_PATH" > "$DETAIL_LIST"; then
  fail '无法读取备份归档目录；已中止清理。'
fi
if ! awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { bad=1 } END { exit bad }' "$DETAIL_LIST"; then
  fail '备份包含符号链接或特殊文件，当前还原工具无法安全处理；已中止清理。'
fi
rm -f "$DETAIL_LIST"
DETAIL_LIST=''

STAMP="$(date '+%Y%m%d-%H%M%S')"
if [ -L "$SNAPSHOT_ROOT" ]; then fail '清理快照目录不能是符号链接。'; fi
mkdir -p "$SNAPSHOT_ROOT"
[ -d "$SNAPSHOT_ROOT" ] && [ ! -L "$SNAPSHOT_ROOT" ] || fail '清理快照目录不安全。'
[ "$(/usr/bin/stat -f '%u' "$SNAPSHOT_ROOT" 2>/dev/null || echo invalid)" = 0 ] || fail '清理快照目录必须由 root 拥有。'
chmod 0700 "$SNAPSHOT_ROOT"
SNAPSHOT="$SNAPSHOT_ROOT/$BUNDLE_ID.$STAMP.pid-$$"
mkdir "$SNAPSHOT" || fail '无法创建唯一的清理前快照目录。'
chmod 0700 "$SNAPSHOT"
cp -Rp "$MATCH/." "$SNAPSHOT/" || fail '清理前快照创建失败；未清理数据。'
SNAPSHOT_READY=1

# Keep the MCM metadata marker so iOS retains the current container registration.
DESTRUCTIVE_STARTED=1
find "$MATCH" -mindepth 1 -maxdepth 1 ! -name '.com.apple.mobile_container_manager.metadata.plist' -exec rm -rf {} + ||
  fail '清理过程中发生错误；已触发自动回滚。'
CURRENT_ID="$(plutil -extract MCMMetadataIdentifier raw -o - "$MATCH/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null || true)"
[ "$CURRENT_ID" = "$BUNDLE_ID" ] || fail '容器元数据校验失败；已触发自动回滚。'
REMAINING="$(find "$MATCH" -mindepth 1 -maxdepth 1 ! -name '.com.apple.mobile_container_manager.metadata.plist' -print -quit)" || fail '清理结果目录检查失败；已触发自动回滚。'
[ -z "$REMAINING" ] || fail '清理后仍有未删除项目；已触发自动回滚。'

# Queue Keychain cleanup for execution inside the target app process. This is
# deliberately limited to the app's private application-identifier access group;
# shared groups and iCloud-synchronizable items are excluded.
CACHE_DIR="$MATCH/Library/Caches"
mkdir -p "$CACHE_DIR" || fail '无法创建目标 App 的 Keychain 清理任务目录；已触发自动回滚。'
[ -d "$MATCH/Library" ] && [ ! -L "$MATCH/Library" ] || fail 'Library 目录不安全；已触发自动回滚。'
[ -d "$CACHE_DIR" ] && [ ! -L "$CACHE_DIR" ] || fail 'Caches 目录不安全；已触发自动回滚。'
chown mobile:mobile "$MATCH/Library" "$CACHE_DIR" || fail '无法设置 Keychain 清理任务目录权限；已触发自动回滚。'
chmod 0700 "$MATCH/Library" "$CACHE_DIR" || fail '无法设置 Keychain 清理任务目录模式；已触发自动回滚。'
REQUEST_ID="$(/usr/bin/od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
[ "${#REQUEST_ID}" -eq 32 ] || fail '无法生成 Keychain 清理任务编号；已触发自动回滚。'
REQUEST_PATH="$CACHE_DIR/.modhw-keychain-clean.request.plist"
RESULT_PATH="$CACHE_DIR/.modhw-keychain-clean.result.plist"
REQUEST_TMP="$REQUEST_PATH.tmp.$REQUEST_ID"
rm -f "$REQUEST_PATH" "$RESULT_PATH" "$REQUEST_TMP"
umask 077
cat > "$REQUEST_TMP" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>bundleIdentifier</key><string>$BUNDLE_ID</string>
<key>requestID</key><string>$REQUEST_ID</string>
</dict></plist>
EOF
chown mobile:mobile "$REQUEST_TMP" || fail '无法设置 Keychain 清理任务所有者；已触发自动回滚。'
chmod 0600 "$REQUEST_TMP" || fail '无法设置 Keychain 清理任务权限；已触发自动回滚。'
mv "$REQUEST_TMP" "$REQUEST_PATH" || fail '无法发布 Keychain 清理任务；已触发自动回滚。'

SUCCESS=1
echo "App 本地数据容器清理完成：$BUNDLE_ID"
echo "自动备份：$ARCHIVE_NAME"
echo "回滚快照：$SNAPSHOT"
echo 'Keychain 清理任务已排队：首次打开目标 App 后执行。'
echo '范围：仅目标 App 私有 application-identifier 访问组的本机条目；共享 Keychain 组及 iCloud 同步条目不删除。'
echo 'App Groups、共享容器、系统数据库、通知/云端记录或服务端数据不在清理范围内。'
