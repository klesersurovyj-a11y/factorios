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

// What the app and the converter share: paths, the redirected symbols and the slot manifest's format.
let core: Target = .target(
    name: "FactoriOSCore",
    swiftSettings: strictSwift
)

// `mise run build` sets FACTORIOS_CORE_ONLY to compile the core and the converter for the Mac itself; xtool and the iOS
// build see every other target.
let coreOnly = Context.environment["FACTORIOS_CORE_ONLY"] != nil

// The development Mac's command that converts the imported game before scripts/deploy signs it and copies it to a
// device. It only exists in the host build, so xtool's iOS project never sees a macOS executable.
let hostTargets: [Target] =
    coreOnly
    ? [.executableTarget(name: "FactoriOSConvert", dependencies: ["FactoriOSCore"], swiftSettings: strictSwift)]
    : []

// SDL3's Apple XCFramework, built from SDL's pinned source with the dynamic API on, is prepared by the iOS build and
// dev tasks. xtool embeds the binary target in the app's Frameworks directory, where the game's static SDL3 finds it
// through SDL3_DYNAMIC_API.
let appleTargets: [Target] =
    coreOnly
    ? []
    : [
        .binaryTarget(name: "SDL3", path: "Vendor/SDL3.xcframework"),
        // The game's Mac-only API surface on UIKit/Metal, and the SDL3 bridge.
        .target(name: "FactoriOSCompat", cSettings: strictObjC),
        // The app: its @main, the launcher, loading and running the converted game, and the on-screen controller.
        .target(
            name: "FactoriOSRuntime",
            dependencies: ["FactoriOSCore", "FactoriOSCompat", "SDL3"],
            swiftSettings: strictSwift
        ),
    ]
// xtool builds the FactoriOS library into FactoriOS.app.
let products: [Product] =
    coreOnly
    ? [.executable(name: "factorios-convert", targets: ["FactoriOSConvert"])]
    : [.library(name: "FactoriOS", targets: ["FactoriOSRuntime"])]

let package = Package(
    name: "FactoriOS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: [core] + hostTargets + appleTargets
)
