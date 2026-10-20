# Lumen

Lumen is a lightweight, experimental home-screen launcher for televisions running Android, with local watch
history and optional coding-agent status.

**Status:** experimental, version 0.1.0. It's a personal project tested on one TV (below). It is only
distributed as source: build it yourself. There's no official APK yet, and its package name (`local.tvhome`) will
change before there is one, so a later official build won't install over a self-built one.

## Screenshots

Coming soon: `docs/screenshots/home.png` (home screen), `agents-card.png` (Agents card),
`notification.png` (agent notification over another app) and `pairing.png` (pairing code).

## Features

- Big clock, date and a greeting (holidays included).
- **Now playing** card: artwork, title and app of whatever is playing or paused, with play/pause. OK opens the
  app's player. Hidden when nothing is playing.
- **Continue watching**: the last 10 shows and movies you played, with artwork, episode, app and a progress bar.
  Home lands on it, so OK goes straight back to what you just left. Lumen builds this list itself as you watch
  (Android doesn't let other apps read Google TV's own list). Music, casting and Live TV are left out.
- Two layouts (Settings): **Rows** (Continue watching, Favorites, Apps) or **Grid** (every app five across).
- Every installed TV app shows up automatically, using its own banner. Hold **OK** on an app to add it to or
  remove it from Favorites, move it, hide it, or open App info.
- **Inputs** lists the HDMI ports by device name (via HDMI-CEC) and says what's plugged in.
- The background takes on the colour of whichever app is focused.
- Optional **Agents** card and **agent notifications** for T3 Code chats on a Mac (off until you turn them on;
  see [Agents](#agents-optional)).
- No analytics or tracking. About 50 MB of memory on the tested TV.
- Plain Android framework code with no libraries, built without Gradle.

## Tested devices and requirements

- Tested on one Sony BRAVIA with Google TV, Android 12 (API 31). Lumen needs Android 9 (API 28) or later and
  targets API 31. Other TVs and other Android TV builds are untested; expect rough edges.
- Some parts are Sony or US specific: the **Live TV** entry in Inputs only appears if Sony's Live TV app is
  installed, and the starting favourites are US streaming apps (any that aren't installed are skipped; change
  `DEFAULT_FAVORITES` in `HomeActivity.java`). Catching the Home button is Google TV specific (below).
- To build: the Android SDK with build-tools 36.0.0, platform 34 and platform-tools (ADB), and JDK 17 or later.
  `build.sh` looks for the SDK in `$ANDROID_HOME`, or `~/Library/Android/sdk`, and also uses `openssl`, `zip` and
  the JDK's `keytool`.
- For Agents: a Mac with macOS, the Xcode command-line tools (for `swiftc`) and T3 Code.

## Build and install

1. On the TV, turn on Developer options, then **network debugging** (or USB debugging), and note the address it
   shows, such as `192.0.2.10:5555` (the example address used below).
2. Build and install:

   ```sh
   ./build.sh                     # builds lumen.apk
   ./build.sh 192.0.2.10:5555     # builds it and installs it on that TV (accept the prompt on the TV)
   ./build.sh grant 192.0.2.10:5555   # grants the one permission (see Permissions)
   ```

The signing key is created on the first build in `keys/` (ignored by git). Keep it: updates must be signed with
the same key. The version is in `VERSION`.

## Permissions

| What | Why | How |
| --- | --- | --- |
| Notification-listener access | Android only shares media sessions (what's playing) with notification listeners. Lumen uses it for Now playing and Continue watching. Lumen ignores notifications themselves, but Android lets any listener read them. | `./build.sh grant <tv>` (prints this first). Revoke in the TV's Settings, or `adb shell cmd notification disallow_listener local.tvhome/local.tvhome.MediaAccess`. |
| Accessibility service | Catches the Home button (and Google TV's home screen appearing) so Home opens Lumen, and draws agent notifications over other apps. It sees remote key presses but passes all except Home straight on, can't read window contents, and only receives window events from Google TV's home screen. | `./set-home.sh lumen <tv>` (below). |
| Internet | Only to reach the Lumen Agents helper on your own Mac over the home network, when Agents are on. | Granted at install. |

Lumen doesn't ask for anything else.

## Make it the Home button

Google TV ignores the normal default-home setting, so Lumen (like Projectivy) catches the Home button with an
accessibility service.

```sh
./set-home.sh lumen 192.0.2.10:5555        # Home opens Lumen
./set-home.sh stock 192.0.2.10:5555        # undo: Home opens the stock Google TV home again
./set-home.sh projectivy 192.0.2.10:5555   # optional: if you use Projectivy, make it Home instead
```

The script only adds or removes Lumen's (and Projectivy's) service; any other accessibility services you have on
stay as they are. When you're done, turn **network debugging off** again in the TV's Developer options: anyone on
your network who can get the TV to accept a connection could otherwise use it.

## Agents (optional)

> Lumen Agents is an unofficial integration with T3 Code and is not affiliated with or endorsed by T3 Tools, Inc.
> It uses an internal, undocumented interface that may change without notice. Tested with T3 Code (Beta) 0.1.0
> (`x-t3-orchestration-protocol: 2`).

The Agents card shows your T3 Code chats on a Mac that are working, waiting for you (approval, input or a plan),
done or failed, each with its model's logo. OK on a chat shows what it last said. Agent notifications show a small
card over other apps for a few seconds when a chat finishes, fails or needs you (it never takes focus from the
remote). Chat titles, project names and the last message are shown on the TV, so anyone in the room can see them.
Both are off until you turn them on in Lumen's Settings.

`mac/LumenAgents.swift` is a small helper for the Mac (one Swift file, no dependencies). It reads T3 Code with its
own read-only token (`t3 auth session issue --scope orchestration:read`, listed as "Lumen TV" in T3 Code's
connections; it lasts 30 days and is renewed on its own) and shares a short summary on port 47837, advertised over
Bonjour as `_lumen-agents._tcp` so the TV finds it when its address changes. The TV's request waits there until a
chat changes, so updates are instant without polling. All T3-specific code lives in the helper.

1. Install the helper (builds it and runs it at login with launchd as `local.lumen.agents`):

   ```sh
   ./mac/install.sh
   ```

2. In Lumen's Settings, turn on **Agents**. Once the TV finds the Mac, the card shows a 16-character code.
3. Approve it on the Mac (first time only; any case, dashes optional):

   ```sh
   lumen-agents pair K7QM-9XRT-4HNP-2WVD
   ```

4. Optionally turn on **Agent notifications** in Settings.

Other commands: `lumen-agents devices` (paired TVs), `lumen-agents unpair all` (or a name), `lumen-agents status`
(what the TV would see). To pair with a new key, pick **Pair again** in Lumen's Settings; it also asks the Mac to
drop the old key (if the Mac can't be reached, use `lumen-agents unpair`).

- **`lumen-agents` command:** installed in `~/.local/bin`; add that to your `PATH` if your shell doesn't find it.
- **T3 Code location:** the helper reads `~/.t3`, or `$T3CODE_HOME`. launchd doesn't see your shell's variables,
  so if you use a different location, install with it set: `T3CODE_HOME=/path/to/t3 ./mac/install.sh` writes it
  into the launchd job.
- **Which T3 Code it trusts:** before sending its token, the helper checks that the process named in T3's
  `server-runtime.json` is run by you, is an app's own binary (`<name>.app/Contents/MacOS/<name>`, where the
  name starts with "T3 Code", so the regular and Beta apps wherever they're installed) and holds the listening socket on that port. Other ways of
  running T3 Code's server (such as from source) aren't accepted.
- **Removing it:** `./mac/install.sh uninstall` stops and removes the helper but keeps its token, pairings and
  log. `./mac/install.sh purge` also deletes `~/Library/Application Support/Lumen Agents` and
  `~/Library/Logs/lumen-agents.log`. Either way, revoke its T3 Code session ("Lumen TV" in T3 Code's
  connections, or `t3 auth session list` and `t3 auth session revoke`).

## Privacy and security

Watch history stays on the TV, there's no tracking, and the only network use is to your own Mac when Agents are
on. Details: [PRIVACY.md](PRIVACY.md). How pairing and encryption work, what they don't protect, and how to report
a vulnerability: [SECURITY.md](SECURITY.md).

## Uninstall and recovery

1. `./set-home.sh stock <tv>` so Home opens the stock home screen (or `projectivy`).
2. `adb -s <tv> uninstall local.tvhome`.
3. If you used Agents: `./mac/install.sh purge` on the Mac and revoke the T3 Code session (above).
4. Turn off network debugging on the TV.

If Lumen misbehaves and Home keeps opening it, you can also turn its service off on the TV in Settings ›
Accessibility (Lumen), or open the TV's Settings from Lumen's Settings sheet.

## Troubleshooting

- **"Mac offline":** the Mac is asleep, on another network, or the helper isn't running. Check
  `launchctl print gui/$(id -u)/local.lumen.agents` and the log.
- **No chats, or "T3 Code isn't running":** open T3 Code. `lumen-agents status` shows what the helper sees.
- **Stuck on a code, or a new Mac:** pick **Pair again** in Lumen's Settings and approve the new code; on the Mac,
  `lumen-agents unpair all` forgets old TVs.
- **Logs:** `~/Library/Logs/lumen-agents.log`. They can include TV names, error messages and short, truncated
  chat text, so look them over and redact them before sharing.
- **Now playing or Continue watching says "waiting for permission":** run `./build.sh grant <tv>`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and licenses

Lumen is released under the [MIT License](LICENSE), Copyright (c) 2026 Aaron Molina. The model logos in
`res/drawable/brand_*.xml` are adapted from [Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT, Copyright (c)
2023 LobeHub); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The same notices are in Lumen's Settings ›
Licenses & notices.

## Trademarks

Product names and logos, including Anthropic and Claude, OpenAI, xAI and Grok, Google, Gemini, Google TV, Android
and YouTube, Cursor and Anysphere, OpenCode, T3 Code, Sony and BRAVIA, Netflix, and others mentioned here, belong to
their respective owners. They're used only to identify the model or app. Lumen isn't affiliated with or endorsed
by any of them.
