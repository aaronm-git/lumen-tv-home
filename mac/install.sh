#!/bin/sh
# Builds Lumen Agents and runs it in the background on this Mac (a launchd agent that starts at login).
#   ./mac/install.sh            build, install and (re)start
#   ./mac/install.sh uninstall  stop it and remove it (pairings, the T3 token and the log are kept)
#   ./mac/install.sh purge      uninstall, and also delete the token, pairings, admin secret and log
set -eu
cd "$(dirname "$0")"
APP="$HOME/Library/Application Support/Lumen Agents"
BIN="$APP/lumen-agents"
PLIST="$HOME/Library/LaunchAgents/local.lumen.agents.plist"
LOG="$HOME/Library/Logs/lumen-agents.log"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
    ""|uninstall|purge) ;;
    *) echo "usage: $0 [uninstall|purge]" >&2; exit 1 ;;
esac

launchctl bootout "$DOMAIN/local.lumen.agents" 2>/dev/null || true
case "${1:-}" in
    uninstall|purge)
        rm -f "$PLIST" "$BIN" "$HOME/.local/bin/lumen-agents"
        if [ "$1" = purge ]; then
            rm -rf "$APP" "$LOG"
            echo "Removed Lumen Agents with its token, pairings and log."
        else
            echo "Removed Lumen Agents. Its token, pairings and log are kept (./mac/install.sh purge deletes them)."
        fi
        echo "Revoke its T3 Code session too: Lumen TV in T3 Code's connections, or"
        echo "  ~/.t3/bin/t3 auth session list   then   ~/.t3/bin/t3 auth session revoke <id>"
        echo "The TV's copy of its key goes when you uninstall Lumen or clear its storage."
        exit 0 ;;
esac

mkdir -p "$APP" "$HOME/Library/LaunchAgents" "$HOME/.local/bin" "$HOME/Library/Logs"
chmod 700 "$APP"
# Token, keys and log are for your eyes only.
find "$APP" -maxdepth 1 -type f ! -name lumen-agents -exec chmod 600 {} +
touch "$LOG"
chmod 600 "$LOG"
swiftc -O -swift-version 5 -o "$BIN" LumenAgents.swift
ln -sf "$BIN" "$HOME/.local/bin/lumen-agents"

# launchd doesn't see your shell's variables, so a custom T3 Code location goes into the job.
ENVVARS=
if [ -n "${T3CODE_HOME:-}" ]; then
    ENVVARS="<key>EnvironmentVariables</key><dict><key>T3CODE_HOME</key><string>$T3CODE_HOME</string></dict>"
fi
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
    <key>Umask</key><integer>63</integer>
    <key>StandardErrorPath</key><string>$LOG</string>
    $ENVVARS
</dict>
</plist>
PLIST
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Lumen Agents is running (log: ~/Library/Logs/lumen-agents.log)."
echo "Pair the TV from Lumen's home screen, then run: lumen-agents pair <code>"
