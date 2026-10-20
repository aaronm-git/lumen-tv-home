#!/bin/sh
# Builds Lumen without Gradle.
#   ./build.sh                  build lumen.apk
#   ./build.sh <tv-ip:port>     build it and install it on the TV over ADB
#   ./build.sh grant <tv-ip:port>  grant the one permission Lumen needs (says what it is first)
set -eu
cd "$(dirname "$0")"

if [ "${1:-}" = grant ]; then
    [ $# -eq 2 ] || { echo "usage: $0 grant <tv-ip:port>" >&2; exit 1; }
    echo "Granting notification-listener access to Lumen (local.tvhome/.MediaAccess)."
    echo "Android only shares media sessions (what's playing) with notification listeners. Lumen uses it for"
    echo "Now playing and Continue watching and ignores notifications themselves, but Android lets any listener"
    echo "read them. Revoke it in the TV's Settings, or: adb shell cmd notification disallow_listener ..."
    adb connect "$2" >/dev/null
    adb -s "$2" shell cmd notification allow_listener local.tvhome/local.tvhome.MediaAccess
    echo "Done."
    exit 0
fi

. ./VERSION
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$SDK/build-tools/36.0.0
JAR=$SDK/platforms/android-34/android.jar
OUT=build

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/unsigned.apk" -I "$JAR" --manifest AndroidManifest.xml --java "$OUT/gen" \
    --min-sdk-version 28 --target-sdk-version 31 --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" "$OUT/res.zip"
javac --release 17 -Xlint:-options -classpath "$JAR" -d "$OUT/classes" $(find src "$OUT/gen" -name '*.java')
"$BT/d8" --release --min-api 28 --lib "$JAR" --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')
(cd "$OUT/dex" && zip -q ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

# Updates must be signed with the same key, so it is made once and kept in keys/.
if [ ! -f keys/lumen.jks ]; then
    mkdir -p keys
    (umask 077 && openssl rand -hex 16 > keys/password)
    keytool -genkeypair -keystore keys/lumen.jks -alias lumen -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Lumen TV Home" -storepass "$(cat keys/password)" -keypass "$(cat keys/password)" >/dev/null
fi
"$BT/apksigner" sign --ks keys/lumen.jks --ks-pass file:keys/password --out lumen.apk "$OUT/aligned.apk"
echo "Built lumen.apk ($VERSION_NAME)"

if [ $# -gt 0 ]; then
    adb connect "$1" >/dev/null
    adb -s "$1" install -r lumen.apk
    echo "Installed. First time? Run ./build.sh grant $1 for Now playing and Continue watching."
fi
