import Foundation
import HealthKit

/// TrendCategoryBuilder Heart 子模块。
/// 从 TrendCategoryBuilder.swift 按职责拆分，对外接口不变。

extension TrendCategoryBuilder {

    static func buildHeartECGRecords(from samples: [HeartECGSample]) -> [HeartECGRecordModel] {
        samples.map { sample in
            let samplingFrequencyText: String
            if let samplingFrequencyHz = sample.samplingFrequencyHz, samplingFrequencyHz > 0 {
                samplingFrequencyText = "\(Int(samplingFrequencyHz.rounded())) Hz"
            } else {
                samplingFrequencyText = "未提供"
            }

            let durationSeconds = sample.voltageMeasurements.last?.timeSinceSampleStart ?? 0
            let durationText = durationSeconds > 0 ? "\(Int(durationSeconds.rounded())) 秒" : "未提供"
            let averageHeartRateText = sample.averageHeartRate.map { "\(Int($0.rounded())) 次/分" } ?? "未提供"
            let algorithmVersionText = sample.classification == "房颤提示" ? "建议结合临床记录持续观察" : nil

            return HeartECGRecordModel(
                id: sample.id.uuidString,
                sampledAt: sample.sampledAt,
                classificationTitle: sample.classification,
                classificationDetail: Self.heartECGClassificationDetail(for: sample.classification),
                averageHeartRateText: averageHeartRateText,
                samplingFrequencyText: samplingFrequencyText,
                durationText: durationText,
                symptomsStatusText: sample.symptomsStatus,
                algorithmVersionText: algorithmVersionText,
                voltagePoints: sample.voltageMeasurements.map {
                    HeartECGVoltagePoint(timeOffset: $0.timeSinceSampleStart, millivolts: $0.millivolts)
                }
            )
        }
    }

    static func buildHeartECGSummary(
        records: [HeartECGRecordModel],
        overall: TrendCategoryStatus
    ) -> HeartECGSummaryModel {
        if records.isEmpty {
            let status: TrendCategoryStatus = overall == .ready ? .noData : overall
            return HeartECGSummaryModel(
                status: status,
                headline: "暂无心电图记录",
                detail: "当前还没有可展示的心电图记录，完成记录后这里会自动形成 ECG 专项卡。",
                recordCountText: "0 条记录",
                latestRecord: nil
            )
        }

        return HeartECGSummaryModel(
            status: .ready,
            headline: records.first?.classificationTitle ?? "最近 ECG 记录",
            detail: records.first?.classificationDetail ?? "最近一次心电图记录可用于辅助判断当前心律状态。",
            recordCountText: "\(records.count) 条记录",
            latestRecord: records.first
        )
    }

    static func buildHeartClinicalMonitorSummary(
        bloodPressure: (systolic: Double?, diastolic: Double?, sampledAt: Date?)?,
        irregularHeartRhythmDate: Date?,
        highHeartRateEventDate: Date?,
        lowHeartRateEventDate: Date?,
        hypertensionEventDate: Date?
    ) -> HeartClinicalMonitorSummary {
        let bloodPressureStatus = heartMonitorStatus(hasRecord: bloodPressure != nil)
        let bloodPressureValue: String
        if let systolic = bloodPressure?.systolic, let diastolic = bloodPressure?.diastolic {
            bloodPressureValue = "\(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg"
        } else {
            bloodPressureValue = heartMonitorValueText(status: bloodPressureStatus, readyText: "有记录")
        }

        let bloodPressureDetail = if let sampledAt = bloodPressure?.sampledAt {
            "最近测量 \(Self.dateText(sampledAt))"
        } else {
            "健康 App 暂无可读取的血压记录。"
        }
        let irregularStatus = heartMonitorStatus(forDate: irregularHeartRhythmDate)
        let irregularDetail = if let irregularHeartRhythmDate {
            "最近提示 \(Self.dateText(irregularHeartRhythmDate))"
        } else {
            "健康 App 暂无房颤事件记录。"
        }
        let irregularValue = if irregularHeartRhythmDate != nil {
            "有记录"
        } else {
            heartMonitorValueText(status: irregularStatus, readyText: "有记录")
        }
        let highHeartRateStatus = heartMonitorStatus(forDate: highHeartRateEventDate)
        let highHeartRateDetail = if let highHeartRateEventDate {
            "最近提醒 \(Self.dateText(highHeartRateEventDate))"
        } else {
            "健康 App 暂无高心率通知事件。"
        }
        let highHeartRateValue = if highHeartRateEventDate != nil {
            "有提醒"
        } else {
            heartMonitorValueText(status: highHeartRateStatus, readyText: "有提醒")
        }
        let lowHeartRateStatus = heartMonitorStatus(forDate: lowHeartRateEventDate)
        let lowHeartRateDetail = if let lowHeartRateEventDate {
            "最近提醒 \(Self.dateText(lowHeartRateEventDate))"
        } else {
            "健康 App 暂无低心率通知事件。"
        }
        let lowHeartRateValue = if lowHeartRateEventDate != nil {
            "有提醒"
        } else {
            heartMonitorValueText(status: lowHeartRateStatus, readyText: "有提醒")
        }
        let hypertensionStatus = heartMonitorStatus(forDate: hypertensionEventDate)
        let hypertensionDetail = if let hypertensionEventDate {
            "最近提醒 \(Self.dateText(hypertensionEventDate))"
        } else {
            "健康 App 暂无高血压通知事件。"
        }
        let hypertensionValue = if hypertensionEventDate != nil {
            "有提醒"
        } else {
            heartMonitorValueText(status: hypertensionStatus, readyText: "有提醒")
        }

        let items = [
            HeartClinicalMonitorItem(
                title: "血压",
                value: bloodPressureValue,
                detail: bloodPressureDetail,
                status: bloodPressureStatus
            ),
            HeartClinicalMonitorItem(
                title: "房颤历史",
                value: irregularValue,
                detail: irregularDetail,
                status: irregularStatus
            ),
            HeartClinicalMonitorItem(
                title: "高心率通知",
                value: highHeartRateValue,
                detail: highHeartRateDetail,
                status: highHeartRateStatus
            ),
            HeartClinicalMonitorItem(
                title: "低心率通知",
                value: lowHeartRateValue,
                detail: lowHeartRateDetail,
                status: lowHeartRateStatus
            ),
            HeartClinicalMonitorItem(
                title: "高血压通知",
                value: hypertensionValue,
                detail: hypertensionDetail,
                status: hypertensionStatus
            ),
            HeartClinicalMonitorItem(
                title: "逐搏测量",
                value: "已纳入监测层",
                detail: "逐搏测量将和 ECG、房颤与异常心率事件一起作为专项监测能力逐步补齐。",
                status: .partial
            )
        ]

        return HeartClinicalMonitorSummary(
            headline: "监测与告警",
            detail: "把房颤历史、异常心率提醒、血压与逐搏测量放在一起，更适合做心率的临床监测补充阅读。",
            items: items
        )
    }

    static func heartECGClassificationDetail(for title: String) -> String {
        switch title {
        case "窦性心律":
            return String(localized: "当前记录更接近规则窦性节律，可继续结合症状与连续心率趋势一起判断。")
        case "房颤提示":
            return String(localized: "本次记录提示存在房颤风险，建议结合房颤历史与医生建议进一步核对。")
        default:
            return String(localized: "这条 ECG 记录可作为离散节律检查结果，用于补充连续心率趋势判断。")
        }
    }

    static func heartMonitorStatus(hasRecord: Bool) -> TrendCategoryStatus {
        hasRecord ? .ready : .noData
    }

    static func heartMonitorStatus(forDate date: Date?) -> TrendCategoryStatus {
        heartMonitorStatus(hasRecord: date != nil)
    }

    static func heartMonitorValueText(status: TrendCategoryStatus, readyText: String) -> String {
        switch status {
        case .ready:
            return readyText
        case .noData:
            return String(localized: "无数据")
        case .partial:
            return String(localized: "可查看")
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

}
