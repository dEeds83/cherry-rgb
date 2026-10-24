#!/usr/bin/env bash
# Builds "Cherry RGB.app" (release) and optionally installs it to ~/Applications.
#   scripts/bundle.sh            -> build/Cherry RGB.app
#   scripts/bundle.sh --install  -> also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product CherryRGBApp
swift build -c release --product cherryrgb

APP="build/Cherry RGB.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/CherryRGBApp "$APP/Contents/MacOS/CherryRGBApp"
cp .build/release/cherryrgb build/cherryrgb

# Ad-hoc signature. Note: macOS ties the Input Monitoring grant to the code
# hash, so after every rebuild the permission has to be re-enabled.
codesign --force --sign - --identifier de.fabiandietz.cherryrgb "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x CherryRGBApp 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"Cherry RGB.app"
    cp -R "$APP" ~/Applications/
    open ~/Applications/"Cherry RGB.app"
    echo "Installed to ~/Applications/Cherry RGB.app"
fi
