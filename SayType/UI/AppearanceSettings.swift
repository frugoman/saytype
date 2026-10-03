import SwiftUI

/// Colours, shapes, type and layout, all changeable, with a live preview.
struct AppearanceSettings: View {
    @ObservedObject private var theme = Theme.shared
    @State private var previewOn = true

    var body: some View {
        PlayPage {
            PlaySection("Preview", tint: .pink) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            PlayChip(text: "Listening", tint: .mint, icon: "mic.fill")
                            PlayChip(text: "Typing", tint: .blue)
                            PlayChip(text: "Off", tint: .butter)
                        }
                        Toggle("Looks like this", isOn: $previewOn)
                        HStack {
                            Button("Soft button") {}
                            Button("Primary") {}.buttonStyle(.playPrimary)
                        }
                    }
                    Spacer()
                    ZStack {
                        Circle().fill(theme.soft(.pink)).frame(width: 84, height: 84)
                        Circle().strokeBorder(theme.accent, lineWidth: 3).frame(width: 84, height: 84)
                            .scaleEffect(previewOn ? 1.08 : 0.92).opacity(previewOn ? 1 : 0.4)
                        Image(systemName: "mic.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(theme.accent)
                    }
                    .animation(theme.spring, value: previewOn)
                }
            }

            PlaySection("Colours", tint: .lavender) {
                Text("Palette").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) {
                    ForEach(PaletteID.allCases) { palette in
                        let selected = theme.palette == palette
                        Button {
                            withAnimation(theme.spring) { theme.palette = palette }
                        } label: {
                            VStack(spacing: 7) {
                                HStack(spacing: -6) {
                                    ForEach([PlayTint.pink, .blue, .mint, .butter], id: \.self) { t in
                                        Circle().fill(Color(hex: palette.soft(t)))
                                            .frame(width: 22, height: 22)
                                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                                    }
                                }
                                Text(palette.label).font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous)
                                .fill(selected ? theme.accent.opacity(0.12) : theme.ink.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: theme.radius(16), style: .continuous)
                                .strokeBorder(selected ? theme.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Accent").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach(AccentID.allCases.filter { $0 != .custom }) { accent in
                        let color = Color(hex: accent.hex ?? 0)
                        Button {
                            withAnimation(theme.spring) { theme.accentID = accent }
                        } label: {
                            Circle().fill(color).frame(width: 30, height: 30)
                                .overlay {
                                    if theme.accentID == accent {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                                            .transition(.scale)
                                    }
                                }
                                .scaleEffect(theme.accentID == accent ? 1.12 : 1)
                        }
                        .buttonStyle(.plain)
                        .help(accent.label)
                    }
                    ColorPicker("", selection: Binding(get: { theme.customAccent },
                                                       set: { theme.customAccent = $0; theme.accentID = .custom }),
                                supportsOpacity: false)
                        .labelsHidden()
                        .help("Pick any colour")
                }

                Text("Mode").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                PlaySegmented(selection: $theme.appearance, options: AppearanceMode.allCases.map { ($0, $0.label) })
            }

            PlaySection("Shape and type", tint: .butter) {
                LabeledContent("Corners") {
                    PlaySegmented(selection: $theme.corners, options: CornerStyle.allCases.map { ($0, $0.label) })
                }
                LabeledContent("Spacing") {
                    PlaySegmented(selection: $theme.density, options: DensityStyle.allCases.map { ($0, $0.label) })
                }
                LabeledContent("Font") {
                    PlaySegmented(selection: $theme.fontStyle, options: FontStyle.allCases.map { ($0, $0.label) })
                }
            }

            PlaySection("Layout and motion", tint: .mint) {
                Toggle("Sidebar on the left (off puts tabs along the top)", isOn: $theme.sidebar)
                Toggle("Floating shapes in the background", isOn: $theme.shapes)
                Toggle("Animations", isOn: $theme.animations)
            } footer: {
                Text("Animations also turn off automatically when macOS \"Reduce motion\" is on.")
            }

            HStack {
                Spacer()
                Button("Reset to the default look") { withAnimation(theme.spring) { theme.resetToDefaults() } }
            }
        }
    }
}
