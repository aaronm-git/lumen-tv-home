#!/bin/sh
set -eu
cd "$(dirname "$0")"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lumen-android-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
javac --release 17 -d "$WORK" $(find stubs -name '*.java') ../../src/local/tvhome/AgentStatus.java AgentStatusTest.java
java -cp "$WORK" local.tvhome.AgentStatusTest
