import QuickPlay
import SwiftUI

struct LibraryStorageContext: Sendable {
    let container: AppContainer
    let onResumeQuickPlay: @MainActor @Sendable (QuickPlaySession) -> Void
}

private struct LibraryStorageContextKey: EnvironmentKey {
    static let defaultValue: LibraryStorageContext? = nil
}

extension EnvironmentValues {
    var libraryStorageContext: LibraryStorageContext? {
        get { self[LibraryStorageContextKey.self] }
        set { self[LibraryStorageContextKey.self] = newValue }
    }
}
