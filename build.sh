#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p HandsOff.app/Contents/MacOS
cp Info.plist HandsOff.app/Contents/
swiftc -swift-version 5 -O main.swift -o HandsOff.app/Contents/MacOS/HandsOff
# A stable identity (e.g. SIGN_ID="Apple Development: …") keeps macOS permissions across rebuilds; ad-hoc resets them.
codesign -fs "${SIGN_ID:--}" HandsOff.app
HandsOff.app/Contents/MacOS/HandsOff --selftest
