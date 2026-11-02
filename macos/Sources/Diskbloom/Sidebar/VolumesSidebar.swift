import AppKit
import SwiftUI

/// Mounted disks and common folders. Selecting one shows its overview.
struct VolumesSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var volumes = MountedVolume.all()

    private static let folders: [Place] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            .home,
            .folder(home.appendingPathComponent("Desktop"), name: "Desktop", icon: "menubar.dock.rectangle"),
            .folder(home.appendingPathComponent("Documents"), name: "Documents", icon: "doc.text"),
            .folder(home.appendingPathComponent("Downloads"), name: "Downloads", icon: "arrow.down.circle"),
            .folder(home.appendingPathComponent("Library"), name: "Library", icon: "building.columns"),
            .folder(URL(fileURLWithPath: "/Applications"), name: "Applications", icon: "square.grid.2x2"),
        ]
    }()

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section("Disks") {
                ForEach(volumes) { volume in
                    VolumeRow(volume: volume)
                        .tag(volume.place)
                        .contextMenu { PlaceMenu(place: volume.place, ejectable: volume.isEjectable) }
                }
            }
            Section("Folders") {
                ForEach(Self.folders) { folder in
                    Label(folder.name, systemImage: folder.icon)
                        .tag(folder)
                        .contextMenu { PlaceMenu(place: folder, ejectable: false) }
                }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = MountedVolume.all()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = MountedVolume.all()
        }
    }
}
