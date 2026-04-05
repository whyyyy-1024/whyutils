#!/usr/bin/env bash
set -euo pipefail

LABEL="com.whyutils.swiftui"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "LaunchAgent removed: $PLIST"
