# Security

Found something? Please tell us privately first, through this repository's **Security → Report a vulnerability** form. Include your Grock and macOS versions, how to reproduce it, and what happened. Synthetic files and example text are better than your real ones.

If that form isn't available, open a plain issue asking for a private contact, and leave the details out of it.

Report the native app, its file handling, the `grock://` scheme, the CLI, and the bridges between the app and grok.com here. Grock is sandboxed and those bridges are deliberately narrow ([DEC-056](docs/DECISIONS.md#dec-056-web-content-gets-a-short-leash)), so if you find a way through, we want to know.

Anything in grok.com itself goes to xAI. Grock loads their site; it doesn't run it.

Only the latest release gets fixes. Grock updates itself, so that's the version most people have.

Please keep passwords, cookies, tokens, and private conversations out of reports.
