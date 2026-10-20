# Quickstart: Install Lumen

This page shows you how to build Lumen from source, install it on your TV, and configure the Home button and media access.

## Objectives

- Build and install your own signed APK.
- Make the remote's **Home** button open Lumen.
- Verify **Now playing** and **Continue watching**.
- Customize your home screen and install updates.

## Before you begin

You need:

- A TV running Android 9 (API 28) or later, a remote, and access to its developer options. Lumen is tested only on one Sony BRAVIA with Google TV running Android 12. Home-button interception assumes the Google TV launcher.
- A computer and TV on the same trusted network, with network debugging available on the TV.
- Git, JDK 17, Android SDK Command-Line Tools, `openssl`, and `zip`. The Mac-only Agents helper is optional.

Complete these checks before connecting to the TV:

1. In your computer's shell, set the SDK and JDK locations and add their tools to `PATH`:

   ```sh
   export ANDROID_HOME="ANDROID_SDK_DIRECTORY"
   export JAVA_HOME="JDK_DIRECTORY"
   export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
   ```

   Replace *`ANDROID_SDK_DIRECTORY`* with your absolute Android SDK path, commonly *`~/Library/Android/sdk`* on macOS (use the expanded absolute path inside the quotes). Replace *`JDK_DIRECTORY`* with the absolute JDK 17 home directory. This assumes the SDK Command-Line Tools are installed in *`cmdline-tools/latest`*; use their actual directory if different. Add the exports to your shell's startup file if you want them to persist. Without *`ANDROID_HOME`*, the build script defaults to *`$HOME/Library/Android/sdk`*.

2. In the same shell, install the exact SDK packages the build uses:

   ```sh
   sdkmanager "build-tools;36.0.0" "platforms;android-34" "platform-tools"
   ```

   Accept any SDK license prompts. Platform 34 supplies the compile-time API; Lumen still targets API 31.

3. In the same shell, verify the command locations:

   ```sh
   command -v git sdkmanager adb javac keytool openssl zip
   ```

   Each command must resolve to an executable. In particular, *`adb`* comes from SDK platform-tools, and *`javac`* and *`keytool`* come from the JDK.

4. In the same shell, verify the compiler and build tools:

   ```sh
   javac -version
   test -f "$ANDROID_HOME/platforms/android-34/android.jar"
   test -x "$ANDROID_HOME/build-tools/36.0.0/aapt2"
   test -x "$ANDROID_HOME/build-tools/36.0.0/d8"
   test -x "$ANDROID_HOME/build-tools/36.0.0/zipalign"
   test -x "$ANDROID_HOME/build-tools/36.0.0/apksigner"
   ```

   Verify that *`javac`* reports version 17. Each *`test`* command must exit successfully; it prints nothing on success. See [Build tools are missing](troubleshooting.md#build-tools-are-missing) if a check fails.

## Get the source

1. On the repository page, copy its clone URL.
2. On your computer, clone the repository:

   ```sh
   git clone REPOSITORY_URL lumen-tv-home
   ```

   Replace *`REPOSITORY_URL`* with the clone URL you copied.

3. In your shell, enter the source directory:

   ```sh
   cd lumen-tv-home
   ```

Run the remaining repository scripts from this directory.

## Turn on network debugging on the TV and connect

1. In the TV's system settings, enable developer options using the instructions for your TV model.
2. In the TV's developer options, turn on network debugging. The setting name varies by TV.
3. In the TV's network or debugging settings, note the address and debugging port.
4. On your computer, request a connection:

   ```sh
   adb connect DEVICE_ADDRESS
   ```

   Replace *`DEVICE_ADDRESS`* throughout this guide with the TV's IP address and ADB port, such as *`192.0.2.10:5555`*. Use the port your TV provides. If your TV requires a separate wireless-debugging pairing procedure, complete its manufacturer-provided procedure first; Lumen's scripts don't perform ADB pairing.

5. On the TV, accept the debugging authorization prompt for your computer.
6. On your computer, verify the connection:

   ```sh
   adb devices
   ```

   The entry for your TV must have state *`device`*. If it is absent, *`offline`*, or *`unauthorized`*, follow [ADB can't connect or shows unauthorized](troubleshooting.md#adb-cant-connect-or-shows-unauthorized).

## Build and install Lumen

> [!IMPORTANT]
> Keep *`keys/lumen.jks`* and *`keys/password`* together in a safe location. The first build creates them, and Git ignores them. Updates require the same signing key. If you lose it, installing a replacement build requires removing the old app and losing its local data.

1. In the source directory, build the APK:

   ```sh
   ./build.sh
   ```

   The script rebuilds *`build/`* and writes *`lumen.apk`*. It reads the version from *`VERSION`*.

2. In the source directory, install the APK on your connected TV:

   ```sh
   adb -s DEVICE_ADDRESS install -r lumen.apk
   ```

   Wait for installation to complete before continuing.

## Allow media access

Android shares active media sessions with notification listeners. Lumen uses this access for **Now playing** and to record **Continue watching**. It ignores notification contents, but Android grants listeners the ability to read them. See [TV permissions](../PRIVACY.md#tv-data-and-permissions).

1. In the source directory, grant notification-listener access:

   ```sh
   ./build.sh grant DEVICE_ADDRESS
   ```

   The script explains the access before granting it to *`local.tvhome/local.tvhome.MediaAccess`*.

2. In Lumen, open **Settings**. With **Now playing** and **Continue watching** on, their descriptions must no longer say **waiting for permission**.

Optional: To revoke access later, use the TV's notification-access settings, if available. Revoking access stops both media features. You can also revoke access with ADB:

1. On your computer, revoke the listener's access:

   ```sh
   adb -s DEVICE_ADDRESS shell cmd notification disallow_listener local.tvhome/local.tvhome.MediaAccess
   ```

## Make Lumen the Home button

Lumen uses an accessibility service to intercept **Home** and redirect the Google TV home screen to Lumen. It passes other remote keys through, can't read window contents, and receives window events only from the Google TV launcher. The same service draws optional agent notifications over other apps.

1. In the source directory, enable Lumen's accessibility service:

   ```sh
   ./set-home.sh lumen DEVICE_ADDRESS
   ```

   The script turns off Projectivy's accessibility service if present, preserves other accessibility services, and sends a Home key event. Lumen opens. For alternatives, see [Restore the Home button](uninstall.md#restore-the-home-button).

## Verify setup

1. On the TV, select **Lumen** in the installed-app list. Its home screen opens.
2. On the remote, press **Home**. Lumen opens again.
3. In a streaming app that publishes media sessions, play a show or movie for at least 20 seconds.
4. On the remote, press **Home**. **Now playing** shows the playing or paused media, and **Continue watching** includes the show.

> [!NOTE]
> An empty **Continue watching** row at first is expected. Lumen records your viewing from this point forward; it doesn't import Google TV's history. Music, casting, and Live TV aren't recorded, and media-session support varies by app.

## Customize your home screen

### Add or remove a favorite

1. On an app tile, press and hold **OK** to open its options.
2. In the options, select **Add to Favorites** or **Remove from Favorites**.

### Move a favorite

**Move** appears in **Rows** when the favorites row has at least two visible apps.

1. On a favorite tile, press and hold **OK** to open its options.
2. In the options, select **Move**.
3. On the remote, press **Left** or **Right** to move the favorite.
4. On the remote, press **OK** to finish.

### Hide or restore an app

1. If the app is a favorite, [remove it from Favorites](#add-or-remove-a-favorite) first.
2. On the app tile, press and hold **OK** to open its options.
3. In the options, select **Hide**. The app disappears from Lumen.
4. Optional: In **Settings > Hidden apps**, select the app to restore it. The **Hidden apps** label includes a count.

### Change the layout

1. In Lumen, select **Settings > Rows** or **Settings > Grid**.

### Switch inputs

1. In Lumen, select **Inputs** to open the input list.
2. In the list, select an HDMI device or, on supported Sony TVs, **Live TV**.

### Manage watch history

Removing a show deletes its history entry. Clearing history removes every recorded show and thumbnail.

1. On a show in **Continue watching**, press and hold **OK** to open its options.
2. In the options, select **Remove from Continue watching** for that show, or **Clear Continue watching** for the whole history.

You can also select **Settings > Clear watch history** when history exists. Turning **Settings > Continue watching** off stops recording and progress updates but keeps existing history.

## Update Lumen

Before updating, complete the [debugging connection checks](#turn-on-network-debugging-on-the-tv-and-connect) again and verify that your original *`keys/lumen.jks`* and *`keys/password`* are in the source directory. Obtain the updated source without replacing those files.

1. In the updated source directory, rebuild with the existing key:

   ```sh
   ./build.sh
   ```

2. In the source directory, install the update:

   ```sh
   adb -s DEVICE_ADDRESS install -r lumen.apk
   ```

3. On the remote, press **Home** to verify that Lumen opens with your settings and history intact.

If Android reports *`INSTALL_FAILED_UPDATE_INCOMPATIBLE`*, read [Install fails with a signature mismatch](troubleshooting.md#install-fails-with-install_failed_update_incompatible) before removing anything.

## Turn off debugging

Leaving ADB network debugging enabled lets other devices on the network try to connect to your TV.

1. In the TV's developer options, turn off network debugging after installation or updates. Lumen and Agents don't require it for normal use.

## What's next

- [Set up the optional Agents card and notifications](set-up-agents.md#before-you-begin).
- [Troubleshoot Lumen](troubleshooting.md#before-you-begin).
- [Review local data storage](../PRIVACY.md#tv-data-and-permissions).
