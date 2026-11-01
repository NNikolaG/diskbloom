import DiskbloomKit
import SwiftUI

/// Progress while a scan runs.
struct ScanningView: View {
    @EnvironmentObject private var model: AppModel
    let path: String
    let scanned: UInt64

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning \(path)").font(.headline)
            Text("\(Format.count(scanned)) items")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Cancel") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
