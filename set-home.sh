#!/bin/sh
# Chooses what the remote's Home button opens: ./set-home.sh lumen|projectivy [tv-ip:port]
set -eu
T=${2:-192.168.4.127:5555}
LUMEN=local.tvhome/.HomeKeyService
PROJECTIVY=com.spocky.projengmenu/.services.ProjectivyAccessibilityService
case "${1:-}" in
    lumen) ON=$LUMEN OFF=$PROJECTIVY ;;
    projectivy) ON=$PROJECTIVY OFF=$LUMEN ;;
    *) echo "usage: $0 lumen|projectivy [tv-ip:port]" >&2; exit 1 ;;
esac

adb connect "$T" >/dev/null
# Projectivy is disabled while Lumen is home; turn it back on first if switching to it.
[ "$1" = projectivy ] && adb -s "$T" shell pm enable com.spocky.projengmenu >/dev/null
CUR=$(adb -s "$T" shell settings get secure enabled_accessibility_services | tr -d '\r')
[ "$CUR" = null ] && CUR=
# Keep any other accessibility services as they are; swap only these two.
NEW=$(printf '%s\n' "$CUR" | tr ':' '\n' | grep -vxF -e "$ON" -e "$OFF" -e "" | { cat; echo "$ON"; } | paste -sd: -)
adb -s "$T" shell settings put secure enabled_accessibility_services "$NEW"
adb -s "$T" shell settings put secure accessibility_enabled 1
adb -s "$T" shell input keyevent HOME
echo "Home button now opens $1"
