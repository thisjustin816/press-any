import EmulationCore
import EmulatorDomain

public struct SameBoyCoreFactory: EmulatorCoreFactory {
    public let descriptor = CoreDescriptor(identifier: "sameboy", version: "1.0.3")
    public let supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]

    public init() {}

    public func makeCore() throws -> any EmulatorCore {
        SameBoyAdapter()
    }
}
