#!/bin/sh
set -eu
cd "$(dirname "$0")"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lumen-agents-tests.XXXXXX")
trap 'pkill -f "$WORK/" 2>/dev/null || true; chmod -R u+rwx "$WORK"; rm -rf "$WORK"' EXIT
APP="$WORK/T3 Code.app/Contents/MacOS"
mkdir -p "$APP"
swiftc -swift-version 5 -o "$WORK/lumen-agents" ../LumenAgents.swift
swiftc -swift-version 5 -o "$APP/T3 Code" FakeT3.swift
swiftc -swift-version 5 -o "$WORK/tests" AgentsTests.swift
"$WORK/tests" "$WORK/lumen-agents" "$APP/T3 Code" "$WORK"
