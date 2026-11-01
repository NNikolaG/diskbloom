import SwiftUI

/// Scan results in the selected mode.
struct ResultView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.inaccessible > 0 { AccessBanner() }
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
            }
        }
    }
}
