import Foundation
import Testing
@testable import BioBalance

/// WorkoutAnalysisComputation 纯逻辑聚焦测试：分段切分、爬升滞回、海拔抽样。
struct WorkoutAnalysisComputationTests {

    // MARK: 分段（按公里）

    @Test func distanceSplitsComputePacePerKilometer() {
        // 3 公里，每公里 6 分钟（360s）：距离轨迹按 6 分钟一公里推进。
        let track: [(offset: TimeInterval, kilometers: Double)] = (0...3).map { (TimeInterval($0) * 360, Double($0)) }
        let heart: [(offset: TimeInterval, beatsPerMinute: Double)] = [
            (60, 120), (240, 140), (400, 150), (700, 160), (1000, 155)
        ]

        let splits = WorkoutAnalysisComputation.distanceSplits(
            distanceTrack: track,
            heartRateTrack: heart,
            elevationTrack: [],
            totalDistanceKilometers: 3
        ) ?? []

        #expect(splits.count == 3)
        #expect(splits[0].paceSecondsPerKilometer == 360)
        #expect(splits[1].paceSecondsPerKilometer == 360)
        #expect(splits[2].paceSecondsPerKilometer == 360)
        // 第一段内 (60, 240) 两个样本 → 均值 130。
        #expect(splits[0].averageHeartRate == 130)
    }

    @Test func distanceSplitsReturnNilWithoutUsableTrack() {
        let short: [(offset: TimeInterval, kilometers: Double)] = [(0, 0)]
        #expect(WorkoutAnalysisComputation.distanceSplits(
            distanceTrack: short, heartRateTrack: [], elevationTrack: [], totalDistanceKilometers: 5
        ) == nil)
        #expect(WorkoutAnalysisComputation.distanceSplits(
            distanceTrack: [], heartRateTrack: [], elevationTrack: [], totalDistanceKilometers: 0.5
        ) == nil)
    }

    @Test func timeSplitsCoverPartialLastSegment() {
        // 13 分钟训练按 5 分钟切分 → 3 段（5/5/3）。
        let distance: [(offset: TimeInterval, kilometers: Double)] = [(0, 0), (780, 2.6)]
        let splits = WorkoutAnalysisComputation.timeSplits(
            distanceTrack: distance,
            heartRateTrack: [(100, 130), (700, 150)],
            elevationTrack: [],
            duration: 13 * 60
        )

        #expect(splits.count == 3)
        #expect(splits[0].duration == 300)
        #expect(splits[2].duration == 180)
        #expect(abs((splits[0].distanceKilometers ?? 0) - 1.0) < 0.001)
        // 2.6 公里 / 13 分钟 → 均匀配速 300s/km。
        #expect(splits.allSatisfy { abs(($0.paceSecondsPerKilometer ?? 0) - 300) < 1 })
    }

    // MARK: 爬升（滞回法）

    @Test func ascentGainFiltersPressureNoise() {
        // 100 → 101.5 → 100：振幅小于 2 米阈值，不计爬升。
        let flat: [(offset: TimeInterval, meters: Double)] = [(0, 100), (10, 101.5), (20, 100)]
        #expect(WorkoutAnalysisComputation.ascentGain(from: flat) == 0)

        // 100 → 104（+4 计入）→ 102（下行重置）→ 107（+5 计入）→ 106.8（尾部小幅回落忽略）。
        let rolling: [(offset: TimeInterval, meters: Double)] = [(0, 100), (10, 104), (20, 102), (30, 107), (40, 106.8)]
        #expect(WorkoutAnalysisComputation.ascentGain(from: rolling) == 9)
    }

    @Test func ascentGainNilWithoutEnoughSamples() {
        #expect(WorkoutAnalysisComputation.ascentGain(from: []) == nil)
        #expect(WorkoutAnalysisComputation.ascentGain(from: [(0, 50)]) == nil)
    }

    // MARK: 海拔曲线抽样

    @Test func elevationProfileKeepsEndpointsWhenDownsampling() {
        let track: [(offset: TimeInterval, meters: Double)] = (0..<300).map { (Double($0) * 10, Double($0 % 40)) }
        let profile = WorkoutAnalysisComputation.elevationProfile(from: track, maxCount: 90)

        #expect(profile.count == 90)
        #expect(profile.first?.offset == 0)
        #expect(profile.last?.offset == track.last?.offset)
        // 抽样保持时间单调。
        #expect(zip(profile, profile.dropFirst()).allSatisfy { $0.offset <= $1.offset })
    }

    @Test func elevationProfilePassthroughSmallTracks() {
        let track: [(offset: TimeInterval, meters: Double)] = [(0, 10), (5, 20), (9, 15)]
        let profile = WorkoutAnalysisComputation.elevationProfile(from: track)
        #expect(profile.count == 3)
        #expect(profile[1].elevationMeters == 20)
    }

    // MARK: 报告组装

    @Test func buildReportReturnsNilForInsufficientSamples() {
        #expect(WorkoutAnalysisComputation.buildReport(
            workoutID: UUID(),
            startedAt: Date(),
            duration: 600,
            totalDistanceKilometers: 1,
            distanceTrack: [],
            heartRateTrack: [(10, 120)],
            elevationTrack: [],
            recordedAscentMeters: nil
        ) == nil)
    }

    @Test func buildReportPrefersDistanceSplitsAndFallsBackToRecordedAscent() {
        let distance: [(offset: TimeInterval, kilometers: Double)] = [(0, 0), (300, 0.5), (600, 1.0), (900, 1.5)]
        let heart: [(offset: TimeInterval, beatsPerMinute: Double)] = [(50, 120), (700, 160)]
        let elevation: [(offset: TimeInterval, meters: Double)] = [(0, 100), (300, 106), (600, 103), (900, 108)]

        let report = WorkoutAnalysisComputation.buildReport(
            workoutID: UUID(),
            startedAt: Date(),
            duration: 900,
            totalDistanceKilometers: 1.5,
            distanceTrack: distance,
            heartRateTrack: heart,
            elevationTrack: elevation,
            recordedAscentMeters: nil
        )

        #expect(report != nil)
        #expect(report?.splitKind == .distance)
        #expect(report?.splits.count == 1) // 1.5 km 只能定位一个完整公里段
        #expect(report?.peakHeartRate == 160)
        #expect(report?.maxElevationMeters == 108)
        // 轨迹滞回：100→106(+6) →103→108(+5) = 11 米。
        #expect(report?.totalAscentMeters == 11)

        // 无海拔轨迹时回退记录值。
        let fallback = WorkoutAnalysisComputation.buildReport(
            workoutID: UUID(),
            startedAt: Date(),
            duration: 600,
            totalDistanceKilometers: 1,
            distanceTrack: [(0, 0), (600, 1)],
            heartRateTrack: heart,
            elevationTrack: [],
            recordedAscentMeters: 42
        )
        #expect(fallback?.totalAscentMeters == 42)
        #expect(fallback?.hasElevation == false)
    }

    @Test func buildReportUsesTimeSplitsWithoutDistance() {
        let report = WorkoutAnalysisComputation.buildReport(
            workoutID: UUID(),
            startedAt: Date(),
            duration: 700,
            totalDistanceKilometers: nil,
            distanceTrack: [],
            heartRateTrack: [(100, 130), (300, 140), (600, 150)],
            elevationTrack: [(0, 0), (350, 8), (690, 3)],
            recordedAscentMeters: nil
        )

        #expect(report?.splitKind == .time)
        #expect(report?.splits.count == 3) // 700s / 300s → 3 段
        #expect(report?.hasElevation == true)
    }
}
