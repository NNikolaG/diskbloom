import Foundation

/// Where the command line tools Diskbloom uses live.
public enum ToolLocations {
    public static let xcrun = "/usr/bin/xcrun"
    public static let tmutil = "/usr/bin/tmutil"

    /// Docker's CLI: Homebrew, Docker Desktop's own copy or `~/.docker/bin`.
    public static func docker(home: String = NSHomeDirectory()) -> String? {
        Shell.firstExecutable([
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            home + "/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ])
    }
}
