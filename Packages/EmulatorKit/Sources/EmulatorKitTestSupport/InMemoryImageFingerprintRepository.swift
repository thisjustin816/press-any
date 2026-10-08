import EmulatorApplication
import EmulatorDomain
import Foundation

public final class InMemoryImageFingerprintRepository: ImageFingerprintRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: ImageFingerprint] = [:]

    public init() {}

    public func saveFingerprint(_ fingerprint: ImageFingerprint) throws {
        lock.withLock { values[fingerprint.imageSHA256] = fingerprint }
    }

    public func fetchFingerprints(imageSHA256s: [String]) throws -> [String: ImageFingerprint] {
        let wanted = Set(imageSHA256s)
        return lock.withLock { values.filter { wanted.contains($0.key) } }
    }

    public func deleteFingerprint(imageSHA256: String) throws {
        _ = lock.withLock { values.removeValue(forKey: imageSHA256) }
    }
}
