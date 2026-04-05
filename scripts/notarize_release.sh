#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="whyutils-swift"
APP_PATH="$ROOT/dist/${APP_NAME}.app"
ZIP_PATH="$ROOT/dist/${APP_NAME}.zip"
SIGN_IDENTITY="${WHYUTILS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${WHYUTILS_NOTARY_PROFILE:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Missing WHYUTILS_SIGN_IDENTITY."
  echo "Example:"
  echo "  WHYUTILS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \\"
  echo "  WHYUTILS_NOTARY_PROFILE='whyutils-notary' ./scripts/notarize_release.sh"
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Missing WHYUTILS_NOTARY_PROFILE."
  echo "Create profile first:"
  echo "  xcrun notarytool store-credentials 'whyutils-notary' --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>"
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Please install Xcode Command Line Tools."
  exit 1
fi

echo "[1/6] Build and sign app bundle"
WHYUTILS_SIGN_IDENTITY="$SIGN_IDENTITY" WHYUTILS_SIGN_MODE=identity ./scripts/build_app.sh

if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
  echo "codesign verify failed."
  exit 1
fi

if codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -q "Signature=adhoc"; then
  echo "Refusing to notarize ad-hoc signed app. Use a real Developer ID identity."
  exit 1
fi

echo "[2/6] Submit to notary service and wait"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "[3/6] Staple ticket"
xcrun stapler staple "$APP_PATH"

echo "[4/6] Validate stapled ticket"
xcrun stapler validate "$APP_PATH"

echo "[5/6] Gatekeeper assessment"
spctl --assess --type execute -vv "$APP_PATH"

echo "[6/6] Done"
echo "Release app: $APP_PATH"
echo "Release zip: $ZIP_PATH"
echo "Share zip with colleagues."

