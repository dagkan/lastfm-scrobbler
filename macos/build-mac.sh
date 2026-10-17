#!/usr/bin/env bash
# Build, sign, notarize and package Last.fm Scrobbler for macOS, then publish
# the DMG + update manifests to R2 (same bucket/worker as the Windows build).
#
# Run on a Mac with Xcode, xcodegen and (for notarization) a notarytool
# keychain profile:
#   brew install xcodegen
#   xcrun notarytool store-credentials "lastfm-notary" --apple-id <id> --team-id G7Y47M9B73
#
# Usage:
#   ./build-mac.sh                       # build + notarize + upload
#   ./build-mac.sh --skip-upload         # local DMG only
#   ./build-mac.sh --skip-notarize       # unsigned-for-notary dev build (Gatekeeper will warn)
#   ./build-mac.sh --notes "a;b;c"       # release notes for versions.json (semicolon separated)
set -euo pipefail

cd "$(dirname "$0")"

SKIP_UPLOAD=0; SKIP_NOTARIZE=0; NOTES=""
NOTARY_PROFILE="${NOTARY_PROFILE:-lastfm-notary}"
BUCKET="${BUCKET:-lastfm-releases}"
R2_PUBLIC="${R2_PUBLIC:-https://pub-8a5464b225534730b481b262ffe4748b.r2.dev}"
R2_PREFIX="lastfm-scrobbler/macos"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-upload)   SKIP_UPLOAD=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --notes)         NOTES="$2"; shift ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
  shift
done

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"')
[[ -n "$VERSION" ]] || { echo "MARKETING_VERSION not found in project.yml"; exit 1; }
echo "▶ Version $VERSION"

BUILD=build
ARCHIVE="$BUILD/LastFmScrobbler.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Last.fm Scrobbler.app"
DMG="$BUILD/LastFmScrobbler-$VERSION.dmg"
rm -rf "$BUILD"; mkdir -p "$BUILD"

# ── 1. Project + archive ─────────────────────────────────────────────────────
command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

xcodebuild -project LastFmScrobbler.xcodeproj \
  -scheme LastFmScrobbler -configuration Release \
  -archivePath "$ARCHIVE" archive \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" | xcpretty 2>/dev/null || true
[[ -d "$ARCHIVE" ]] || { echo "archive failed"; exit 1; }

# ── 2. Export with Developer ID ──────────────────────────────────────────────
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$EXPORT" >/dev/null
[[ -d "$APP" ]] || APP=$(find "$EXPORT" -maxdepth 1 -name '*.app' | head -1)
[[ -d "$APP" ]] || { echo "export produced no .app"; exit 1; }
echo "▶ Exported: $APP"

# ── 3. DMG ───────────────────────────────────────────────────────────────────
STAGE="$BUILD/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Last.fm Scrobbler" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "▶ DMG: $DMG"

# ── 4. Notarize + staple ─────────────────────────────────────────────────────
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  echo "▶ Notarizing (profile: $NOTARY_PROFILE)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG" || true
else
  echo "⚠ notarization skipped"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "▶ SHA-256: $SHA"

# ── 5. Manifests ─────────────────────────────────────────────────────────────
DMG_NAME=$(basename "$DMG")
DMG_URL="$R2_PUBLIC/$R2_PREFIX/$DMG_NAME"
TODAY=$(date +%Y-%m-%d)

python3 - "$VERSION" "$DMG_URL" "$SHA" "$TODAY" "$NOTES" "$BUILD" "$R2_PUBLIC/$R2_PREFIX/versions.json" <<'PY'
import json, sys, urllib.request
version, url, sha, today, notes_raw, build, versions_url = sys.argv[1:]
notes = [n.strip() for n in notes_raw.split(";") if n.strip()]

with open(f"{build}/latest.json", "w") as f:
    json.dump({"version": version, "url": url, "sha256": sha, "notes": notes}, f, indent=2)

try:
    existing = json.load(urllib.request.urlopen(versions_url, timeout=15))
except Exception:
    existing = []
# normalise old bare-string notes and drop a previous entry for this version
for e in existing:
    if isinstance(e.get("notes"), str):
        e["notes"] = [e["notes"]] if e["notes"] else []
existing = [e for e in existing if e.get("version") != version]
versions = [{"version": version, "url": url, "sha256": sha, "date": today, "notes": notes}] + existing
with open(f"{build}/versions.json", "w") as f:
    json.dump(versions[:10], f, indent=2)
print(f"▶ versions.json: {len(versions[:10])} entries")
PY

if [[ $SKIP_UPLOAD -eq 1 ]]; then
  echo "⏸  --skip-upload: nothing uploaded."
  exit 0
fi

# ── 6. Upload to R2 (wrangler lives in ../worker) ────────────────────────────
WRANGLER="npx --prefix ../worker wrangler"
$WRANGLER r2 object put "$BUCKET/$R2_PREFIX/$DMG_NAME"     --file "$DMG"                 --content-type application/x-apple-diskimage --remote
$WRANGLER r2 object put "$BUCKET/$R2_PREFIX/latest.json"   --file "$BUILD/latest.json"   --content-type application/json --cache-control "no-cache,no-store" --remote
$WRANGLER r2 object put "$BUCKET/$R2_PREFIX/versions.json" --file "$BUILD/versions.json" --content-type application/json --cache-control "no-cache,no-store" --remote

echo ""
echo "✅ v$VERSION published"
echo "   Manifest : $R2_PUBLIC/$R2_PREFIX/latest.json"
echo "   DMG      : $DMG_URL"
