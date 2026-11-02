import Foundation

/// Environment variables used by CI screenshots and quick manual tests.
public struct LaunchOptions: Sendable, Equatable {
    public enum View: String, Sendable {
        case largest, duplicates, types
    }

    /// `DISKBLOOM_SCAN=/path`: scan this folder right away.
    public var scanPath: String?
    /// `DISKBLOOM_CLEAN=1`: open Smart Clean after that scan.
    public var openCleaner = false
    /// `DISKBLOOM_OVERVIEW=1`: show the boot disk overview.
    public var showOverview = false
    /// `DISKBLOOM_OVERVIEW=/path`: show the overview of this folder instead.
    public var overviewPath: String?
    /// `DISKBLOOM_MODE=largest|duplicates|types`: initial result view (duplicates also starts the search).
    public var view: View?
    /// `DISKBLOOM_SEARCH=text`: search the scan for this name.
    public var searchQuery: String?
    /// `DISKBLOOM_DEMO=1`: put one item in the Trash list.
    public var demoCollector = false

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        scanPath = environment["DISKBLOOM_SCAN"].flatMap { $0.isEmpty ? nil : $0 }
        openCleaner = environment["DISKBLOOM_CLEAN"] != nil
        showOverview = environment["DISKBLOOM_OVERVIEW"] != nil
        overviewPath = environment["DISKBLOOM_OVERVIEW"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        view = environment["DISKBLOOM_MODE"].flatMap(View.init(rawValue:))
        searchQuery = environment["DISKBLOOM_SEARCH"].flatMap { $0.isEmpty ? nil : $0 }
        demoCollector = environment["DISKBLOOM_DEMO"] != nil
    }

    public static let current = LaunchOptions()
}
