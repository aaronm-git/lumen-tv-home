# Contributing

Thanks for your interest! Lumen is a small personal project, so changes are reviewed as time allows.

## Building

See the README: `./build.sh` builds `lumen.apk` (Android SDK build-tools 36.0.0, platform 34, JDK 17), and
`./build.sh <tv-ip:port>` installs it. The Mac helper builds with
`swiftc -O -swift-version 5 -o /tmp/lumen-agents mac/LumenAgents.swift`, or `./mac/install.sh`.

## Style

- No libraries and no Gradle: plain Java on the Android framework, and Foundation, Network and CryptoKit for the
  Swift helper.
- Keep it light: small memory use, no polling where a held request will do, no extra permissions.
- Match the surrounding code: short comments that say why, plain names, and the same layout.
- Anything T3 Code specific belongs in `mac/LumenAgents.swift`, not in the TV app.

## Reporting bugs

Open an issue with:

- the TV model and Android version (Settings › Device preferences › About);
- the Lumen version (`VERSION`) or commit;
- for Agents, the macOS and T3 Code versions;
- what you did, what you expected and what happened.

Logs help, but `~/Library/Logs/lumen-agents.log` and `adb logcat` can contain chat text, TV and Mac names and
addresses: redact them first.

## Security issues

Please don't open public issues for vulnerabilities; see [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
