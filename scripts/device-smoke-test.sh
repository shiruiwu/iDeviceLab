#!/bin/sh
# iDeviceLab / Alpha11 non-destructive smoke test for jailbroken iOS.
set +e

section() { printf '\n===== %s =====\n' "$1"; }

section "Device"
uname -a
sw_vers 2>/dev/null || true
id

section "Installed packages"
dpkg-query -W -f='${Package} ${Version} ${Status}\n' com.idevelab.core com.modhw.ios 2>/dev/null || true

section "Rootless paths"
ls -ld /var/jb 2>&1
ls -l /var/jb/usr/libexec/idevelab-core 2>&1
ls -l /var/jb/Library/LaunchDaemons/com.idevelab.core.plist 2>&1
ls -l /var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.dylib 2>&1

section "Alpha11 plist syntax"
if [ -f /var/mobile/Library/Preferences/com.modhw.ios.devices.plist ]; then
  plutil -lint /var/mobile/Library/Preferences/com.modhw.ios.devices.plist
else
  echo "Alpha11 plist not found at the primary path"
fi

section "Rootless Core HTTP status"
curl --max-time 3 -sS http://127.0.0.1:18080/status || true
printf '\n'

section "Alpha11 local plist diagnostics"
curl --max-time 3 -sS http://127.0.0.1:18080/config/status || true
printf '\n'

section "LaunchDaemon state"
launchctl print system/com.idevelab.core 2>&1 | head -40

section "Recent Core logs"
tail -40 /var/mobile/Library/Logs/iDeviceLab-core.log 2>/dev/null || true
tail -40 /var/mobile/Library/Logs/iDeviceLab-core-error.log 2>/dev/null || true

echo
echo "Smoke test finished. This script only reads status and logs; it does not modify files or restart services."
