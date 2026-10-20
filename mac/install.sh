#!/bin/sh
# Builds Lumen Agents and runs it in the background on this Mac (a launchd agent that starts at login).
#   ./mac/install.sh            build, install and (re)start
#   ./mac/install.sh uninstall  stop it and remove it (pairings and the T3 token are kept)
set -eu
cd "$(dirname "$0")"
APP="$HOME/Library/Application Support/Lumen Agents"
BIN="$APP/lumen-agents"
PLIST="$HOME/Library/LaunchAgents/local.lumen.agents.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/local.lumen.agents" 2>/dev/null || true
if [ "${1:-}" = uninstall ]; then
    rm -f "$PLIST" "$BIN" "$HOME/.local/bin/lumen-agents"
    echo "Removed Lumen Agents. Revoke its T3 token in T3 Code's connections list (Lumen TV)."
    exit 0
fi

mkdir -p "$APP" "$HOME/Library/LaunchAgents" "$HOME/.local/bin"
chmod 700 "$APP"
swiftc -O -swift-version 5 -o "$BIN" LumenAgents.swift
ln -sf "$BIN" "$HOME/.local/bin/lumen-agents"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.lumen.agents</string>
    <key>ProgramArguments</key><array><string>$BIN</string><string>serve</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>Nice</key><integer>5</integer>
    <key>LowPriorityIO</key><true/>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/lumen-agents.log</string>
</dict>
</plist>
PLIST
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Lumen Agents is running (log: ~/Library/Logs/lumen-agents.log)."
echo "Pair the TV from Lumen's home screen, then run: lumen-agents pair <code>"
