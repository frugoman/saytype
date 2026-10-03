import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A colour that adapts to light and dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

/// The pastel families the interface is built from. Each has a soft background and a bold accent.
enum PlayTint: String, CaseIterable, Identifiable {
    case pink, blue, mint, lavender, butter, peach
    var id: String { rawValue }

    /// A stable colour for a title, so a section keeps its colour from run to run.
    static func auto(for title: String) -> PlayTint {
        let sum = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return allCases[sum % allCases.count]
    }
}

enum PaletteID: String, CaseIterable, Identifiable {
    case candy, ocean, sunset, cloud
    var id: String { rawValue }
    var label: String {
        switch self {
        case .candy: return "Candy"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .cloud: return "Cloud"
        }
    }

    /// Soft pastel for each tint.
    func soft(_ tint: PlayTint) -> UInt32 {
        switch self {
        case .candy:
            switch tint {
            case .pink: return 0xFFD9E6
            case .blue: return 0xD3EAFF
            case .mint: return 0xD4F6E8
            case .lavender: return 0xE5DCFF
            case .butter: return 0xFFF1BF
            case .peach: return 0xFFE0CC
            }
        case .ocean:
            switch tint {
            case .pink: return 0xF3DDF0
            case .blue: return 0xC9E6FF
            case .mint: return 0xC6F2EA
            case .lavender: return 0xD9DEFF
            case .butter: return 0xE8F5C8
            case .peach: return 0xD8EEF2
            }
        case .sunset:
            switch tint {
            case .pink: return 0xFFCFD8
            case .blue: return 0xFFE3D1
            case .mint: return 0xFFF0C2
            case .lavender: return 0xF6D4F0
            case .butter: return 0xFFE9A8
            case .peach: return 0xFFD2B8
            }
        case .cloud:
            switch tint {
            case .pink: return 0xECE6F0
            case .blue: return 0xE2EAF2
            case .mint: return 0xE2EFEA
            case .lavender: return 0xE8E4F3
            case .butter: return 0xF1EEDF
            case .peach: return 0xF0E8E2
            }
        }
    }

    /// Bold accent for each tint.
    func bold(_ tint: PlayTint) -> UInt32 {
        switch tint {
        case .pink: return 0xFF5C8A
        case .blue: return 0x4F8DFF
        case .mint: return 0x12C9A5
        case .lavender: return 0x8B5CF6
        case .butter: return 0xFFB800
        case .peach: return 0xFF7A59
        }
    }

    var canvas: (top: UInt32, bottom: UInt32) {
        switch self {
        case .candy: return (0xFFF7FB, 0xF1F7FF)
        case .ocean: return (0xF1FAFF, 0xF0FBF7)
        case .sunset: return (0xFFF6EE, 0xFFF0F4)
        case .cloud: return (0xF8F8FB, 0xF3F4F8)
        }
    }
}

enum AccentID: String, CaseIterable, Identifiable {
    case coral, turquoise, yellow, violet, pink, blue, custom
    var id: String { rawValue }
    var hex: UInt32? {
        switch self {
        case .coral: return 0xFF6B5E
        case .turquoise: return 0x10C4B6
        case .yellow: return 0xFFBE0B
        case .violet: return 0x8B5CF6
        case .pink: return 0xFF5C9D
        case .blue: return 0x3D7BFF
        case .custom: return nil
        }
    }
    var label: String { rawValue.capitalized }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CornerStyle: String, CaseIterable, Identifiable {
    case crisp, soft, bubbly
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scale: CGFloat { self == .crisp ? 0.45 : self == .soft ? 1 : 1.5 }
}

enum DensityStyle: String, CaseIterable, Identifiable {
    case compact, cozy, roomy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scale: CGFloat { self == .compact ? 0.78 : self == .cozy ? 1 : 1.25 }
}

enum FontStyle: String, CaseIterable, Identifiable {
    case rounded, standard, serif, mono
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .standard: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

/// The look of the whole app. Everything reads from here, and every option is saved.
@MainActor
final class Theme: ObservableObject {
    static let shared = Theme()

    @Published var palette: PaletteID { didSet { save() } }
    @Published var accentID: AccentID { didSet { save() } }
    @Published var customAccent: Color { didSet { save() } }
    @Published var appearance: AppearanceMode { didSet { save() } }
    @Published var corners: CornerStyle { didSet { save() } }
    @Published var density: DensityStyle { didSet { save() } }
    @Published var fontStyle: FontStyle { didSet { save() } }
    @Published var animations: Bool { didSet { save() } }
    @Published var shapes: Bool { didSet { save() } }
    @Published var sidebar: Bool { didSet { save() } }

    private let d = UserDefaults.standard
    private var loading = true

    private init() {
        let d = UserDefaults.standard
        palette = PaletteID(rawValue: d.string(forKey: "theme.palette") ?? "") ?? .candy
        accentID = AccentID(rawValue: d.string(forKey: "theme.accent") ?? "") ?? .coral
        let rgb = d.array(forKey: "theme.customAccent") as? [Double] ?? [0.55, 0.36, 0.96]
        customAccent = Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
        appearance = AppearanceMode(rawValue: d.string(forKey: "theme.appearance") ?? "") ?? .system
        corners = CornerStyle(rawValue: d.string(forKey: "theme.corners") ?? "") ?? .soft
        density = DensityStyle(rawValue: d.string(forKey: "theme.density") ?? "") ?? .cozy
        fontStyle = FontStyle(rawValue: d.string(forKey: "theme.font") ?? "") ?? .rounded
        animations = d.object(forKey: "theme.animations") as? Bool ?? true
        shapes = d.object(forKey: "theme.shapes") as? Bool ?? true
        sidebar = d.object(forKey: "theme.sidebar") as? Bool ?? true
        loading = false
    }

    private func save() {
        guard !loading else { return }
        d.set(palette.rawValue, forKey: "theme.palette")
        d.set(accentID.rawValue, forKey: "theme.accent")
        if let c = NSColor(customAccent).usingColorSpace(.sRGB) {
            d.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: "theme.customAccent")
        }
        d.set(appearance.rawValue, forKey: "theme.appearance")
        d.set(corners.rawValue, forKey: "theme.corners")
        d.set(density.rawValue, forKey: "theme.density")
        d.set(fontStyle.rawValue, forKey: "theme.font")
        d.set(animations, forKey: "theme.animations")
        d.set(shapes, forKey: "theme.shapes")
        d.set(sidebar, forKey: "theme.sidebar")
    }

    func resetToDefaults() {
        palette = .candy; accentID = .coral; appearance = .system; corners = .soft; density = .cozy
        fontStyle = .rounded; animations = true; shapes = true; sidebar = true
    }

    // MARK: Colours

    func soft(_ tint: PlayTint) -> Color {
        let base = Color(hex: palette.soft(tint))
        return Color(light: base, dark: base.opacity(0.22))
    }
    func bold(_ tint: PlayTint) -> Color { Color(hex: palette.bold(tint)) }

    var accent: Color { accentID == .custom ? customAccent : Color(hex: accentID.hex ?? 0xFF6B5E) }
    var canvasTop: Color { Color(light: Color(hex: palette.canvas.top), dark: Color(hex: 0x16131F)) }
    var canvasBottom: Color { Color(light: Color(hex: palette.canvas.bottom), dark: Color(hex: 0x1B1827)) }
    var card: Color { Color(light: .white.opacity(0.82), dark: Color.white.opacity(0.07)) }
    var cardStroke: Color { Color(light: Color(hex: 0x2A2733, opacity: 0.07), dark: .white.opacity(0.10)) }
    var ink: Color { Color(light: Color(hex: 0x2A2733), dark: Color(hex: 0xF3F0FA)) }
    var inkSoft: Color { Color(light: Color(hex: 0x2A2733, opacity: 0.62), dark: Color(hex: 0xF3F0FA, opacity: 0.62)) }
    var shadow: Color { Color(light: Color(hex: 0x6B5B95, opacity: 0.14), dark: .black.opacity(0.35)) }

    // MARK: Shape and motion

    func radius(_ base: CGFloat) -> CGFloat { base * corners.scale }
    func space(_ base: CGFloat) -> CGFloat { base * density.scale }
    var font: Font.Design { fontStyle.design }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The standard gentle spring; instant when animations are off or "Reduce motion" is on.
    var spring: Animation? {
        guard animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        return .spring(response: 0.42, dampingFraction: 0.78)
    }
}
