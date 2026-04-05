#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="whyutils-swift"
BUNDLE_ID="com.whyutils.swiftui"
APP_PATH="$ROOT/dist/${APP_NAME}.app"
ZIP_PATH="$ROOT/dist/${APP_NAME}.zip"
SIGN_IDENTITY="${WHYUTILS_SIGN_IDENTITY:-}"
SIGN_MODE="${WHYUTILS_SIGN_MODE:-adhoc}"
ARCHS="${WHYUTILS_ARCHS:-arm64 x86_64}"

echo "[1/5] Building release binary..."
BINARIES=()
for ARCH in $ARCHS; do
  echo "  - building for $ARCH"
  if swift build -c release --arch "$ARCH" --product "$APP_NAME" >/dev/null; then
    BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"
    BIN_PATH="$BIN_DIR/$APP_NAME"
    if [[ -f "$BIN_PATH" ]]; then
      BINARIES+=("$BIN_PATH")
    fi
  else
    echo "    warning: build failed for $ARCH, skipped"
  fi
done

if [[ ${#BINARIES[@]} -eq 0 ]]; then
  echo "No build artifacts were produced."
  exit 1
fi

echo "[2/5] Creating .app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
  lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/$APP_NAME"
else
  cp "${BINARIES[0]}" "$APP_PATH/Contents/MacOS/$APP_NAME"
fi
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>whyutils</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>whyutils 需要自动化权限以便将剪贴板历史粘贴回目标应用</string>
</dict>
</plist>
PLIST

echo "[3/5] Codesign..."
if command -v codesign >/dev/null 2>&1; then
  if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Using identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH" >/dev/null
  elif [[ "$SIGN_MODE" == "adhoc" ]]; then
    echo "Using ad-hoc signature (permissions may reset after rebuild)."
    codesign --force --deep --sign - "$APP_PATH" >/dev/null || true
  else
    echo "Skip codesign (recommended for local debug to keep TCC permissions stable)."
    echo "Set WHYUTILS_SIGN_IDENTITY to a fixed cert for stable signed builds."
    codesign --remove-signature "$APP_PATH" >/dev/null 2>&1 || true
  fi
fi

echo "[4/5] Packaging zip..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[5/5] Done"
echo "App: $APP_PATH"
echo "Zip: $ZIP_PATH"
echo "Run: open '$APP_PATH'"
