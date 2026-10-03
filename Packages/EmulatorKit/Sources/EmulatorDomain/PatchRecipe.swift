import Foundation

public struct PatchRecipeItem: Codable, Equatable, Sendable {
    public let position: Int
    public let patchAssetID: UUID
    public let enabled: Bool

    public init(position: Int, patchAssetID: UUID, enabled: Bool = true) {
        self.position = position
        self.patchAssetID = patchAssetID
        self.enabled = enabled
    }
}

public struct PatchRecipe: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let resultBuildID: UUID
    public let baseBuildID: UUID
    public let expectedResultSHA256: String
    public let items: [PatchRecipeItem]
    public let createdAt: Date

    public init(
        id: UUID,
        resultBuildID: UUID,
        baseBuildID: UUID,
        expectedResultSHA256: String,
        items: [PatchRecipeItem],
        createdAt: Date
    ) {
        self.id = id
        self.resultBuildID = resultBuildID
        self.baseBuildID = baseBuildID
        self.expectedResultSHA256 = expectedResultSHA256
        self.items = items
        self.createdAt = createdAt
    }
}
