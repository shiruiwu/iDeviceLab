#!/var/jb/bin/sh
# Restore a verified global + per-App Hook configuration bundle with rollback.
set -eu
PREFERENCES='/var/mobile/Library/Preferences'
CONFIG="$PREFERENCES/com.modhw.ios.devices.plist"
PROFILE_DIR="$PREFERENCES/com.modhw.ios.profiles"
BACKUP_DIR="$PREFERENCES/mod_hw_for_ios_backups"
fail() { echo "配置还原中止：$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail '请以 root 权限运行。'
[ -d "$PREFERENCES" ] && [ ! -L "$PREFERENCES" ] || fail 'Preferences 目录不安全。'
[ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ] || fail '配置备份目录不存在或不安全。'

LATEST="$(ls -1t "$BACKUP_DIR"/config-*.tar.gz 2>/dev/null | head -n 1 || true)"
if [ -n "$LATEST" ] && [ -r "$LATEST" ]; then
  MANIFEST="$LATEST.sha256"
  [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || fail '配置归档缺少 SHA-256 清单。'
  (cd "$BACKUP_DIR" && sha256sum -c "$(basename "$MANIFEST")" >/dev/null) || fail '配置归档 SHA-256 校验失败。'

  STAGE="$(mktemp -d "$BACKUP_DIR/.restore-stage.XXXXXX")" || fail '无法创建还原暂存目录。'
  LISTING="$BACKUP_DIR/.restore-list.$$"
  VERBOSE="$BACKUP_DIR/.restore-verbose.$$"
  ROLLBACK="$BACKUP_DIR/rollback-snapshots/config-bundle-$(date '+%Y%m%d-%H%M%S')-$$"
  TEMP_GLOBAL="$PREFERENCES/.com.modhw.ios.devices.restore.$$"
  TEMP_PROFILES="$PREFERENCES/.com.modhw.ios.profiles.restore.$$"
  GLOBAL_EXISTED=0
  PROFILES_EXISTED=0
  RESTORE_STARTED=0
  SUCCESS=0

  finish() {
    STATUS=$?
    trap - EXIT HUP INT TERM
    if [ "$RESTORE_STARTED" -eq 1 ] && [ "$SUCCESS" -ne 1 ]; then
      echo '检测到还原中断或失败，正在恢复还原前快照。' >&2
      if [ "$GLOBAL_EXISTED" -eq 1 ]; then
        cp -p "$ROLLBACK/global-before.plist" "$TEMP_GLOBAL" &&
          chown root:mobile "$TEMP_GLOBAL" && chmod 0640 "$TEMP_GLOBAL" &&
          mv -f "$TEMP_GLOBAL" "$CONFIG" || STATUS=1
      else
        rm -f "$CONFIG"
      fi
      if [ "$PROFILES_EXISTED" -eq 1 ]; then
        rm -rf "$PROFILE_DIR"
        cp -Rp "$ROLLBACK/profiles-before" "$PROFILE_DIR" || STATUS=1
      else
        rm -rf "$PROFILE_DIR"
      fi
    fi
    rm -rf "$STAGE" "$TEMP_PROFILES"
    rm -f "$TEMP_GLOBAL" "$LISTING" "$VERBOSE"
    exit "$STATUS"
  }
  trap finish EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  tar -tzf "$LATEST" > "$LISTING" 2>/dev/null || fail '配置归档目录表损坏。'
  while IFS= read -r ENTRY; do
    case "$ENTRY" in
      './'|'./com.modhw.ios.devices.plist'|'./com.modhw.ios.profiles'|'./com.modhw.ios.profiles/') ;;
      './com.modhw.ios.profiles/'*.plist)
        PROFILE_NAME="${ENTRY#./com.modhw.ios.profiles/}"
        case "$PROFILE_NAME" in
          ''|.*|*/*|*..*|*.) fail "归档中的分 App 配置路径无效：$ENTRY" ;;
          *[!A-Za-z0-9._-]*) fail "归档中的分 App 配置文件名无效：$ENTRY" ;;
          *.plist) ;;
          *) fail "归档中的分 App 配置不是 plist：$ENTRY" ;;
        esac
        BUNDLE_ID="${PROFILE_NAME%.plist}"
        [ -n "$BUNDLE_ID" ] || fail "归档中的分 App Bundle ID 为空：$ENTRY"
        ;;
      *) fail "归档包含未允许的路径：$ENTRY" ;;
    esac
  done < "$LISTING"
  if LC_ALL=C sort "$LISTING" | uniq -d | grep -q .; then
    fail '配置归档包含重复路径，拒绝还原。'
  fi
  tar -tvzf "$LATEST" > "$VERBOSE" 2>/dev/null || fail '无法读取配置归档详细目录。'
  while IFS= read -r LINE; do
    TYPE="$(printf '%s' "$LINE" | cut -c 1)"
    case "$TYPE" in -|d) ;; *) fail '配置归档包含符号链接、硬链接或特殊文件。' ;; esac
  done < "$VERBOSE"

  tar -xzf "$LATEST" -C "$STAGE" || fail '配置归档解压失败。'
  if [ -f "$STAGE/com.modhw.ios.devices.plist" ]; then
    [ ! -L "$STAGE/com.modhw.ios.devices.plist" ] || fail '全局配置是符号链接。'
    plutil -lint "$STAGE/com.modhw.ios.devices.plist" >/dev/null 2>&1 || fail '全局配置 plist 格式无效。'
    plutil -convert xml1 -o - "$STAGE/com.modhw.ios.devices.plist" 2>/dev/null | grep -q '<dict>' || fail '全局配置根对象不是 Dictionary。'
  fi
  if [ -e "$STAGE/com.modhw.ios.profiles" ]; then
    [ -d "$STAGE/com.modhw.ios.profiles" ] && [ ! -L "$STAGE/com.modhw.ios.profiles" ] || fail 'per-App 配置目录不安全。'
    for PROFILE in "$STAGE/com.modhw.ios.profiles"/*.plist; do
      [ -f "$PROFILE" ] || continue
      [ ! -L "$PROFILE" ] || fail 'per-App 配置包含符号链接。'
      NAME="$(basename "$PROFILE")"
      BUNDLE_ID="$(printf '%s' "$NAME" | sed 's/\.plist$//')"
      case "$BUNDLE_ID" in ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) fail "per-App 配置文件名无效：$NAME" ;; esac
      plutil -lint "$PROFILE" >/dev/null 2>&1 || fail "per-App plist 格式无效：$NAME"
      plutil -convert xml1 -o - "$PROFILE" 2>/dev/null | grep -q '<dict>' || fail "per-App plist 根对象不是 Dictionary：$NAME"
    done
  fi
  [ -f "$STAGE/com.modhw.ios.devices.plist" ] || [ -d "$STAGE/com.modhw.ios.profiles" ] || fail '归档中没有可还原的配置。'

  mkdir -p "$BACKUP_DIR/rollback-snapshots"
  mkdir -m 0700 "$ROLLBACK"
  chown root:wheel "$ROLLBACK"
  chmod 0700 "$ROLLBACK"
  if [ -e "$CONFIG" ]; then
    [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ] || fail '当前全局配置不是普通文件。'
    cp -p "$CONFIG" "$ROLLBACK/global-before.plist"
    GLOBAL_EXISTED=1
  fi
  if [ -e "$PROFILE_DIR" ]; then
    [ -d "$PROFILE_DIR" ] && [ ! -L "$PROFILE_DIR" ] || fail '当前 per-App 配置路径不安全。'
    if find "$PROFILE_DIR" -type l -print | grep -q .; then fail '当前 per-App 配置目录含有符号链接。'; fi
    cp -Rp "$PROFILE_DIR" "$ROLLBACK/profiles-before"
    PROFILES_EXISTED=1
  fi

  RESTORE_STARTED=1
  if [ -f "$STAGE/com.modhw.ios.devices.plist" ]; then
    cp "$STAGE/com.modhw.ios.devices.plist" "$TEMP_GLOBAL"
    chown root:mobile "$TEMP_GLOBAL"
    chmod 0640 "$TEMP_GLOBAL"
    mv -f "$TEMP_GLOBAL" "$CONFIG"
  else
    rm -f "$CONFIG"
  fi
  if [ -d "$STAGE/com.modhw.ios.profiles" ]; then
    rm -rf "$TEMP_PROFILES"
    mkdir -m 0750 "$TEMP_PROFILES"
    for PROFILE in "$STAGE/com.modhw.ios.profiles"/*.plist; do
      [ -f "$PROFILE" ] || continue
      cp "$PROFILE" "$TEMP_PROFILES/$(basename "$PROFILE")"
      chown root:mobile "$TEMP_PROFILES/$(basename "$PROFILE")"
      chmod 0640 "$TEMP_PROFILES/$(basename "$PROFILE")"
    done
    chown root:mobile "$TEMP_PROFILES"
    chmod 0750 "$TEMP_PROFILES"
    rm -rf "$PROFILE_DIR"
    mv "$TEMP_PROFILES" "$PROFILE_DIR"
  else
    rm -rf "$PROFILE_DIR"
  fi
  SUCCESS=1
  echo "全局与 per-App Hook 配置还原完成。来源：$(basename "$LATEST")"
  echo "还原前快照保留在：$ROLLBACK"
  echo '未重启 SpringBoard 或目标 App；请检查配置并重新启动需要应用配置的 App。'
  exit 0
fi

# Backward compatibility for legacy single-plist backups created by earlier builds.
LATEST="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'com.modhw.ios.devices.*.plist' -print 2>/dev/null | sort | tail -n 1)"
[ -n "$LATEST" ] && [ -r "$LATEST" ] || fail '没有找到可用的配置备份。'
plutil -lint "$LATEST" >/dev/null 2>&1 || fail '旧版备份 plist 格式无效。'
plutil -convert xml1 -o - "$LATEST" 2>/dev/null | grep -q '<dict>' || fail '旧版备份根对象不是 Dictionary。'
mkdir -p "$BACKUP_DIR/rollback-snapshots"
STAMP="$(date '+%Y%m%d-%H%M%S')"
if [ -f "$CONFIG" ]; then cp -p "$CONFIG" "$BACKUP_DIR/rollback-snapshots/current-before-restore.$STAMP.$$.plist"; fi
TMP="$PREFERENCES/.com.modhw.ios.devices.restore.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
cp "$LATEST" "$TMP"
plutil -lint "$TMP" >/dev/null
chown mobile:mobile "$TMP"
chmod 0644 "$TMP"
mv -f "$TMP" "$CONFIG"
trap - EXIT HUP INT TERM
echo "旧版全局配置还原完成。来源：$(basename "$LATEST")"
echo '未重启 SpringBoard 或其他系统进程；请先检查配置，再按需手动重载。'
