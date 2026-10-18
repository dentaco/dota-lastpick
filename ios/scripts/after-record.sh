#!/bin/zsh
# Waits for the App Store Connect record (created by hand in the web UI), then: upload a build, wait until it's
# VALID, push the listing + screenshots, set up internal TestFlight. Never submits for review.
#   scripts/after-record.sh            (polls every 60 s for up to 24 h)
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=.build/after-record.log
mkdir -p .build
exec > >(tee -a $LOG) 2>&1
echo "== $(date) waiting for the ASC record of com.dentaco.lastpick"

for i in {1..1440}; do
  node -e 'import("./scripts/asc-client.mjs").then(m => m.appId()).then(id => { console.log("record", id); process.exit(0) }).catch(() => process.exit(1))' && break
  (( i == 1440 )) && { echo "gave up after 24 h"; exit 1; }
  sleep 60
done

echo "== $(date) uploading"
scripts/ios-release.sh 2>&1 | grep -v "^    export" | tail -20 || { echo "release failed"; exit 1; }

echo "== $(date) waiting for the build to finish processing"
for i in {1..90}; do
  STATE=$(node -e 'import("./scripts/asc-client.mjs").then(async m => { const id = await m.appId(); const b = (await m.asc("GET", `/builds?filter[app]=${id}&sort=-uploadedDate&limit=1`)).data[0]; console.log(b ? b.attributes.processingState : "NONE") })')
  echo "  build: $STATE"
  [[ "$STATE" == "VALID" ]] && break
  [[ "$STATE" == "INVALID" || "$STATE" == "FAILED" ]] && { echo "build rejected by processing — check ASC → Build Uploads"; exit 1; }
  sleep 60
done
[[ "$STATE" == "VALID" ]] || { echo "build still $STATE after 90 min — stopping before the listing; rerun later"; exit 1; }

echo "== $(date) listing"
node scripts/asc-listing.mjs
echo "== $(date) TestFlight"
node scripts/asc-testflight.mjs || echo "TestFlight tester step failed — add russkiytv@icloud.com to the Internal group in ASC → TestFlight"
echo "== $(date) done — NOT submitted. Left: App Privacy (web UI) + Alex's go to submit."
osascript -e 'display notification "Build on TestFlight, listing filled. Not submitted." with title "Last Pick"' 2>/dev/null || true
