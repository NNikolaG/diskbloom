import SwiftUI

/// Disk usage ring: used (accent) and purgeable (orange).
struct UsageRing: View {
    let used: Double
    let purgeable: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: used)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if purgeable > 0.002 {
                Circle()
                    .trim(from: used, to: min(1, used + purgeable))
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(used.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title.bold().monospacedDigit())
                Text("used").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
