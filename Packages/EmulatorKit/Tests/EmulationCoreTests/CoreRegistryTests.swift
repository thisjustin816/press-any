import EmulatorApplication
import EmulationCore
import EmulatorKitTestSupport
import EmulatorDomain
import Foundation
import XCTest

final class CoreRegistryTests: XCTestCase {
    func testRegistryReturnsNewestCompatibleVersionForFirstLaunch() throws {
        let registry = CoreRegistry(factories: [
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.3")),
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.1.0")),
        ])

        let factory = try registry.latestFactory(system: .gameBoyColor, preferredIdentifier: "sameboy")

        XCTAssertEqual(factory.descriptor.version, "1.1.0")
    }

    func testAPrereleaseIsOlderThanItsReleaseAndOrderedByItsNumber() throws {
        func latest(_ versions: [String]) throws -> String {
            try CoreRegistry(factories: versions.map { FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: $0)) })
                .latestFactory(system: .gameBoy).descriptor.version
        }
        XCTAssertEqual(try latest(["1.0.5", "1.0.5-prerelease.53+19a7b14", "1.0.4"]), "1.0.5")
        XCTAssertEqual(try latest(["1.0.5-prerelease.53+19a7b14", "1.0.5-prerelease.9+abc1234"]), "1.0.5-prerelease.53+19a7b14")
        XCTAssertEqual(try latest(["1.0.4", "1.0.5-prerelease.9+19a7b14"]), "1.0.5-prerelease.9+19a7b14")
    }

    func testABuildPinnedToAReplacedVersionRunsOnItsReplacementAndAnExactPinWins() throws {
        let old = CoreDescriptor(identifier: "sameboy", version: "1.0.3")
        let replacement = CoreRegistry(factories: [
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.4"), replacedDescriptors: [old]),
        ])
        XCTAssertEqual(try replacement.factory(for: old).descriptor.version, "1.0.4")

        let both = CoreRegistry(factories: [
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.4"), replacedDescriptors: [old]),
            FakeCoreFactory(descriptor: old),
        ])
        XCTAssertEqual(try both.factory(for: old).descriptor.version, "1.0.3")
        XCTAssertThrowsError(try CoreRegistry(factories: [FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.4"))])
            .factory(for: old))
    }

    func testFirstLaunchPinsLatestCompatibleCore() throws {
        let build = makeBuild(corePin: nil)
        let repository = InMemoryBuildRepository([build])
        let registry = CoreRegistry(factories: [
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.3")),
        ])
        let resolver = ResolveCoreForBuild(
            builds: repository,
            registry: registry,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let core = try resolver.execute(buildID: build.id)

        XCTAssertEqual(core.descriptor, .init(identifier: "sameboy", version: "1.0.3"))
        XCTAssertEqual(try repository.fetchBuild(id: build.id)?.corePin?.descriptor, core.descriptor)
        XCTAssertEqual(
            try repository.fetchBuild(id: build.id)?.corePin?.pinnedAt,
            Date(timeIntervalSince1970: 100)
        )
    }

    func testPinnedBuildDoesNotSilentlyMoveToNewerCore() throws {
        let pin = CorePin(
            descriptor: .init(identifier: "sameboy", version: "1.0.3"),
            pinnedAt: Date(timeIntervalSince1970: 50)
        )
        let build = makeBuild(corePin: pin)
        let repository = InMemoryBuildRepository([build])
        let registry = CoreRegistry(factories: [
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.3")),
            FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.1.0")),
        ])

        let core = try ResolveCoreForBuild(builds: repository, registry: registry).execute(buildID: build.id)

        XCTAssertEqual(core.descriptor.version, "1.0.3")
    }

    func testFakeCoreRoundTripsStateAndBattery() throws {
        let core = FakeEmulatorCore(descriptor: .init(identifier: "fake", version: "1.0.0"))
        try core.loadImage(Data(repeating: 0, count: 32 * 1024), system: .gameBoy)
        try core.loadPersistentSave(Data([1, 2, 3]))
        _ = try core.runFrame(input: EmulatorInputState(a: true))
        let state = try core.serializeState()
        _ = try core.runFrame(input: EmulatorInputState())
        try core.loadPersistentSave(Data([9]))

        try core.deserializeState(state)
        let restored = try core.runFrame(input: EmulatorInputState())

        XCTAssertEqual(try core.persistentSaveData(), Data([1, 2, 3]))
        XCTAssertEqual(restored.bgra8888.first, 2)
    }
}

private func makeBuild(corePin: CorePin?) -> Build {
    Build(
        id: UUID(),
        gameID: UUID(),
        system: .gameBoyColor,
        displayName: "Test",
        imageAssetID: UUID(),
        imageSHA256: String(repeating: "a", count: 64),
        sourceKind: .importedImage,
        corePin: corePin,
        createdAt: Date(timeIntervalSince1970: 1),
        modifiedAt: Date(timeIntervalSince1970: 1)
    )
}
