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
