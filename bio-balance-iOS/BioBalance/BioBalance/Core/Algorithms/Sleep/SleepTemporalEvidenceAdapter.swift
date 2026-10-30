import Foundation

/// Temporal evidence derived from normalized sleep-session boundaries and
/// timestamped stage samples. Missing values remain `nil` when the source does
/// not prove the metric.
nonisolated struct SleepTemporalEvidence: Equatable, Sendable {
    let timeInBedMinutes: Int?
    let wakeAfterSleepOnsetMinutes: Int?
}

/// Converts session-level timestamps into inputs accepted by the pure scoring
/// engine. The adapter deliberately does not infer latency because
/// `SleepInterval.start` does not currently retain whether it came from an
/// explicit HealthKit `inBed` sample.
nonisolated struct SleepTemporalEvidenceAdapter {
    private static let maximumSessionMinutes = 24 * 60

    func resolve(
        sleepInterval: SleepInterval?,
        durationMinutes: Int,
        stages: [SleepStage]
    ) -> SleepTemporalEvidence {
        guard durationMinutes > 0,
              let sleepInterval,
              sleepInterval.end > sleepInterval.start else {
            return SleepTemporalEvidence(
                timeInBedMinutes: nil,
                wakeAfterSleepOnsetMinutes: nil
            )
        }

        let sessionMinutes = Int(sleepInterval.end.timeIntervalSince(sleepInterval.start) / 60)
        guard sessionMinutes >= durationMinutes,
              sessionMinutes <= Self.maximumSessionMinutes else {
            return SleepTemporalEvidence(
                timeInBedMinutes: nil,
                wakeAfterSleepOnsetMinutes: nil
            )
        }

        return SleepTemporalEvidence(
            timeInBedMinutes: sessionMinutes,
            wakeAfterSleepOnsetMinutes: wasoMinutes(
                stages: stages,
                sessionStart: sleepInterval.start,
                sessionEnd: sleepInterval.end
            )
        )
    }

    private func wasoMinutes(
        stages: [SleepStage],
        sessionStart: Date,
        sessionEnd: Date
    ) -> Int? {
        let asleepIntervals = normalizedIntervals(
            stages: stages,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            matching: isAsleepStage
        )
        guard let firstAsleep = asleepIntervals.map(\.start).min(),
              let lastAsleep = asleepIntervals.map(\.end).max(),
              lastAsleep > firstAsleep else { return nil }

        let awakeIntervals = normalizedIntervals(
            stages: stages,
            sessionStart: firstAsleep,
            sessionEnd: lastAsleep,
            matching: isAwakeStage
        )
        guard !awakeIntervals.isEmpty else { return nil }

        let merged = merge(awakeIntervals)
        let seconds = merged.reduce(0) { $0 + $1.duration }
        return max(0, Int(seconds / 60))
    }

    private func normalizedIntervals(
        stages: [SleepStage],
        sessionStart: Date,
        sessionEnd: Date,
        matching predicate: (SleepStage) -> Bool
    ) -> [DateInterval] {
        stages.compactMap { stage in
            guard predicate(stage),
                  let rawStart = stage.startDate,
                  let rawEnd = stage.endDate else { return nil }
            let start = max(rawStart, sessionStart)
            let end = min(rawEnd, sessionEnd)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    private func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private func isAwakeStage(_ stage: SleepStage) -> Bool {
        stage.sourceType == ".awake"
            || stage.stage.contains("清醒")
            || stage.stage.localizedCaseInsensitiveContains("awake")
    }

    private func isAsleepStage(_ stage: SleepStage) -> Bool {
        if stage.sourceType?.hasPrefix(".asleep") == true { return true }
        if isAwakeStage(stage) { return false }
        return stage.stage.contains("睡")
            || stage.stage.contains("快速眼动")
            || stage.stage.localizedCaseInsensitiveContains("core")
            || stage.stage.localizedCaseInsensitiveContains("light")
            || stage.stage.localizedCaseInsensitiveContains("deep")
            || stage.stage.localizedCaseInsensitiveContains("rem")
    }
}
