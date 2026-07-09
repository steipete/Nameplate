---
name: nameplate-attention
description: "On-screen agent alert: topmost message card + pulsating screen borders via Nameplate. Use before password-manager auth prompts or whenever blocked on the human."
---

# Nameplate Attention

Grab the human's attention at the Mac: a topmost message card plus pulsating colored borders on every display. Always include the reason — never fire a contextless alert.

## Command

- Binary: `nameplate` — `/Applications/Nameplate.app/Contents/Helpers/nameplate` (symlink it onto your PATH; a repo checkout build lives at `<repo>/Nameplate.app/Contents/Helpers/nameplate`).
- `nameplate attention "<why you need the human>" --title "<agent> → <system>" [--duration <seconds>] [--color <hex>]`
- Example, right before an interactive 1Password `op` prompt (which carries no reason field of its own):
  `nameplate attention "Need 1Password approval for release verification; no secret read." --title "Codex → 1Password"`
- Launches Nameplate.app if it is not running. By default the card stays until the human clicks it; pass `--duration <seconds>` (max 120) for auto-dismiss.
- Requests are timestamped; anything older than 2 minutes is dropped, so a login-time launch never replays stale alerts.

## Extras

- `nameplate splash` — replay the identity splash (which Mac is this?).
- `nameplate settings` — open Nameplate settings.
- No CLI at hand? `notifyutil -p com.steipete.nameplate.splash` works from any shell, including SSH.
