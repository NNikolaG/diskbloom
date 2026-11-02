import AppKit
import SwiftUI

/// The window under the menu bar item: every disk with its free space, and shortcuts
/// into the app.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    let status: DiskStatus
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(status.volumes) { volume in
                Button { show { model.showOverview(of: volume.place) } } label: {
                    VolumeUsageRow(volume: volume)
                }
                .help("Show this disk in Diskbloom")
            }
            Divider().padding(.vertical, 4)
            Button { show {} } label: { Label("Open Diskbloom", systemImage: "macwindow") }
            Button { show { model.scanHome() } } label: { Label("Scan Home", systemImage: "house") }
                .disabled(model.isScanning)
            Button { show { model.startSmartClean() } } label: { Label("Smart Clean", systemImage: "sparkles") }
                .disabled(model.isScanning)
            Divider().padding(.vertical, 4)
            settingsButton
            Button { NSApp.terminate(nil) } label: { Label("Quit Diskbloom", systemImage: "power") }
                .keyboardShortcut("q")
        }
        .buttonStyle(MenuRowStyle())
        .padding(8)
        .frame(width: 290)
        .onAppear {
            MainWindow.rememberOpener(openWindow)
            status.refresh()
        }
    }

    @ViewBuilder private var settingsButton: some View {
        let label = Label("Settings…", systemImage: "gearshape")
        if #available(macOS 14, *) {
            SettingsLink { label }
                .simultaneousGesture(TapGesture().onEnded { close(activating: true) })
        } else {
            Button {
                close(activating: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: { label }
        }
    }

    /// Runs `action` on the model, then brings the main window forward.
    private func show(_ action: () -> Void) {
        action()
        close(activating: false)
        MainWindow.show(using: openWindow)
    }

    private func close(activating: Bool) {
        dismiss()
        if activating { NSApp.activate(ignoringOtherApps: true) }
    }
}
