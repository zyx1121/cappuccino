# Cappuccino

> Keep your Mac awake — even with the lid closed — *only* while Claude Code is working, then let it sleep.

A tiny menu-bar utility for the one thing [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) and [Caffeine](https://www.caffeine-app.net/) make you babysit: Cappuccino watches Claude Code and flips lid-close sleep on/off **automatically**, so you can shut the lid mid-task and walk away. When the work stops, normal sleep comes back on its own.

## Why

- **Amphetamine / Caffeine / Sleepless** keep you awake, but you toggle them by hand.
- **vibe-caffeine** auto-detects coding agents, but uses an `IOPMAssertion` — which *cannot* keep a Mac awake with the lid closed (lid-close is forced sleep, not idle sleep).

Cappuccino is the missing intersection: **auto-detection + true lid-closed keep-awake**.

## How it works

| Layer | Mechanism |
|-------|-----------|
| Detect | FSEvents on `~/.claude/projects` → session writes = "busy"; 180s silence — or all `claude` processes gone — = "idle" |
| Keep awake | `pmset disablesleep 1` — the only lever that survives a closed lid (undocumented, but real; resets to `0` on reboot) |
| Protect display | When the lid shuts while keeping awake, `pmset displaysleepnow` parks the built-in panel — else disablesleep leaves it powered (Apple Silicon burn-in / battery drain) |
| Authorize | A one-time Touch ID sheet installs a tightly-scoped `sudoers` drop-in permitting *only* `pmset disablesleep 0/1` + `displaysleepnow`; toggles after that need no password |
| Safety nets | Hard battery floor (default 15%, wins even over manual override), Low Power Mode auto-off, restore normal sleep on quit |

State machine: `keepAwake = (manualOverride || (auto && claudeBusy)) && !belowBatteryFloor && !(lowPowerMode && !manualOverride)`

## Build

No Xcode — SwiftPM + a Makefile that bundles and codesigns:

```sh
make            # build + bundle + sign → build/Cappuccino.app
make run        # build + open
make verify     # check signature + current SleepDisabled state
```

Set `SIGN_ID` in the `Makefile` to your own `Apple Development` cert hash (`security find-identity -p codesigning -v`).

## Usage

Launch it; a ⚡️/🌙 icon sits in the menu bar.

- **Claude Code 工作時不睡** — auto mode (on by default). Shut the lid mid-task; it stays awake until the work goes idle.
- **持續闔蓋不睡** — manual override: stay awake regardless of detection (still bounded by the battery floor).
- **低電量自動關** — battery floor at which Cappuccino forces normal sleep so it can't drain the Mac.

Verify it's live: `pmset -g | grep SleepDisabled` (1 = keeping awake).

If Cappuccino is force-quit while keeping awake, restore sleep manually: `sudo pmset -a disablesleep 0`.

## Security

The only privileged actions are `pmset disablesleep 0/1` and `pmset displaysleepnow`. The `sudoers` grant (`/etc/sudoers.d/cappuccino-disablesleep`, `root:wheel`, `0440`) permits exactly those commands and nothing else, validated with `visudo` before install. See [`scripts/grant.sh`](scripts/grant.sh). Uninstall the grant with `sudo rm /etc/sudoers.d/cappuccino-disablesleep`.

## TODO

- [ ] Battery-floor as a live slider; auto-off timer (1h/2h).
- [ ] Residual detection gap: one inference longer than 180s while a `claude` process is still alive can read as idle (needs a streaming busy signal Claude Code doesn't expose).

## Prior art

[vibe-caffeine](https://github.com/jjyr/vibe-caffeine) (agent detection) · [Sleepless](https://github.com/Aboudjem/Sleepless) (disablesleep + safety nets) · [Macchiato](https://github.com/ObservedObserver/Macchiato) (XPC-helper authorization)
