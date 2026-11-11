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

let package = Package(
    name: "FactoriOS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // xtool builds the FactoriOS library into FactoriOS.app.
        .library(name: "FactoriOS", targets: ["FactoriOSRuntime"]),
        // The Mac command `deploy` runs to convert the imported game before signing it.
        .executable(name: "factorios-convert", targets: ["FactoriOSConvert"]),
    ],
    targets: [
        // What the app and the converter share: paths, the redirected symbols and the slot manifest's format.
        .target(name: "FactoriOSCore", swiftSettings: strictSwift),
        .executableTarget(name: "FactoriOSConvert", dependencies: ["FactoriOSCore"], swiftSettings: strictSwift),
        // SDL3's Apple XCFramework, built from the External/SDL submodule with the dynamic API on. xtool embeds it in
        // the app's Frameworks directory, where the game's static SDL3 finds it through SDL3_DYNAMIC_API.
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
)
