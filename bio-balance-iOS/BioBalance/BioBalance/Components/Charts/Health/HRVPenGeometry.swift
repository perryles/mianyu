import Foundation

nonisolated enum HRVPenGeometry {
    /// One shared pen tip for the stroke and its filled area, measured along the path.
    static func revealedPoints(_ points: [CGPoint], progress: Double) -> [CGPoint] {
        guard !points.isEmpty, progress > 0 else { return [] }
        guard points.count > 1, progress < 1 else { return points }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return [points[0]] }
        var remaining = total * progress
        var result = [points[0]]
        for index in lengths.indices {
            let length = lengths[index]
            if remaining >= length {
                result.append(points[index + 1])
                remaining -= length
            } else {
                let fraction = length > 0 ? remaining / length : 0
                result.append(CGPoint(
                    x: points[index].x + (points[index + 1].x - points[index].x) * fraction,
                    y: points[index].y + (points[index + 1].y - points[index].y) * fraction
                ))
                break
            }
        }
        return result
    }

    static func nearestIndex(x: CGFloat, positions: [CGPoint]) -> Int? {
        guard x.isFinite else { return nil }
        return positions.indices.filter { positions[$0].x.isFinite && positions[$0].y.isFinite }
            .min { abs(positions[$0].x - x) < abs(positions[$1].x - x) }
    }
}
