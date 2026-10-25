#!/usr/bin/env bash
# Builds "Desk Gear.app" (release) and optionally installs it to ~/Applications.
#   scripts/bundle.sh            -> build/Desk Gear.app
#   scripts/bundle.sh --install  -> also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product DeskGearApp
swift build -c release --product deskgear

APP="build/Desk Gear.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/DeskGearApp "$APP/Contents/MacOS/DeskGearApp"
cp .build/release/deskgear build/deskgear

# Ad-hoc signature. Note: macOS ties the Input Monitoring grant to the code
# hash, so after every rebuild the permission has to be re-enabled.
codesign --force --sign - --identifier de.fabiandietz.deskgear "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x DeskGearApp 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"Desk Gear.app"
    cp -R "$APP" ~/Applications/
    open ~/Applications/"Desk Gear.app"
    echo "Installed to ~/Applications/Desk Gear.app"
fi
