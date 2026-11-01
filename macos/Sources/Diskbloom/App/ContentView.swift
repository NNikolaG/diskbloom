import AppKit
import QuickLook
import SwiftUI

/// The window: sidebar with disks and folders, and the detail area for the current phase.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            VolumesSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            VStack(spacing: 0) {
                detail
                if model.phase == .ready { CollectorBar() }
            }
            .toolbar { toolbar }
        }
        .sheet(isPresented: $model.showCleaner) { CleanerView().environmentObject(model) }
        .quickLookPreview($model.previewURL)
        .alert("Diskbloom", isPresented: $model.isShowingAlert) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .idle:
            if let place = model.selected {
                PlaceOverview(place: place)
            } else {
                ContentUnavailable(title: "Diskbloom", message: "Choose a disk or folder on the left.",
                                   symbol: "circle.hexagongrid")
            }
        case .scanning(let path, let scanned):
            ScanningView(path: path, scanned: scanned)
        case .failed(let message):
            ContentUnavailable(title: "Something went wrong", verbatim: message, symbol: "exclamationmark.triangle")
        case .ready:
            ResultView()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.phase == .ready {
                Picker("View", selection: $model.resultMode) {
                    Label("Map", systemImage: "chart.pie").tag(ResultMode.map)
                    Label("Largest files", systemImage: "list.number").tag(ResultMode.largest)
                    Label("Duplicates", systemImage: "doc.on.doc").tag(ResultMode.duplicates)
                }
                .pickerStyle(.segmented)
                .help("Map, largest files or duplicates")
                Button { model.showOverview() } label: { Label("Disk overview", systemImage: "square.grid.2x2") }
                    .help("Back to the overview and actions for this disk")
                Button { model.zoomOut() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(model.crumbs.count < 2 || model.resultMode != .map)
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Rescan only this folder")
                    .disabled(model.refreshing)
                Button { model.showCleaner = true } label: { Label("Smart Clean", systemImage: "sparkles") }
            }
            Button { chooseFolder() } label: { Label("Choose folder", systemImage: "folder") }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Scan")
        if panel.runModal() == .OK, let url = panel.url { model.scan(url) }
    }
}
