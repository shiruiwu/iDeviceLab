#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v xcodebuild >/dev/null || { echo 'Xcode is required.' >&2; exit 1; }
command -v swiftc >/dev/null || { echo 'Swift is required.' >&2; exit 1; }
if [[ -z "$(printenv THEOS || true)" ]]; then echo 'Set THEOS to your Theos installation.' >&2; exit 1; fi
python3 tools/validate_project.py
swiftc -frontend -parse manager/ModHWManager/ModHWManagerApp.swift
make clean package
mkdir -p release
find packages -maxdepth 1 -type f -name '*.deb' -exec cp -f {} release/ +
bash scripts/build-trollstore-ipa.sh
echo "Release outputs are in $ROOT/release/"
