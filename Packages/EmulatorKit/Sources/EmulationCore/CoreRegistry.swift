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

    /// The core a Build is pinned to, or the one that replaced that version.
    public func factory(for descriptor: CoreDescriptor) throws -> any EmulatorCoreFactory {
        guard let factory = factories.first(where: { $0.descriptor == descriptor })
                ?? factories.first(where: { $0.replacedDescriptors.contains(descriptor) }) else {
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
        guard let latest = compatible.max(by: { Self.isOlder($0.descriptor.version, than: $1.descriptor.version) }) else {
            throw CoreRegistryError.noCompatibleCore(system: system, identifier: preferredIdentifier)
        }
        return latest
    }

    /// Orders versions as releases are ordered: a prerelease such as "1.0.5-prerelease.53+19a7b14"
    /// comes before "1.0.5". A version that isn't numbered that way is compared as numeric text.
    private static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        if let lhsKey = Build.versionSortKey(for: lhs), let rhsKey = Build.versionSortKey(for: rhs) {
            return lhsKey < rhsKey
        }
        return lhs.compare(rhs, options: .numeric) == .orderedAscending
    }
}
