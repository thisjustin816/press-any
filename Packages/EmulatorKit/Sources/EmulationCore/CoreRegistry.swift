import EmulatorDomain
import Foundation

public enum CoreRegistryError: Error, Equatable {
    case noCompatibleCore(system: GameSystem, identifier: String?)
    case pinnedCoreUnavailable(CoreDescriptor)
}

public struct CoreRegistry: Sendable {
    private let factories: [any EmulatorCoreFactory]

    public init(factories: [any EmulatorCoreFactory]) {
        self.factories = factories
    }

    public func factory(for descriptor: CoreDescriptor) throws -> any EmulatorCoreFactory {
        guard let factory = factories.first(where: { $0.descriptor == descriptor }) else {
            throw CoreRegistryError.pinnedCoreUnavailable(descriptor)
        }
        return factory
    }

    public func latestFactory(
        system: GameSystem,
        preferredIdentifier: String? = nil
    ) throws -> any EmulatorCoreFactory {
        let compatible = factories.filter { factory in
            factory.supportedSystems.contains(system)
                && (preferredIdentifier == nil || factory.descriptor.identifier == preferredIdentifier)
        }
        guard let latest = compatible.max(by: { lhs, rhs in
            lhs.descriptor.version.compare(rhs.descriptor.version, options: .numeric) == .orderedAscending
        }) else {
            throw CoreRegistryError.noCompatibleCore(system: system, identifier: preferredIdentifier)
        }
        return latest
    }
}
