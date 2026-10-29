import EmulationCore
import EmulatorDomain

public struct SameBoyCoreFactory: EmulatorCoreFactory {
    public let descriptor = SameBoyAdapter.coreDescriptor
    public let replacedDescriptors = SameBoyAdapter.replacedCoreDescriptors
    public let supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]

    public init() {}

    public func makeCore() throws -> any EmulatorCore {
        SameBoyAdapter()
    }
}
