#!/bin/zsh
# 6.9" App Store screenshots (1320×2868) from the iPhone 17 Pro Max simulator, Debug build with the demo drafts.
#   scripts/app-store-screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(xcrun simctl list devices available | grep -m1 "iPhone 17 Pro Max" | grep -oE '[0-9A-F-]{36}')
OUT=docs/app-store/screenshots
xcrun simctl boot $SIM 2>/dev/null || true
xcrun simctl status_bar $SIM override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
cp ../public/data.json LastPick/Resources/data.json
xcodegen generate --quiet
xcodebuild -project LastPick.xcodeproj -scheme LastPick -configuration Debug -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath .build/dd -quiet build
xcrun simctl install $SIM .build/dd/Build/Products/Debug-iphonesimulator/LastPick.app
mkdir -p $OUT && rm -f $OUT/*.png(N)
# launch <demo full|mid> <tab> [extra SIMCTL_CHILD_ env assignments…] — hooks are DEBUG-only (see DraftView.debugHooks)
launch() { xcrun simctl terminate $SIM com.dentaco.lastpick 2>/dev/null || true; env "SIMCTL_CHILD_LASTPICK_DEMO=$1" "SIMCTL_CHILD_LASTPICK_TAB=$2" "${@:3}" xcrun simctl launch $SIM com.dentaco.lastpick >/dev/null; sleep 3.5; }
shot() { sleep 1.2; xcrun simctl io $SIM screenshot "$OUT/$1.png" >/dev/null 2>&1; echo "  $1"; }
tap() { idb ui tap --udid $SIM $1 $2; }

launch full 0; shot 01-draft
launch full 0 SIMCTL_CHILD_LASTPICK_DEMO_EXPAND=1 SIMCTL_CHILD_LASTPICK_DEMO_SCROLL=best; shot 02-why
launch mid 0 SIMCTL_CHILD_LASTPICK_DEMO_SCROLL=predictions; shot 03-they-might-pick
launch mid 1; shot 04-meta
launch mid 2; tap 81 315; shot 05-hero-matchups
xcrun simctl terminate $SIM com.dentaco.lastpick 2>/dev/null || true
sips -g pixelWidth -g pixelHeight $OUT/01-draft.png | tail -2
