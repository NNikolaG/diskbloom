import DiskbloomKit
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(AppSettings.showMenuBarExtraKey) private var showMenuBarExtra = true
    @AppStorage(AppSettings.notifyLowSpaceKey) private var notifyLowSpace = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Toggle(isOn: $showMenuBarExtra) {
                Text("Show free space in the menu bar")
                Text("All disks and quick actions are one click away.")
            }
            Toggle(isOn: $notifyLowSpace) {
                Text("Notify when the startup disk is almost full")
                thresholdDescription
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { MainWindow.rememberOpener(openWindow) }
    }

    private var thresholdDescription: Text {
        let alert = LowSpaceAlert()
        let share = alert.fraction.formatted(.percent.precision(.fractionLength(0)))
        let limit = Format.bytes(UInt64(alert.limit))
        return Text("When less than \(share) or \(limit) is free, whichever is smaller. macOS asks for permission before the first notification.")
    }
}
