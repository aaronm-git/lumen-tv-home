#!/bin/sh
# Offline tests for the TV's AgentStatus (see AgentStatusTest.java): compiles it with small stand-ins for Android's
# classes (stubs/) in a temporary folder and runs it on this Mac's JVM against a fake helper on 127.0.0.1. Doesn't
# need the Android SDK, a TV, an emulator or ADB.
set -eu
cd "$(dirname "$0")"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lumen-android-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
javac --release 17 -d "$WORK" $(find stubs -name '*.java') ../../src/local/tvhome/AgentStatus.java AgentStatusTest.java
java -cp "$WORK" local.tvhome.AgentStatusTest
