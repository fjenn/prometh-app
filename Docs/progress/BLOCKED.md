# Blocked

## M8 live Composio broker and GitHub connect

This item only. Milestones continue.

### Evidence

- `COMPOSIO_API_KEY` is unset in this environment.
- `~/.config/prometh/composio.env` does not exist. The file was not created and no key was printed.
- No broker URL is configured (`PROMETH_BROKER_URL` is unset).
- This host cannot complete "Continue in browser".

### What is already proven

The stdio server, approval-token refusal, and hash-locked install passed on Linux. See `Docs/progress/M8/REPORT.md`. The app hides connector UI until a broker URL is set.

### What unblocks it

1. Put `COMPOSIO_API_KEY` in `~/.config/prometh/composio.env` (mode 600, `KEY=VALUE`). Do not commit that file.
2. Set the broker URL with `PROMETH_BROKER_URL` or Customize › Advanced.
3. On the Mac, run the steps under PENDING MAC VERIFICATION in `Docs/progress/M8/REPORT.md`, including the GitHub connect and the Approve / Deny sheet.
