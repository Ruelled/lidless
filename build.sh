#!/bin/sh
# Build Lidless.app, copy it to ~/Applications and install the `lidless` command in ~/.local/bin.
#   ./build.sh               build and install
#   ./build.sh --no-install  build only (CI)
set -eu
cd "$(dirname "$0")"
version=0.2
commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)
app=build/Lidless.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# Universal binary: Apple silicon and Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos13" \
    Sources/*.swift -o "build/Lidless-$arch"
done
lipo -create build/Lidless-arm64 build/Lidless-x86_64 -output "$app/Contents/MacOS/Lidless"
cp skill/SKILL.md "$app/Contents/Resources/SKILL.md"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Lidless</string>
  <key>CFBundleIdentifier</key><string>io.github.ruelled.lidless</string>
  <key>CFBundleExecutable</key><string>Lidless</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LidlessCommit</key><string>$commit</string>
  <key>LidlessSource</key><string>$(pwd)</string>
</dict></plist>
EOF
codesign --force -s - "$app"
[ "${1:-}" = "--no-install" ] && exit 0

mkdir -p ~/Applications
rm -rf ~/Applications/Lidless.app
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/Lidless.app"

# The `lidless` command: a wrapper that runs the app binary in command line mode.
mkdir -p ~/.local/bin
printf '#!/bin/sh\n# Installed by Lidless. Runs the command line of the Lidless app.\nexec "%s" "$@"\n' \
  "$HOME/Applications/Lidless.app/Contents/MacOS/Lidless" > ~/.local/bin/lidless
chmod 755 ~/.local/bin/lidless
echo "Installed ~/.local/bin/lidless"

# Keep agent skills current, but only where the user installed them.
for dir in .claude/skills .codex/skills .agents/skills; do
  if [ -f "$HOME/$dir/lidless/SKILL.md" ]; then
    cp skill/SKILL.md "$HOME/$dir/lidless/SKILL.md"
    echo "Updated ~/$dir/lidless/SKILL.md"
  fi
done

if pgrep -qf "Lidless.app/Contents/MacOS/Lidless$"; then
  echo "Lidless is running the old build. Quit it from its menu and open it again."
fi
