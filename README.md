# MonitorRefresh

**English** | [简体中文](README.zh-CN.md)

A tiny macOS menu bar app that revives a stuck, black, or half-dark external monitor **without touching any cables**. One click sends a DDC power-cycle command to the monitor over the video cable — the software equivalent of pressing its power button.

## Why this exists

Some external monitors occasionally lose part of their picture until you physically unplug and replug them. This is especially common with **dual-panel stacked portable monitors** (e.g. EHOMEWEI X-series, JSAUX FlipGo and similar), where the internal controller that splits one video stream across two panels gets stuck and one half of the screen goes black or dim.

Re-handshaking the video signal from the Mac side (changing resolution, sleeping the display, even a software unplug/replug) often does **not** fix this, because the fault is inside the monitor's own controller. What fixes it is cutting power to the monitor — and it turns out you can do that in software: most monitors accept the DDC/CI `powerMode` command (VCP `0xD6`) over the video cable itself.

This app puts that fix one click away in your menu bar. It was built for an EHOMEWEI dual stacked monitor (which shows up in macOS as "LINK") whose upper half regularly went dark, and the DDC power-cycle revives it reliably.

## Requirements

- macOS 13 or later (Apple Silicon and Intel both fine)
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) installed in `/Applications` — the free version is sufficient. MonitorRefresh uses BetterDisplay's CLI to talk DDC to your monitors.
- Xcode Command Line Tools to build (`xcode-select --install`)

## Install

```sh
git clone https://github.com/uiharu-kazari/monitor-refresh.git
cd monitor-refresh
./build.sh
open ~/Applications/MonitorRefresh.app
```

To start it automatically at login: System Settings → General → Login Items → add **MonitorRefresh**, or:

```sh
osascript -e 'tell application "System Events" to make new login item at end with properties {path:"'$HOME'/Applications/MonitorRefresh.app", hidden:true}'
```

## Usage

Click the display icon in the menu bar:

- **Power Cycle "\<monitor\>"** — one entry per connected monitor. Sends DDC off, waits 6 seconds, sends DDC on. The monitor blanks briefly and comes back with its controller reset. This is the main fix.
- **Advanced →**
  - **Disconnect & Reconnect "\<monitor\>"** — software unplug/replug: macOS fully removes the display and re-adds it (a real hot-plug event). Note: this may rearrange windows, and display disconnection may require BetterDisplay Pro.
  - **Sleep & Wake All Displays** — forces every display through a sleep/wake handshake.
- The icon turns into an hourglass while a fix is running.

The display list is rebuilt every time the menu opens, so newly connected monitors appear automatically.

## Just want the shell script?

If you don't need the menu bar app, everything the app does is also available as a standalone script: [`scripts/monitor-refresh.sh`](scripts/monitor-refresh.sh). It only needs zsh and BetterDisplay — no compiling.

```sh
./scripts/monitor-refresh.sh --list             # list your connected monitor names
./scripts/monitor-refresh.sh "LINK"             # DDC power-cycle that monitor (the main fix)
./scripts/monitor-refresh.sh "LINK" --reconnect # software unplug/replug instead
./scripts/monitor-refresh.sh --hard             # sleep all displays 5s, then wake
```

Use `--list` first to find your monitor's exact name, then pass that name to power-cycle it. The power-cycle sends DDC off, waits 6 seconds, and sends DDC on — the monitor blanks briefly and comes back with its internal controller reset. Handy for keyboard-launcher tools (Raycast, Alfred), `ssh`, or cron.

## How it works

- Monitor enumeration and DDC commands go through the BetterDisplay CLI (`BetterDisplay get -identifiers`, `BetterDisplay set -name=... -ddc -vcp=powerMode -value=4/1`).
- DDC through DP→HDMI converters and docks is flaky, so every DDC command is retried up to 5 times.
- The app itself is ~200 lines of Swift (`Sources/main.swift`), compiled directly with `swiftc` — no Xcode project, no dependencies, menu-bar only (no Dock icon).

## Troubleshooting

- **"No displays found"** — make sure BetterDisplay.app is installed in `/Applications` and running.
- **Power cycle does nothing** — your monitor may not implement VCP `0xD6`. Check with `BetterDisplay get -name=<name> -ddcCapabilities`. Some monitors only blank the backlight instead of truly cutting power; for those, the physical power button or an inline USB-C power switch remains the fallback.
- **Monitor connected through a hub/adapter** — DDC usually still passes through, but if all commands fail, try a direct connection.

## License

[MIT](LICENSE)
