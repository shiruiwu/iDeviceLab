#!/bin/sh
# Run on the jailbroken iPhone over SSH after installing the Manager IPA and Rootless DEB.
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

package_installed() {
    dpkg -s com.idevelab.core 2>/dev/null | grep -q 'Status: install ok installed'
}

manager_installed() {
    for plist in /var/containers/Bundle/Application/*/iDeviceLab.app/Info.plist; do
        [ -f "$plist" ] || continue
        bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null || true)"
        [ "$bundle_id" = "com.idevelab.manager" ] && return 0
    done
    return 1
}

launchd_loaded() {
    launchctl print system/com.idevelab.core >/dev/null 2>&1
}

api_check() {
    route="$1"
    code="$(curl --connect-timeout 2 --max-time 8 -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:18080/$route" 2>/dev/null || true)"
    [ "$code" = "200" ]
}

check "Rootless Core executable exists" test -x /var/jb/usr/libexec/idevelab-core
check "Debian package is installed" package_installed
check "Manager IPA is installed" manager_installed
check "LaunchDaemon plist parses" plutil -lint /var/jb/Library/LaunchDaemons/com.idevelab.core.plist
check "LaunchDaemon is loaded" launchd_loaded

for route in status system compatibility apps maintenance/apps hooks/status config/status; do
    check "Loopback API /$route returns HTTP 200" api_check "$route"
done

if [ "$failures" -eq 0 ]; then
    printf '\nDevice acceptance checks passed. Hook runtime injection is NOT proven by these checks.\n'
    exit 0
fi
printf '\nDevice acceptance checks failed: %s\n' "$failures"
exit 1
