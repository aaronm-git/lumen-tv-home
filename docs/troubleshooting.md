# Troubleshoot Lumen

This page shows you how to diagnose build, TV, pairing, and notification problems and look up Lumen's commands.

## Before you begin

- Keep the Lumen source directory available; run repository scripts from that directory.
- For TV commands, [turn on network debugging and verify your ADB connection](quickstart.md#turn-on-network-debugging-on-the-tv-and-connect). Replace *`DEVICE_ADDRESS`* in the commands below with the TV's IP address and ADB port.
- For helper commands, use the Mac account that installed Lumen Agents. Check [the helper prerequisites](set-up-agents.md#before-you-begin).
- Note your Lumen version from *`VERSION`* and the symptom before changing settings. Preserve your signing key and redact diagnostics before sharing them.

## Build tools are missing

**Cause:** The script uses fixed SDK package versions. A missing executable, *`android.jar`*, or a JDK tool outside *`PATH`* prevents the build.

1. On your computer, repeat the [SDK and JDK verification checks](quickstart.md#before-you-begin). Verify *`ANDROID_HOME`*, the JDK 17 *`bin`* directory in *`PATH`*, build-tools 36.0.0, platform 34, and platform-tools.
2. In the source directory, rebuild:

   ```sh
   ./build.sh
   ```

   The script writes *`lumen.apk`* after compilation and signing succeed. If the failure mentions *`keys/password`*, restore it with its matching *`keys/lumen.jks`*; don't generate a replacement key for an existing installation.

## ADB can't connect or shows unauthorized

**Cause:** Network debugging is off, the address or port changed, the computer isn't authorized, or the network blocks device-to-device connections.

1. In the TV's developer options, verify that network debugging is on.
2. In the TV's network or debugging settings, verify its current IP address and debugging port.
3. On your computer, verify that it uses the same reachable network as the TV. Guest Wi-Fi and client isolation can block the connection.
4. On your computer, reconnect with the current address:

   ```sh
   adb connect DEVICE_ADDRESS
   ```

5. On the TV, accept the debugging authorization prompt. If your TV requires wireless-debugging pairing first, follow its manufacturer's pairing procedure.
6. On your computer, check the state:

   ```sh
   adb devices
   ```

   Continue only when the TV's state is *`device`*. An *`unauthorized`* state means authorization isn't complete; *`offline`* means the ADB connection isn't ready.

Turn off network debugging when you finish troubleshooting.

## Install fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE

**Cause:** The APK's signing key doesn't match the installed app. Android rejects an update signed with a different key.

1. In the source directory, check that *`keys/lumen.jks`* and *`keys/password`* are the files from the original build.
2. If you have the original key files, restore both files to *`keys/`*.
3. In the source directory, [rebuild and install the update](quickstart.md#update-lumen).

> [!WARNING]
> If you can't recover the original key, removing the app deletes its watch history, artwork, favorites, hidden apps, settings, and TV-side Agents pairing data. The Mac's pairing copy and T3 Code session remain. Use the removal procedure only if you accept this data loss.

4. If the original key is unavailable, [restore Home and uninstall the old TV app](uninstall.md#restore-the-home-button).
5. In the source directory, follow [Build and install Lumen](quickstart.md#build-and-install-lumen) for the replacement APK.
6. On the TV, repeat [media-access setup](quickstart.md#allow-media-access), [Home-button setup](quickstart.md#make-lumen-the-home-button), and Agents pairing if you use it.

## Home opens another launcher

**Cause:** Lumen's accessibility service isn't enabled, another launcher intercepts Home, or the TV doesn't use the assumed Google TV launcher.

1. In the source directory, enable Lumen's service:

   ```sh
   ./set-home.sh lumen DEVICE_ADDRESS
   ```

   This disables Projectivy's accessibility service, preserves unrelated services, and sends **Home**. It doesn't disable other launchers' services.

2. On the remote, press **Home** to verify that Lumen opens.
3. If another launcher still intercepts Home, review its Home-button configuration in the TV's accessibility settings.
4. If the script reports **Couldn't read the TV's accessibility services; nothing was changed.**, repeat the [ADB checks](#adb-cant-connect-or-shows-unauthorized).

Other Android TV launchers are untested. The fallback window-event handler recognizes only *`com.google.android.apps.tv.launcherx`*. To undo the setup, [restore the Home button](uninstall.md#restore-the-home-button).

## Media settings show waiting for permission

**Cause:** **Now playing** and **Continue watching** require notification-listener access. Turning their settings on doesn't grant access.

1. In the source directory, grant media access:

   ```sh
   ./build.sh grant DEVICE_ADDRESS
   ```

   This enables *`local.tvhome/local.tvhome.MediaAccess`*. Android grants notification listeners broader access than media sessions; Lumen ignores notification contents.

2. In Lumen, open **Settings** to verify that the enabled media features no longer show **On  ·  waiting for permission**.

## Continue watching is empty

**Cause:** The history starts empty, recording is off, media access is missing, or the playback doesn't qualify.

1. In Lumen, verify that **Settings > Continue watching** is on. With no history, the home screen shows **CONTINUE WATCHING  ·  SHOWS YOU PLAY WILL APPEAR HERE**.
2. In Lumen's **Settings**, check for **waiting for permission**. If present, follow [Allow media access](quickstart.md#allow-media-access).
3. In a streaming app that publishes a media session with a title, play a show or movie for at least 20 seconds. The recorder saves progress every 30 seconds and on pause.
4. On the remote, press **Home** to check the row.

Lumen doesn't import Google TV history. Lumen excludes selected music, casting, and live-TV apps. Other apps that publish media sessions can appear in watch history. Turning **Continue watching** off stops recording and updates without deleting existing entries. Clearing history or uninstalling removes the entries; they can't be recovered from Google TV.

## Mac offline

**Cause:** Lumen can't reach its helper. The Mac might be asleep, the helper might be stopped, the network might block discovery, or a pairing might have been removed on the Mac.

1. On the Mac, verify that it is awake and on the same reachable local network as the TV.
2. On the Mac, check the helper:

   ```sh
   lumen-agents status
   ```

   If the command isn't found, follow [lumen-agents: command not found](#lumen-agents-command-not-found).

3. On the Mac, inspect the launchd job:

   ```sh
   launchctl print "gui/$(id -u)/local.lumen.agents"
   ```

4. If the job is installed but stopped, start it on the Mac:

   ```sh
   launchctl kickstart -k "gui/$(id -u)/local.lumen.agents"
   ```

   If the job isn't installed, follow [Install the helper](set-up-agents.md#install-the-helper).

5. If local status works but the TV remains offline, check network or firewall restrictions on Bonjour discovery and TCP port 47837. Keep the helper on a trusted local network; don't expose it through router port forwarding.
6. If you removed a pairing on the Mac, follow [Replace a pairing](set-up-agents.md#replace-a-pairing). Lumen keeps an established key until you select **Pair again**, even if the Mac rejects it.

## lumen-agents: command not found

**Cause:** *`~/.local/bin`* isn't in your shell's *`PATH`*, or the helper isn't installed.

1. In your Mac's shell, add the command directory:

   ```sh
   export PATH="$HOME/.local/bin:$PATH"
   ```

2. In the same shell, verify the command location:

   ```sh
   command -v lumen-agents
   ```

3. If the command is still absent, [install the helper](set-up-agents.md#install-the-helper).
4. In your shell's startup file, add the export so future shells can find the command.

## T3 Code isn't running or T3 Code needs a new token

**Cause:** The helper can't find a trusted T3 Code listener, or its read-only session is missing, expired, or rejected. The TV shows **T3 Code isn't running** for *`offline`* and **T3 Code needs a new token** for an authentication state.

1. On your Mac, open the installed T3 Code app. A server run from source doesn't pass the helper's app-binary check.
2. On your Mac, verify the expected CLI path without running it:

   ```sh
   test -x "$HOME/.t3/bin/t3"
   ```

   For a custom T3 Code directory, check its *`bin/t3`* instead.

3. If you use a custom directory, repeat [Use a custom T3 Code directory](set-up-agents.md#optional-use-a-custom-t3-code-directory). Setting a shell variable alone doesn't update an existing launchd job.
4. On your Mac, inspect *`~/Library/Logs/lumen-agents.log`* for **T3 Code's t3 command isn't at** or **t3 auth session issue failed**, followed by the path or exit status. Don't share token files.
5. After correcting the cause, allow the helper to retry token issuance. It attempts issuance at most once every 10 minutes and renews its 30-day token automatically.
6. On your Mac, verify recovery:

   ```sh
   lumen-agents status
   ```

   The JSON field *`t3`* must be *`ok`*. A successful connection with an empty *`chats`* list is valid; idle, archived, deleted, or already-seen completed chats don't appear on the card.

## Pairing doesn't complete

**Cause:** The code is wrong, the pending request expired, the helper restarted, or the TV can't reach the Mac. Pending requests expire after 15 minutes; an expired request causes the TV to generate a new code.

1. On the TV, keep Lumen's home screen open with **Settings > Agents** on.
2. If you see **Mac offline**, complete the [Mac connectivity checks](#mac-offline).
3. On your Mac, run the pairing command with the code currently displayed on the TV:

   ```sh
   lumen-agents pair PAIRING_CODE
   ```

   Replace *`PAIRING_CODE`* with the current 16-character code. Letter case doesn't matter; dashes are optional. The error **No TV is showing that code. Open Lumen's home screen and try again.** means the helper couldn't approve a matching pending request.

4. If the code still fails, select **Settings > Pair again** on the TV to replace the key and code.
5. On your Mac, repeat the pairing command with the new code.

## Notifications don't appear

**Cause:** Notifications are off, the accessibility service isn't active, the TV is asleep, Lumen is visible, or no new qualifying state change occurs.

1. In Lumen, verify that **Settings > Agent notifications** is on.
2. On the remote, press **Home** to check that Lumen's accessibility service opens Lumen. If it doesn't, follow [Make Lumen the Home button](quickstart.md#make-lumen-the-home-button). This service is required for overlays even if you don't otherwise need Home remapping, and enabling it also intercepts Home.
3. In Lumen, verify that the [Agents pairing](set-up-agents.md#pair-the-tv) works.
4. On the TV, open another app and keep the TV awake.
5. In T3 Code, let a chat newly finish, fail, or request input, approval, or plan review. A brief card appears without taking remote focus.

The first snapshot doesn't generate notifications. Lumen shows updates on its Agents card while its home screen is visible. Granting notification-listener media access alone doesn't enable agent notifications.

## Collect diagnostic information

Logs and status responses can contain chat text, TV and Mac names, addresses, and T3 Code errors. Inspect and redact them before sharing. Never attach signing keys, passwords, pairing keys or codes, admin secrets, or T3 Code tokens.

1. In the source directory, read *`VERSION`* and note the commit:

   ```sh
   git rev-parse --short HEAD
   ```

2. On your Mac, collect the OS and compiler versions:

   ```sh
   sw_vers
   swiftc --version
   ```

3. Optional: On your Mac, inspect the helper's current status:

   ```sh
   lumen-agents status
   ```

4. Optional: On your Mac, read *`~/Library/Logs/lumen-agents.log`* locally for relevant errors.
5. Optional: On your computer, collect TV logs from the authorized device:

   ```sh
   adb -s DEVICE_ADDRESS logcat -d
   ```

6. In your report, include the redacted relevant excerpt and the details listed in [Report a bug](../CONTRIBUTING.md#report-a-bug). For a vulnerability, use [private reporting](../SECURITY.md#report-a-vulnerability).

## Command reference

### Repository scripts

Run these commands from the source directory. In this reference, *`DEVICE_ADDRESS`* is the TV's ADB address and port; *`PAIRING_CODE`* is the code on the TV; *`DEVICE_NAME_OR_ID`* is a value from the device list.

| Command | Behavior |
| --- | --- |
| `./build.sh` | Recreates `build/` and builds `lumen.apk`; creates a signing key only if `keys/lumen.jks` is absent. |
| `./build.sh DEVICE_ADDRESS` | Builds, connects, and installs with `adb install -r`. |
| `./build.sh grant DEVICE_ADDRESS` | Connects and grants notification-listener media access; doesn't build. |
| `./set-home.sh lumen DEVICE_ADDRESS` | Enables Lumen's accessibility service and removes Projectivy's service from the enabled list. |
| `./set-home.sh stock DEVICE_ADDRESS` | Removes Lumen's and Projectivy's accessibility services so Home returns to the stock launcher. |
| `./set-home.sh projectivy DEVICE_ADDRESS` | Requires installed Projectivy, enables its package and service, and removes Lumen's service. |
| `./mac/install.sh` | Builds, installs, and starts or restarts the Mac helper. |
| `./mac/install.sh uninstall` | Stops the helper and removes its binary, command link, and launchd file; retains token, pairings, helper ID, admin secret, and log. |
| `./mac/install.sh purge` | Also deletes the helper's data directory and log. See [removal consequences](uninstall.md#remove-lumen-agents) first. |

All *`set-home.sh`* modes preserve unrelated accessibility services and send a Home key event after the change.

For an installer preview, set *`LUMEN_DRY_RUN`* to a nonempty value. It runs checks and shows intended changes without installing, stopping, or removing the helper. An install preview stages a temporary launchd file; it doesn't compile the Swift helper. Use one operation at a time:

```sh
LUMEN_DRY_RUN=1 ./mac/install.sh
```

To preview an uninstall instead:

```sh
LUMEN_DRY_RUN=1 ./mac/install.sh uninstall
```

To preview a purge instead:

```sh
LUMEN_DRY_RUN=1 ./mac/install.sh purge
```

### Helper commands

| Command | Behavior |
| --- | --- |
| `lumen-agents serve` | Runs the server in the foreground; launchd normally runs this. Don't start a second copy on the installed port. |
| `lumen-agents pair PAIRING_CODE` | Approves a pending TV pairing. |
| `lumen-agents devices` | Lists paired TV names and IDs. |
| `lumen-agents unpair "DEVICE_NAME_OR_ID"` | Removes matching pairings on the Mac; doesn't clear TV data. |
| `lumen-agents unpair all` | Removes all TV pairings on this helper. |
| `lumen-agents status` | Prints JSON with `t3`, `threads`, and `chats` from the local helper. |

The CLI authenticates to the helper over loopback with a local admin secret. It isn't a remote administration interface.

### Environment variables

| Variable | Meaning |
| --- | --- |
| `ANDROID_HOME` | Android SDK directory for `build.sh`; defaults to `$HOME/Library/Android/sdk`. |
| `PATH` | Must include JDK tools and ADB for the TV scripts, and `~/.local/bin` for the installed helper command. |
| `JAVA_HOME` | Used in the quickstart to add JDK 17 to `PATH`; `build.sh` itself invokes `javac` and `keytool` from `PATH`. |
| `T3CODE_HOME` | T3 Code data directory; defaults to `~/.t3`. Set at helper install time to persist it in launchd. |
| `LUMEN_DRY_RUN` | Any nonempty value enables installer preview, including for `uninstall` and `purge`. |
| `LUMEN_AGENTS_PORT` | Helper test-instance TCP port; a valid nonzero UInt16 overrides 47837. Setting the variable disables Bonjour advertising. |
| `LUMEN_AGENTS_DIR` | Helper test-instance data directory. Setting the variable disables Bonjour advertising. |

The two test-instance variables belong to the helper binary, not the installer; the installer doesn't write them into launchd. The CLI and test server must use matching values. The installer requires *`HOME`* to match the account's actual home directory and rejects symlinked application-data, launchd, or log paths, and an unrelated command-link destination.

### File locations

| Location | Contents |
| --- | --- |
| `VERSION` | APK version name and code. Increase the code for each newer APK you install. |
| `build/`, `lumen.apk` | Generated Android build files and signed APK. |
| `keys/lumen.jks`, `keys/password` | Signing key and password; keep both for updates. |
| `~/Library/Application Support/Lumen Agents/` | Helper binary and private `t3-token`, `devices.json`, `id`, and `admin` files. See [Mac data](../PRIVACY.md#mac-data). |
| `~/.local/bin/lumen-agents` | Command symlink to the installed helper binary. |
| `~/Library/LaunchAgents/local.lumen.agents.plist` | Per-user launchd job. |
| `~/Library/Logs/lumen-agents.log` | Helper standard-error log; redact before sharing. |
| `~/.t3/bin/t3` | Default T3 Code CLI; custom installations use `T3CODE_HOME/bin/t3`. |
| `~/.t3/userdata/server-runtime.json` | Default T3 Code listener metadata read by the helper; under `T3CODE_HOME` when customized. |
| Lumen's private TV storage | Preferences, Agents pairing data, `watch-history.json`, and thumbnails in `art/`. |

## What's next

- [Report a reproducible bug](../CONTRIBUTING.md#report-a-bug).
- [Review security limitations](../SECURITY.md#known-limitations-and-accepted-risks).
- [Remove Lumen and its helper](uninstall.md#before-you-begin).
