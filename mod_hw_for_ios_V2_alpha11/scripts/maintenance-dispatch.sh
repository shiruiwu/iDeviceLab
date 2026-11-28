#!/var/jb/bin/sh
# Root-only, fixed-command dispatcher for Alpha11 maintenance scripts.
# This is a terminal entry point, not a remote service or arbitrary command runner.
set -eu
PATH='/var/jb/usr/bin:/usr/bin:/bin'
export PATH
umask 077
fail() { echo "维护操作已中止：$*" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || fail '必须在越狱终端以 root 身份运行（先执行 su）。'
[ "$#" -ge 1 ] || fail '用法：mod-hw-maintenance <backup|verify|restore|clean> …'
ACTION="$1"
shift
case "$ACTION" in
  backup)
    [ "$#" -eq 1 ] || fail '用法：mod-hw-maintenance backup <bundle.identifier>'
    exec /var/jb/usr/bin/mod-hw-app-backup "$1"
    ;;
  verify)
    [ "$#" -eq 1 ] || fail '用法：mod-hw-maintenance verify <archive-name.tar.gz>'
    case "$1" in ''|*/*|*..*|*.tmp*|*.tar.gz.tar.gz) fail '归档文件名无效。' ;; *.tar.gz) ;; *) fail '归档必须以 .tar.gz 结尾。' ;; esac
    exec /var/jb/usr/bin/mod-hw-app-backup-verify "$1"
    ;;
  restore)
    [ "$#" -eq 3 ] && [ "$3" = '--confirm' ] || fail '用法：mod-hw-maintenance restore <bundle.identifier> <archive-name.tar.gz> --confirm'
    case "$2" in ''|*/*|*..*|*.tmp*|*.tar.gz.tar.gz) fail '归档文件名无效。' ;; *.tar.gz) ;; *) fail '归档必须以 .tar.gz 结尾。' ;; esac
    exec /var/jb/usr/bin/mod-hw-app-restore "$1" "$2" --confirm
    ;;
  clean)
    [ "$#" -eq 2 ] && [ "$2" = '--confirm' ] || fail '用法：mod-hw-maintenance clean <bundle.identifier> --confirm'
    exec /var/jb/usr/bin/mod-hw-app-clean "$1" --confirm
    ;;
  *)
    fail '未知操作；仅允许 backup、verify、restore、clean。'
    ;;
esac
