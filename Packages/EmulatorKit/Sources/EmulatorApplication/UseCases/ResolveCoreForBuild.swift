import EmulationCore
import EmulatorDomain
import Foundation

public enum ResolveCoreForBuildError: Error, Equatable {
    case buildNotFound(UUID)
}

public struct ResolveCoreForBuild: Sendable {
    private let builds: any BuildRepository
    private let registry: CoreRegistry
    private let now: @Sendable () -> Date

    public init(
        builds: any BuildRepository,
        registry: CoreRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.builds = builds
        self.registry = registry
        self.now = now
    }

    public func execute(buildID: UUID) throws -> any EmulatorCore {
        guard var build = try builds.fetchBuild(id: buildID) else {
            throw ResolveCoreForBuildError.buildNotFound(buildID)
        }

        let factory: any EmulatorCoreFactory
        if let pin = build.corePin {
            factory = try registry.factory(for: pin.descriptor)
        } else {
            factory = try registry.latestFactory(system: build.system, preferredIdentifier: "sameboy")
            let timestamp = now()
            build.corePin = CorePin(descriptor: factory.descriptor, pinnedAt: timestamp)
            build.modifiedAt = timestamp
            try builds.updateBuildMetadata(build)
        }

        return try factory.makeCore()
    }
}
