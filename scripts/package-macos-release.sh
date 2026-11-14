#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <output-directory> [derived-data-directory]" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$1"
if [[ $# -eq 2 ]]; then
  derived_data="$2"
else
  derived_data="$(mktemp -d "${TMPDIR:-/tmp}/nova-derived.XXXXXX")"
fi
output_dir="$(mkdir -p "$output_dir" && cd "$output_dir" && pwd)"
derived_data="$(mkdir -p "$derived_data" && cd "$derived_data" && pwd)"
project="$repo_root/NOVA Copilot.xcodeproj"
scheme="NOVA Copilot"
app="$derived_data/Build/Products/Release/NOVA Copilot.app"
entitlements="$repo_root/NOVA Copilot/NOVA Copilot.entitlements"
version="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$project/project.pbxproj" | tail -1)"
if [[ -z "$version" ]]; then
  echo "Could not read MARKETING_VERSION from $project/project.pbxproj" >&2
  exit 65
fi

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  build

if [[ ! -d "$app" ]]; then
  echo "Xcode did not produce the expected app bundle: $app" >&2
  exit 66
fi

# Keep the outer ad-hoc signature consistent with this non-notarized distribution.
# Do not use --deep or --options runtime: Sparkle ships separately signed XPC helpers,
# and library validation cannot validate third-party Team IDs when this app has none.
codesign --force --sign - --entitlements "$entitlements" --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"

main_signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
if grep -q 'flags=.*runtime' <<<"$main_signature"; then
  echo "Unexpected Hardened Runtime flag on ad-hoc app; Sparkle may fail library validation." >&2
  exit 70
fi

stage="$(mktemp -d "$output_dir/.nova-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/NOVA Copilot.app"
ln -s /Applications "$stage/Applications"
zip_path="$output_dir/NOVA-Copilot-${version}.zip"
dmg_path="$output_dir/NOVA-Copilot-${version}.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
hdiutil create -volname "NOVA Copilot ${version}" -srcfolder "$stage" -ov -format UDZO "$dmg_path"

echo "Built ad-hoc signed NOVA Copilot ${version}."
echo "App: $app"
echo "Sparkle ZIP: $zip_path"
echo "DMG: $dmg_path"
