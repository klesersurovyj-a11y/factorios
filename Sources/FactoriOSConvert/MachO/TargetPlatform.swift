/// Where the converted library runs; dyld only loads an image tagged with its own platform.
enum TargetPlatform: String, CaseIterable, Sendable {
    /// An iPhone or iPad.
    case device
    /// The iOS Simulator on an Apple silicon Mac.
    case simulator

    /// The `LC_BUILD_VERSION` platform.
    var buildVersionPlatform: UInt32 {
        switch self {
        case .device:
            MachO.platformIOS
        case .simulator:
            MachO.platformIOSSimulator
        }
    }
}
