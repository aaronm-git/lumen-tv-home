# Set up Lumen Agents

This page shows you how to install the Mac helper, pair your TV, and display T3 Code chat status in Lumen.

Lumen Agents is an unofficial integration with T3 Code and is not affiliated with or endorsed by T3 Tools, Inc. It uses an internal, undocumented interface that may change without notice.

The card shows chats that are **Working**, **Waiting for you**, **Done**, or **Failed**. It can show chat titles, project names, model names, messages, and your Mac's name. Anyone in the room can see this information. Press **OK** on a chat to read its available message; reply in T3 Code on your Mac or phone.

The **Agents** card and **Agent notifications** are off by default on new installs. TVs with an existing pairing from before that default keep them on.

## Before you begin

You need:

- A Mac with Xcode Command Line Tools, including *`swiftc`*. The helper uses Foundation, Network, and CryptoKit without third-party dependencies.
- The T3 Code app installed and run at least once. The integration is tested with T3 Code (Beta) 0.1.0, orchestration protocol 2. Source-run servers aren't accepted by the helper's process check.
- T3 Code's *`t3`* executable at *`~/.t3/bin/t3`*, or *`bin/t3`* inside your custom *`T3CODE_HOME`* directory.
- Your Mac and TV on the same trusted local network. Guest or isolated Wi-Fi can prevent discovery and connections. Don't forward helper port 47837 from your router to the internet.
- [Lumen installed on your TV](quickstart.md#before-you-begin) and the source directory on your Mac.

The verified OS and compiler versions are macOS 27.0 (build 26A428) and Apple Swift 6.4 (swiftlang-6.4.0.34.1), targeting arm64. These versions come from *`sw_vers`* and *`swiftc --version`* and aren't minimum supported versions. The installer compiles in Swift 5 language mode.

1. On the Mac, verify the OS and compiler:

   ```sh
   sw_vers
   swiftc --version
   ```

   If *`swiftc`* isn't available, install Xcode Command Line Tools before continuing.

2. On the Mac, verify T3 Code's CLI without running it:

   ```sh
   test -x "$HOME/.t3/bin/t3"
   ```

   This command prints nothing on success. If you use a custom directory, verify *`T3CODE_HOME/bin/t3`* instead and follow [Use a custom T3 Code directory](#optional-use-a-custom-t3-code-directory) when installing.

3. On the Mac, open T3 Code so its local server is running.

## Install the helper

1. In the Lumen source directory on your Mac, install the helper:

   ```sh
   ./mac/install.sh
   ```

   The script builds the helper, installs it for your account, and starts the launchd job *`local.lumen.agents`*. The job also starts at login.

2. In your Mac's shell, add the installed command directory to *`PATH`*:

   ```sh
   export PATH="$HOME/.local/bin:$PATH"
   ```

   Add this line to your shell's startup file if you want it to persist.

3. In the same shell, allow the helper to read T3 Code:

   ```sh
   lumen-agents authorize
   ```

   This runs T3 Code's own *`t3 auth session issue`* once to create a read-only session labeled **Lumen TV**. The helper never creates a session by itself, so until you run this command the TV shows **T3 Code access needed**. Run it again whenever T3 Code stops accepting the session; see [Revoke or allow T3 Code access](#revoke-or-allow-t3-code-access).

4. In the same shell, verify that the helper can read T3 Code:

   ```sh
   lumen-agents status
   ```

   In the JSON response, *`t3`* must be *`ok`*. An empty *`chats`* list is valid when no chats need to appear. See [T3 Code isn't running or T3 Code access needed](troubleshooting.md#t3-code-isnt-running-or-t3-code-access-needed) for other states.

## Turn on Agents on the TV

1. In Lumen, select **Settings > Agents** to turn the card on.
2. On the remote, press **Back** to return to Lumen's home screen. Once discovery completes, the card shows the Mac's name and a pairing code.

## Pair the TV

1. On the TV's Agents card, read the current 16-character code, shown in four groups separated by dashes.
2. On your Mac, approve that code:

   ```sh
   lumen-agents pair PAIRING_CODE
   ```

   Replace *`PAIRING_CODE`* with the code currently displayed on your TV. Letter case doesn't matter, and dashes are optional. Keep Lumen open while pairing.

3. On the TV, verify that the pairing code disappears. The card shows eligible chats, or a T3 Code status message if the helper can't read T3 Code. When T3 Code is connected but no chats qualify, the card hides.

Working chats, requests for approval or input, and unseen plans qualify. Unseen completed or failed chats qualify for up to 24 hours if they aren't snoozed. The card shows at most three chat rows and a count of additional chats; it isn't a complete T3 Code chat history.

## Optional: Turn on agent notifications

Notifications show a small card over another app for a few seconds when a chat finishes, fails, or needs you. They don't take remote focus. The TV must be awake, and notifications don't repeat the initial status snapshot or appear over Lumen's own home screen.

The accessibility service from [Make Lumen the Home button](quickstart.md#make-lumen-the-home-button) is required even if you skipped Home remapping. Enabling that service also makes **Home** open Lumen; the current code has no notification-only service mode. Notification-listener media access is a different permission and doesn't enable these overlays.

1. On the TV, verify that Lumen's accessibility service is enabled by pressing **Home**. Lumen opens. If it doesn't, complete [Make Lumen the Home button](quickstart.md#make-lumen-the-home-button).
2. In Lumen, select **Settings > Agent notifications** to turn notifications on.
3. On the TV, open another app.
4. In T3 Code on your Mac, let a chat change to a finished, failed, or waiting state. A notification appears over the TV app.

## Optional: Use a custom T3 Code directory

Use this procedure instead of a default installation, or to update an existing installation. Verify that the custom directory contains *`bin/t3`* and belongs to the T3 Code app you run.

1. In the Lumen source directory, install with the custom location:

   ```sh
   T3CODE_HOME="T3_CODE_DIRECTORY" ./mac/install.sh
   ```

   Replace *`T3_CODE_DIRECTORY`* with the absolute T3 Code data-directory path. The installer writes *`T3CODE_HOME`* into the launchd job because launchd doesn't inherit your shell's variables. Set it on every reinstall that must retain the custom location.

2. If this is the first installation, or the TV shows **T3 Code access needed**, allow the helper to read T3 Code. The helper runs that directory's *`bin/t3`*:

   ```sh
   lumen-agents authorize
   ```

3. In your Mac's shell, verify the reinstalled helper:

   ```sh
   lumen-agents status
   ```

## Replace a pairing

**Pair again** deletes the TV's key and asks the Mac to delete its copy. If the Mac is unreachable, remove the old entry on the Mac separately.

1. In Lumen, select **Settings > Pair again** with **Agents** on. Lumen creates a new code when it reaches a helper.
2. On your Mac, list the stored TV pairings:

   ```sh
   lumen-agents devices
   ```

3. Optional: On your Mac, remove an old pairing that remains in the list:

   ```sh
   lumen-agents unpair "DEVICE_NAME_OR_ID"
   ```

   Replace *`DEVICE_NAME_OR_ID`* with a name or ID from the device list. An ID selects one TV; a shared name can match more than one. The removed TV gets nothing more at once, including a request it's waiting on; other TVs keep working. If the helper can't save the change, the command fails and says so: the key would return when the helper restarts, so fix the permissions of *`~/Library/Application Support/Lumen Agents`* and run it again.

4. On your Mac, run the [pairing procedure](#pair-the-tv) with the new code.

## Revoke or allow T3 Code access

Revoking the **Lumen TV** session cuts off chat data to every paired TV. To keep one TV from seeing chats while the others still do, [unpair](#replace-a-pairing) that TV instead.

1. To revoke, in T3 Code, revoke **Lumen TV** in its list of connected clients, or follow [Revoke the T3 Code session](uninstall.md#revoke-the-t3-code-session).

   T3 Code closes the helper's update stream right away. Within a few seconds the helper drops the chats it holds, tells waiting TVs, deletes the token, and records the rejection in *`t3-blocked`*. The TVs show **T3 Code access needed**. The helper doesn't retry or create a new session, even after a restart.

2. To allow access again, on your Mac, run:

   ```sh
   lumen-agents authorize
   ```

T3 Code gives the same answer for a revoked session as for an expired one, so the helper handles both the same way. Sessions last a year, so you run *`lumen-agents authorize`* about once a year. A session from an earlier version of the helper keeps its 30-day lifetime: after you update the helper, run *`lumen-agents authorize`* once to get one that lasts a year. A short drop, such as T3 Code restarting, isn't a rejection: the TV shows **T3 Code isn't running** with no chats, and the helper reconnects with the same session.

## How it works

The helper advertises *`_lumen-agents._tcp`* over Bonjour, normally on port 47837. Lumen discovers it and follows its address changes. The TV keeps a long-poll request open; the helper replies when chat status changes or the wait expires. The helper follows T3 Code's update stream rather than repeatedly fetching the chat list.

The helper uses a read-only *`orchestration:read`* T3 Code token, labeled **Lumen TV**, with a one-year lifetime. Only *`lumen-agents authorize`* creates one. Before sending the token to T3 Code's local server, it checks that the process in *`userdata/server-runtime.json`* runs as your user, is an app binary whose name starts with **T3 Code**, and owns the listening socket. This accepts regular and Beta app bundles wherever installed; it doesn't cryptographically authenticate T3 Code.

The TV generates a random pairing code. The code isn't sent between the TV and the Mac. The *`lumen-agents`* command submits it to the helper over the Mac's loopback interface at 127.0.0.1. The TV and Mac combine the code with a P-256 ECDH shared secret and both public keys to derive a pairing key. Paired requests are signed with HMAC-SHA256; replies are encrypted and authenticated with AES-GCM and bound to the request time.

Bonjour exposes your Mac's name and helper port. The TV's model name, the existence, timing, and size of network traffic, and anything visible on the TV aren't confidential. For pairing floods, replay after a helper restart, local connection exhaustion, the listener-check race, shared directional keys, and other limitations, read [Known limitations and accepted risks](../SECURITY.md#known-limitations-and-accepted-risks).

## What's next

- [Diagnose pairing and notification problems](troubleshooting.md#mac-offline).
- [Look up commands, variables, and file locations](troubleshooting.md#command-reference).
- [Review what the helper stores](../PRIVACY.md#mac-data).
- [Remove the helper and revoke its session](uninstall.md#remove-lumen-agents).
