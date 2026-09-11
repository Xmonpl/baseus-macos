#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    bin_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c release
    bin_dir="$(swift build -c release --show-bin-path)"
fi

mkdir -p dist .build
staging="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Baseus Menu.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/BaseusMenu" "$app/Contents/MacOS/BaseusMenu"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Baseus-Menu-macOS.zip"
# Replace the bundle rather than overwriting a potentially running executable.
if [[ -d "dist/Baseus Menu.app" ]]; then
    mv "dist/Baseus Menu.app" "$staging/previous.app"
fi
mv "$app" "dist/Baseus Menu.app"
echo "Gotowe: $PWD/dist/Baseus Menu.app"
