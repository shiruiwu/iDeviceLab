#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <host-or-ip> <plist-path> [ssh-user]" >&2
  exit 2
fi
host="$1"
plist_path="$2"
user=mobile
if [[ $# -eq 3 ]]; then user="$3"; fi
command -v ssh >/dev/null
command -v scp >/dev/null
[[ -f "$plist_path" ]] || { echo "File not found: $plist_path" >&2; exit 1; }
remote="$user@$host"
stage="/tmp/mod_hw_for_ios.devices.$$.plist"
dest="/var/mobile/Library/Preferences/com.modhw.ios.devices.plist"
ssh "$remote" 'mkdir -p /var/mobile/Library/Preferences'
scp -- "$plist_path" "$remote:$stage"
ssh "$remote" "set -eu; plutil -lint '$stage'; if [ -f '$dest' ]; then cp -p '$dest' '$dest.bak'; fi; mv '$stage' '$dest'; chmod 0644 '$dest'; plutil -lint '$dest'"
echo "Installed to $remote:$dest; no processes were restarted."
