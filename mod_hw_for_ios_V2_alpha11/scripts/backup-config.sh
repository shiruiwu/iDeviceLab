#!/bin/sh
# Back up the global Hook plist and all per-App Hook profiles as one verified archive.
set -eu
PREFERENCES='/var/mobile/Library/Preferences'
CONFIG="$PREFERENCES/com.modhw.ios.devices.plist"
PROFILE_DIR="$PREFERENCES/com.modhw.ios.profiles"
BACKUP_DIR="$PREFERENCES/mod_hw_for_ios_backups"
fail() { echo "配置备份中止：$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail '请以 root 权限运行。'
[ -d "$PREFERENCES" ] && [ ! -L "$PREFERENCES" ] || fail 'Preferences 目录不存在或不安全。'
mkdir -p "$BACKUP_DIR"
[ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ] || fail '配置备份目录不安全。'
chown root:wheel "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

STAMP="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE_NAME="config-$STAMP-$$.tar.gz"
ARCHIVE="$BACKUP_DIR/$ARCHIVE_NAME"
MANIFEST="$ARCHIVE.sha256"
STAGE="$(mktemp -d "$BACKUP_DIR/.config-stage.XXXXXX")" || fail '无法创建暂存目录。'
TMP_ARCHIVE="$BACKUP_DIR/.$ARCHIVE_NAME.tmp"
TMP_MANIFEST="$BACKUP_DIR/.$ARCHIVE_NAME.sha256.tmp"
COMMITTED=0
cleanup() {
  STATUS=$?
  trap - EXIT HUP INT TERM
  rm -rf "$STAGE"
  if [ "$COMMITTED" -ne 1 ]; then
    rm -f "$TMP_ARCHIVE" "$TMP_MANIFEST" "$ARCHIVE" "$MANIFEST"
  fi
  exit "$STATUS"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

FOUND=0
if [ -f "$CONFIG" ]; then
  [ ! -L "$CONFIG" ] || fail '全局配置是符号链接。'
  plutil -lint "$CONFIG" >/dev/null 2>&1 || fail '全局配置 plist 格式无效。'
  plutil -convert xml1 -o - "$CONFIG" 2>/dev/null | grep -q '<dict>' || fail '全局配置根对象不是 Dictionary。'
  cp -p "$CONFIG" "$STAGE/com.modhw.ios.devices.plist"
  cmp -s "$CONFIG" "$STAGE/com.modhw.ios.devices.plist" || fail '全局配置备份与原文件字节不一致。'
  plutil -lint "$STAGE/com.modhw.ios.devices.plist" >/dev/null 2>&1 || fail '暂存的全局配置 plist 校验失败。'
  FOUND=1
fi

if [ -e "$PROFILE_DIR" ]; then
  [ -d "$PROFILE_DIR" ] && [ ! -L "$PROFILE_DIR" ] || fail 'per-App 配置路径不是安全目录。'
  mkdir -m 0700 "$STAGE/com.modhw.ios.profiles"
  for PROFILE in "$PROFILE_DIR"/*.plist; do
    [ -f "$PROFILE" ] || continue
    [ ! -L "$PROFILE" ] || fail "配置文件是符号链接：$(basename "$PROFILE")"
    plutil -lint "$PROFILE" >/dev/null 2>&1 || fail "配置文件 plist 无效：$(basename "$PROFILE")"
    plutil -convert xml1 -o - "$PROFILE" 2>/dev/null | grep -q '<dict>' || fail "配置文件根对象不是 Dictionary：$(basename "$PROFILE")"
    NAME="$(basename "$PROFILE")"
    BUNDLE_ID="$(printf '%s' "$NAME" | sed 's/\.plist$//')"
    case "$BUNDLE_ID" in ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) fail "配置文件名不是有效 Bundle ID：$NAME" ;; esac
    cp -p "$PROFILE" "$STAGE/com.modhw.ios.profiles/$NAME"
    cmp -s "$PROFILE" "$STAGE/com.modhw.ios.profiles/$NAME" || fail "分 App 配置备份与原文件字节不一致：$NAME"
    plutil -lint "$STAGE/com.modhw.ios.profiles/$NAME" >/dev/null 2>&1 || fail "暂存的分 App plist 校验失败：$NAME"
    FOUND=1
  done
fi
[ "$FOUND" -eq 1 ] || fail '没有可备份的全局或 per-App Hook 配置。'

tar -czpf "$TMP_ARCHIVE" -C "$STAGE" . || fail '配置归档创建失败。'
tar -tzf "$TMP_ARCHIVE" >/dev/null 2>&1 || fail '配置归档无法读取。'
HASH="$(sha256sum "$TMP_ARCHIVE" | awk '{print $1}')"
HASH_LEN="$(printf '%s' "$HASH" | wc -c | tr -d ' ')"
[ "$HASH_LEN" -eq 64 ] || fail '无法计算配置归档 SHA-256。'
printf '%s  %s\n' "$HASH" "$ARCHIVE_NAME" > "$TMP_MANIFEST"
chown root:wheel "$TMP_ARCHIVE" "$TMP_MANIFEST"
chmod 0600 "$TMP_ARCHIVE" "$TMP_MANIFEST"
mv "$TMP_ARCHIVE" "$ARCHIVE"
mv "$TMP_MANIFEST" "$MANIFEST"
(cd "$BACKUP_DIR" && sha256sum -c "$(basename "$MANIFEST")" >/dev/null) || fail '配置归档提交后的完整性校验失败。'
COMMITTED=1
echo "配置与分 App Hook 配置备份完成：$ARCHIVE_NAME"
echo "SHA-256：$HASH"
