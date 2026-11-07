public import FactoriOSCore
public import Observation

/// Carries the player's start request from the launcher to the run-loop pump that hosts it.
@MainActor
@Observable
public final class LaunchCoordinator {
    /// Why the game couldn't start, for the launcher to show; cleared by the next launch.
    public private(set) var launchError: String?

    /// The request the pump hasn't picked up yet.
    private var pendingRequest: LaunchRequest?

    init() {
        launchError = nil
        pendingRequest = nil
    }

    /// Starts the game: ends the launcher's run-loop pump, which then starts the session.
    public func launch(_ request: LaunchRequest) {
        launchError = nil
        pendingRequest = request
    }

    /// The pending request, which is cleared.
    func takeRequest() -> LaunchRequest? {
        let request = pendingRequest
        pendingRequest = nil
        return request
    }

    /// Reports that the requested start failed; the launcher stays up.
    func fail(_ message: String) {
        launchError = message
    }
}
