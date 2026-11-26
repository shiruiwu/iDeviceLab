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
if command -v launchctl >/dev/null 2>&1; then
  check 'Alpha11 Core launchd service is loaded' launchctl print system/com.idevelab.core.alpha11
else
  echo '[FAIL] launchctl is unavailable'
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
check 'Config diagnostic command installed' command -v mod-hw-diagnose
echo "Result: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
