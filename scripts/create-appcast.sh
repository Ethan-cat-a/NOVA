#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 <NOVA Copilot.app> <update.dmg> [download-url-prefix] [appcast.xml]" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
archive="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
download_prefix="${3:-https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/}"
output="${4:-$repo_root/appcast.xml}"
sign_update="${SPARKLE_SIGN_UPDATE:-$repo_root/Vendor/Sparkle/bin/sign_update}"
plist="$app_bundle/Contents/Info.plist"

if [[ ! -d "$app_bundle" || ! -f "$plist" ]]; then
  echo "App bundle or Contents/Info.plist not found: $app_bundle" >&2
  exit 66
fi
if [[ ! -f "$archive" ]]; then
  echo "Update archive not found: $archive" >&2
  exit 66
fi
if [[ ! -x "$sign_update" ]]; then
  echo "Sparkle sign_update tool not found or not executable: $sign_update" >&2
  exit 69
fi
if [[ ! "$download_prefix" =~ ^https://[A-Za-z0-9./_-]+$ ]]; then
  echo "Download URL prefix must be an HTTPS URL without query parameters." >&2
  exit 64
fi
if [[ "$download_prefix" != */ ]]; then
  download_prefix="$download_prefix/"
fi

archive_name="$(basename "$archive")"
if [[ ! "$archive_name" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  echo "Update archive filename must use only letters, numbers, dots, underscores, plus signs, and hyphens." >&2
  exit 64
fi

short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
archive_length="$(stat -f '%z' "$archive")"
published_at="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')"
archive_signature="$("$sign_update" -p "$archive")"
download_url="${download_prefix}${archive_name}"
output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
temporary_feed="$(mktemp "$output_dir/.appcast.XXXXXX.xml")"
trap 'rm -f "$temporary_feed"' EXIT

cat > "$temporary_feed" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>NOVA Copilot</title>
    <link>https://github.com/Ethan-cat-a/NOVA</link>
    <description>NOVA Copilot software updates</description>
    <language>en</language>
    <item>
      <title>Version ${short_version}</title>
      <pubDate>${published_at}</pubDate>
      <sparkle:version>${build_version}</sparkle:version>
      <sparkle:shortVersionString>${short_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimum_system_version}</sparkle:minimumSystemVersion>
      <enclosure url="${download_url}" length="${archive_length}" type="application/octet-stream" sparkle:edSignature="${archive_signature}" />
    </item>
  </channel>
</rss>
EOF

"$sign_update" --verify "$archive" "$archive_signature"
"$sign_update" "$temporary_feed" >/dev/null
"$sign_update" --verify "$temporary_feed"
mv "$temporary_feed" "$output"
trap - EXIT
echo "Signed appcast for NOVA Copilot ${short_version} (build ${build_version})."
