#!/bin/sh
# CI guard for the three version locations documented in AGENTS.md.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

APP_VERSION=$(sed -n 's/.*static let appVersion = "\([^"]*\)".*/\1/p' "$ROOT/Sources/Gantry/App/AppModel.swift" || true)
PLIST_VERSION=$(awk -F'[<>]' '/<key>CFBundleShortVersionString<\/key>/{getline; print $3; exit}' "$ROOT/Resources/Info.plist" || true)
MCP_VERSION=$(sed -n 's/.*"version": \.string("\([^"]*\)").*/\1/p' "$ROOT/Sources/GantryPluginMCP/main.swift" || true)

if [ -z "$APP_VERSION" ] || [ -z "$PLIST_VERSION" ] || [ -z "$MCP_VERSION" ]; then
    echo "version check: could not read all three version sources" >&2
    echo "  AppModel:   ${APP_VERSION:-missing}" >&2
    echo "  Info.plist: ${PLIST_VERSION:-missing}" >&2
    echo "  MCP helper: ${MCP_VERSION:-missing}" >&2
    exit 1
fi

if [ "$APP_VERSION" != "$PLIST_VERSION" ] || [ "$APP_VERSION" != "$MCP_VERSION" ]; then
    echo "version mismatch: AppModel=$APP_VERSION Info.plist=$PLIST_VERSION MCP=$MCP_VERSION" >&2
    exit 1
fi

echo "versions match: $APP_VERSION"
