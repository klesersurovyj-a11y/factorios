import CoreHaptics
import Foundation

/// Plays the game's controller rumble on the device's Taptic Engine.
///
/// SDL reports rumble as two motor strengths and later a stop (both 0); the engine plays one continuous event whose
/// intensity follows the stronger motor. Devices without haptics (iPads) play nothing.
@MainActor
final class RumbleHaptics {
    /// The continuous event's length; it loops, so this only bounds a single pattern.
    private static let patternDuration: TimeInterval = 30

    private let engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?

    init() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            engine = try? CHHapticEngine()
        } else {
            engine = nil
        }
    }

    /// Rumbles with the stronger of the two strengths (0 to 1), or stops when both are 0.
    func rumble(low: Float, high: Float) {
        guard let engine else {
            // No Taptic Engine on this device: rumble has nowhere to go.
            return
        }
        let strength = min(max(low, high), 1)
        guard strength > 0 else {
            stop()
            return
        }
        do {
            let active = try player ?? start(engine)
            try active.sendParameters(
                [CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: strength, relativeTime: 0)],
                atTime: CHHapticTimeImmediate
            )
        } catch {
            // The system stops the engine when the app goes to the background; the next rumble starts it again.
            player = nil
        }
    }

    private func start(_ engine: CHHapticEngine) throws -> any CHHapticAdvancedPatternPlayer {
        try engine.start()
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ],
            relativeTime: 0,
            duration: Self.patternDuration
        )
        let created = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
        created.loopEnabled = true
        try created.start(atTime: CHHapticTimeImmediate)
        player = created
        return created
    }

    private func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }
}
