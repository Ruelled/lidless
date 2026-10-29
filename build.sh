#!/bin/sh
# Build Lidless.app and copy it to ~/Applications.
set -eu
cd "$(dirname "$0")"
app=build/Lidless.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
# Universal binary: Apple silicon and Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos13" \
    Lidless.swift -o "build/Lidless-$arch"
done
lipo -create build/Lidless-arm64 build/Lidless-x86_64 -output "$app/Contents/MacOS/Lidless"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Lidless</string>
  <key>CFBundleIdentifier</key><string>io.github.ruelled.lidless</string>
  <key>CFBundleExecutable</key><string>Lidless</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - "$app"
[ "${1:-}" = "--no-install" ] && exit 0
mkdir -p ~/Applications
rm -rf ~/Applications/Lidless.app
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/Lidless.app"
