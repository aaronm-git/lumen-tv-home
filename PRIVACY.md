# Privacy

Lumen has no analytics, tracking, ads or accounts, and sends nothing to its author or any other service.

## On the TV

- **Watch history.** To build Continue watching, Lumen records what you play: titles, episode, app, progress and
  a small thumbnail per show. It keeps the last 20 shows and shows the latest 10. It's kept in Lumen's private app
  storage on the TV, which other apps can't read. Clear it in Settings (**Clear watch history**), stop it by turning
  **Continue watching** off (nothing is recorded or updated while it's off, and what's already there is kept until
  you clear it), or remove it by clearing Lumen's storage or uninstalling Lumen. Music, casting and Live TV aren't
  recorded.
- **Favourites, hidden apps and settings** are kept in the same private storage.
- **Agents pairing.** Once you pair with a Mac, Lumen keeps its pairing key, the pairing code, a device id made from
  its key, the Mac's name, the helper's id and its address on your network, and whether pairing finished, in the
  same private storage. **Pair again** deletes the key, code and device id (and asks the Mac to drop its copy of
  the key); the Mac's name, id and address stay until the next pairing replaces them. Clearing Lumen's storage
  (Clear data under Apps › Lumen in the TV's Settings) or uninstalling Lumen removes all of it.
- **Notification-listener access.** Android only shares media sessions (what's playing) with apps that have
  notification-listener access, so Lumen asks for it. Lumen uses it only for media sessions and ignores the
  contents of notifications, but note that Android grants listeners broader access: an app with it could read
  your notifications. You can revoke it at any time (see the README); Now playing and Continue watching then stop.
- **Accessibility service.** Used to catch the Home button and to draw agent notifications. It can't read window
  contents, only receives window events from Google TV's home screen, and passes every key except Home straight
  on. Lumen does not read or collect anything on screen.

## Network

Lumen only uses the network for the optional Agents feature, and only to talk to the Lumen Agents helper on your
own Mac on the local network. With Agents and agent notifications off (the default for new
installs), Lumen makes no network connections. When either is on, and only while the TV is awake (and, for the card, while Lumen is showing), the TV
looks for the helper with Bonjour on the local network and keeps one request open to it. The TV sends its model
name (as Android reports it) when pairing so you can tell TVs apart on the Mac.

The chat titles, project names, model names and the last message of T3 Code chats that the helper sends are shown
on the TV screen, so anyone in the room can see them. They're kept in memory only, not saved on the TV.

## On the Mac (Lumen Agents)

The helper reads your T3 Code chats through T3 Code's local server with a read-only token and keeps only what it
needs to show them. It stores, readable only by your user account:

- `~/Library/Application Support/Lumen Agents/`
  - `t3-token`: its read-only T3 Code session token (30 days, renewed on its own).
  - `devices.json`: paired TVs (name and the key shared with each).
  - `id`: a random identifier for this helper, so the TV recognises it.
  - `admin`: a random secret for the `lumen-agents` command to talk to the helper.
  - `lumen-agents`: the helper itself.
- `~/Library/Logs/lumen-agents.log`: the helper's log. It can include TV names, error messages from T3 Code and
  short, truncated chat text. Redact it before sharing.

`./mac/install.sh purge` deletes all of it. Revoke the T3 Code session as well ("Lumen TV" in T3 Code's
connections, or `t3 auth session list` and `t3 auth session revoke`).

On your network the helper advertises itself over Bonjour with your Mac's name; see [SECURITY.md](SECURITY.md)
for what else is visible on the network.
