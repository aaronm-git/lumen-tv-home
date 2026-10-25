#!/bin/sh
set -eu
cd "$(dirname "$0")"
case "$#:${1:-}" in
    0:|1:uninstall|1:purge) ;;
    *) echo "usage: $0 [uninstall|purge]" >&2; exit 1 ;;
esac

ACCOUNT=$(dscl -plist . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null \
    | plutil -extract dsAttrTypeStandard:NFSHomeDirectory.0 raw -o - - 2>/dev/null || true)
case "$ACCOUNT" in
    /*) ;;
    *) echo "Couldn't look up your account's home folder; nothing was changed." >&2; exit 1 ;;
esac
while case "${HOME:-}" in ?*/) true ;; *) false ;; esac; do HOME=${HOME%/}; done
if [ "$ACCOUNT" != "${HOME:-}" ]; then
    echo "\$HOME (${HOME:-unset}) isn't your account's home folder ($ACCOUNT); nothing was changed." >&2
    exit 1
fi
if [ ! -d "$ACCOUNT" ]; then
    echo "Your home folder ($ACCOUNT) doesn't exist; nothing was changed." >&2
    exit 1
fi

APP="$HOME/Library/Application Support/Lumen Agents"
BIN="$APP/lumen-agents"
PLIST="$HOME/Library/LaunchAgents/local.lumen.agents.plist"
LOG="$HOME/Library/Logs/lumen-agents.log"
LINK="$HOME/.local/bin/lumen-agents"
DOMAIN="gui/$(id -u)"

for f in "$APP" "$PLIST" "$LOG"; do
    if [ -L "$f" ]; then
        echo "$f is a symlink; remove it or put the real thing there first. Nothing was changed." >&2
        exit 1
    fi
done
if { [ -e "$LINK" ] || [ -L "$LINK" ]; } && [ "$(readlink "$LINK" || true)" != "$BIN" ]; then
    echo "$LINK isn't a link to Lumen Agents; move it out of the way first. Nothing was changed." >&2
    exit 1
fi

case "${1:-}" in
    uninstall|purge)
        if [ -n "${LUMEN_DRY_RUN:-}" ]; then
            echo "Would stop $DOMAIN/local.lumen.agents and remove: $PLIST $BIN $LINK"
            [ "$1" = purge ] && echo "  and: $APP $LOG"
            exit 0
        fi
        launchctl bootout "$DOMAIN/local.lumen.agents" 2>/dev/null || true
        rm -f "$PLIST" "$BIN" "$LINK"
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

STAGE=
NEW=$(mktemp "${TMPDIR:-/tmp}/lumen-agents.XXXXXX")
trap 'rm -f "$NEW"; [ -z "$STAGE" ] || rm -rf "$STAGE"' EXIT
plutil -create xml1 "$NEW"
plutil -insert Label -string local.lumen.agents "$NEW"
plutil -insert ProgramArguments -array "$NEW"
plutil -insert ProgramArguments -string "$BIN" -append "$NEW"
plutil -insert ProgramArguments -string serve -append "$NEW"
plutil -insert RunAtLoad -bool YES "$NEW"
plutil -insert KeepAlive -bool YES "$NEW"
plutil -insert ThrottleInterval -integer 30 "$NEW"
plutil -insert Nice -integer 5 "$NEW"
plutil -insert LowPriorityIO -bool YES "$NEW"
plutil -insert Umask -integer 63 "$NEW"
plutil -insert StandardErrorPath -string "$LOG" "$NEW"
if [ -n "${T3CODE_HOME:-}" ]; then
    plutil -insert EnvironmentVariables -dictionary "$NEW"
    plutil -insert EnvironmentVariables.T3CODE_HOME -string "$T3CODE_HOME" "$NEW"
fi
plutil -lint -s "$NEW"
if [ -n "${LUMEN_DRY_RUN:-}" ]; then
    echo "Would build $BIN and install this as $PLIST:"
    cat "$NEW"
    exit 0
fi

mkdir -p "$APP" "$HOME/Library/LaunchAgents" "$HOME/.local/bin" "$HOME/Library/Logs"
chmod 700 "$APP"
find "$APP" -maxdepth 1 -type f ! -name lumen-agents -exec chmod 600 {} +
touch "$LOG"
chmod 600 "$LOG"
STAGE=$(mktemp -d "$APP/.install.XXXXXX")
swiftc -O -swift-version 5 -o "$STAGE/lumen-agents" LumenAgents.swift

[ ! -e "$BIN" ] || cp -p "$BIN" "$STAGE/previous"
[ ! -e "$PLIST" ] || cp -p "$PLIST" "$STAGE/previous.plist"
launchctl bootout "$DOMAIN/local.lumen.agents" 2>/dev/null || true
if ! { mv -f "$STAGE/lumen-agents" "$BIN" && ln -sf "$BIN" "$LINK" && chmod 644 "$NEW" \
        && mv -f "$NEW" "$PLIST" && launchctl bootstrap "$DOMAIN" "$PLIST"; }; then
    if [ -e "$STAGE/previous.plist" ]; then
        if { [ ! -e "$STAGE/previous" ] || mv -f "$STAGE/previous" "$BIN"; } \
                && mv -f "$STAGE/previous.plist" "$PLIST" && launchctl bootstrap "$DOMAIN" "$PLIST"; then
            echo "Couldn't start the new Lumen Agents; the previous version is running again." >&2
        else
            echo "Couldn't start the new Lumen Agents or put the previous one back; it isn't running." >&2
            if [ -e "$STAGE/previous" ] || [ -e "$STAGE/previous.plist" ]; then
                echo "The previous version's files are in $STAGE." >&2
                STAGE=
            fi
        fi
    else
        if [ -e "$STAGE/previous" ]; then mv -f "$STAGE/previous" "$BIN" || true; else rm -f "$BIN" "$LINK"; fi
        rm -f "$PLIST"
        echo "Couldn't start Lumen Agents; it isn't installed." >&2
    fi
    exit 1
fi
echo "Lumen Agents is running (log: ~/Library/Logs/lumen-agents.log)."
echo "Allow it to read T3 Code (first time, or after T3 Code rejects its token): lumen-agents authorize"
echo "Pair the TV from Lumen's home screen, then run: lumen-agents pair <code>"
