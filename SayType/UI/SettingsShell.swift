import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, voice, vocabulary, commands, apps, ai, history, speak, automation, appearance, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .voice: return "Voice → Text"
        case .vocabulary: return "Vocabulary"
        case .commands: return "Commands"
        case .apps: return "Apps"
        case .ai: return "AI"
        case .history: return "History"
        case .speak: return "Text → Voice"
        case .automation: return "Automation"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .voice: return "waveform"
        case .vocabulary: return "character.book.closed.fill"
        case .commands: return "text.badge.plus"
        case .apps: return "square.grid.2x2.fill"
        case .ai: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        case .speak: return "speaker.wave.2.fill"
        case .automation: return "terminal.fill"
        case .appearance: return "paintpalette.fill"
        case .about: return "heart.fill"
        }
    }

    var tint: PlayTint {
        switch self {
        case .general: return .blue
        case .voice: return .mint
        case .vocabulary: return .butter
        case .commands: return .lavender
        case .apps: return .peach
        case .ai: return .pink
        case .history: return .blue
        case .speak: return .mint
        case .automation: return .lavender
        case .appearance: return .pink
        case .about: return .peach
        }
    }

    static let groups: [(title: String, panes: [SettingsPane])] = [
        ("Dictation", [.general, .voice, .vocabulary, .commands, .apps, .ai, .history]),
        ("More", [.speak, .automation]),
        ("This app", [.appearance, .about]),
    ]
}

/// The settings window: a colourful sidebar and a page of cards.
struct SettingsView: View {
    @ObservedObject private var theme = Theme.shared
    @AppStorage("settings.pane") private var paneID = SettingsPane.general.rawValue
    @Namespace private var highlight

    private var pane: SettingsPane { SettingsPane(rawValue: paneID) ?? .general }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayBackdrop()
            HStack(spacing: 0) {
                sidebar
                content
            }
            SaveIndicator().padding(14)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 580, idealHeight: 640)
        .playStyle()
    }

    private var content: some View {
        Group {
            switch pane {
            case .general: GeneralSettings()
            case .voice: SpeechToTextSettings()
            case .vocabulary: VocabularySettings()
            case .commands: CommandsSettings()
            case .apps: ProfileSettings()
            case .ai: AISettings()
            case .history: HistorySettings()
            case .speak: TextToSpeechSettings()
            case .automation: AutomationSettings()
            case .appearance: AppearanceSettings()
            case .about: AboutSettings()
            }
        }
        .id(pane)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func select(_ pane: SettingsPane) {
        withAnimation(theme.spring) { paneID = pane.rawValue }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space(16)) {
                HStack(spacing: 9) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 26)).foregroundStyle(theme.accent)
                    Text("SayType").font(.system(size: 19, weight: .heavy))
                }
                .padding(.horizontal, 10).padding(.top, 6)

                ForEach(SettingsPane.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title.uppercased())
                            .font(.system(size: 10.5, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(theme.inkSoft).padding(.horizontal, 10).padding(.bottom, 2)
                        ForEach(group.panes) { row($0) }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 208)
        .background(theme.canvasTop.opacity(0.94))
        .background(theme.card.opacity(0.6))
        .overlay(alignment: .trailing) { Rectangle().fill(theme.cardStroke).frame(width: 1) }
    }

    private func row(_ p: SettingsPane) -> some View {
        let selected = p == pane
        return Button { select(p) } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(selected ? Color.white : theme.bold(p.tint))
                    .frame(width: 27, height: 27)
                    .background(RoundedRectangle(cornerRadius: theme.radius(9), style: .continuous)
                        .fill(selected ? theme.bold(p.tint) : theme.soft(p.tint)))
                Text(p.title).font(.system(size: 13.5, weight: selected ? .bold : .medium))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: theme.radius(13), style: .continuous)
                        .fill(theme.soft(p.tint).opacity(0.9))
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
