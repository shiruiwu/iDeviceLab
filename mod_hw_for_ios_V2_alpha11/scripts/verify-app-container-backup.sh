#!/bin/sh
# Verify a backup archive created by mod-hw-app-backup.
set -eu
BACKUP_ROOT='/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups'
if [ "$(id -u)" -ne 0 ]; then
  echo '请以 root 权限运行。' >&2
  exit 1
fi
if [ "$#" -ne 1 ]; then
  echo '用法：mod-hw-app-backup-verify <archive-name.tar.gz>' >&2
  exit 2
fi
NAME="$1"
case "$NAME" in
  ''|*/*|*..*|*.tmp*) echo '只允许指定备份目录中的归档文件名。' >&2; exit 2 ;;
  *.tar.gz) ;;
  *) echo '备份文件必须以 .tar.gz 结尾。' >&2; exit 2 ;;
esac
ARCHIVE="$BACKUP_ROOT/$NAME"
MANIFEST="${ARCHIVE%.tar.gz}.txt"
[ -f "$ARCHIVE" ] && [ -r "$ARCHIVE" ] || { echo '归档不存在或不可读。' >&2; exit 3; }
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] || { echo '备份清单不存在。' >&2; exit 4; }
EXPECTED="$(awk -F= '$1 == "sha256" {print $2; exit}' "$MANIFEST")"
RECORDED="$(awk -F= '$1 == "archive" {print $2; exit}' "$MANIFEST")"
[ "$RECORDED" = "$NAME" ] || { echo '清单与归档文件名不匹配。' >&2; exit 5; }
case "$EXPECTED" in
  ''|*[!0-9a-f]*) echo '清单中的 SHA-256 格式无效。' >&2; exit 6 ;;
esac
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'SHA-256 不匹配，归档可能损坏或已被修改。' >&2; exit 7; }
tar -tzf "$ARCHIVE" >/dev/null
echo '备份完整性验证通过。'
echo "归档：$NAME"
echo "SHA-256：$ACTUAL"
echo '注意：校验通过仅表示文件与生成时清单一致，不代表可恢复 Keychain 或系统管理数据。'
