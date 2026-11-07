// swift-tools-version: 6.2
import PackageDescription

let strictSwift: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let strictObjC: [CSetting] = [
    .unsafeFlags([
        "-Werror", "-Weverything",
        "-Wno-declaration-after-statement", "-Wno-missing-include-dirs", "-Wno-padded",
        "-Wno-poison-system-directories", "-Wno-objc-messaging-id", "-Wno-direct-ivar-access",
        "-Wno-unsafe-buffer-usage",
        "-Wno-pre-c11-compat", "-Wno-switch-default",
    ])
]

let core: Target = .target(
    name: "FactoriOSCore",
    dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SwiftASN1", package: "swift-asn1"),
    ],
    swiftSettings: strictSwift
)

// UIKit, Metal and the Objective-C runtime build only for Apple platforms. `mise run build-host` sets
// FACTORIOS_CORE_ONLY to compile the core on the build machine itself; xtool, which cross-compiles from Linux too,
// sees every target.
let coreOnly = Context.environment["FACTORIOS_CORE_ONLY"] != nil

// The development Mac's command that imports, converts and signs the game before it is copied to a device. It only
// exists in the host build, so xtool's iOS project never sees a macOS executable.
let hostTargets: [Target] =
    coreOnly
    ? [.executableTarget(name: "FactoriOSPrepare", dependencies: ["FactoriOSCore"], swiftSettings: strictSwift)]
    : []

// SDL3's official, pinned Apple XCFramework is prepared by the iOS build and dev tasks. xtool embeds the binary target
// in the app's Frameworks directory, where the game's static SDL3 finds it through SDL3_DYNAMIC_API.
let appleTargets: [Target] =
    coreOnly
    ? []
    : [
        .binaryTarget(name: "SDL3", path: "Vendor/SDL3.xcframework"),
        // The game's Mac-only API surface on UIKit/Metal, and the SDL3 bridge.
        .target(name: "FactoriOSCompat", cSettings: strictObjC),
        // Signing, loading and running the converted game.
        .target(
            name: "FactoriOSRuntime",
            dependencies: ["FactoriOSCore", "FactoriOSCompat"],
            swiftSettings: strictSwift
        ),
        // SwiftUI launcher and on-screen controller.
        .target(name: "FactoriOSUI", dependencies: ["FactoriOSCore", "FactoriOSRuntime"], swiftSettings: strictSwift),
        // Entry point: hands the app's start-up to SDL, as SDL requires on iOS.
        .target(
            name: "FactoriOSApp",
            dependencies: ["FactoriOSUI", "FactoriOSRuntime", "SDL3"],
            swiftSettings: strictSwift
        ),
    ]
// xtool builds the FactoriOS library into FactoriOS.app.
let products: [Product] =
    coreOnly
    ? [
        .library(name: "FactoriOSCore", targets: ["FactoriOSCore"]),
        .executable(name: "factorios-prepare", targets: ["FactoriOSPrepare"]),
    ]
    : [.library(name: "FactoriOS", targets: ["FactoriOSApp"])]

let package = Package(
    name: "FactoriOS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.7.4"),
    ],
    targets: [core] + hostTargets + appleTargets
)
