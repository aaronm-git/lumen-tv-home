# Lumen

A home screen for the BRAVIA, built from scratch with Claude Code on 2026-10-19.

- Big clock, date and a greeting (holidays included).
- **Now playing** card (top right): artwork, title and app of whatever is playing or paused, with
  play/pause. OK opens the app's player. Hidden when nothing is playing.
- **Continue watching**: the last 10 shows and movies you played, with artwork, episode, app and a
  progress bar. Home lands on it, so OK goes straight back to what you just left (the exact player
  while the app still has it open, otherwise the app). Lumen builds this list itself as you watch:
  Android doesn't let non-Google apps read Google TV's own list. Music, casting and Live TV are left out.
- Two layouts (Settings): **Rows** (Continue watching, Favorites, Apps) or **Grid** (Continue watching,
  then every app five across, Apple TV style). The page scrolls and the clock slides away as you go down.
- **Agents** card (top right, under Now playing): your T3 Code chats on the Mac that are working, waiting for
  you (approval, input or a plan), done or failed, each with its model's logo (Claude, OpenAI, Grok, Gemini,
  Cursor, OpenCode). New ones slide in. OK on a chat shows what it last said. Hidden when nothing is going on;
  says "Mac offline" when the Mac can't be reached. Needs the Lumen Agents helper on the Mac (below).
- **Agent notifications**: when a chat finishes, fails or needs you while you're in another app, a small card
  shows over it for a few seconds (it never takes focus from the remote). Both can be switched off in Settings.
- Every installed TV app shows up automatically, using its own banner.
- The background glows in the colour of whichever app is focused.
- **Inputs** lists the HDMI ports by device name (via HDMI-CEC) and says what's plugged in.
- Hold **OK** on any app to add/remove it from Favorites, move it, hide it, or open App info.
  Changes are saved on the TV.
- No tracking. The only network use is talking to your Mac for the Agents card and notifications: one request
  the Mac holds open and answers when a chat changes, only while the home screen is showing or notifications
  are on and the TV is awake. About 50 MB of memory (Projectivy: ~97 MB).

Continue watching and Now playing need one permission, which `build.sh` grants over ADB:
notification-listener access. Android only shares media sessions with listeners; Lumen's ignores every
notification. Watch history (titles, progress and small thumbnails) stays on the TV in Lumen's private
storage, and can be cleared or switched off in Settings.

Plain Android framework code with no libraries, built without Gradle.

## Build and install

```sh
./build.sh 192.168.4.127:5555   # builds lumen.apk and installs it
```

Needs the Android SDK (build-tools 36.0.0, platform 34) and a JDK. The signing key is created on the first
build in `keys/`; keep it, because updates must be signed with the same key.

## Make it the Home button

Google TV ignores the normal default-home setting, so Lumen (like Projectivy) catches the Home button with
an accessibility service that only listens for the Home key and the stock home screen appearing. The same
service shows agent notifications over other apps.

```sh
./set-home.sh lumen        # Home opens Lumen
./set-home.sh projectivy   # re-enables Projectivy and makes it Home again
```

## Agents (T3 Code on the Mac)

`mac/LumenAgents.swift` is a small helper for the Mac (one Swift file, no dependencies). It reads T3 Code with
its own read-only token (`t3 auth session issue --scope orchestration:read`, listed as "Lumen TV" in T3 Code's
connections and revocable there), loads the thread list from `/api/orchestration/shell`, then follows the
server's shell stream so it only wakes when a chat changes. It shares a short summary on port 47837 (the TV's
request waits there until something changes, so updates are instant without polling) and
advertises it over Bonjour as `_lumen-agents._tcp`, so the TV finds the Mac even when its address changes. All
T3-specific code lives here: if a T3 Code update changes something, only the helper needs rebuilding.

```sh
./mac/install.sh                  # build it and run it at login (launchd: local.lumen.agents)
lumen-agents pair 123456          # approve the code the TV shows (first time only)
lumen-agents devices              # paired TVs;  lumen-agents unpair all  forgets them
lumen-agents status               # what the TV would see
./mac/install.sh uninstall
```

Pairing: the TV and the Mac agree a key (P-256 ECDH) and both derive the six-digit code from their public keys,
so approving the code on the Mac also proves nothing in between swapped keys. After that requests are signed
(HMAC-SHA256) and replies encrypted (AES-GCM) with that key, so other devices on the Wi-Fi can neither read the
status nor fake it. Token, pairings and logs live in
`~/Library/Application Support/Lumen Agents` and `~/Library/Logs/lumen-agents.log`.

## Customise

- Starting favourites (first launch only): `DEFAULT_FAVORITES` in `HomeActivity.java`.
- Provider logos in `res/drawable/brand_*.xml` are from [Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT).
- Remove it completely: `adb uninstall local.tvhome` after switching back to Projectivy.
