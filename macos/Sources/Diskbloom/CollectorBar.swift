import AppKit
import DiskbloomFFI
import SwiftUI

/// Korpa za brisanje (kao Collector u DaisyDisk-u): skupljas stavke dok pregledas disk,
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
                Text("Za brisanje").font(.headline)
                if model.collector.isEmpty {
                    Text("Prevuci folder ovde ili klikni 🗑 pored stavke u listi")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(model.collector.count) stavki · \(Fmt.bytes(model.collectorTotal))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.collector.isEmpty {
                    Button("Isprazni") { model.collector = [] }
                    if let p = model.trashProgress {
                        ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 120)
                    }
                    Button("Premesti u Trash…") { confirm = true }
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
        .confirmationDialog("Premestiti \(model.collector.count) stavki (\(Fmt.bytes(model.collectorTotal))) u Trash?",
                            isPresented: $confirm) {
            Button("Premesti u Trash", role: .destructive) { model.trashCollector() }
        } message: {
            Text("Stavke mozes vratiti iz Trash-a dok ga ne ispraznis.")
        }
    }
}
