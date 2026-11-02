import AppKit
import SwiftUI

@main
struct DiskbloomApp: App {
    @StateObject private var model: AppModel
    /// Free space for the menu bar item and the low-space notification.
    @StateObject private var diskStatus: DiskStatus
    @AppStorage(AppSettings.showMenuBarExtraKey) private var showMenuBarExtra = true

    init() {
        // Needed when started as a bare binary (`swift run`) outside an .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Created here so the notification handler is ready even when a click on the
        // notification is what launched the app.
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        _diskStatus = StateObject(wrappedValue: DiskStatus { [weak model] in
            model?.showOverview(of: .bootVolume)
            MainWindow.show()
        })
    }

    var body: some Scene {
        WindowGroup(id: MainWindow.id) {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { model.applyLaunchOptions() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarContent(status: diskStatus)
                .environmentObject(model)
        } label: {
            MenuBarLabel(status: diskStatus)
        }
        .menuBarExtraStyle(.window)
    }
}
