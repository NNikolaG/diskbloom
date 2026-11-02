import Foundation

/// Entry points used from outside the main window: the menu bar item and the low-space
/// notification. None of them interrupts a scan that is already running.
extension AppModel {
    /// Shows the overview of a disk (with its actions) in the main window.
    func showOverview(of place: Place) {
        guard !isScanning else { return }
        select(place)
        showOverview()
    }

    /// Smart Clean for the current scan, or after scanning Home when there is none yet
    /// (Home holds nearly everything Smart Clean looks for, and is quicker than the disk).
    func startSmartClean() {
        guard !isScanning else { return }
        if tree != nil {
            showCleaner = true
        } else {
            scan(.home, clean: true)
        }
    }

    func scanHome() {
        guard !isScanning else { return }
        scan(.home)
    }
}
