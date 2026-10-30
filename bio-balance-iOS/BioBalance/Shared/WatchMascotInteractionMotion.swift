import CoreGraphics
import Foundation

/// Native watchOS counterpart of the bundled Emotion Ball gesture timing.
nonisolated public enum WatchMascotInteractionMotion {
    public static let duration: TimeInterval = 1.35

    private static let bounceSegments: [(height: CGFloat, duration: TimeInterval)] = [
        (12, 0.5), (7, 0.382), (3.5, 0.27), (1.5, 0.177)
    ]

    public static func normalizedDrag(translation: CGFloat, extent: CGFloat) -> CGFloat {
        guard extent > 0 else { return 0 }
        return min(1, max(-1, translation / extent))
    }

    public static func bounceOffset(elapsed: TimeInterval) -> CGFloat {
        guard elapsed > 0 else { return 0 }
        var cursor: TimeInterval = 0
        for segment in bounceSegments {
            let end = cursor + segment.duration
            if elapsed < end {
                let progress = CGFloat((elapsed - cursor) / segment.duration)
                return -segment.height * 4 * progress * (1 - progress)
            }
            cursor = end
        }
        return 0
    }

    public static func spinDegrees(elapsed: TimeInterval) -> Double {
        let progress = min(1, max(0, elapsed / 0.65))
        let eased = 1 - pow(1 - progress, 3)
        return eased * 720
    }

    public static func burstProgress(elapsed: TimeInterval) -> Double {
        min(1, max(0, elapsed / 0.6))
    }

    public static func shouldCelebrate(travel: CGFloat, didLongPress: Bool, reduceMotion: Bool) -> Bool {
        !reduceMotion && !didLongPress && travel < 12
    }
}
