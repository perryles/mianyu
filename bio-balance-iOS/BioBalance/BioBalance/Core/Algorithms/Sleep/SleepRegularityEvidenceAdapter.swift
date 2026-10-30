import Foundation

/// History-backed bedtime evidence for a single primary sleep session.
/// Missing or insufficient history remains unavailable rather than becoming a
/// synthetic normal value.
nonisolated struct SleepRegularityEvidence: Equatable, Sendable {
    let bedtimeDeviationMinutes: Double?
    let referenceNightCount: Int
}

/// Derives a robust bedtime deviation from prior primary-sleep starts.
///
/// The baseline uses a circular medoid instead of a linear average, so times on
/// opposite sides of midnight remain close. A noon-to-noon day anchor prevents
/// duplicate sessions around midnight from counting as separate nights.
nonisolated struct SleepRegularityEvidenceAdapter {
    private static let minutesPerDay = 24.0 * 60.0
    private static let minimumReferenceNights = 3
    private static let maximumReferenceNights = 7

    func resolve(
        currentBedtime: Date?,
        recentBedtimes: [Date],
        calendar: Calendar = .current
    ) -> SleepRegularityEvidence {
        guard let currentBedtime else {
            return SleepRegularityEvidence(
                bedtimeDeviationMinutes: nil,
                referenceNightCount: 0
            )
        }

        var latestByCircadianDay: [Date: Date] = [:]
        for bedtime in recentBedtimes where bedtime < currentBedtime {
            let day = circadianDayAnchor(for: bedtime, calendar: calendar)
            if bedtime > (latestByCircadianDay[day] ?? .distantPast) {
                latestByCircadianDay[day] = bedtime
            }
        }

        let references = Array(
            latestByCircadianDay.values
                .sorted()
                .suffix(Self.maximumReferenceNights)
        )
        guard references.count >= Self.minimumReferenceNights else {
            return SleepRegularityEvidence(
                bedtimeDeviationMinutes: nil,
                referenceNightCount: references.count
            )
        }

        let referenceMinutes = references.map {
            minuteOfDay(for: $0, calendar: calendar)
        }
        let baseline = circularMedoid(referenceMinutes)
        let current = minuteOfDay(for: currentBedtime, calendar: calendar)
        return SleepRegularityEvidence(
            bedtimeDeviationMinutes: circularDistance(current, baseline),
            referenceNightCount: references.count
        )
    }

    private func circadianDayAnchor(for date: Date, calendar: Calendar) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -12, to: date)
            ?? date.addingTimeInterval(-12 * 3_600)
        return calendar.startOfDay(for: shifted)
    }

    private func minuteOfDay(for date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60
    }

    private func circularMedoid(_ values: [Double]) -> Double {
        values.sorted().min { lhs, rhs in
            let lhsDistance = values.reduce(0) { $0 + circularDistance(lhs, $1) }
            let rhsDistance = values.reduce(0) { $0 + circularDistance(rhs, $1) }
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs < rhs
        } ?? 0
    }

    private func circularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: Self.minutesPerDay)
        return min(raw, Self.minutesPerDay - raw)
    }
}
