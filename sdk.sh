# Sourced by build.sh and test.sh.
# Command Line Tools 27 have no SwiftUI macro plugin, so the macOS 27 SDK cannot compile @State.
# In that case, use the newest macOS 26 SDK that the Command Line Tools still hold.
clt=/Library/Developer/CommandLineTools
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p 2>/dev/null)" = "$clt" ] \
   && ! ls "$clt"/usr/lib/swift/host/plugins/*SwiftUIMacros* >/dev/null 2>&1; then
  sdk=$(ls -d "$clt"/SDKs/MacOSX26.[0-9]*.sdk 2>/dev/null | sort -V | tail -1)
  if [ -n "$sdk" ]; then export SDKROOT="$sdk"
  else echo "warning: no SwiftUI macro plugin and no macOS 26 SDK; the build can fail" >&2; fi
fi
