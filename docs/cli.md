# CLI reference

Nameplate's installed executable is both the desktop app and its command-line client. Homebrew links the macOS helper from inside `Nameplate.app`; Windows and Linux use the same executable that runs the tray app or overlay daemon.

For a direct macOS app install, link the bundled helper into a directory on `PATH`:

```sh
ln -s /Applications/Nameplate.app/Contents/Helpers/nameplate ~/bin/nameplate
```

## Platform support

| Command or option | macOS | Windows | Linux |
| --- | --- | --- | --- |
| `splash` | ✓ | ✓ | ✓ |
| `attention --title --duration --color` | ✓ | ✓ | ✓ |
| `attention --wait --timeout` | ✓ | — | — |
| `settings` | ✓ | — | — |
| `dismiss` | ✓ | — | — |

## Common commands

Replay the identity splash:

```sh
nameplate splash
```

Ask for the user's attention:

```sh
nameplate attention "Need approval before release" \
  --title "Agent needs attention" --duration 30 --color "#E24B30"
```

Without `--duration`, the card remains until a mouse click. On X11, Windows, and macOS the click dismisses the card without consuming the click intended for the underlying control. Wayland does not allow global click observation, so use `--duration` there.

## macOS commands

The macOS CLI adds acknowledgement and lifecycle commands:

```text
nameplate attention <message> [--title <title>] [--duration <seconds>] [--color <hex>]
  [--wait] [--timeout <seconds>]
nameplate splash
nameplate settings
nameplate dismiss
```

`--wait` blocks for up to 600 seconds by default. `--timeout` changes that limit and requires `--wait`.

| Exit code | Outcome |
| --- | --- |
| `0` | The user clicked to dismiss the alert. |
| `3` | Nameplate dismissed the alert without a click. |
| `4` | The wait timed out, the request expired, or a newer state superseded it. |

Concurrent alerts queue in order. `nameplate dismiss` clears active and queued alerts without quitting the app. The CLI starts Nameplate when needed.

## macOS scripting hooks

Darwin notifications work from an SSH session without activating the app:

```sh
notifyutil -p com.steipete.nameplate.splash
notifyutil -p com.steipete.nameplate.settings
```

The `nameplate://splash` and `nameplate://settings` URLs are also registered. Darwin notifications are the more dependable path for a menu-bar-only app.

The repository includes a [Nameplate attention skill](../skills/nameplate-attention/SKILL.md) for agents that need a structured human-approval handoff.
