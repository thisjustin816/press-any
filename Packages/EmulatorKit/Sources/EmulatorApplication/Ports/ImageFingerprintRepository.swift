import EmulatorDomain

public protocol ImageFingerprintRepository: Sendable {
    /// The source asset must still exist when persistence stores its evidence.
    func saveFingerprint(_ fingerprint: ImageFingerprint) throws
    /// One bulk read for all candidate source images, including images in Recently Deleted.
    func fetchFingerprints(imageSHA256s: [String]) throws -> [String: ImageFingerprint]
    func deleteFingerprint(imageSHA256: String) throws
}
