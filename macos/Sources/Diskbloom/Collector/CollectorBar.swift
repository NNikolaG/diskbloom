import AppKit
import DiskbloomKit
import SwiftUI

/// The Trash list: collect items while browsing, see the total, then move everything to
/// the Trash at once. Always visible so items can be dragged onto it.
struct CollectorBar: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirm = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summary
            if !model.collector.isEmpty { chips }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(targeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap({ UInt32($0) }) { model.collect(id) }
            return true
        } isTargeted: { targeted = $0 }
        .confirmationDialog("Move \(Format.count(model.collector.count)) items (\(Format.bytes(model.collectorTotal))) to the Trash?",
                            isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { model.trashCollector() }
        } message: {
            Text("You can put items back from the Trash until you empty it.")
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: model.collector.isEmpty ? "trash" : "trash.fill")
                .foregroundStyle(model.collector.isEmpty ? Color.secondary : Color.red)
                .accessibilityHidden(true)
            Text("Trash list").font(.headline)
            if model.collector.isEmpty {
                Text("Drag items here, or click 🗑 next to any item")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(Format.count(model.collector.count)) items · \(Format.bytes(model.collectorTotal))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.collector.isEmpty {
                Button("Clear") { model.collector = [] }
                if let progress = model.trashProgress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 120)
                }
                Button("Move to Trash…") { confirm = true }
                    .disabled(model.trashProgress != nil)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(model.collector) { item in
                    HStack(spacing: 4) {
                        Text(item.name).lineLimit(1)
                        Text(Format.bytes(item.size)).foregroundStyle(.secondary)
                        IconButton(symbol: "xmark.circle.fill", label: "Remove from Trash list") {
                            model.uncollect(item.id)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .help(item.path)
                }
            }
        }
    }
}
