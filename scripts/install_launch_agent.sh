#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT/dist/whyutils-swift.app}"
EXEC="$APP_PATH/Contents/MacOS/whyutils-swift"
LABEL="com.whyutils.swiftui"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -x "$EXEC" ]]; then
  echo "Executable not found: $EXEC"
  echo "Build app first: $ROOT/scripts/build_app.sh"
  exit 1
fi

mkdir -p "$(dirname "$PLIST")"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$EXEC</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
PLIST

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"

echo "LaunchAgent installed: $PLIST"
