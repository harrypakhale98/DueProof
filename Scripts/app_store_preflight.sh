#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/DueProof.xcodeproj"
SCHEME="DueProof"
SIM_DESTINATION="${SIM_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/DueProof.xcarchive}"

RUN_BUILD=0
RUN_TESTS=0
RUN_ARCHIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      RUN_BUILD=1
      ;;
    --test)
      RUN_TESTS=1
      ;;
    --archive)
      RUN_ARCHIVE=1
      ;;
    --all)
      RUN_BUILD=1
      RUN_TESTS=1
      RUN_ARCHIVE=1
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: Scripts/app_store_preflight.sh [--build] [--test] [--archive] [--all]

Runs DueProof release-readiness checks that can be verified from the repo.

Environment:
  SIM_DESTINATION  Simulator destination for tests.
  ARCHIVE_PATH     Archive path for --archive.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

failures=0
warnings=0

pass() {
  printf 'PASS | %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'WARN | %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL | %s\n' "$1"
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$ROOT_DIR/$path" ]]; then
    pass "$label exists"
  else
    fail "$label missing at $path"
  fi
}

require_text() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if grep -qE "$pattern" "$ROOT_DIR/$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

lint_plist() {
  local path="$1"
  if plutil -lint "$ROOT_DIR/$path" >/dev/null; then
    pass "$path plist parses"
  else
    fail "$path plist does not parse"
  fi
}

lint_json() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$ROOT_DIR/$path" >/dev/null; then
      pass "$path JSON parses"
    else
      fail "$path JSON does not parse"
    fi
  else
    warn "jq not installed; skipped JSON parse for $path"
  fi
}

require_icon() {
  local file="$1"
  local path="DueProof/Resources/Assets.xcassets/AppIcon.appiconset/$file"
  require_file "$path" "$file"

  if [[ -f "$ROOT_DIR/$path" ]]; then
    local dimensions
    dimensions="$(sips -g pixelWidth -g pixelHeight "$ROOT_DIR/$path" 2>/dev/null | awk '/pixelWidth|pixelHeight/ { print $2 }' | paste -sd x -)"
    if [[ "$dimensions" == "1024x1024" ]]; then
      pass "$file is 1024x1024"
    else
      fail "$file must be 1024x1024, found ${dimensions:-unknown}"
    fi
  fi
}

run_xcodebuild() {
  local label="$1"
  shift

  if xcodebuild "$@" >/tmp/dueproof-xcodebuild.log 2>&1; then
    pass "$label"
  else
    fail "$label"
    sed -n '1,80p' /tmp/dueproof-xcodebuild.log
  fi
}

echo "DueProof App Store preflight"
echo "Root: $ROOT_DIR"
echo

require_file "DueProof/Resources/Info.plist" "Main Info.plist"
require_file "DueProof/Resources/PrivacyInfo.xcprivacy" "Privacy manifest"
require_file "DueProof/Resources/DueProof.entitlements" "Main entitlements"
require_file "DueProofWidget/DueProofWidget.entitlements" "Widget entitlements"
require_file "DueProofShareExtension/DueProofShareExtension.entitlements" "Share extension entitlements"

lint_plist "DueProof/Resources/Info.plist"
lint_plist "DueProof/Resources/PrivacyInfo.xcprivacy"
lint_plist "DueProof/Resources/DueProof.entitlements"
lint_plist "DueProofWidget/Info.plist"
lint_plist "DueProofShareExtension/Info.plist"
lint_json "DueProof/Resources/Assets.xcassets/Contents.json"
lint_json "DueProof/Resources/Assets.xcassets/AccentColor.colorset/Contents.json"
lint_json "DueProof/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"

require_text "DueProof/Resources/Info.plist" "NSCameraUsageDescription" "Camera usage description present"
require_text "DueProof/Resources/Info.plist" "NSPhotoLibraryUsageDescription" "Photo library usage description present"
require_text "DueProof/Resources/Info.plist" "NSFaceIDUsageDescription" "Face ID usage description present"
require_text "DueProof/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPICategoryUserDefaults" "Privacy manifest declares UserDefaults"
require_text "DueProof/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPICategoryFileTimestamp" "Privacy manifest declares file timestamps"
require_text "DueProof/Resources/PrivacyInfo.xcprivacy" "<false/>" "Privacy manifest declares no tracking"
require_text "DueProof/Resources/DueProof.entitlements" "iCloud.com.hardik.dueproof" "iCloud container entitlement matches app code"
require_text "DueProof/Resources/DueProof.entitlements" "group.com.hardik.dueproof" "App group entitlement present"
require_text "DueProofWidget/DueProofWidget.entitlements" "group.com.hardik.dueproof" "Widget app group entitlement present"
require_text "DueProofShareExtension/DueProofShareExtension.entitlements" "group.com.hardik.dueproof" "Share extension app group entitlement present"
require_text "DueProof.xcodeproj/project.pbxproj" "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" "App target uses AppIcon"
require_text "DueProof.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com.hardik.dueproof;" "Main bundle id set"
require_text "DueProof.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com.hardik.dueproof.widget;" "Widget bundle id set"
require_text "DueProof.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com.hardik.dueproof.share;" "Share extension bundle id set"
require_text "DueProof.xcodeproj/project.pbxproj" "TARGETED_DEVICE_FAMILY = 1;" "iPhone-only target family set"

require_icon "DueProofIcon.png"
require_icon "DueProofIconDark.png"
require_icon "DueProofIconTinted.png"

if find "$ROOT_DIR" -maxdepth 4 \( -name Package.resolved -o -name Podfile -o -name Cartfile -o -name '*.xcframework' -o -name '*.framework' \) | grep -q .; then
  warn "Third-party dependency artifacts found; review SDK privacy manifests before submission"
else
  pass "No third-party package manager or binary framework artifacts found"
fi

if grep -R -nE "import (Firebase|AppTrackingTransparency|AdSupport)|FirebaseApp|ATTrackingManager|ASIdentifierManager|URLSession|URLRequest|Crashlytics|Amplitude|Mixpanel|Sentry|AdMob" \
  "$ROOT_DIR/DueProof" "$ROOT_DIR/DueProofWidget" "$ROOT_DIR/DueProofShareExtension" \
  --include='*.swift' >/tmp/dueproof-network-scan.log; then
  fail "Network/tracking SDK symbols found in app code"
  sed -n '1,80p' /tmp/dueproof-network-scan.log
else
  pass "No app-code network, tracking, analytics, ads, or crash SDK symbols found"
fi

if xcodebuild -version >/tmp/dueproof-xcodebuild-version.log 2>&1; then
  pass "Full Xcode toolchain is selected"
else
  fail "Full Xcode toolchain is not selected; xcodebuild cannot run"
  sed -n '1,20p' /tmp/dueproof-xcodebuild-version.log
fi

if [[ "$RUN_BUILD" -eq 1 ]]; then
  run_xcodebuild "Simulator build passes" \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS Simulator" \
    build
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  run_xcodebuild "Unit tests pass" \
    test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$SIM_DESTINATION"
fi

if [[ "$RUN_ARCHIVE" -eq 1 ]]; then
  run_xcodebuild "Release archive passes" \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive
fi

echo
warn "Owner still must confirm App Store Connect metadata, public Privacy Policy URL, Support URL, screenshots, age rating, export compliance, pricing, and availability"
warn "Owner still must run physical-device QA for camera, Photos picker, Face ID/passcode, notifications, iCloud sync, widget, and share extension"

echo
printf 'Summary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

exit 0
