# Security

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's private vulnerability reporting: on the repository's
**Security** tab, choose **Report a vulnerability**. Don't open a public issue. Include the Lumen version
(`VERSION`), the TV model and Android version, the T3 Code version if it involves Lumen Agents, and steps to
reproduce. Redact logs (see below).

## Supported versions

Only the latest version on the default branch is supported. There are no official binary releases.

## Scope and intended use

Lumen and Lumen Agents are meant for a trusted home network. Never forward port 47837 (or any Lumen port) from
your router to the internet, and don't run the helper on networks you don't trust.

Lumen Agents is an unofficial integration with T3 Code and is not affiliated with or endorsed by T3 Tools, Inc. It
uses an internal, undocumented interface that may change without notice.

## Design summary

- **Pairing.** The TV makes a random 16-character code (80 bits) and shows it; the code never goes over the
  network. The TV and the Mac agree a secret with ECDH on P-256, and the key is derived from that secret, the code
  and both public keys. Until you type the code on the Mac with `lumen-agents pair`, the Mac only answers
  "pending"; it then checks the TV's latest signed request against the code. A device in between sees the public
  keys but not the code, so it shouldn't be able to derive the key or guess the code in practice.
- **Requests and replies.** After pairing, each request (method, path, query and time) is signed with
  HMAC-SHA256. Times must be recent and only go up, so replayed requests are rejected. Replies are encrypted and
  authenticated with AES-GCM under the same key and bound to the request's time. The TV ignores anything that
  isn't sealed with its key. Keys are tagged with the pairing scheme; keys from an older scheme are dropped on both
  sides.
- **Pair again / unpair.** Pair again on the TV forgets its key and asks the Mac, with a request signed by that key,
  to drop it too. `lumen-agents unpair` removes keys on the Mac.
- **T3 Code token.** The helper uses its own read-only token (`orchestration:read`, 30 days, renewed on its own),
  issued with T3 Code's `t3` command and stored readable only by you.
- **T3 listener check.** Before sending the token, the helper checks that the process named in T3 Code's
  `server-runtime.json` is run by you, is a `T3 Code….app` binary and holds the listening socket on that port. This
  stops another local user from catching the token by taking the port while T3 Code is closed. It's a check on the
  process, not cryptographic proof that the other end is T3 Code.
- **Local commands.** `lumen-agents` talks to the helper on 127.0.0.1 with a random admin secret written to a file
  only you can read, and requests must be addressed to 127.0.0.1 or localhost, so other users and web pages
  shouldn't be able to use it.
- **Limits.** Connection counts are capped per source and in total, pairing requests are rate-limited per source,
  and text from T3 Code is cleaned of control characters and capped in length before it reaches logs or the TV.

## What isn't confidential

- The Bonjour advertisement (`_lumen-agents._tcp`), including your Mac's name and the helper's port.
- That a TV is talking to the Mac, and the timing and size of the traffic (for example, a reply arrives when a chat
  changes).
- The TV's model name, sent when pairing.
- Anything shown on the TV screen.

## Known limitations and accepted risks

- **Pairing flood.** Someone on the network, especially from many addresses, can keep the Mac's pending-pairing
  slots busy and delay new pairings. Already-paired TVs aren't affected.
- **Check-then-use race.** There's a short window between the T3 listener check and the request, in which another
  process could in principle take the port.
- **Loopback slots.** Other users on the same Mac can open connections to the helper on loopback and use up the
  slots reserved for the `lumen-agents` command (they can't authenticate, but they can make the command wait).
- **Replays after a restart.** The helper keeps each TV's latest request time in memory only, so after the helper
  restarts, someone who recorded the TV's signed requests from the last 10 minutes could send them again. Those are
  status requests, whose replies they can't read, and Pair again's request to drop the TV's key.
- **One key per pairing.** Requests and replies use the same key, not separate keys per direction.
- **Network debugging.** Leaving ADB network debugging on lets others on the network try to connect to the TV;
  turn it off after setup.
- **Notification-listener access** lets Lumen read notifications even though it ignores them (see PRIVACY.md).

## Review status

The pairing, the helper's server and the TV client went through an AI-assisted security review of their code
before release, and the issues it found were fixed. That was a scoped review, not an audit or a certification.
Treat Lumen as experimental software.

## Logs

`~/Library/Logs/lumen-agents.log` can include TV names, T3 Code error messages and short, truncated chat text.
Remove anything private before attaching it to a report.

## Removing everything

See [PRIVACY.md](PRIVACY.md) and the README: `./mac/install.sh purge` on the Mac, revoke the T3 Code session,
`./set-home.sh stock <tv>` and `adb uninstall local.tvhome` on the TV.
