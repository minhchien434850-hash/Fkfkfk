#!/usr/bin/env bash
# Generate the Xcode project and install dev tools.
set -e
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
command -v swiftformat >/dev/null 2>&1 || brew install swiftformat

xcodegen
echo "✅ RemoteDesktop.xcodeproj generated. Open it in Xcode 16+."
