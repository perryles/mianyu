import Foundation

enum WatchSnapshotArbitration {
    static let maxStressHistoryPoints = 48
    static let maxTimestamp: Int64 = 4_102_444_800

    private static let historyRetentionSeconds: Int = 24 * 60 * 60
    private static let snapshotType = "snapshot"
    private static let recoveryStates = ["pending", "completed", "snoozed", "skipped", "notApplicable"]

    static func isValidTimestamp(_ timestamp: Int) -> Bool {
        timestamp > 0 && Int64(timestamp) <= maxTimestamp
    }

    static func shouldAcceptRemoteSnapshot(
        incomingTimestamp: Int,
        lastAcceptedRemoteTimestamp: Int?
    ) -> Bool {
        guard isValidTimestamp(incomingTimestamp) else { return false }
        guard let lastAcceptedRemoteTimestamp else { return true }
        return incomingTimestamp >= lastAcceptedRemoteTimestamp
    }

    static func resolvedTimestamp(incomingTimestamp: Int, currentTimestamp: Int) -> Int {
        guard isValidTimestamp(incomingTimestamp) else { return max(1, currentTimestamp) }
        return max(incomingTimestamp, currentTimestamp)
    }

    static func shouldPreserveLocalHeartRate(
        localPublishedAt: Date?,
        incomingTimestamp: Int
    ) -> Bool {
        guard let localPublishedAt else { return false }
        return localPublishedAt.timeIntervalSince1970 > TimeInterval(incomingTimestamp)
    }

    static func boundedStressHistory(
        _ points: [WatchStressHistoryPoint],
        maxPoints: Int = maxStressHistoryPoints,
        now: Date = Date()
    ) -> [WatchStressHistoryPoint] {
        let nowTimestamp = Int(now.timeIntervalSince1970)
        let oldestAcceptedTimestamp = nowTimestamp - historyRetentionSeconds
        let latestByTimestamp = Dictionary(points.map { ($0.timestamp, $0) }) { lhs, rhs in
            lhs.value >= rhs.value ? lhs : rhs
        }
        return latestByTimestamp.values
            .filter {
                isValidTimestamp($0.timestamp)
                    && $0.timestamp >= oldestAcceptedTimestamp
                    && $0.value > 0
                    && $0.value <= 100
            }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(max(1, maxPoints))
    }

    static func sanitizedSnapshotPayload(_ payload: [String: Any]) -> [String: Any]? {
        guard payload["type"] as? String == snapshotType else { return nil }

        let requiredIntegerKeys = [
            "bpm", "stress", "timestamp", "steps", "activeEnergy", "exerciseMinutes",
            "standHours", "stepsGoal", "activeEnergyGoal", "exerciseMinutesGoal",
            "standHoursGoal", "sleepDurationMinutes", "sleepScore", "waterIntakeMl",
            "waterTargetMl", "caffeineRemainedMg", "sedentaryElapsedMinutes",
            "sedentaryBreakDurationMinutes"
        ]
        let requiredDoubleKeys = ["hrv", "waterCompletionRate"]
        let requiredBoolKeys = [
            "sedentaryIsCounting", "sedentaryPausedBySleep",
            "sedentaryBreakIsActive", "sleepMonitoringActive"
        ]

        for key in requiredIntegerKeys where numberValue(payload[key]) == nil { return nil }
        for key in requiredDoubleKeys where numberValue(payload[key]) == nil { return nil }
        for key in requiredBoolKeys where payload[key] as? Bool == nil { return nil }
        guard isValidTimestamp(intValue(payload["timestamp"]) ?? 0) else { return nil }

        var sanitized: [String: Any] = payload
        sanitized["bpm"] = min(max(intValue(payload["bpm"]) ?? 0, 0), 250)
        sanitized["hrv"] = clampedDouble(numberValue(payload["hrv"]), lower: 0, upper: 500)
        sanitized["stress"] = min(max(intValue(payload["stress"]) ?? 0, 0), 100)
        sanitized["stressTrend"] = trimmedString(payload["stressTrend"]) ?? "稳定"

        for key in requiredIntegerKeys where key != "bpm" && key != "stress" && key != "timestamp" {
            sanitized[key] = max(0, intValue(payload[key]) ?? 0)
        }
        sanitized["waterCompletionRate"] = clampedDouble(
            numberValue(payload["waterCompletionRate"]),
            lower: 0,
            upper: 1
        )

        if let history = payload["stressHistory"] as? [[String: Any]] {
            let points = history.compactMap { item -> WatchStressHistoryPoint? in
                guard let timestamp = intValue(item["timestamp"]),
                      let value = intValue(item["value"]) else {
                    return nil
                }
                return WatchStressHistoryPoint(timestamp: timestamp, value: value)
            }
            sanitized["stressHistory"] = boundedStressHistory(points).map {
                ["timestamp": $0.timestamp, "value": $0.value]
            }
        } else if let history = payload["stressHistory"] as? [WatchStressHistoryPoint] {
            sanitized["stressHistory"] = boundedStressHistory(history).map {
                ["timestamp": $0.timestamp, "value": $0.value]
            }
        } else {
            sanitized["stressHistory"] = []
        }

        if let plan = payload["recoveryPlan"] as? [String: Any] {
            if let sanitizedPlan = sanitizedRecoveryPlan(plan) {
                sanitized["recoveryPlan"] = sanitizedPlan
            } else {
                sanitized.removeValue(forKey: "recoveryPlan")
            }
        }

        return sanitized
    }

    static func payloadSignature(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return String(describing: payload).hashValue.description
        }
        return data.base64EncodedString()
    }

    static func payloadByteCount(_ payload: [String: Any]) -> Int {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return 0
        }
        return data.count
    }

    private static func sanitizedRecoveryPlan(_ plan: [String: Any]) -> [String: Any]? {
        guard let planID = trimmedString(plan["planID"]),
              let dayStart = intValue(plan["dayStart"]),
              dayStart > 0,
              let rawActions = plan["actions"] as? [[String: Any]] else {
            return nil
        }

        var actions: [[String: Any]] = []
        var seenActionIDs = Set<String>()
        var mainActionCount = 0

        for item in rawActions.prefix(3) {
            guard let actionID = trimmedString(item["actionID"]),
                  let title = trimmedString(item["title"]),
                  let role = trimmedString(item["role"]),
                  let state = trimmedString(item["state"]),
                  !seenActionIDs.contains(actionID) else {
                continue
            }
            let normalizedRole: String?
            switch role {
            case "main": normalizedRole = "main"
            case "supporting": normalizedRole = "supporting"
            default: normalizedRole = nil
            }
            guard let normalizedRole, recoveryStates.contains(state) else { continue }

            seenActionIDs.insert(actionID)
            if normalizedRole == "main" { mainActionCount += 1 }
            actions.append([
                "actionID": actionID,
                "title": title,
                "role": normalizedRole,
                "state": state
            ])
        }

        guard mainActionCount == 1, (1...3).contains(actions.count) else { return nil }
        return ["planID": planID, "dayStart": dayStart, "actions": actions]
    }

    private static func numberValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let double = value as? Double { return double.isFinite ? double : nil }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber {
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite { return Int(double.rounded()) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func clampedDouble(_ value: Double?, lower: Double, upper: Double) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, lower), upper)
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
