import SwiftUI

/// Context menu for a disk or folder in the sidebar.
struct PlaceMenu: View {
    @EnvironmentObject private var model: AppModel
    let place: Place
    let ejectable: Bool

    var body: some View {
        Button("Scan") { model.scan(place) }
        Button("Smart Clean") { model.scan(place, clean: true) }
        Divider()
        Button("Show in Finder") { model.revealInFinder(url: place.url) }
        if ejectable {
            Button("Eject") { model.eject(place) }
        }
    }
}
