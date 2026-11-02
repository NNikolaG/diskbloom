import SwiftUI

/// Scan results in the selected mode, or search results while the search field has text.
struct ResultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.inaccessible > 0 { AccessBanner() }
            if model.isSearching {
                SearchResultsView()
            } else {
                modeContent
            }
        }
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: Text("Search files and folders"))
        // Picking another view (toolbar or ⌘1–⌘4) leaves the search.
        .onChange(of: model.resultMode) { model.searchQuery = "" }
    }

    @ViewBuilder private var modeContent: some View {
        switch model.resultMode {
        case .map:
            // A plain HStack: HSplitView added up ideal widths and pushed content
            // out of the window.
            HStack(spacing: 0) {
                SunburstView()
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ChildrenList().frame(width: 340)
            }
        case .largest:
            LargestFilesView()
        case .duplicates:
            DuplicatesView()
        case .types:
            TypesView()
        }
    }
}
