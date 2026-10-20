# Privacy

This page shows you how to review Lumen's data storage and permissions and remove stored information.

Lumen has no analytics, tracking, ads, or accounts. It sends nothing to its author or any other service.

## Before you begin

- Distinguish TV storage from Mac storage. Clearing one doesn't remove data from the other.
- Before granting access, review the notification-listener and accessibility permissions below.
- Before removing data, check the [removal procedure](docs/uninstall.md#before-you-begin) and its data-loss consequences.

## TV data and permissions

### Watch history

To build **Continue watching**, Lumen records titles, episode information, app, playback progress, and a small thumbnail per show. It retains the last 20 shows and displays the latest 10. Lumen excludes selected music, casting, and live-TV apps. Other apps that publish media sessions can appear in watch history.

History stays in Lumen's private app storage on the TV, which other apps can't read. The history file is *`watch-history.json`*, with thumbnails in *`art/`*.

Choose a control in Lumen's **Settings**:

- **Clear watch history** deletes recorded history. This control appears when history exists.
- **Continue watching** turns recording and progress updates on or off. Turning it off retains existing history until you clear it.

Clearing Lumen's app storage or uninstalling Lumen also removes history.

### Favorites and settings

Favorites, hidden apps, and settings stay in the same private TV storage.

### Agents pairing

After pairing, Lumen stores the pairing key, pairing code, a device ID derived from its key, the Mac's name, the helper ID, its local-network address, and whether pairing completed. This information stays in Lumen's private TV storage.

**Settings > Pair again** deletes the TV's key, code, and device ID and asks the Mac to remove its copy of the key. The saved Mac name, helper ID, and address remain until the next pairing replaces them.

Clearing Lumen's storage in the TV's app settings, or uninstalling Lumen, removes all TV-side pairing data. Look for **Clear data** under **Apps > Lumen** in the TV's system settings; menu nesting can vary by manufacturer.

### Notification-listener access

Android shares active media sessions only with apps that have notification-listener access. Lumen uses this access for **Now playing** and **Continue watching**, and ignores notification contents. Android nevertheless grants broader access: an app with this permission can read notifications.

You can revoke access at any time through the TV's notification-access controls, if available, or the command in [Allow media access](docs/quickstart.md#allow-media-access). **Now playing** and **Continue watching** then stop.

### Accessibility service

The accessibility service intercepts **Home** and draws agent notifications over other apps. It can't read window contents, receives window events only from the Google TV home screen, and passes every key except Home through. Lumen doesn't read or collect screen contents.

## Local-network data

Lumen uses the network only for the optional Agents feature, to communicate with the helper on your own Mac over your local network. With **Agents** and **Agent notifications** off, the default on new installs, Lumen makes no network connections.

When either feature is on, the TV discovers the helper with Bonjour and keeps one request open to it. These connections run only while the TV is awake; the card also requires Lumen to be visible. The TV sends its Android-reported model name during pairing so you can distinguish TVs on the Mac.

Chat titles, project names, model names, and the last message sent by the helper appear on the TV, where anyone in the room can see them. This chat information stays in memory and isn't saved on the TV.

## Mac data

The helper reads chats through T3 Code's local server with a read-only token and retains only what it needs to display them. It stores the following in your account, with the data readable only by you:

| Location | Data |
| --- | --- |
| `~/Library/Application Support/Lumen Agents/t3-token` | Read-only T3 Code session token, valid for 30 days and renewed automatically. |
| `~/Library/Application Support/Lumen Agents/devices.json` | Paired TV names and the key shared with each TV. |
| `~/Library/Application Support/Lumen Agents/id` | Random helper identifier so the TV recognizes the helper. |
| `~/Library/Application Support/Lumen Agents/admin` | Random secret for the local helper command. |
| `~/Library/Application Support/Lumen Agents/lumen-agents` | Installed helper binary. |
| `~/Library/Logs/lumen-agents.log` | Helper log, which can include TV names, T3 Code error messages, and short, truncated chat text. Redact it before sharing. |

The installer also creates *`~/Library/LaunchAgents/local.lumen.agents.plist`* and the command link *`~/.local/bin/lumen-agents`*.

The helper advertises your Mac's name over Bonjour. See [Information that isn't confidential](SECURITY.md#information-that-isnt-confidential) for other visible network information.

## Remove stored data

- On the TV, clearing Lumen's storage or uninstalling it removes all Lumen data there. Clearing only watch history leaves settings and pairing data intact.
- On the Mac, *`./mac/install.sh uninstall`* stops and removes the helper but keeps its token, pairings, helper ID, admin secret, and log.
- On the Mac, *`./mac/install.sh purge`* also deletes the entire Lumen Agents application-support directory and its log.
- Purging doesn't revoke T3 Code's session record. List and revoke the **Lumen TV** session with T3 Code's CLI.

Follow [Remove Lumen](docs/uninstall.md#before-you-begin) for ordered steps and the commands to revoke the session.

## What's next

- [Understand the security design and limitations](SECURITY.md#security-design).
- [Remove Lumen and revoke its T3 Code session](docs/uninstall.md#before-you-begin).
