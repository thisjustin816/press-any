import EmulatorApplication
import Foundation

public struct LibretroArtworkProvider: ArtworkProvider {
    public static let rights = "Artwork belongs to the respective game's developers and publishers. "
        + "Scans and contributions are provided by the Libretro thumbnail community; no blanket artwork license is asserted."

    private let client: any ArtworkHTTPClient
    private let now: @Sendable () -> Date

    public init(client: any ArtworkHTTPClient = URLSessionArtworkHTTPClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? {
        let system = lookup.system == .gameBoy ? "Nintendo - Game Boy" : "Nintendo - Game Boy Color"
        let reserved = CharacterSet(charactersIn: "&*/:`<>?\\|\"")
        let componentCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for name in lookup.releaseNames {
            try Task.checkCancellation()
            guard !name.isEmpty else { continue }
            let filename = name.unicodeScalars.map { reserved.contains($0) ? "_" : String($0) }.joined()
            guard let path = filename.addingPercentEncoding(withAllowedCharacters: componentCharacters),
                  let systemPath = system.addingPercentEncoding(withAllowedCharacters: componentCharacters),
                  let url = URL(string: "https://thumbnails.libretro.com/\(systemPath)/Named_Boxarts/\(path).png") else { continue }
            guard let data = try await client.image(at: url, maximumBytes: ImportSizeLimit.artwork.bytes) else { continue }
            guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw ArtworkDownloadError.invalidImage }
            return ProvidedArtwork(data: data, fileExtension: "png", provenance: ArtworkProvenance(
                provider: "libretro", sourceURL: url, fetchedAt: now(), rights: Self.rights,
                inheritedFrom: lookup.inherited ? name : nil))
        }
        return nil
    }
}
