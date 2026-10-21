import Foundation

// The springs of the blob. Opening may bounce: it lands in open air. Closing and
// the peek going away land on the hardware notch, and an underdamped spring
// overshoots that edge: the blob sank inside the notch as a small block and then
// grew back. So what lands on the notch is critically damped.

public struct BlobSpring: Equatable {
    public let response: Double
    public let damping: Double
}

public enum Motion {
    public static let open = BlobSpring(response: 0.36, damping: 0.82)
    public static let close = BlobSpring(response: 0.34, damping: 1.0)
    public static let peekIn = BlobSpring(response: 0.42, damping: 0.78)
    public static let peekOut = BlobSpring(response: 0.36, damping: 1.0)

    /// Fraction of the travel a spring goes past its target before settling.
    public static func overshoot(damping z: Double) -> Double {
        guard z < 1 else { return 0 }
        return exp(-z * .pi / (1 - z * z).squareRoot())
    }
}
