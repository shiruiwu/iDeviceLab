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

# Require one well-formed value for every identity/integrity field.
MANIFEST_VALUES="$(awk -F= -v name="$NAME" '
  $1 == "sha256" {
    sha_count++
    if (NF != 2 || length($2) != 64 || $2 ~ /[^0-9a-f]/) bad=1
    sha=$2
  }
  $1 == "archive" {
    archive_count++
    if (NF != 2 || $2 != name) bad=1
  }
  $1 == "bundle_id" {
    bundle_count++
    if (NF != 2 || $2 == "" || $2 ~ /[^A-Za-z0-9._-]/ || substr($2,1,1) == "." || index($2,"..") > 0 || substr($2,length($2),1) == ".") bad=1
    bundle=$2
  }
  $1 == "container_id" {
    container_count++
    if (NF != 2 || $2 == "" || $2 ~ /[^A-Za-z0-9._-]/ || substr($2,1,1) == "." || index($2,"..") > 0 || substr($2,length($2),1) == ".") bad=1
    container=$2
  }
  $1 == "scope" {
    scope_count++
    if (NF != 2 || $2 != "app-data-container-only") bad=1
  }
  END {
    if (sha_count != 1 || archive_count != 1 || bundle_count != 1 ||
        container_count != 1 || scope_count != 1 || bad) exit 1
    print sha "|" bundle "|" container
  }
' "$MANIFEST")" || {
  echo '清单中的 SHA-256、Bundle ID、容器 ID、scope 或归档字段无效/重复。' >&2
  exit 6
}
EXPECTED=$(printf '%s' "$MANIFEST_VALUES" | cut -d '|' -f 1)

ACTUAL="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL" = "$EXPECTED" ] || {
  echo 'SHA-256 不匹配，归档可能损坏或已被修改。' >&2
  exit 7
}

tar -tzf "$ARCHIVE" >/dev/null
# Keep verifier policy aligned with restore and cleanup: only regular files
# and directories are accepted by the current safe extraction implementation.
if ! tar -tvzf "$ARCHIVE" | awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { bad=1 } END { exit bad }'; then
  echo '归档包含符号链接或特殊文件；当前还原/清理流程不接受此类条目。' >&2
  exit 8
fi
echo '备份完整性验证通过。'
echo "归档：$NAME"
echo "SHA-256：$ACTUAL"
echo '注意：本命令只验证文件完整性和 tar 可读性，不执行解压或还原，也不代表可恢复 Keychain、App Groups 或系统管理数据。'
