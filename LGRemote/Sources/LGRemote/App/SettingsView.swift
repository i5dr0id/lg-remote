import AppKit
import LGTVKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(TVModel.self) private var model
    @State private var host = ""
    @State private var mac = ""
    @AppStorage(Prefs.showInDockKey) private var showInDock = true
    @AppStorage(Prefs.openOnLaunchKey) private var openOnLaunch = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cliMessage: String?

    var body: some View {
        Form {
            Section("Television") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        StatusLight()
                        Text(model.statusText).foregroundStyle(.secondary)
                    }
                }
                TextField("IP address", text: $host, prompt: Text("192.168.1.100"))
                TextField("MAC address", text: $mac, prompt: Text("Needed to turn the TV on"))
                HStack {
                    Button("Save & Connect") { model.updateConfig(host: host, mac: mac) }
                        .keyboardShortcut(.defaultAction)
                    Button(model.isDiscovering ? "Searching…" : "Discover") { model.discover() }
                        .disabled(model.isDiscovering)
                    Spacer()
                    Button("Forget Pairing", role: .destructive) { model.forgetPairing() }
                        .disabled(model.config.clientKey == nil)
                }
                ForEach(model.discovered, id: \.host) { tv in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tv.name ?? "LG TV")
                            Text("\(tv.host)  \(tv.mac ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") {
                            model.use(tv)
                            host = tv.host
                            mac = tv.mac ?? mac
                        }
                    }
                }
            }

            Section("App") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { Prefs.applyDockPolicy() }
                Toggle("Open remote window on launch", isOn: $openOnLaunch)
                Toggle("Launch at login (runs in the menu bar)", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section("Command Line") {
                LabeledContent("Command") { Text("lgremote").monospaced() }
                HStack {
                    Button("Install `lgremote` Command") { cliMessage = installCLI() }
                    if let cliMessage { Text(cliMessage).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Run `lgremote help` in Terminal for all commands. The CLI and app share the same pairing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            host = model.config.host ?? ""
            mac = model.config.mac ?? ""
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.flash("Login item: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func installCLI() -> String {
        guard let exe = Bundle.main.executableURL else { return "Executable not found" }
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        let fm = FileManager.default
        for dir in candidates where fm.isWritableFile(atPath: dir) {
            let link = dir + "/lgremote"
            try? fm.removeItem(atPath: link)
            if (try? fm.createSymbolicLink(atPath: link, withDestinationPath: exe.path)) != nil {
                return "Installed at \(link)"
            }
        }
        return "No writable bin directory found"
    }
}
