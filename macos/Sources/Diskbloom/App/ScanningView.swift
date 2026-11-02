import DiskbloomKit
import SwiftUI

/// Progress while a scan runs: the map fills in as top-level folders finish.
struct ScanningView: View {
    @Environment(AppModel.self) private var model
    let path: String
    let scanned: UInt64

    var body: some View {
        VStack(spacing: 16) {
            ScanPreview(segments: model.scanPreview)
                .frame(width: 300, height: 300)
            Text("Scanning \(path)").font(.headline)
            Text("\(Format.count(scanned)) items")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Cancel") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
