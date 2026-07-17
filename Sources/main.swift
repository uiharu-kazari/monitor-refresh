import Cocoa
import IOKit

// MARK: - Localization
//
// The menu UI follows the system language: Simplified Chinese when the user's
// preferred language is Chinese, English otherwise. (The --list / --power-cycle
// CLI output stays English so scripts parse consistently.)
enum L {
    // Read the user's raw preferred-language order from the global domain. This is not
    // filtered by the app's bundled localizations (there are none — the app is a single
    // binary), and it honors a `-AppleLanguages (zh-Hans)` launch override.
    static let isZH: Bool = {
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        return (langs?.first ?? Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
    }()
    static func t(_ en: String, _ zh: String) -> String { isZH ? zh : en }
}

// MARK: - Native DDC over IOAVService (Apple Silicon)
//
// Talks DDC/CI directly to external displays through the private IOAVService IOKit API —
// the same mechanism used by m1ddc and MonitorControl. No third-party software needed.
//
// Displays are discovered by walking the IORegistry: each display's framebuffer node
// (IOMobileFramebufferShim / AppleCLCD2, which carries the product name) appears in
// traversal order right before its matching DCPAVServiceProxy (the DDC endpoint).

final class ExternalDisplay {
    let name: String
    let avService: CFTypeRef
    init(name: String, avService: CFTypeRef) {
        self.name = name
        self.avService = avService
    }
}

enum NativeDDC {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let createFn: CreateFn? = loadSymbol("IOAVServiceCreateWithService")
    private static let writeFn: WriteFn? = loadSymbol("IOAVServiceWriteI2C")

    private static func loadSymbol<T>(_ name: String) -> T? {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static var available: Bool { createFn != nil && writeFn != nil }

    static func externalDisplays() -> [ExternalDisplay] {
        guard let createFn else { return [] }
        var result: [ExternalDisplay] = []
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively),
                                       &iterator) == KERN_SUCCESS else { return [] }
        var lastProductName: String?
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            var classNameC = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(entry, &classNameC)
            let className = String(cString: classNameC)

            if className == "IOMobileFramebufferShim" || className == "AppleCLCD2" {
                if let name = productName(of: entry) { lastProductName = name }
                continue
            }
            guard className == "DCPAVServiceProxy" else { continue }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External",
                  let avService = createFn(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            var name = lastProductName ?? "External Display"
            let clashes = result.filter { $0.name == name || $0.name.hasPrefix(name + " (") }.count
            if clashes > 0 { name += " (\(clashes + 1))" }
            result.append(ExternalDisplay(name: name, avService: avService))
        }
        IOObjectRelease(iterator)
        return result
    }

    private static func productName(of entry: io_registry_entry_t) -> String? {
        for key in ["DisplayAttributes", "Metadata"] {
            guard let dict = IORegistryEntryCreateCFProperty(entry, key as CFString,
                                                             kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            if let name = (dict["ProductAttributes"] as? [String: Any])?["ProductName"] as? String {
                return name
            }
            if let name = dict["ProductName"] as? String { return name }
        }
        return nil
    }

    // DDC/CI "Set VCP Feature" write. Retried because DDC through converters/docks is flaky.
    static func setVCP(_ avService: CFTypeRef, code: UInt8, value: UInt16) -> Bool {
        guard let writeFn else { return false }
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        for _ in 1...5 {
            var buffer = packet
            if writeFn(avService, 0x37, 0x51, &buffer, UInt32(buffer.count)) == KERN_SUCCESS {
                return true
            }
            usleep(500_000)
        }
        return false
    }

    // Power cycle = DDC powerMode (VCP 0xD6) off, wait, on — the software equivalent of
    // pressing the monitor's power button. Blocking — call off the main thread.
    static func powerCycle(_ display: ExternalDisplay) {
        _ = setVCP(display.avService, code: 0xD6, value: 4)
        sleep(6)
        _ = setVCP(display.avService, code: 0xD6, value: 1)
    }
}

// MARK: - Command line mode (MonitorRefresh --list | --power-cycle <name>)

let cliArgs = CommandLine.arguments
if cliArgs.count > 1 {
    switch cliArgs[1] {
    case "--list":
        NativeDDC.externalDisplays().forEach { print($0.name) }
    case "--power-cycle" where cliArgs.count > 2:
        guard let display = NativeDDC.externalDisplays().first(where: { $0.name == cliArgs[2] }) else {
            FileHandle.standardError.write("display \"\(cliArgs[2])\" not found — try --list\n".data(using: .utf8)!)
            exit(1)
        }
        print("DDC power-cycling \"\(display.name)\" (off 6s, then on)...")
        NativeDDC.powerCycle(display)
        print("Done.")
    default:
        print("usage: MonitorRefresh [--list | --power-cycle <display name>]")
    }
    exit(0)
}

// MARK: - Menu bar app

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
    var displays: [ExternalDisplay] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.toolTip = L.t("Monitor Refresh — revive a stuck monitor without replugging cables",
                                         "Monitor Refresh — 无需拔插线缆即可唤醒卡住的显示器")
        menu.delegate = self
        statusItem.menu = menu
    }

    // The menu is rebuilt every time it opens, so newly connected displays show up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if running {
            menu.addItem(withTitle: L.t("Working…", "处理中…"), action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }
        displays = NativeDDC.externalDisplays()
        if displays.isEmpty {
            let hint = NativeDDC.available
                ? L.t("No external displays found", "未找到外接显示器")
                : L.t("Unsupported system (Apple Silicon required)", "系统不支持（需要 Apple Silicon）")
            menu.addItem(withTitle: hint, action: nil, keyEquivalent: "")
        }
        for (index, display) in displays.enumerated() {
            let item = NSMenuItem(title: L.t("Power Cycle “\(display.name)”", "电源循环 “\(display.name)”"),
                                  action: #selector(powerCycle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = !running
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let sleepItem = NSMenuItem(title: L.t("Sleep & Wake All Displays", "休眠并唤醒所有显示器"),
                                   action: #selector(sleepAll), keyEquivalent: "")
        sleepItem.target = self
        sleepItem.isEnabled = !running
        menu.addItem(sleepItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.t("Quit Monitor Refresh", "退出 Monitor Refresh"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc func powerCycle(_ sender: NSMenuItem) {
        guard displays.indices.contains(sender.tag) else { return }
        let display = displays[sender.tag]
        runInBackground { NativeDDC.powerCycle(display) }
    }

    @objc func sleepAll() {
        guard !running else { return }
        setBusy(true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "pmset displaysleepnow; sleep 5; /usr/bin/caffeinate -u -t 2"]
        process.terminationHandler = { _ in
            DispatchQueue.main.async { self.setBusy(false) }
        }
        do { try process.run() } catch { setBusy(false) }
    }

    func runInBackground(_ work: @escaping () -> Void) {
        guard !running else { return }
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            work()
            DispatchQueue.main.async { self.setBusy(false) }
        }
    }

    func setBusy(_ busy: Bool) {
        running = busy
        statusItem.button?.appearsDisabled = busy
        statusItem.button?.image = busy
            ? NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Working…")
            : makeStatusIcon()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
