# Contribute to Lumen

This page shows you how to build Lumen for development and report changes or bugs with useful diagnostic information.

Lumen is a small personal project. Changes are reviewed as time allows.

## Before you begin

- For the TV app, complete the [quickstart prerequisites](docs/quickstart.md#before-you-begin): Android SDK build-tools 36.0.0, platform 34, platform-tools, and JDK 17.
- For the Mac helper, verify the [macOS and Swift prerequisites](docs/set-up-agents.md#before-you-begin).
- Read the code conventions below and match the surrounding implementation.
- Preserve your signing key if you install over an existing build.

## Build the TV app

1. In the source directory, build the APK:

   ```sh
   ./build.sh
   ```

   The script writes *`lumen.apk`*.

2. Optional: After [connecting to your TV](docs/quickstart.md#turn-on-network-debugging-on-the-tv-and-connect), build and install in one command:

   ```sh
   ./build.sh DEVICE_ADDRESS
   ```

   Replace *`DEVICE_ADDRESS`* with the TV's IP address and ADB port. For separate build and install steps, see [Build and install Lumen](docs/quickstart.md#build-and-install-lumen).

## Build the Mac helper

1. In the source directory, compile a development binary:

   ```sh
   swiftc -O -swift-version 5 -o /tmp/lumen-agents mac/LumenAgents.swift
   ```

   This builds the helper without installing or starting it. For test-instance variables, see the [environment-variable reference](docs/troubleshooting.md#environment-variables).

   Alternatively, to build, install, and start the per-user helper, follow [Install the helper](docs/set-up-agents.md#install-the-helper), which uses:

   ```sh
   ./mac/install.sh
   ```

2. In the source directory, run the helper's offline tests:

   ```sh
   ./mac/tests/run.sh
   ```

   The script builds the helper, a fake T3 Code server, and the tests in a temporary directory, then runs them over loopback. The test helper and the fake server listen on 127.0.0.1 only, and the tests check that neither accepts connections on the Mac's network addresses. The tests cover access rejection and authorization, reconnecting after a drop, and pairing removal, including removals that can't be saved. They don't use your installed helper, its files, T3 Code, or a TV, and they take under a minute.

3. In the source directory, run the TV side's offline tests:

   ```sh
   ./tests/android/run.sh
   ```

   The script compiles *`AgentStatus.java`* with small stand-ins for Android's classes and runs it on your computer's JDK against a fake helper on 127.0.0.1. The tests cover replies that arrive after the TV stopped listening or after **Pair again**, and clearing chats on the first failed request. They don't need the Android SDK, a TV, an emulator, or ADB, and they don't cover the views. Build the app with *`./build.sh`* to compile everything.

## Code conventions

- Use plain Java with the Android framework for the TV app, without libraries or Gradle. Use Foundation, Network, and CryptoKit for the Swift helper.
- Keep memory use small. Prefer a held request to polling, and don't add extra permissions.
- Write self-descriptive code with clear names and structure. Do not add code comments; rewrite unclear code instead. Keep explanations and license notices in documentation or license files.
- Keep all T3 Code-specific code in *`mac/LumenAgents.swift`*, outside the TV app.

## Report a bug

Logs from *`~/Library/Logs/lumen-agents.log`* and *`adb logcat`* can contain chat text, TV and Mac names, and addresses. Inspect and redact them before attaching anything. Use [Collect diagnostic information](docs/troubleshooting.md#collect-diagnostic-information) for commands.

1. On the TV, note the model and Android version from its system settings. Depending on your TV, these can appear under **Settings > Device preferences > About**; manufacturer paths vary.
2. In the source directory, note the Lumen version from *`VERSION`* or the commit ID.
3. For an Agents issue, note your macOS and T3 Code versions.
4. On the repository's issue page, open an issue with these details, what you did, what you expected, what happened, and relevant redacted logs.

## Security reports

Report vulnerabilities privately rather than opening a public issue. Follow [Report a vulnerability](SECURITY.md#report-a-vulnerability).

## Contribution license

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

## What's next

- [Troubleshoot a problem before reporting it](docs/troubleshooting.md#before-you-begin).
- [Review security limitations before changing pairing or networking](SECURITY.md#known-limitations-and-accepted-risks).
