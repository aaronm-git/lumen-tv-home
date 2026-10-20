# Security

This page shows you how to assess Lumen's security boundaries and report a vulnerability privately.

## Before you begin

- Use Lumen and Lumen Agents only on a trusted home network. Don't run the helper on an untrusted network or forward port 47837, or any Lumen port, from your router to the internet.
- For a report, identify your Lumen version in `VERSION`, TV model, and Android version. Include your T3 Code version if the issue involves Agents.
- Review and redact logs before sharing them. Don't include tokens, pairing keys, admin secrets, or signing credentials.

Lumen Agents is an unofficial integration with T3 Code and is not affiliated with or endorsed by T3 Tools, Inc. It uses an internal, undocumented interface that may change without notice.

## Report a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting. Don't open a public issue.

1. On the repository's GitHub page, select **Security**.
2. On the **Security** tab, select **Report a vulnerability**.
3. In the private report, include the versions and device details listed above, steps to reproduce, and redacted relevant logs.

## Supported versions

Only the latest version on the default branch is supported. There are no official binary releases.

## Security design

### Pairing

The TV generates a random 16-character code (80 bits) and displays it. The code never travels over the network. The TV and Mac agree on a secret using P-256 ECDH and derive the pairing key from the secret, the code, and both public keys.

Until you enter the code on the Mac with *`lumen-agents pair`*, the Mac answers signed status requests with *`pending`*. Entering the code lets the Mac verify the TV's latest signed request. A device between the TV and Mac sees the public keys but not the code, so it shouldn't be able to derive the key or guess the code in practice.

### Requests and replies

After pairing, requests sign the method, path, query, and time with HMAC-SHA256. Request times must be recent and increase, which rejects replays within one helper process lifetime. See [Replays after a restart](#known-limitations-and-accepted-risks) for the restart limitation.

Replies use AES-GCM encryption and authentication with the same pairing key and bind to the request's time. The TV ignores replies that aren't sealed with its key. Pairing keys carry a scheme version; both sides drop keys from older schemes.

### Pairing removal

**Settings > Pair again** on the TV forgets its key and sends a request signed with that key asking the Mac to remove its copy. The Mac command *`lumen-agents unpair`* removes Mac-side pairing keys. Follow [Replace a pairing](docs/set-up-agents.md#replace-a-pairing) for the procedure.

### T3 Code token and listener check

The helper uses its own read-only T3 Code token with scope *`orchestration:read`*. T3 Code's *`t3`* command issues the token for 30 days; the helper renews it automatically and stores it readable only by your user account.

Before sending the token, the helper checks that the process identified by T3 Code's *`userdata/server-runtime.json`* runs as your user, is a binary inside an app bundle whose name starts with **T3 Code**, and owns the listening socket on the stated port. This prevents another local user from taking the port while T3 Code is closed and receiving the token. The check identifies a process; it isn't cryptographic proof that the peer is T3 Code.

### Local commands

The *`lumen-agents`* command connects to the helper at 127.0.0.1 with a random admin secret stored in a file only you can read. Requests must address 127.0.0.1 or localhost. These checks are intended to prevent other users and web pages from administering the helper.

### Resource limits

The helper caps connection counts per source and in total, rate-limits pairing requests per source, and removes control characters from T3 Code text. It also caps text length before the text reaches logs or the TV.

## Information that isn't confidential

- The Bonjour advertisement, *`_lumen-agents._tcp`*, including your Mac's name and the helper's port.
- The fact that a TV communicates with the Mac, and traffic timing and size. For example, a reply arrives when a chat changes.
- The TV's model name, sent during pairing.
- Anything displayed on the TV screen.

## Known limitations and accepted risks

- **Pairing flood:** Someone on the network, especially using many addresses, can keep pending-pairing slots busy and delay new pairings. Already-paired TVs aren't affected.
- **Check-then-use race:** Another process could, in principle, take the T3 Code port during the short interval between the listener check and the request.
- **Loopback slots:** Other users on the Mac can consume connection slots reserved for the local command. They can't authenticate, but they can make the command wait.
- **Replays after a restart:** Each TV's latest request time is stored only in memory. After a helper restart, someone who recorded signed requests from the last 10 minutes could replay them. Replayable operations are status requests, whose replies the recorder can't read, and the request from **Pair again** to drop the TV's key.
- **One key per pairing:** Requests and replies use the same key rather than separate keys for each direction.
- **Network debugging:** Leaving ADB network debugging on lets other devices on the network try to connect to the TV. Turn it off after setup.
- **Notification-listener access:** Android grants Lumen the ability to read notifications, although Lumen ignores their contents. See [TV data and permissions](PRIVACY.md#tv-data-and-permissions).

## Review status

The pairing, helper server, and TV client underwent an AI-assisted code security review before release, and the issues found in that review were fixed. This was a scoped review, not an audit or certification. Treat Lumen as experimental software.

## Diagnostic logs

The helper log at *`~/Library/Logs/lumen-agents.log`* can include TV names, T3 Code errors, and short, truncated chat text. Remove private information before attaching an excerpt to a report. See [Collect diagnostic information](docs/troubleshooting.md#collect-diagnostic-information).

## Remove stored data and access

To remove everything, restore the stock Home button, uninstall the TV app, purge the Mac helper's data and log, and revoke its T3 Code session. Follow [Remove Lumen](docs/uninstall.md#before-you-begin) and review [Data removal](PRIVACY.md#remove-stored-data) for the consequences.

## What's next

- [Review privacy and storage details](PRIVACY.md#tv-data-and-permissions).
- [Report a vulnerability privately](#report-a-vulnerability).
