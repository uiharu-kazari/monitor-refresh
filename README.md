# MonitorRefresh

**English** | [简体中文](README.zh-CN.md)

A tiny macOS menu bar app that revives a stuck, black, or half-dark external monitor **without touching any cables**. One click sends a DDC power-cycle command to the monitor over the video cable — the software equivalent of pressing its power button.

**No dependencies.** The app talks DDC/CI to your monitors directly through the system's IOKit (the same mechanism used by [m1ddc](https://github.com/waydabber/m1ddc) and [MonitorControl](https://github.com/MonitorControl/MonitorControl)).

## Why this exists

Some external monitors occasionally lose part of their picture until you physically unplug and replug them. This is especially common with **dual-panel stacked portable monitors** (e.g. EHOMEWEI X-series, JSAUX FlipGo and similar), where the internal controller that splits one video stream across two panels gets stuck and one half of the screen goes black or dim.

Re-handshaking the video signal from the Mac side (changing resolution, sleeping the display, even a software unplug/replug) often does **not** fix this, because the fault is inside the monitor's own controller. What fixes it is cutting power to the monitor — and it turns out you can do that in software: most monitors accept the DDC/CI `powerMode` command (VCP `0xD6`) over the video cable itself.

This app puts that fix one click away in your menu bar. It was built for an EHOMEWEI dual stacked monitor (which shows up in macOS as "LINK") whose upper half regularly went dark, and the DDC power-cycle revives it reliably.

## Requirements

- An **Apple Silicon** Mac (M1 or newer)
- macOS 13 or later
- That's it — no drivers, no helper apps.

## Install

### Option A: download the DMG

Grab the latest `MonitorRefresh-x.y.z.dmg` from [Releases](https://github.com/uiharu-kazari/monitor-refresh/releases), open it, and drag **MonitorRefresh** into Applications.

Because this is a free open-source app without an Apple Developer certificate, macOS will block the first launch. Approve it once via **System Settings → Privacy & Security → "Open Anyway"**, or clear the quarantine flag in Terminal:

```sh
xattr -cr /Applications/MonitorRefresh.app
```

### Option B: build from source

Requires Xcode Command Line Tools (`xcode-select --install`). Apps you build yourself are not quarantined — no security prompt.

```sh
git clone https://github.com/uiharu-kazari/monitor-refresh.git
cd monitor-refresh
./build.sh
open ~/Applications/MonitorRefresh.app
```

### Start at login

System Settings → General → Login Items → add **MonitorRefresh**, or:

```sh
osascript -e 'tell application "System Events" to make new login item at end with properties {path:"'$HOME'/Applications/MonitorRefresh.app", hidden:true}'
```

## Usage

Click the display-with-refresh-arrow icon in the menu bar:

- **Power Cycle "\<monitor\>"** — one entry per connected monitor. Sends DDC off, waits 6 seconds, sends DDC on. The monitor blanks briefly and comes back with its controller reset. This is the main fix.
- **Sleep & Wake All Displays** — forces every display through a sleep/wake handshake (a gentler alternative worth trying for other kinds of display glitches).
- The icon turns into an hourglass while a fix is running.

The display list is rebuilt every time the menu opens, so newly connected monitors appear automatically.

The menu is localized: it shows **Simplified Chinese** when your system language is Chinese, and English otherwise. To preview the Chinese menu without changing your system language:

```sh
open -n ~/Applications/MonitorRefresh.app --args -AppleLanguages '(zh-Hans)'
```

## Command line

The app binary doubles as a CLI — handy for Raycast/Alfred scripts, `ssh`, or cron:

```sh
APP=~/Applications/MonitorRefresh.app/Contents/MacOS/MonitorRefresh
$APP --list                  # list connected monitor names
$APP --power-cycle "LINK"    # DDC power-cycle that monitor
```

[`scripts/monitor-refresh.sh`](scripts/monitor-refresh.sh) wraps this with a shorter syntax and adds `--hard` (sleep/wake all displays):

```sh
./scripts/monitor-refresh.sh --list
./scripts/monitor-refresh.sh "LINK"
./scripts/monitor-refresh.sh --hard
```

## How it works

- Displays are discovered by walking the IORegistry: each display's framebuffer node (which carries the product name) is paired with its `DCPAVServiceProxy` DDC endpoint.
- The power-cycle is a DDC/CI *Set VCP Feature* write of `powerMode` (VCP `0xD6`) — value 4 (off), then 1 (on) — sent over I2C via the private `IOAVService` API. This is the same approach proven by [m1ddc](https://github.com/waydabber/m1ddc) and [MonitorControl](https://github.com/MonitorControl/MonitorControl).
- DDC through DP→HDMI converters and docks is flaky, so every DDC write is retried up to 5 times.
- The whole app is ~250 lines of Swift (`Sources/main.swift`), compiled directly with `swiftc` — no Xcode project, no dependencies, menu-bar only (no Dock icon).

## Troubleshooting

- **"Unsupported system"** — the native DDC path requires Apple Silicon. On Intel Macs, use a DDC tool like [ddcctl](https://github.com/kfix/ddcctl) instead.
- **Power cycle does nothing** — your monitor may not implement VCP `0xD6`. Some monitors only blank the backlight instead of truly cutting power; for those, the physical power button or an inline USB-C power switch remains the fallback.
- **Monitor connected through a hub/adapter** — DDC usually still passes through (the original problem monitor sits behind a DP→HDMI converter and works fine), but if all commands fail, try a direct connection.

## License

[MIT](LICENSE)
