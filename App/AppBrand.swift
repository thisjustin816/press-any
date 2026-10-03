import Foundation

/// The user-facing product name. Its one source is the app target's
/// `INFOPLIST_KEY_CFBundleDisplayName` build setting in project.yml.
enum AppBrand {
    static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? ""
}
