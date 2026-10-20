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
- Every installed TV app shows up automatically, using its own banner.
- The background glows in the colour of whichever app is focused.
- **Inputs** lists the HDMI ports by device name (via HDMI-CEC) and says what's plugged in.
- Hold **OK** on any app to add/remove it from Favorites, move it, hide it, or open App info.
  Changes are saved on the TV.
- No internet access, no background work, no tracking. About 50 MB of memory (Projectivy: ~97 MB).

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
an accessibility service that only listens for the Home key and the stock home screen appearing.

```sh
./set-home.sh lumen        # Home opens Lumen
./set-home.sh projectivy   # re-enables Projectivy and makes it Home again
```

## Customise

- Starting favourites (first launch only): `DEFAULT_FAVORITES` in `HomeActivity.java`.
- Remove it completely: `adb uninstall local.tvhome` after switching back to Projectivy.
