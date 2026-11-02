import AppKit
import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// The sunburst map. Rust computes the layout; this view draws it and handles the pointer.
struct SunburstView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let geometry = SunburstGeometry(size: proxy.size, rings: AppModel.rings)
            ZStack {
                Canvas { context, _ in draw(in: &context, geometry: geometry) }
                centerLabel
                    .frame(width: geometry.inner * 1.55, height: geometry.inner * 1.4)
                    .position(geometry.center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in hover(phase, geometry: geometry) }
            .onTapGesture(coordinateSpace: .local) { location in
                switch geometry.hit(location, in: model.segments) {
                case .center: model.zoomOut()
                case .segment(let segment): model.open(segment)
                case .none: break
                }
            }
            .contextMenu { contextMenu }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Disk map"))
        .accessibilityValue(Text(verbatim: model.focusInfo.map { "\(model.title($0)), \(Format.bytes($0.size))" } ?? ""))
    }

    private func draw(in context: inout GraphicsContext, geometry: SunburstGeometry) {
        let separator = Color(nsColor: .windowBackgroundColor)
        // Segments come parent first, so one pass knows whether an ancestor is queued.
        var dimmed: Set<UInt32> = model.isCollected(model.focus) ? [model.focus] : model.collectedIDs
        for segment in model.segments {
            let path = geometry.path(segment)
            let queued = dimmed.contains(segment.parent) || segment.id.map(dimmed.contains) == true
            if queued, let id = segment.id { dimmed.insert(id) }
            let color = Palette.color(segment, highlighted: model.hovered == segment)
            context.fill(path, with: .color(queued ? color.opacity(0.22) : color))
            context.stroke(path, with: .color(separator), lineWidth: 0.8)
        }
        context.fill(geometry.centerDisc, with: .color(Color(nsColor: .controlBackgroundColor)))
    }

    private func hover(_ phase: HoverPhase, geometry: SunburstGeometry) {
        guard case .active(let location) = phase,
              case .segment(let segment) = geometry.hit(location, in: model.segments)
        else {
            if model.hovered != nil { model.hovered = nil }
            return
        }
        if model.hovered != segment {
            model.hovered = segment
            if let id = segment.id { model.lastHoveredID = id }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if let id = model.hovered?.id {
            Button(model.collectedIDs.contains(id) ? LocalizedStringKey("Remove from Trash list") : "Add to Trash list") {
                model.toggleCollect(id)
            }
            Button("Quick Look") { model.quickLook(id) }
            Button("Show in Finder") { model.revealInFinder(id) }
        }
    }

    @ViewBuilder private var centerLabel: some View {
        let hovered = model.hovered
        let name = hovered?.name ?? model.focusInfo.map(model.title) ?? ""
        let size = hovered?.size ?? model.focusInfo?.size ?? 0
        VStack(spacing: 4) {
            Text(name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Text(Format.bytes(size))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Group {
                if let hovered, let focus = model.focusInfo {
                    Text("\(Format.percent(hovered.size, of: focus.size)) of \(model.title(focus))")
                } else if model.crumbs.count > 1 {
                    Text("\(Format.percent(size, of: model.rootSize)) of \(model.rootTitle)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if hovered == nil, model.crumbs.count > 1 {
                Text("click to go back")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
