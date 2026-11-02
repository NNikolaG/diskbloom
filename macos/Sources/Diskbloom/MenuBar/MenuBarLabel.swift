import DiskbloomKit
import SwiftUI

/// The menu bar item itself: a disk symbol and the startup disk's free space ("84 GB").
struct MenuBarLabel: View {
    @ObservedObject var status: DiskStatus

    var body: some View {
        if let boot = status.boot {
            let free = Format.shortBytes(boot.free)
            Label(free, systemImage: "internaldrive")
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(Text("\(Format.bytes(UInt64(clamping: boot.free))) free on \(boot.name)"))
        } else {
            Image(systemName: "internaldrive")
                .accessibilityLabel(Text(verbatim: "Diskbloom"))
        }
    }
}
