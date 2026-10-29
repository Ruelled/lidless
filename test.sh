#!/bin/sh
# Unit tests. Needs no running app and changes nothing on the Mac.
set -eu
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 -target "$(uname -m)-apple-macos13" $(ls Sources/*.swift | grep -v '/App.swift$') Tests/main.swift -o build/tests
build/tests
