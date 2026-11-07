import FactoriOSCompat

/// Monotonic count of game frames submitted to Metal.
public enum PresentedFrames {
    /// Reads the counter maintained by the Metal presentation compatibility hook.
    public static var current: UInt64 {
        FOSCompatPresentedFrameCount()
    }
}
