import AppKit
import DiskbloomFFI
import SwiftUI

/// "Korpa" kao u DaisyDisk-u: skupljas stavke, vidis ukupnu velicinu, pa brises odjednom.
struct CollectorBar: View {
    @EnvironmentObject var model: AppModel
    @State private var confirm = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Collector", systemImage: "tray.full").font(.headline)
                Text("\(model.collector.count) stavki, \(Fmt.bytes(model.collectorTotal))").foregroundStyle(.secondary)
                Spacer()
                Button("Isprazni") { model.collector = [] }
                Button("Premesti u Trash…") { confirm = true }.keyboardShortcut(.delete, modifiers: .command)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(model.collector) { item in
                        HStack(spacing: 4) {
                            Text(item.name).lineLimit(1)
                            Text(Fmt.bytes(item.size)).foregroundStyle(.secondary)
                            Button { model.uncollect(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                        }
                        .font(.callout)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .help(item.path)
                    }
                }
            }
        }
        .padding(10)
        .background(targeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap({ UInt32($0) }) { model.collect(id) }
            return true
        } isTargeted: { targeted = $0 }
        .confirmationDialog("Premestiti \(model.collector.count) stavki (\(Fmt.bytes(model.collectorTotal))) u Trash?",
                            isPresented: $confirm) {
            Button("Premesti u Trash", role: .destructive) { model.trashCollector() }
        } message: {
            Text("Stavke mozes vratiti iz Trash-a dok ga ne ispraznis.")
        }
    }
}
