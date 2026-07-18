# MonitorRefresh — agent notes

macOS menu bar app that revives a stuck / black / half-dark external monitor with one
click by sending a **DDC power-cycle** over the video cable (software equivalent of
pressing the monitor's power button). Built originally for an EHOMEWEI dual-stacked
portable monitor (shows up in macOS as "LINK") whose upper panel kept going dark.

Repo: https://github.com/uiharu-kazari/monitor-refresh (public, MIT). Current version 1.0.1.

## Layout

- `Sources/main.swift` — the entire app (~250 lines, single file). No Xcode project.
- `build.sh` — compiles with `swiftc` into `~/Applications/MonitorRefresh.app`, copies
  `Resources/Info.plist`, ad-hoc code-signs.
- `Resources/Info.plist` — bundle metadata. `LSUIElement=true` (menu-bar only, no Dock
  icon). Bump `CFBundleShortVersionString` when releasing.
- `scripts/monitor-refresh.sh` — thin shell wrapper around the app binary's CLI mode.
- `README.md` + `README.zh-CN.md` — English and Simplified Chinese, cross-linked. **Keep
  them in sync** — any user-facing change edits both.

## Build & run

```sh
./build.sh
open ~/Applications/MonitorRefresh.app     # menu bar icon = display with a refresh arrow
```

Requires Xcode Command Line Tools. **Apple Silicon only** (native DDC path needs it).

## How it works (the load-bearing details)

- **Display discovery**: walk the IORegistry (`IORegistryCreateIterator`, recursive).
  Each display's framebuffer node (`IOMobileFramebufferShim` / `AppleCLCD2`) carries the
  product name in its `DisplayAttributes`/`Metadata` dict, and appears in traversal order
  **right before** its matching `DCPAVServiceProxy` node (the DDC endpoint, `Location ==
  "External"`). We pair them by remembering the last-seen framebuffer name.
- **DDC power-cycle**: DDC/CI *Set VCP Feature* write of `powerMode` (VCP `0xD6`) —
  value `4` (off), wait 6s, value `1` (on) — via the private `IOAVServiceWriteI2C`
  (I2C addr `0x37`, sub-addr `0x51`, standard DDC checksum). Same mechanism as
  [m1ddc](https://github.com/waydabber/m1ddc) / MonitorControl.
- **Retries**: DDC through DP→HDMI converters/docks is flaky, so every write retries up
  to 5×. The original problem monitor sits behind a DP→HDMI converter and works fine.

### ⚠️ Gotchas / dead ends already hit

- **`IOAVServiceCopyEDID` segfaults** in this setup (tried both 1-arg and 2-arg
  signatures) — do **not** use it for names. That's why names come from the IORegistry
  framebuffer node instead. Don't "simplify" back to reading EDID.
- **Language detection** reads `AppleLanguages` from the global `UserDefaults` domain, not
  `Locale.preferredLanguages` (the latter is filtered by bundled `.lproj` localizations,
  which this single-binary app has none of). This also honors a `-AppleLanguages '(zh-Hans)'`
  launch override, useful for previewing/testing.
- **Ad-hoc signed** (no Apple Developer cert) → Gatekeeper blocks first launch of the DMG.
  README documents the "Open Anyway" / `xattr -cr` workaround. Notarization is the only way
  to remove the prompt and needs a paid Apple Developer account.

## CLI mode

The app binary doubles as a CLI (used by `scripts/monitor-refresh.sh`, and handy for
Raycast/Alfred/cron):

```sh
MonitorRefresh --list                  # print external display names, one per line
MonitorRefresh --power-cycle "LINK"    # DDC power-cycle that display
```

CLI output stays **English regardless of system language** so scripts parse consistently.
Only the GUI menu is localized.

## Localization

`enum L { static func t(_ en:, _ zh:) }` picks Chinese when the system language is Chinese,
English otherwise. Only the menu bar UI strings go through `L.t`. To add a language, extend
`L` and wrap the new strings. The product name "MonitorRefresh" is a brand — never translate
the title; the Chinese README uses a translated *tagline* under it, not a renamed title.

## Releasing

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
2. `./build.sh`
3. Build the DMG (drag-to-Applications layout):
   ```sh
   mkdir dmgroot && cp -R ~/Applications/MonitorRefresh.app dmgroot/ && ln -s /Applications dmgroot/Applications
   hdiutil create -volname MonitorRefresh -srcfolder dmgroot -ov -format UDZO MonitorRefresh-<ver>.dmg
   ```
4. `gh release create v<ver> MonitorRefresh-<ver>.dmg --title "MonitorRefresh <ver>" --notes "..."`

Verify a release by downloading the DMG, mounting it, and running
`.../MonitorRefresh.app/Contents/MacOS/MonitorRefresh --list` from the mounted copy.

## Conventions

- Commit trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`.
- Any user-facing change → update **both** READMEs.
- Keep it a single-file `swiftc` build with zero third-party dependencies. BetterDisplay was
  an earlier dependency and was deliberately removed — don't reintroduce a runtime dep for
  a feature that native IOKit can do.
