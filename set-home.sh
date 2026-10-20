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
    # Projectivy may have been disabled while Lumen was home; turn it back on first.
    adb -s "$T" shell pm enable com.spocky.projengmenu >/dev/null
fi
CUR=$(adb -s "$T" shell settings get secure enabled_accessibility_services | tr -d '\r')
[ "$CUR" = null ] && CUR=
NEW=$(printf '%s\n' "$CUR" | tr ':' '\n' | grep -vxF -e "$LUMEN" -e "$LUMEN_LONG" \
    -e "$PROJECTIVY" -e "$PROJECTIVY_LONG" -e "" | paste -sd: - || true)
[ -n "$ON" ] && NEW=${NEW:+$NEW:}$ON
if [ -n "$NEW" ]; then
    adb -s "$T" shell settings put secure enabled_accessibility_services "$NEW"
    adb -s "$T" shell settings put secure accessibility_enabled 1
else
    adb -s "$T" shell settings delete secure enabled_accessibility_services >/dev/null
    adb -s "$T" shell settings put secure accessibility_enabled 0
fi
adb -s "$T" shell input keyevent HOME
echo "Home button now opens ${1}. When you're done, turn off network debugging in the TV's Developer options."
