// swift-tools-version: 6.1
import PackageDescription

// The pinned SameBoy git submodule. Run `git submodule update --init` if this path is missing.
let sameBoyCorePath = "Dependencies/SameBoy/Core"

let package = Package(
    name: "EmulatorKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "EmulatorDomain", targets: ["EmulatorDomain"]),
        .library(name: "EmulatorApplication", targets: ["EmulatorApplication"]),
        .library(name: "AssetStorage", targets: ["AssetStorage"]),
        .library(name: "Importing", targets: ["Importing"]),
        .library(name: "Patching", targets: ["Patching"]),
        .library(name: "EmulationCore", targets: ["EmulationCore"]),
        .library(name: "EmulationSession", targets: ["EmulationSession"]),
        .library(name: "QuickPlay", targets: ["QuickPlay"]),
        .library(name: "GameplayInput", targets: ["GameplayInput"]),
        .library(name: "GameplayAudio", targets: ["GameplayAudio"]),
        .library(name: "SameBoyAdapter", targets: ["SameBoyAdapter"]),
        .library(name: "ToolchainDetection", targets: ["ToolchainDetection"]),
        .library(name: "GameIdentity", targets: ["GameIdentity"]),
        .library(name: "PersistenceGRDB", targets: ["PersistenceGRDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "EmulatorDomain"),
        .target(name: "EmulatorApplication", dependencies: ["EmulatorDomain", "EmulationCore"]),
        .target(name: "AssetStorage", dependencies: ["EmulatorDomain", "EmulatorApplication"]),
        // The system zlib, for reading zip archives.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "Importing", dependencies: ["EmulatorDomain", "EmulatorApplication", "ToolchainDetection", "GameIdentity", "CZlib"]),
        // Importing for its ROM header rules, so a patched image is classified the way an import is.
        .target(name: "Patching", dependencies: ["EmulatorDomain", "EmulatorApplication", "Importing", "ToolchainDetection"]),
        .target(name: "EmulationCore", dependencies: ["EmulatorDomain"]),
        .target(name: "EmulationSession", dependencies: ["EmulatorDomain", "EmulatorApplication", "EmulationCore"]),
        .target(name: "QuickPlay", dependencies: ["EmulatorDomain", "EmulatorApplication", "EmulationCore", "EmulationSession", "Importing"]),
        .target(name: "GameplayInput", dependencies: ["EmulationCore"]),
        .target(name: "GameplayAudio", dependencies: ["EmulationCore"]),
        // Test doubles shared by the test targets; not a product, so the app never links it.
        .target(name: "EmulatorKitTestSupport", dependencies: ["EmulatorDomain", "EmulatorApplication", "EmulationCore"]),
        .target(name: "ToolchainDetection", dependencies: ["EmulatorDomain"]),
        // No-Intro's known dumps, bundled as data; Scripts/generate-known-dumps.py writes the file.
        .target(name: "GameIdentity", dependencies: ["EmulatorDomain", "EmulatorApplication"], resources: [.process("Resources")]),
        // SameBoy's headers are not self-contained (apu.h uses GB_ENUM, which only save_state.h
        // defines), so a clang module over Core/ cannot build in Xcode. Only the C bridge includes
        // them, through the header search path below; Swift sees SameBoyBridge alone. SwiftPM needs
        // some public headers directory, so point it at graphics/, which holds no headers.
        .target(
            name: "SameBoyCoreSource",
            path: sameBoyCorePath,
            publicHeadersPath: "graphics",
            cSettings: [
                .define("GB_INTERNAL"),
                .define("GB_VERSION", to: "\"1.0.3\""),
                .define("GB_COPYRIGHT_YEAR", to: "\"2026\""),
                .define("_GNU_SOURCE", .when(platforms: [.linux])),
                .unsafeFlags(["-std=gnu11"]),
            ]
        ),
        .target(
            name: "SameBoyBridge",
            dependencies: ["SameBoyCoreSource"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("../../\(sameBoyCorePath)")]
        ),
        .target(
            name: "SameBoyAdapter",
            dependencies: ["EmulatorDomain", "EmulationCore", "SameBoyBridge"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "PersistenceGRDB",
            dependencies: [
                "EmulatorDomain",
                "EmulatorApplication",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "EmulatorDomainTests", dependencies: ["EmulatorDomain"]),
        .testTarget(name: "EmulatorApplicationTests", dependencies: ["EmulatorKitTestSupport", "EmulatorApplication", "EmulatorDomain", "AssetStorage", "Importing", "GameIdentity"]),
        .testTarget(name: "AssetStorageTests", dependencies: ["EmulatorKitTestSupport", "AssetStorage"]),
        .testTarget(name: "ImportingTests", dependencies: ["EmulatorKitTestSupport", "Importing", "AssetStorage", "GameIdentity"]),
        .testTarget(name: "PatchingTests", dependencies: ["EmulatorKitTestSupport", "Patching", "AssetStorage", "EmulatorApplication"]),
        .testTarget(name: "EmulationCoreTests", dependencies: ["EmulationCore", "EmulatorKitTestSupport", "EmulatorApplication"]),
        .testTarget(name: "EmulationSessionTests", dependencies: ["EmulationSession", "EmulationCore", "EmulatorKitTestSupport", "AssetStorage", "PersistenceGRDB"]),
        .testTarget(name: "QuickPlayTests", dependencies: ["QuickPlay", "EmulatorKitTestSupport", "AssetStorage", "Importing"]),
        .testTarget(name: "GameplayInputTests", dependencies: ["GameplayInput", "EmulationCore"]),
        .testTarget(name: "GameplayAudioTests", dependencies: ["GameplayAudio", "EmulationCore"]),
        .testTarget(name: "SameBoyAdapterTests", dependencies: ["SameBoyAdapter", "EmulatorKitTestSupport"]),
        .testTarget(name: "GameIdentityTests", dependencies: ["GameIdentity", "EmulatorDomain", "EmulatorKitTestSupport", "AssetStorage"]),
        .testTarget(name: "ToolchainDetectionTests", dependencies: ["ToolchainDetection", "EmulatorDomain", "EmulatorKitTestSupport"]),
        .testTarget(
            name: "ArchitectureProofTests",
            dependencies: [
                "EmulatorDomain", "EmulatorApplication", "AssetStorage", "Importing",
                "Patching", "EmulationCore", "EmulatorKitTestSupport", "EmulationSession", "QuickPlay",
            ]
        ),
        .testTarget(
            name: "PersistenceGRDBTests",
            dependencies: [
                "PersistenceGRDB", "EmulatorApplication", "EmulatorDomain", "AssetStorage",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
