#!/bin/sh
# Verify a backup archive created by mod-hw-app-backup.
# This is an integrity/readability check only; it never extracts or restores data.
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
[ -d "$BACKUP_ROOT" ] && [ ! -L "$BACKUP_ROOT" ] || {
  echo '备份目录不存在或不是安全的普通目录。' >&2
  exit 3
}
[ -f "$ARCHIVE" ] && [ -r "$ARCHIVE" ] && [ ! -L "$ARCHIVE" ] || {
  echo '归档不存在、不可读或为符号链接。' >&2
  exit 4
}
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || {
  echo '备份清单不存在、不可读或为符号链接。' >&2
  exit 5
}

# Require exactly one SHA-256 and archive entry; reject duplicate/malformed fields.
if ! awk -F= -v name="$NAME" '
  $1 == "sha256" {
    sha_count++
    if (NF != 2 || length($2) != 64 || $2 ~ /[^0-9a-f]/) bad=1
    sha=$2
  }
  $1 == "archive" {
    archive_count++
    if (NF != 2 || $2 != name) bad=1
  }
  END {
    if (sha_count != 1 || archive_count != 1 || bad) exit 1
    print sha
  }
' "$MANIFEST" > "$MANIFEST.check.$$"; then
  rm -f "$MANIFEST.check.$$"
  echo '清单中的 SHA-256 或归档文件名字段无效/重复。' >&2
  exit 6
fi
EXPECTED="$(cat "$MANIFEST.check.$$")"
rm -f "$MANIFEST.check.$$"

ACTUAL="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL" = "$EXPECTED" ] || {
  echo 'SHA-256 不匹配，归档可能损坏或已被修改。' >&2
  exit 7
}

tar -tzf "$ARCHIVE" >/dev/null
echo '备份完整性验证通过。'
echo "归档：$NAME"
echo "SHA-256：$ACTUAL"
echo '注意：本命令只验证文件完整性和 tar 可读性，不执行解压或还原，也不代表可恢复 Keychain、App Groups 或系统管理数据。'
