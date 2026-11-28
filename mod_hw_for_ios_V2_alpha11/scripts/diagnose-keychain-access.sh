#!/var/jb/bin/sh
# Read-only inspection of signed Keychain entitlement declarations for one installed app.
# Does not read, export, delete, or modify Keychain items.
set -eu
BUNDLE_ROOT='/var/containers/Bundle/Application'
fail() { echo "Keychain 诊断中止：$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail '请以 root 权限运行。'
[ "$#" -eq 1 ] || { echo '用法：mod-hw-keychain-diagnose <bundle.identifier>' >&2; exit 2; }
BUNDLE_ID="$1"
case "$BUNDLE_ID" in ''|*[!A-Za-z0-9._-]*|.*|*..*|*.) fail 'Bundle ID 格式无效。' ;; esac
APP_INFO=''; COUNT=0
for INFO in "$BUNDLE_ROOT"/*/*.app/Info.plist; do
  [ -f "$INFO" ] || continue
  IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$INFO" 2>/dev/null || true)"
  if [ "$IDENTIFIER" = "$BUNDLE_ID" ]; then APP_INFO="$INFO"; COUNT=$((COUNT + 1)); fi
done
[ "$COUNT" -eq 1 ] || fail "已安装 App 匹配数量为 $COUNT，无法唯一定位。"
APP_DIR="$(dirname "$APP_INFO")"
EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_INFO" 2>/dev/null || true)"
[ -n "$EXECUTABLE" ] || fail '无法读取 App 可执行文件名称。'
APP_BINARY="$APP_DIR/$EXECUTABLE"
[ -f "$APP_BINARY" ] && [ ! -L "$APP_BINARY" ] || fail 'App 主程序不存在或路径不安全。'
WORK="$(mktemp -d /var/tmp/mod-hw-keychain.XXXXXX)" || fail '无法创建临时目录。'
chmod 0700 "$WORK"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
RAW="$WORK/entitlements.plist"; XML="$WORK/entitlements.xml"; SOURCE=''
if command -v ldid >/dev/null 2>&1; then
  ldid -e "$APP_BINARY" > "$RAW" 2>/dev/null || fail 'ldid 无法读取签名 Entitlements。'
  SOURCE='ldid'
elif command -v codesign >/dev/null 2>&1; then
  codesign -d --entitlements :- "$APP_BINARY" > "$RAW" 2>/dev/null || fail 'codesign 无法读取签名 Entitlements。'
  SOURCE='codesign'
else
  fail '设备未安装 ldid 或 codesign；无法读取签名 Entitlements。'
fi
[ -s "$RAW" ] || fail '签名 Entitlements 为空。'
plutil -lint "$RAW" >/dev/null 2>&1 || fail '签名 Entitlements 不是有效 plist。'
plutil -convert xml1 -o "$XML" "$RAW" || fail '无法规范化签名 Entitlements。'
APP_IDENTIFIER="$(plutil -extract application-identifier raw -o - "$XML" 2>/dev/null || true)"
TEAM_IDENTIFIER="$(plutil -extract com.apple.developer.team-identifier raw -o - "$XML" 2>/dev/null || true)"
KEYCHAIN_GROUPS="$(plutil -extract keychain-access-groups json -o - "$XML" 2>/dev/null || true)"
echo "Bundle ID：$BUNDLE_ID"
echo "Entitlements 来源：$SOURCE"
[ -n "$APP_IDENTIFIER" ] && echo "application-identifier：$APP_IDENTIFIER" || echo 'application-identifier：未声明'
[ -n "$TEAM_IDENTIFIER" ] && echo "team-identifier：$TEAM_IDENTIFIER" || echo 'team-identifier：未声明'
if [ -n "$KEYCHAIN_GROUPS" ]; then echo 'keychain-access-groups：'; printf '%s\n' "$KEYCHAIN_GROUPS"; else echo 'keychain-access-groups：未声明或无法读取'; fi
echo '诊断范围：仅检查签名 Entitlements 中声明的访问组。'
echo '不读取、不导出、不删除 Keychain 项；实际读写能力仍取决于签名、访问控制与运行时权限。'
