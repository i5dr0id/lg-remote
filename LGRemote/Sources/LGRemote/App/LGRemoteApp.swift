import AppKit
import ServiceManagement
import SwiftUI

struct LGRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = TVModel.shared

    var body: some Scene {
        Window("LG Remote", id: WindowID.remote) {
            RemoteView()
                .environment(model)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Prefs.startHidden ? .suppressed : .presented)

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: "av.remote.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum WindowID {
    static let remote = "remote"
}

enum Prefs {
    static let showInDockKey = "showInDock"
    static let openOnLaunchKey = "openOnLaunch"

    static let launchedInBackground = CommandLine.arguments.contains("--background")

    static var showInDock: Bool {
        UserDefaults.standard.object(forKey: showInDockKey) as? Bool ?? true
    }

    static var startHidden: Bool {
        launchedInBackground || SMAppService.mainApp.status == .enabled && wasLaunchedAsLoginItem
            || !(UserDefaults.standard.object(forKey: openOnLaunchKey) as? Bool ?? true)
    }

    /// Login items are launched without a user-initiated "open" Apple Event.
    private static var wasLaunchedAsLoginItem: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    @MainActor
    static func applyDockPolicy() {
        let regular = showInDock && !launchedInBackground
        NSApp.setActivationPolicy(regular ? .regular : .accessory)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.applyDockPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await TVModel.shared.connect() }
    }

    // Closing the remote keeps the app alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
