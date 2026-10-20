# Set up Lumen with an AI coding agent

This page shows you how to hand Lumen's setup to an AI coding agent, such as Claude Code, Codex, Cursor, or Grok, while you stay in control of every change to your TV and Mac.

The agent builds Lumen, installs it, and walks you through the steps that need your hands: turning on network debugging on the TV and reading a pairing code from the screen. It doesn't replace [the written guides](quickstart.md#before-you-begin); it follows them.

## Before you begin

You need:

- An AI coding agent that can run shell commands on your computer and read files.
- The requirements in the [quickstart](quickstart.md#before-you-begin). The agent can check for missing tools, but you approve any installation.
- A Mac, if you want the optional [Agents card and notifications](set-up-agents.md#before-you-begin).

## Give the agent the prompt

1. On your computer, open a terminal in an empty directory that you're comfortable letting the agent work in.
2. Start your agent in that directory.
3. Paste the following prompt:

```text
Set up Lumen, an open-source Android TV home screen, for me. The repository
is https://github.com/aaronm-git/lumen-tv-home.

Follow the repository's own docs, and treat them as the source of truth:
docs/quickstart.md first, then docs/set-up-agents.md only if I say I want the
Agents card and notifications. If a doc and these instructions disagree, stop
and ask me.

Start by cloning the repository and reading README.md, PRIVACY.md,
SECURITY.md, docs/quickstart.md, and docs/set-up-agents.md. Then summarize in
a few sentences what you will change on my computer, my TV, and (if I choose
Agents) my Mac. Wait for me to approve before changing anything.

Rules:
- Ask before every step that installs software, changes system or TV
  settings, enables an accessibility or notification-listener permission, or
  installs a launchd job. Say what it does and how to undo it (docs/uninstall.md).
- Run only the commands the docs list. Don't use sudo. Don't disable
  security features, and don't forward any port from my router.
- Ask me for my TV's IP address and ADB port. Don't scan my network for
  devices.
- Never commit, print, upload, or share anything in keys/. It holds my signing
  key. Tell me to back it up after the first build.
- You can't see my TV. When a step needs the TV (developer options, the ADB
  authorization prompt, the Agents pairing code), tell me exactly what to do
  and wait for me to confirm.
- Use only these tools from the repository: ./build.sh, ./set-home.sh, adb for
  my TV, and ./mac/install.sh with the lumen-agents command for Agents.
- Don't launch other apps on my TV or change settings that the docs don't mention.
- After each phase, run the verification step from the docs and show me the output.
- When setup is complete, remind me to turn off network debugging on the TV.

If a step fails, check docs/troubleshooting.md before trying anything else.
Report errors to me as they appear; don't retry the same failing command
repeatedly.
```

4. Approve or decline each step as the agent asks.
5. When the agent asks, use your TV's remote to turn on developer options and network debugging, accept the debugging authorization prompt, and read the pairing code from the Agents card.

## Verify setup

1. On the remote, press **Home**. Lumen opens.
2. If you chose Agents, the card shows your chats, or it hides when no chat needs attention.

## Stay in control

The agent runs commands as you, so review what it asks to run. Lumen's scripts change your TV's accessibility settings and, for Agents, install a launchd job and a read-only token on your Mac. See [what Lumen reads and stores](../PRIVACY.md#tv-data-and-permissions) and [what to do if you want to undo it](uninstall.md#before-you-begin).

## What's next

- [Customize your home screen](quickstart.md#customize-your-home-screen).
- [Troubleshoot Lumen](troubleshooting.md#before-you-begin).
