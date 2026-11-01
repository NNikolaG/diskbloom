import AppKit
import DiskbloomFFI
import SwiftUI

/// Korpa za brisanje (Collector): skupljas stavke dok pregledas disk,
/// vidis ukupnu velicinu, pa sve saljes u Trash odjednom. Uvek je vidljiva da bi se
/// u nju moglo prevuci.
struct CollectorBar: View {
    @EnvironmentObject var model: AppModel
    @State private var confirm = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: model.collector.isEmpty ? "trash" : "trash.fill")
                    .foregroundStyle(model.collector.isEmpty ? Color.secondary : Color.red)
                Text("Trash list").font(.headline)
                if model.collector.isEmpty {
                    Text("Drag items here, or click 🗑 next to any item")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(Fmt.count(UInt64(model.collector.count))) items · \(Fmt.bytes(model.collectorTotal))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.collector.isEmpty {
                    Button("Clear") { model.collector = [] }
                    if let p = model.trashProgress {
                        ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 120)
                    }
                    Button("Move to Trash…") { confirm = true }
                        .disabled(model.trashProgress != nil)
                        .keyboardShortcut(.delete, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }
            if !model.collector.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.collector) { item in
                            HStack(spacing: 4) {
                                Text(item.name).lineLimit(1)
                                Text(Fmt.bytes(item.size)).foregroundStyle(.secondary)
                                Button { model.uncollect(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                            .help(item.path)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(targeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap({ UInt32($0) }) { model.collect(id) }
            return true
        } isTargeted: { targeted = $0 }
        .confirmationDialog("Move \(Fmt.count(UInt64(model.collector.count))) items (\(Fmt.bytes(model.collectorTotal))) to the Trash?",
                            isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { model.trashCollector() }
        } message: {
            Text("You can put items back from the Trash until you empty it.")
        }
    }
}
