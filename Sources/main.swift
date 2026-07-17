import Cocoa

// Path to the BetterDisplay CLI (the app binary doubles as its CLI).
let bdPath = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

// Menu bar icon: a display with a refresh arrow on its screen (no stock SF Symbol
// combines the two, so it is composited from "display" + "arrow.clockwise").
func makeStatusIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        guard let display = NSImage(systemSymbolName: "display", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)),
              let arrow = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .heavy))
        else { return false }
        display.draw(in: rect)
        let arrowSize = arrow.size
        // Center the arrow on the display glyph's screen area (upper part of the glyph).
        let origin = NSPoint(x: rect.midX - arrowSize.width / 2,
                             y: rect.midY - arrowSize.height / 2 + 2)
        arrow.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Monitor Refresh"
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var running = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.toolTip = "Monitor Refresh — revive a stuck monitor without replugging cables"
        menu.delegate = self
        statusItem.menu = menu
    }

    // The menu is rebuilt every time it opens, so newly connected displays show up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if running {
            menu.addItem(withTitle: "Working…", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }
        let displays = listDisplays()
        if displays.isEmpty {
            menu.addItem(withTitle: "No displays found — is BetterDisplay installed?",
                         action: nil, keyEquivalent: "")
        }
        for name in displays {
            let item = NSMenuItem(title: "Power Cycle “\(name)”",
                                  action: #selector(powerCycle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.isEnabled = !running
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let advanced = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for name in displays {
            let item = NSMenuItem(title: "Disconnect & Reconnect “\(name)”",
                                  action: #selector(replug(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.isEnabled = !running
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let sleepItem = NSMenuItem(title: "Sleep & Wake All Displays",
                                   action: #selector(sleepAll), keyEquivalent: "")
        sleepItem.target = self
        sleepItem.isEnabled = !running
        sub.addItem(sleepItem)
        advanced.submenu = sub
        menu.addItem(advanced)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Monitor Refresh",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    func listDisplays() -> [String] {
        guard FileManager.default.isExecutableFile(atPath: bdPath) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bdPath)
        process.arguments = ["get", "-identifiers"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        var names: [String] = []
        var deviceType = ""
        for line in output.split(separator: "\n") {
            if let range = line.range(of: "\"deviceType\" : \"") {
                let rest = line[range.upperBound...]
                if let end = rest.firstIndex(of: "\"") { deviceType = String(rest[..<end]) }
            }
            if let range = line.range(of: "\"name\" : \""), deviceType == "Display" {
                let rest = line[range.upperBound...]
                if let end = rest.firstIndex(of: "\"") {
                    let name = String(rest[..<end])
                    if !name.isEmpty && !names.contains(name) { names.append(name) }
                }
            }
        }
        return names
    }

    // Turn the monitor off and back on via DDC (VCP 0xD6 powerMode) — the software
    // equivalent of pressing its power button. DDC through adapters/converters can be
    // flaky, so each command retries up to 5 times.
    @objc func powerCycle(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        runShell("""
        for i in 1 2 3 4 5; do "\(bdPath)" set -name="\(name)" -ddc -vcp=powerMode -value=4 2>/dev/null && break; sleep 1; done
        sleep 6
        for i in 1 2 3 4 5; do "\(bdPath)" set -name="\(name)" -ddc -vcp=powerMode -value=1 2>/dev/null && break; sleep 1; done
        """)
    }

    // Software unplug/replug: macOS removes the display and re-adds it (full hot-plug).
    @objc func replug(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        runShell("""
        "\(bdPath)" set -name="\(name)" -connected=off
        sleep 5
        "\(bdPath)" set -name="\(name)" -connected=on
        """)
    }

    @objc func sleepAll() {
        runShell("pmset displaysleepnow; sleep 5; /usr/bin/caffeinate -u -t 2")
    }

    func runShell(_ command: String) {
        guard !running else { return }
        running = true
        statusItem.button?.appearsDisabled = true
        statusItem.button?.image = NSImage(systemSymbolName: "hourglass",
                                           accessibilityDescription: "Working…")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.running = false
                self.statusItem.button?.appearsDisabled = false
                self.statusItem.button?.image = makeStatusIcon()
            }
        }
        do { try process.run() } catch {
            running = false
            statusItem.button?.appearsDisabled = false
            statusItem.button?.image = makeStatusIcon()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
