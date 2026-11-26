#!/bin/sh
# Non-destructive on-device smoke test for Alpha11 on a Rootless jailbreak.
set -u
PASS=0
FAIL=0
SKIP=0
check() {
  label="$1"
  shift
  if "$@"; then
    printf '[PASS] %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '[FAIL] %s\n' "$label"
    FAIL=$((FAIL + 1))
  fi
}
contains() {
  printf '%s' "$1" | grep -Fq "$2"
}
echo 'mod_hw Alpha11 device self-test (read-only)'
check 'Run as root' test "$(id -u)" -eq 0
echo "Model: $(sysctl -n hw.machine 2>/dev/null || echo unknown)"
echo "OS build: $(sysctl -n kern.osversion 2>/dev/null || echo unknown)"
check 'Rootless jailbreak path exists' test -d /var/jb
check 'Alpha11 Core executable installed' test -x /var/jb/usr/libexec/idevelab-core
check 'Alpha11 Core LaunchDaemon plist exists' test -f /var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist
check 'Alpha11 Core LaunchDaemon plist is valid' plutil -lint /var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist
if plutil -extract UserName raw -o - /var/jb/Library/LaunchDaemons/com.idevelab.core.alpha11.plist 2>/dev/null | grep -qx mobile; then
  echo '[PASS] Alpha11 Core runs as mobile (unprivileged)'
  PASS=$((PASS + 1))
else
  echo '[FAIL] Alpha11 Core launchd UserName is not mobile'
  FAIL=$((FAIL + 1))
fi
LAUNCHCTL=''
for candidate in /bin/launchctl /usr/bin/launchctl /var/jb/bin/launchctl /var/jb/basebin/launchctl /var/jb/usr/bin/launchctl; do
  if [ -x "$candidate" ]; then LAUNCHCTL="$candidate"; break; fi
done
if [ -z "$LAUNCHCTL" ] && command -v launchctl >/dev/null 2>&1; then
  LAUNCHCTL="$(command -v launchctl)"
fi
if [ -n "$LAUNCHCTL" ]; then
  check 'Alpha11 Core launchd service is loaded' "$LAUNCHCTL" print system/com.idevelab.core.alpha11
else
  echo '[FAIL] launchctl is unavailable in standard and Dopamine rootless paths'
  FAIL=$((FAIL + 1))
fi
if command -v curl >/dev/null 2>&1; then
  RESPONSE="$(curl --silent --show-error --fail --max-time 3 http://127.0.0.1:18081/status 2>/dev/null || true)"
  if contains "$RESPONSE" '"version":"0.2.0-alpha11"' && contains "$RESPONSE" '"mode":"read-only"'; then
    echo '[PASS] Manager Core loopback endpoint responds with Alpha11 read-only identity'
    PASS=$((PASS + 1))
  else
    echo '[FAIL] Manager Core loopback endpoint did not return the expected status'
    FAIL=$((FAIL + 1))
  fi
else
  echo '[SKIP] curl unavailable; use the manager app to test the Core endpoint'
  SKIP=$((SKIP + 1))
fi
check 'App-container backup command installed' command -v mod-hw-app-backup
check 'App-container backup verifier installed' command -v mod-hw-app-backup-verify
check 'Guarded App-container restore command installed' command -v mod-hw-app-restore
check 'Backup-first App-container cleanup command installed' command -v mod-hw-app-clean
if command -v curl >/dev/null 2>&1; then
  BACKUPS_RESPONSE="$(curl --silent --show-error --fail --max-time 3 http://127.0.0.1:18081/backups 2>/dev/null || true)"
  if contains "$BACKUPS_RESPONSE" '"ok":true' && contains "$BACKUPS_RESPONSE" '"backups":'; then
    echo '[PASS] Backup inventory endpoint responds with a JSON backup list'
    PASS=$((PASS + 1))
  else
    echo '[FAIL] Backup inventory endpoint is unavailable or malformed'
    FAIL=$((FAIL + 1))
  fi
else
  echo '[SKIP] curl unavailable; verify backup list in the manager app'
  SKIP=$((SKIP + 1))
fi
BACKUP_ROOT='/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups'
if [ -d "$BACKUP_ROOT" ]; then
  MOBILE_GID="$(id -g mobile 2>/dev/null || echo unknown)"
  BACKUP_DIR_META="$(stat -f '%u:%g:%Lp' "$BACKUP_ROOT" 2>/dev/null || echo invalid)"
  check 'Backup directory is root-owned and mobile-group traversable (0750)' test "$BACKUP_DIR_META" = "0:$MOBILE_GID:750"
  for ARCHIVE in "$BACKUP_ROOT"/*.tar.gz; do
    [ -f "$ARCHIVE" ] || continue
    META="$(stat -f '%u:%g:%Lp' "$ARCHIVE" 2>/dev/null || echo invalid)"
    check "Archive is root:mobile read-only (0640): $(basename "$ARCHIVE")" test "$META" = "0:$MOBILE_GID:640"
    MANIFEST="${ARCHIVE%.tar.gz}.txt"
    if [ -f "$MANIFEST" ]; then
      META="$(stat -f '%u:%g:%Lp' "$MANIFEST" 2>/dev/null || echo invalid)"
      check "Manifest is root:mobile read-only (0640): $(basename "$MANIFEST")" test "$META" = "0:$MOBILE_GID:640"
    fi
  done
else
  echo '[SKIP] Backup directory not created yet; create a test backup before checking permissions'
  SKIP=$((SKIP + 1))
fi
check 'Config diagnostic command installed' command -v mod-hw-diagnose
check 'Read-only Keychain entitlement diagnostic installed' command -v mod-hw-keychain-diagnose
echo "Result: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
