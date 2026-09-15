# CrazyNotch

A macOS notch companion for Claude Code. Every running agent session appears in
the MacBook notch, tool approvals can be answered without leaving your editor,
and your real plan usage is shown alongside.

## Pieces

| Piece | Role |
| --- | --- |
| `CrazyNotch.app` | Menu-bar agent. Owns the notch panel and a local HTTP server on `127.0.0.1:8787`. |
| `hooks/notch-hook.sh` | Hook client. Forwards every Claude Code hook payload to the app. |
| `hooks/notch-statusline.sh` | Status line wrapper. Forwards rate limits, then delegates to whatever status line you already had. |

## Where the numbers come from

Everything is read locally and nothing is estimated.

- **Rate limits (5H / WEEK)** are Claude Code's own figures, taken from
  `rate_limits` in the status line payload and passed through unchanged. With no
  reading available the meters stay blank rather than showing a guess.
- **Token history** is summed from `~/.claude/projects/**/*.jsonl`, deduplicated
  by message id and including cache reads. A transcript repeats a message's
  usage block across streaming updates, so without deduplication the totals run
  roughly 2.5x high.
- **Per-session context, model and cost** come from the status line and the
  session transcript.
- **Fable** shows `0%` when no Fable tokens exist, which is exact at zero, and
  `—` otherwise, because its ceiling is not exposed locally.

### Known limitation

Only interactive terminal sessions render a status line. The desktop app does
not, and neither does `claude -p`. Rate limit percentages therefore refresh when
you use a terminal session, persist across restarts, and are marked stale after
15 minutes. Reset countdowns are absolute timestamps and stay correct
regardless.

## Install

```bash
./build.sh release
cp -R build/CrazyNotch.app /Applications/
./install.sh                # wires the Claude Code hooks
```

## Approvals

A `PermissionRequest` hook parks until you click Approve or Deny in the notch.
If you answer in Claude instead, or the session moves on, the card clears
itself. If nothing answers before the timeout the decision falls through to
Claude's own prompt, so a session can never get stuck behind this app.

## Brand marks

`Resources/logos/*-mark.png` are vendor icons reduced to tintable white-on-
transparent templates. `fetch-logos.sh` regenerates them from each vendor's own
icon. They are third-party trademarks, kept here only because this repository is
private. Without them the app draws its own fallback marks.
