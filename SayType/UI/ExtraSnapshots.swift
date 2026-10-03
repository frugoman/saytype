import SwiftUI

/// Extra screens to render in `--snapshot` mode (setup walkthrough, Transcribe window, overlays…).
@MainActor
enum ExtraSnapshots {
    static func items() -> [(name: String, view: AnyView, size: CGSize)] { [] }
}
