import AppKit
import SwiftUI

// MARK: - Applying the theme to a window

extension View {
    /// Gives a view the app's look: colours, rounded type, pill switches, soft buttons and fields.
    /// Apply it once at the root of every window and popover.
    func playStyle() -> some View { modifier(PlayStyleModifier()) }

    /// Animates a change with the gentle spring, unless animations are off.
    func playAnimation<V: Equatable>(value: V) -> some View {
        modifier(PlayAnimationModifier(value: value))
    }
}

private struct PlayStyleModifier: ViewModifier {
    @ObservedObject private var theme = Theme.shared

    func body(content: Content) -> some View {
        content
            .fontDesign(theme.font)
            .foregroundStyle(theme.ink)
            .tint(theme.accent)
            .toggleStyle(PlayToggleStyle())
            .buttonStyle(PlayButtonStyle())
            .textFieldStyle(PlayFieldStyle())
            .preferredColorScheme(theme.colorScheme)
    }
}

private struct PlayAnimationModifier<V: Equatable>: ViewModifier {
    @ObservedObject private var theme = Theme.shared
    let value: V
    func body(content: Content) -> some View { content.animation(theme.spring, value: value) }
}

// MARK: - Page and sections

/// A scrolling page of cards. Use it where a `Form` was used.
struct PlayPage<Content: View>: View {
    @ObservedObject private var theme = Theme.shared
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space(18)) { content }
                .padding(.horizontal, theme.space(26))
                .padding(.vertical, theme.space(22))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}

/// A rounded pastel card with an optional title and footnote. Drop-in for `Section`.
struct PlaySection<Content: View, Header: View, Footer: View>: View {
    @ObservedObject private var theme = Theme.shared
    let tint: PlayTint?
    let title: String?
    let content: Content
    let header: Header
    let footer: Footer

    private var resolvedTint: PlayTint { tint ?? .auto(for: title ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space(9)) {
            if title != nil || Header.self != EmptyView.self {
                HStack(spacing: 8) {
                    Circle().fill(theme.bold(resolvedTint)).frame(width: 9, height: 9)
                    if let title { Text(title) } else { header }
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(theme.inkSoft)
                .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: theme.space(13)) { content }
                .padding(theme.space(17))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: theme.radius(22), style: .continuous)
                        .fill(LinearGradient(colors: [theme.soft(resolvedTint).opacity(0.55), theme.card],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .background(
                    RoundedRectangle(cornerRadius: theme.radius(22), style: .continuous).fill(theme.card)
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: theme.radius(22), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(22), style: .continuous).strokeBorder(theme.cardStroke)
                )
                .shadow(color: theme.shadow, radius: 14, y: 5)

            if Footer.self != EmptyView.self {
                footer
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                                removal: .opacity))
    }
}

extension PlaySection where Header == EmptyView, Footer == EmptyView {
    init(_ title: String? = nil, tint: PlayTint? = nil, @ViewBuilder content: () -> Content) {
        self.init(tint: tint, title: title, content: content(), header: EmptyView(), footer: EmptyView())
    }
    init(tint: PlayTint? = nil, @ViewBuilder content: () -> Content) {
        self.init(tint: tint, title: nil, content: content(), header: EmptyView(), footer: EmptyView())
    }
}

extension PlaySection where Footer == EmptyView {
    init(tint: PlayTint? = nil, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(tint: tint, title: nil, content: content(), header: header(), footer: EmptyView())
    }
}

extension PlaySection where Header == EmptyView {
    init(tint: PlayTint? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(tint: tint, title: nil, content: content(), header: EmptyView(), footer: footer())
    }
    init(_ title: String, tint: PlayTint? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(tint: tint, title: title, content: content(), header: EmptyView(), footer: footer())
    }
}

extension PlaySection {
    init(tint: PlayTint? = nil, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.init(tint: tint, title: nil, content: content(), header: header(), footer: footer())
    }
}

// MARK: - Controls

struct PlayToggleStyle: ToggleStyle {
    @ObservedObject private var theme = Theme.shared

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(theme.spring) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? theme.accent : theme.ink.opacity(0.14))
                    Circle().fill(.white).padding(3)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
                .frame(width: 44, height: 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

enum PlayButtonKind { case soft, primary, plain }

struct PlayButtonStyle: ButtonStyle {
    var kind: PlayButtonKind = .soft
    @ObservedObject private var theme = Theme.shared
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        let fill: Color = kind == .primary ? (destructive ? theme.bold(.pink) : theme.accent)
            : theme.ink.opacity(configuration.isPressed ? 0.14 : 0.07)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.white : (destructive ? theme.bold(.pink) : theme.ink))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(fill))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PlayButtonStyle {
    static var playPrimary: PlayButtonStyle { PlayButtonStyle(kind: .primary) }
}

struct PlayFieldStyle: TextFieldStyle {
    @ObservedObject private var theme = Theme.shared

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: theme.radius(12), style: .continuous).fill(theme.ink.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: theme.radius(12), style: .continuous).strokeBorder(theme.cardStroke))
    }
}

/// A row of pill options, e.g. Light / Dark / System.
struct PlaySegmented<Value: Hashable>: View {
    @ObservedObject private var theme = Theme.shared
    @Namespace private var pill
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(theme.spring) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .foregroundStyle(selection == option.value ? Color.white : theme.ink)
                        .background {
                            if selection == option.value {
                                Capsule().fill(theme.accent).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.ink.opacity(0.07)))
    }
}

/// Big selectable cards for a handful of choices (e.g. when SayType listens).
struct PlayChoiceGroup<Value: Hashable>: View {
    @ObservedObject private var theme = Theme.shared
    @Binding var selection: Value
    let options: [(value: Value, title: String, subtitle: String, icon: String, tint: PlayTint)]

    var body: some View {
        VStack(spacing: theme.space(8)) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button {
                    withAnimation(theme.spring) { selection = option.value }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.bold(option.tint))
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous).fill(theme.soft(option.tint)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title).font(.system(size: 14, weight: .semibold))
                            Text(option.subtitle).font(.system(size: 12)).foregroundStyle(theme.inkSoft)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(selected ? theme.accent : theme.ink.opacity(0.25))
                            .symbolEffect(.bounce, value: selected)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous)
                        .fill(selected ? theme.accent.opacity(0.10) : theme.ink.opacity(0.035)))
                    .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous)
                        .strokeBorder(selected ? theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A small coloured label.
struct PlayChip: View {
    @ObservedObject private var theme = Theme.shared
    let text: String
    var tint: PlayTint = .mint
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11.5, weight: .bold))
        }
        .foregroundStyle(theme.bold(tint))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(theme.soft(tint)))
    }
}

// MARK: - Backdrop with drifting shapes

struct PlayBackdrop: View {
    @ObservedObject private var theme = Theme.shared
    /// The menu-bar popover passes false: a continuously redrawn background there kept re-laying out the
    /// popover and made it wobble, and it burned CPU for a window that is open for a few seconds.
    var animated = true

    private struct Shape {
        enum Kind { case circle, ring, square, triangle, squiggle }
        let kind: Kind, tint: PlayTint, size: CGFloat, x: CGFloat, y: CGFloat, speed: Double, phase: Double
    }

    private static let shapes: [Shape] = [
        Shape(kind: .circle, tint: .pink, size: 150, x: 0.88, y: 0.08, speed: 0.35, phase: 0),
        Shape(kind: .ring, tint: .blue, size: 110, x: 0.12, y: 0.22, speed: 0.28, phase: 1.3),
        Shape(kind: .square, tint: .butter, size: 90, x: 0.93, y: 0.55, speed: 0.4, phase: 2.2),
        Shape(kind: .triangle, tint: .mint, size: 100, x: 0.06, y: 0.72, speed: 0.3, phase: 0.7),
        Shape(kind: .squiggle, tint: .lavender, size: 120, x: 0.7, y: 0.93, speed: 0.33, phase: 3.1),
        Shape(kind: .circle, tint: .peach, size: 70, x: 0.4, y: 0.04, speed: 0.45, phase: 4.0),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.canvasTop, theme.canvasBottom], startPoint: .top, endPoint: .bottom)
            if theme.shapes {
                TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !(animated && theme.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        for s in Self.shapes {
                            let dx = CGFloat(sin(t * s.speed + s.phase)) * 18
                            let dy = CGFloat(cos(t * s.speed * 0.8 + s.phase)) * 14
                            let center = CGPoint(x: s.x * size.width + dx, y: s.y * size.height + dy)
                            let rect = CGRect(x: center.x - s.size / 2, y: center.y - s.size / 2, width: s.size, height: s.size)
                            let color = theme.soft(s.tint).opacity(0.85)
                            switch s.kind {
                            case .circle: context.fill(Path(ellipseIn: rect), with: .color(color))
                            case .ring: context.stroke(Path(ellipseIn: rect.insetBy(dx: 8, dy: 8)), with: .color(color), lineWidth: 16)
                            case .square: context.fill(Path(roundedRect: rect, cornerRadius: s.size * 0.28), with: .color(color))
                            case .triangle:
                                var p = Path()
                                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                                p.closeSubpath()
                                context.fill(p.strokedPath(StrokeStyle(lineWidth: 14, lineJoin: .round)), with: .color(color))
                                context.fill(p, with: .color(color))
                            case .squiggle:
                                var p = Path()
                                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                                for i in 1...4 {
                                    let x = rect.minX + rect.width * CGFloat(i) / 4
                                    p.addQuadCurve(to: CGPoint(x: x, y: rect.midY),
                                                   control: CGPoint(x: x - rect.width / 8, y: rect.midY + (i % 2 == 0 ? 26 : -26)))
                                }
                                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            }
                        }
                    }
                }
                // Soft, blurred blobs: you can tell something is there without it pulling your eye.
                .blur(radius: 26)
                .opacity(theme.shapeStrength)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - "Saved" and "Applying" feedback

/// A little pill that confirms a setting was saved, and shows while a model or voice is being applied.
struct SaveIndicator: View {
    @ObservedObject private var theme = Theme.shared
    @ObservedObject private var controller = AppController.shared
    @State private var saved = false
    @State private var bounce = 0
    @State private var hideWork: DispatchWorkItem?
    @State private var armedAt = Date().addingTimeInterval(1.2)

    private var applying: String? {
        if case .loading(let fraction, _) = controller.status { return "Applying… \(Int(fraction * 100))%" }
        return nil
    }

    var body: some View {
        Group {
            if UISnapshot.active {
                EmptyView()
            } else if let applying {
                pill(icon: nil, text: applying, tint: .butter, spinner: true)
            } else if saved {
                pill(icon: "checkmark.circle.fill", text: "Saved", tint: .mint, spinner: false)
            }
        }
        .animation(theme.spring, value: saved)
        .animation(theme.spring, value: applying)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            guard Date() > armedAt else { return }
            flash()
        }
    }

    private func pill(icon: String?, text: String, tint: PlayTint, spinner: Bool) -> some View {
        HStack(spacing: 6) {
            if spinner { ProgressView().controlSize(.small) }
            if let icon {
                Image(systemName: icon).foregroundStyle(theme.bold(tint)).symbolEffect(.bounce, value: bounce)
            }
            Text(text).font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(theme.soft(tint)))
        .overlay(Capsule().strokeBorder(theme.bold(tint).opacity(0.35)))
        .shadow(color: theme.shadow, radius: 8, y: 3)
        .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
    }

    private func flash() {
        saved = true
        bounce += 1
        hideWork?.cancel()
        let work = DispatchWorkItem { saved = false }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
