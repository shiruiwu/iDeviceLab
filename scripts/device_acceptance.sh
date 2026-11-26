#!/bin/sh
# Run on the jailbroken iPhone over SSH after installing the IPA and Rootless DEB.
# Output is limited to package/service/API health; it does not dump device identifiers.
set -eu

failures=0
check() {
    label="$1"
    shift
    if "$@"; then
        printf '[OK] %s\n' "$label"
    else
        printf '[FAIL] %s\n' "$label"
        failures=$((failures + 1))
    fi
}

check "Rootless Core executable exists" test -x /var/jb/usr/libexec/idevelab-core
check "Debian package is installed" dpkg-query -W com.idevelab.core
check "LaunchDaemon plist parses" plutil -lint /var/jb/Library/LaunchDaemons/com.idevelab.core.plist
check "LaunchDaemon is loaded" launchctl print system/com.idevelab.core

api_check() {
    route="$1"
    code="$(curl --connect-timeout 2 --max-time 8 -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:18080/$route" 2>/dev/null || true)"
    [ "$code" = "200" ]
}
for route in status system compatibility apps maintenance/apps hooks/status config/status; do
    check "Loopback API /$route returns HTTP 200" api_check "$route"
done

if [ "$failures" -eq 0 ]; then
    printf '\nDevice acceptance checks passed. Hook runtime injection is NOT proven by these checks.\n'
    exit 0
fi
printf '\nDevice acceptance checks failed: %s\n' "$failures"
exit 1
