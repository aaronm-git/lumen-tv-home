# TV development

My TV is connected to my laptop over network ADB. When making updates to `master`, build and install the updated app on the TV.

- Model: Sony BRAVIA 4K VH2
- Device: `BRAVIA_VH2` (product: `BRAVIA_VH2_UC`)
- ADB address: `192.168.4.127:5555`
- App package: `local.tvhome`
- Android SDK ADB: `$HOME/Library/Android/sdk/platform-tools/adb`

Build and update the TV, preserving its app data:

```sh
./build.sh
"$HOME/Library/Android/sdk/platform-tools/adb" connect 192.168.4.127:5555
"$HOME/Library/Android/sdk/platform-tools/adb" -s 192.168.4.127:5555 install -r lumen.apk
```

Always specify the TV with `-s`; an Android emulator may also be connected. If the address stops working, check `adb devices -l` and `adb mdns services` using the SDK ADB executable above, and verify the TV's model before installing.
