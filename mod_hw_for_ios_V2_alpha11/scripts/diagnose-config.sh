#!/var/jb/bin/sh
# Read-only plist file diagnostics. Does not display values or modify device state.
set -eu
PRIMARY='/var/mobile/Library/Preferences/com.modhw.ios.devices.plist'
LEGACY='/tmp/devices.plist'
check_file() {
  path="$1"
  echo "检查路径：$path"
  if [ ! -e "$path" ]; then echo '  状态：不存在'; return 1; fi
  if [ ! -r "$path" ]; then echo '  状态：存在，但当前用户不可读'; return 1; fi
  echo '  状态：存在且可读'
  if ! plutil -lint "$path" >/dev/null 2>&1; then
    echo '  plist：格式错误或无法解析'; return 1
  fi
  echo '  plist：格式有效'
  if plutil -convert xml1 -o - "$path" 2>/dev/null | grep -q '<dict>'; then
    echo '  根对象：Dictionary'
    return 0
  fi
  echo '  根对象：不是 Dictionary 或无法确认'
  return 1
}
found=0
if check_file "$PRIMARY"; then
  echo '检查结果：主配置路径存在且 plist 结构有效。'; found=1
else
  echo '主路径未通过检查。'
fi
if [ "$found" -eq 0 ]; then
  if check_file "$LEGACY"; then
    echo '检查结果：仅旧版兼容路径存在且 plist 结构有效。'; found=1
  else
    echo '旧版兼容路径也未通过检查。'
  fi
fi
if [ "$found" -eq 0 ]; then
  echo '结论：未发现可用的 plist 配置文件。'
  exit 2
fi
exit 0
