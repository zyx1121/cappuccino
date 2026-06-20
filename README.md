# lidlatte

> Keep your Mac awake — even with the lid closed — *only* while Claude Code is working, then let it sleep.

A tiny menu-bar utility for the one thing [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) and [Caffeine](https://www.caffeine-app.net/) make you babysit: lidlatte watches Claude Code and flips lid-close sleep on/off **automatically**, so you can shut the lid mid-task and walk away. When the work stops, normal sleep comes back on its own.

## Why

- **Amphetamine / Caffeine / Sleepless** keep you awake, but you toggle them by hand.
- **vibe-caffeine** auto-detects coding agents, but uses an `IOPMAssertion` — which *cannot* keep a Mac awake with the lid closed (lid-close is forced sleep, not idle sleep).

lidlatte is the missing intersection: **auto-detection + true lid-closed keep-awake**.

## How it works

| Layer | Mechanism |
|-------|-----------|
| Detect | FSEvents on `~/.claude/projects` → Claude Code session writes = "busy"; 120s of silence = "idle" |
| Keep awake | `pmset disablesleep 1` — the only lever that survives a closed lid (undocumented, but real; resets to `0` on reboot) |
| Authorize | A one-time Touch ID sheet installs a tightly-scoped `sudoers` drop-in permitting *only* `pmset -a disablesleep 0/1`; toggles after that need no password |
| Safety nets | Hard battery floor (default 15%, wins even over manual override), Low Power Mode auto-off, restore normal sleep on quit |

State machine: `keepAwake = (manualOverride || (auto && claudeBusy)) && !belowBatteryFloor && !(lowPowerMode && !manualOverride)`

## Build

No Xcode — SwiftPM + a Makefile that bundles and codesigns:

```sh
make            # build + bundle + sign → build/lidlatte.app
make run        # build + open
make verify     # check signature + current SleepDisabled state
```

Set `SIGN_ID` in the `Makefile` to your own `Apple Development` cert hash (`security find-identity -p codesigning -v`).

## Usage

Launch it; a ⚡️/🌙 icon sits in the menu bar.

- **Claude Code 工作時不睡** — auto mode (on by default). Shut the lid mid-task; it stays awake until the work goes idle.
- **持續闔蓋不睡** — manual override: stay awake regardless of detection (still bounded by the battery floor).
- **低電量自動關** — battery floor at which lidlatte forces normal sleep so it can't drain the Mac.

Verify it's live: `pmset -g | grep SleepDisabled` (1 = keeping awake).

If lidlatte is force-quit while keeping awake, restore sleep manually: `sudo pmset -a disablesleep 0`.

## Security

The only privileged action is `pmset -a disablesleep 0/1`. The `sudoers` grant (`/etc/sudoers.d/lidlatte-disablesleep`, `root:wheel`, `0440`) permits exactly those two commands and nothing else, validated with `visudo` before install. See [`scripts/grant.sh`](scripts/grant.sh). Uninstall the grant with `sudo rm /etc/sudoers.d/lidlatte-disablesleep`.

## TODO

- [ ] `TODO(burn-in)`: on Apple Silicon, force the **built-in display** to sleep while the lid is folded closed (disablesleep keeps the panel powered → burn-in + wasted battery). Needs lid-state detection (`AppleClamshellState` via IOKit) + `pmset displaysleepnow`.
- [ ] `TODO(detection)`: tighten the busy signal with a process/I-O check so a long inference (no disk writes) isn't mistaken for idle.
- [ ] Battery-floor as a live slider; auto-off timer (1h/2h).

## Prior art

[vibe-caffeine](https://github.com/jjyr/vibe-caffeine) (agent detection) · [Sleepless](https://github.com/Aboudjem/Sleepless) (disablesleep + safety nets) · [Macchiato](https://github.com/ObservedObserver/Macchiato) (XPC-helper authorization)
