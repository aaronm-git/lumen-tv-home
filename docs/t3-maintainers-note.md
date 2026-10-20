# Draft note to T3 Code's maintainers

A draft to send before (or as) Lumen goes public. Edit freely.

---

Hi T3 Code team,

I've been building Lumen, a small open-source home screen for Android TVs, and I added an optional feature that
shows my T3 Code chats on the TV: which ones are working, waiting for approval or input, done or failed, with a
short notification when one needs me. It's been really handy for keeping an eye on long runs from the couch, and
I'd like to publish it (MIT licensed) without stepping on your toes.

How it works today: a small helper on the Mac issues its own read-only session with
`t3 auth session issue --scope orchestration:read` (labelled "Lumen TV", 30-day TTL, renewed automatically), reads
`server-runtime.json` to find the local server, loads `/api/orchestration/shell` and follows the shell stream
(`x-t3-orchestration-protocol: 2`). Apart from issuing its own session it only reads, and it checks that the listening process is the
T3 Code app before sending the token. It only sends a short summary (titles, project, model, state and the last
message, length-capped) to the TV over an encrypted, paired connection on the home network. The code is here:
https://github.com/aaronm-git/lumen-tv-home, mainly `mac/LumenAgents.swift`.

A few questions:

1. Are you comfortable with a third-party, read-only integration like this using these interfaces? I know they're
   internal and undocumented, and the README says so and that they may change without notice.
2. Is there a supported or more stable interface you'd prefer I use (or one planned), for example a documented
   read-only status endpoint, event stream or CLI command? I'm happy to switch, and to follow any version or
   protocol checks you recommend.
3. Is it OK to use the name "T3 Code" descriptively ("shows your T3 Code chats", "an unofficial integration with
   T3 Code")? The project says it isn't affiliated with or endorsed by T3 Tools, Inc., and doesn't use your logo.
   I'll change the wording if you'd like something different.

If anything here is a problem, just tell me and I'll adjust or pull the feature. Thanks for making T3 Code!

Best,
Aaron Molina
