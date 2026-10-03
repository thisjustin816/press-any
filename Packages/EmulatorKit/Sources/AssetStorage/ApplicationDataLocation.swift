import Foundation

/// The app's managed-storage root inside Application Support.
///
/// The directory name carries no product branding, so a product rename never moves user data.
public enum ApplicationDataLocation {
    public static let directoryName = "AppData"

    public static func root(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }
}
