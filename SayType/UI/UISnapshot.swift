import AppKit
import SwiftUI

/// Renders the app's screens to PNG files without showing anything on screen:
/// `SayType.app/Contents/MacOS/SayType --snapshot /some/dir [--dark]`. Used to check the design.
@MainActor
enum UISnapshot {
    typealias Item = (name: String, view: AnyView, size: CGSize)

    static var active: Bool { CommandLine.arguments.contains("--snapshot") }

    private static func attach<V: View>(_ view: V) -> AnyView {
        let c = AppController.shared
        return AnyView(view
            .environmentObject(c).environmentObject(c.focus).environmentObject(c.vocabulary)
            .environmentObject(c.snippets).environmentObject(c.profiles).environmentObject(c.history))
    }

    static func items() -> [Item] {
        var result: [Item] = SettingsPane.allCases.map { pane in
            (name: "settings-\(pane.rawValue)", view: attach(SettingsView()), size: CGSize(width: 820, height: 640))
        }
        result.append((name: "menu", view: attach(MenuView().padding(1).background(Color(nsColor: .windowBackgroundColor))),
                       size: CGSize(width: 320, height: 512)))
        result += ExtraSnapshots.items().map { ($0.name, attach($0.view), $0.size) }
        return result
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let dark = args.contains("--dark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        Task { @MainActor in
            AppController.shared.prepareForSnapshot()
            let savedPane = UserDefaults.standard.string(forKey: "settings.pane")
            for item in items() {
                if item.name.hasPrefix("settings-") {
                    UserDefaults.standard.set(String(item.name.dropFirst("settings-".count)), forKey: "settings.pane")
                }
                await render(item, to: dir, dark: dark)
            }
            if let savedPane { UserDefaults.standard.set(savedPane, forKey: "settings.pane") }
            else { UserDefaults.standard.removeObject(forKey: "settings.pane") }
            NSApp.terminate(nil)
        }
    }

    private static func render(_ item: Item, to dir: URL, dark: Bool) async {
        let hosting = NSHostingView(rootView: item.view)
        let window = NSWindow(contentRect: CGRect(x: -6000, y: -6000, width: item.size.width, height: item.size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(1200))
        hosting.layoutSubtreeIfNeeded()
        let scale = 2
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(item.size.width) * scale, pixelsHigh: Int(item.size.height) * scale,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = item.size // points; the extra pixels make the image sharp
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(item.name)\(dark ? "-dark" : "").png"))
            }
        }
        window.orderOut(nil)
    }
}
