#!/bin/zsh
# App Store build of Last Pick: bump build number, test, archive, verify, export, upload.
#
#   scripts/ios-release.sh              test + archive + export + upload to App Store Connect / TestFlight
#   scripts/ios-release.sh --no-upload  stop after the .ipa (no build-number bump)
#
# One-time: node scripts/asc-provision.mjs (bundle id + "Last Pick App Store" profile, installed locally).
# Needs the App Store Connect record for com.dentaco.lastpick before uploading (created in the ASC web UI).
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=86VY69CXCB
ISSUER=1a17aac3-131a-4085-9f1f-8e8023cb043c
KEY=~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER)
OUT=.build/release
SIM_DEST='platform=iOS Simulator,name=iPhone 17 Pro'

UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

# Newest daily snapshot ships inside the app (it refreshes itself afterwards).
cp ../public/data.json LastPick/Resources/data.json
xcodegen generate --quiet

xcodebuild -project LastPick.xcodeproj -scheme LastPick -destination "$SIM_DEST" -derivedDataPath .build/test -quiet test
echo "engine tests passed"

if (( UPLOAD )); then
  CURRENT=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | grep -o '[0-9]\+')
  NEXT=$((CURRENT + 1))
  sed -i.bak "s/CURRENT_PROJECT_VERSION: \"$CURRENT\"/CURRENT_PROJECT_VERSION: \"$NEXT\"/" project.yml && rm project.yml.bak
  echo "build number -> $NEXT"
  xcodegen generate --quiet
fi

rm -rf $OUT && mkdir -p $OUT
xcodebuild -project LastPick.xcodeproj -scheme LastPick -configuration Release \
  -destination 'generic/platform=iOS' -archivePath $OUT/LastPick.xcarchive "${AUTH[@]}" -quiet archive

APP=$OUT/LastPick.xcarchive/Products/Applications/LastPick.app
FAMILY=$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' $APP/Info.plist | tr -d ' \n')
[[ "$FAMILY" == "Array{1}" ]] || { echo "ABORT: build declares device families $FAMILY — iPhone-only expected (iPad would need iPad screenshots)." >&2; exit 1; }
[[ -f $APP/PrivacyInfo.xcprivacy ]] || { echo "ABORT: PrivacyInfo.xcprivacy missing from the bundle." >&2; exit 1; }
[[ -f $APP/data.json ]] || { echo "ABORT: data.json missing from the bundle." >&2; exit 1; }
PORTRAITS=$(ls $APP/Portraits | wc -l | tr -d ' ')
(( PORTRAITS >= 120 )) || { echo "ABORT: only $PORTRAITS hero portraits bundled." >&2; exit 1; }
if strings $APP/LastPick | grep -q "LASTPICK_DEMO"; then
  echo "ABORT: the debug demo-draft seeding is compiled into the release build." >&2; exit 1
fi
if grep -rqaE "sk-ant-|sk_live_|AIza[0-9A-Za-z_-]{35}|BEGIN [A-Z ]*PRIVATE KEY" $APP; then
  echo "ABORT: a secret-looking string is inside the app bundle." >&2; exit 1
fi
echo "checked: iPhone-only, privacy manifest, data + $PORTRAITS portraits bundled, no demo code, no secrets"

xcodebuild -exportArchive -archivePath $OUT/LastPick.xcarchive -exportOptionsPlist ExportOptions.plist \
  -exportPath $OUT/export -quiet
IPA=$(ls $OUT/export/*.ipa)
echo "built: $IPA"

(( UPLOAD )) || exit 0
xcrun altool --upload-app -f "$IPA" -t ios --apiKey $KEY_ID --apiIssuer $ISSUER
echo "uploaded — TestFlight processing takes a few minutes."
