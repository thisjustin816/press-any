import Foundation

/// Managed files an operation is using right now, which cleanup leaves alone. A commit holds the
/// paths it places until the database records them, and the app holds a running game's image.
///
/// Cleanup removes a file only through `removeUnlessHeld`, which runs under the same lock a new
/// hold takes, so no hold can begin between cleanup's check and its removal.
public final class InFlightFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var holds: [String: Int] = [:]

    public init() {}

    /// Holds that end together, when `end()` is called or the lease is released.
    public final class Lease {
        private let files: InFlightFiles
        private var paths: [String] = []

        fileprivate init(files: InFlightFiles) {
            self.files = files
        }

        deinit { files.release(paths) }

        /// Call before the file is placed, so cleanup can't take it in between.
        public func hold(_ relativePath: String) {
            files.hold(relativePath)
            paths.append(relativePath)
        }

        public func end() {
            files.release(paths)
            paths = []
        }
    }

    public func lease() -> Lease { Lease(files: self) }

    public func isHeld(_ relativePath: String) -> Bool {
        lock.withLock { holds[relativePath] != nil }
    }

    /// Runs `remove` unless the path is held, and returns its result, or false when held.
    /// `remove` must not use this registry.
    public func removeUnlessHeld(_ relativePath: String, _ remove: () throws -> Bool) rethrows -> Bool {
        try lock.withLock {
            guard holds[relativePath] == nil else { return false }
            return try remove()
        }
    }

    private func hold(_ relativePath: String) {
        lock.withLock { holds[relativePath, default: 0] += 1 }
    }

    private func release(_ relativePaths: [String]) {
        guard !relativePaths.isEmpty else { return }
        lock.withLock {
            for path in relativePaths {
                let count = holds[path, default: 0] - 1
                holds[path] = count > 0 ? count : nil
            }
        }
    }
}
