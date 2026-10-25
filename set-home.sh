#!/bin/sh
# Chooses what the remote's Home button opens: ./set-home.sh lumen|stock|projectivy <tv-ip:port>
#   lumen       Lumen's accessibility service catches Home
#   stock       turns Lumen's (and Projectivy's) service off, so Home opens the stock Google TV home again
#   projectivy  re-enables Projectivy (if installed) and makes it Home instead
# Only these services are added or removed; any other accessibility services stay as they are.
set -eu
LUMEN=local.tvhome/.HomeKeyService
PROJECTIVY=com.spocky.projengmenu/.services.ProjectivyAccessibilityService
# The TV's own Settings may have saved them in the long form.
LUMEN_LONG=local.tvhome/local.tvhome.HomeKeyService
PROJECTIVY_LONG=com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
case "${1:-}" in
    lumen) ON=$LUMEN ;;
    stock) ON= ;;
    projectivy) ON=$PROJECTIVY ;;
    *) ON=bad ;;
esac
if [ "$ON" = bad ] || [ $# -ne 2 ]; then
    echo "usage: $0 lumen|stock|projectivy <tv-ip:port>" >&2
    exit 1
fi
T=$2

adb connect "$T" >/dev/null
if [ "$1" = projectivy ]; then
    adb -s "$T" shell pm path com.spocky.projengmenu >/dev/null 2>&1 \
        || { echo "Projectivy isn't installed on the TV; try: $0 stock $T" >&2; exit 1; }
fi
# Read the current list first; if the TV doesn't answer, stop rather than overwrite what's there.
CUR=$(adb -s "$T" shell settings get secure enabled_accessibility_services) || CUR=
CUR=$(printf '%s\n' "$CUR" | tr -d '\r')
if [ -z "$CUR" ]; then
    echo "Couldn't read the TV's accessibility services; nothing was changed." >&2
    exit 1
fi
[ "$CUR" = null ] && CUR=
# Projectivy may have been disabled while Lumen was home; turn it back on.
[ "$1" != projectivy ] || adb -s "$T" shell pm enable com.spocky.projengmenu >/dev/null
NEW=$(printf '%s\n' "$CUR" | tr ':' '\n' | grep -vxF -e "$LUMEN" -e "$LUMEN_LONG" \
    -e "$PROJECTIVY" -e "$PROJECTIVY_LONG" -e "" | paste -sd: - || true)

set_services() {
    if [ -n "$1" ]; then
        # One single-quoted string for the TV's shell, so a $ in a service name isn't expanded there.
        adb -s "$T" shell "settings put secure enabled_accessibility_services '$(printf '%s' "$1" | sed "s/'/'\\\\''/g")'"
        adb -s "$T" shell settings put secure accessibility_enabled 1
    else
        adb -s "$T" shell settings delete secure enabled_accessibility_services >/dev/null
        adb -s "$T" shell settings put secure accessibility_enabled 0
    fi
}

# Rewriting the same enabled list doesn't recover a service Android marked as crashed.
set_services "$NEW"
if [ -n "$ON" ]; then
    sleep 1
    if [ "$1" = lumen ]; then
        adb -s "$T" shell am force-stop local.tvhome
        adb -s "$T" shell am start -W -n local.tvhome/.HomeActivity >/dev/null
    fi
    NEW=${NEW:+$NEW:}$ON
    set_services "$NEW"
    ATTEMPTS=0
    while :; do
        STATUS=$(adb -s "$T" shell dumpsys activity services "$ON")
        if printf '%s\n' "$STATUS" | grep -q 'hasBound=true'; then break; fi
        ATTEMPTS=$((ATTEMPTS + 1))
        if [ "$ATTEMPTS" -ge 10 ]; then
            echo "${1}'s Home service didn't connect; Home setup failed." >&2
            exit 1
        fi
        sleep 1
    done
fi
if [ "$1" = lumen ]; then
    # Check Home from another screen, rather than only opening Lumen directly.
    adb -s "$T" shell am start -W -a android.settings.SETTINGS >/dev/null
fi
adb -s "$T" shell input keyevent HOME
if [ "$1" = lumen ]; then
    ATTEMPTS=0
    while :; do
        sleep 1
        STATUS=$(adb -s "$T" shell dumpsys activity activities)
        if printf '%s\n' "$STATUS" | grep -E 'mResumedActivity|topResumedActivity' | grep -q 'local.tvhome/'; then
            break
        fi
        ATTEMPTS=$((ATTEMPTS + 1))
        if [ "$ATTEMPTS" -ge 10 ]; then
            echo "Home didn't open Lumen; Home setup failed." >&2
            exit 1
        fi
    done
fi
echo "Home button now opens ${1}. When you're done, turn off network debugging in the TV's Developer options."
