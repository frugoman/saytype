import Sparkle
import SwiftUI

@main
struct SayTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(updater: appDelegate.updater.updater)
                .environmentObject(controller)
                .environmentObject(controller.focus)
                .environmentObject(LicenseManager.shared)
        } label: {
            MenuBarIcon(status: controller.status)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: appDelegate.updater.updater)
                .environmentObject(controller)
                .environmentObject(controller.vocabulary)
                .environmentObject(LicenseManager.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    /// Sparkle: checks the appcast daily and installs signed updates.
    private(set) lazy var updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)

    // Menu bar apps show update notices without stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        if !OnboardingWindow.isComplete || AppController.shared.needsSetup {
            OnboardingWindow.shared.show()
        }
    }
}

struct MenuBarIcon: View {
    let status: AppController.Status

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch status {
        case .loading: return "arrow.down.circle"
        case .idle: return "mic"
        case .listening: return "mic.fill"
        case .hearing, .transcribing: return "waveform"
        case .speaking: return "speaker.wave.2.fill"
        case .disabled: return "mic.slash"
        case .needsMicPermission, .needsAccessibility, .error, .trialExpired: return "exclamationmark.triangle"
        }
    }
}
