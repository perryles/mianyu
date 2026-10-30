import SwiftUI

private enum BreathingPhase: String {
    case inhale, hold, exhale
    var title: String {
        switch self { case .inhale: return String(localized: "吸气"); case .hold: return String(localized: "停留"); case .exhale: return String(localized: "呼气") }
    }
    var duration: Int { switch self { case .inhale, .hold: return 4; case .exhale: return 6 } }
    var guidance: String {
        switch self {
        case .inhale: return String(localized: "让肩膀放松，慢慢吸气")
        case .hold: return String(localized: "轻轻停留，不要憋气")
        case .exhale: return String(localized: "缓慢呼气，让身体松下来")
        }
    }
}

struct BreathingVitals {
    let stress: Int?
    let heartRate: Int?
    let respiratoryRate: Double?
}

struct BalancedBreathingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: BreathingPhase = .inhale
    @State private var phaseRemaining = 4
    @State private var remaining = 180
    @State private var isRunning = false
    @State private var isCompleted = false
    @State private var startDate: Date?
    @State private var before: BreathingVitals?
    @State private var after: BreathingVitals?
    @State private var completionFeedback = 0
    @State private var completedDuration = 180
    @State private var latestRespiratoryRate: Double?

    private let totalSeconds = 180
    private var elapsed: Int { totalSeconds - remaining }
    private var round: Int { min(13, elapsed / 14 + 1) }
    private var progress: Double { Double(elapsed) / Double(totalSeconds) }

    var body: some View {
        ZStack {
            EmotionStressStyle.page.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "EBF7FF").opacity(0.7), Color(hex: "F2EDFF").opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center)
                .ignoresSafeArea().allowsHitTesting(false)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    EmotionStressPageHeader(title: String(localized: "呼吸放松"), subtitle: String(localized: "把注意力交给呼吸，让节奏慢下来"))
                    breathingRing
                    phaseStrip
                    progressSection
                    controls
                    Text("如感到不适，请停止练习并按需要寻求帮助。")
                        .font(.caption).foregroundStyle(EmotionStressStyle.tertiary).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 30)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $isCompleted) {
            BreathingCompletionView(before: before, after: after, durationSeconds: completedDuration)
        }
        .task(id: isRunning) {
            guard isRunning else { return }
            while isRunning, remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, isRunning else { return }
                tick()
            }
        }
        .onDisappear { isRunning = false }
        .sensoryFeedback(.success, trigger: completionFeedback)
        .task {
            let start = Calendar.current.startOfDay(for: .now)
            latestRespiratoryRate = try? await HealthKitManager.shared.fetchRespiratoryRateSeries(start: start, end: .now).last?.value
        }
    }

    private var breathingRing: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: "E8E1FF").opacity(0.38)).frame(width: 260, height: 260)
                Circle().stroke(Color(hex: "CEC3FF").opacity(0.75), lineWidth: 22).frame(width: 205, height: 205)
                Circle().fill(.white).frame(width: 160, height: 160)
                VStack(spacing: 4) {
                    Text(phase.title).font(.title2.weight(.bold))
                    Text("\(phaseRemaining)").font(.system(size: 34, weight: .bold)).foregroundStyle(phase == .exhale ? EmotionStressStyle.mint : Color(hex: "6F63D7"))
                    Text("秒").font(.caption).foregroundStyle(EmotionStressStyle.tertiary)
                }
            }
            .scaleEffect(reduceMotion ? 1 : ringScale)
            .opacity(reduceMotion ? (phase == .hold ? 0.88 : 1) : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : .easeInOut(duration: Double(phase.duration)), value: phase)
            Text(phase.guidance).font(.subheadline).foregroundStyle(EmotionStressStyle.secondary).frame(maxWidth: .infinity)
        }
    }

    private var ringScale: CGFloat {
        switch phase { case .inhale, .hold: return 1; case .exhale: return 0.82 }
    }

    private var phaseStrip: some View {
        HStack(spacing: 4) {
            phasePill(.inhale); phasePill(.hold); phasePill(.exhale)
        }.padding(8).background(Theme.Colors.surface, in: Capsule()).overlay(Capsule().stroke(EmotionStressStyle.border))
    }
    private func phasePill(_ item: BreathingPhase) -> some View {
        Text("\(item.title) \(item.duration)秒")
            .font(.caption.weight(phase == item ? .bold : .regular)).foregroundStyle(phase == item ? .white : EmotionStressStyle.secondary)
            .frame(maxWidth: .infinity, minHeight: 34).background(phase == item ? EmotionStressStyle.ink : .clear, in: Capsule())
    }
    private var progressSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("第 \(round) / 13 轮").font(.subheadline.weight(.bold))
                Spacer()
                Text("剩余 \(remaining / 60):\(String(format: "%02d", remaining % 60))").font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
            }
            ProgressView(value: progress).tint(EmotionStressStyle.mintMuted)
        }
    }
    private var controls: some View {
        VStack(spacing: 10) {
            Button(isRunning ? "暂停" : (startDate == nil ? "开始练习" : "继续练习")) { toggle() }
                .buttonStyle(BBPrimaryButtonStyle(isFullWidth: true))
            if startDate != nil {
                Button("结束练习") { Task { await finish(early: true) } }
                    .buttonStyle(BBSecondaryButtonStyle(isFullWidth: true))
            }
        }
    }
    private func toggle() {
        if startDate == nil {
            startDate = .now
            before = currentVitals()
        }
        isRunning.toggle()
    }
    private func tick() {
        remaining -= 1
        phaseRemaining -= 1
        if remaining == 0 { Task { await finish(early: false) }; return }
        if phaseRemaining == 0 {
            switch phase { case .inhale: phase = .hold; case .hold: phase = .exhale; case .exhale: phase = .inhale }
            phaseRemaining = phase.duration
        }
    }
    private func finish(early: Bool) async {
        isRunning = false
        guard let startDate else { return }
        let end = Date()
        if end > startDate {
            try? await HealthKitManager.shared.saveMindfulSession(start: startDate, end: end)
        }
        after = currentVitals()
        completedDuration = max(1, Int(end.timeIntervalSince(startDate).rounded()))
        completionFeedback += 1
        isCompleted = true
    }
    private func currentVitals() -> BreathingVitals {
        let realtime = HealthDataManager.shared.realtimeHealth
        return BreathingVitals(
            stress: realtime.flatMap { $0.stress_value > 0 ? $0.stress_value : nil },
            heartRate: realtime.flatMap { $0.bpm > 0 ? $0.bpm : nil },
            respiratoryRate: latestRespiratoryRate
        )
    }
}

struct BreathingCompletionView: View {
    let before: BreathingVitals?
    let after: BreathingVitals?
    let durationSeconds: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mindfulDays: [TimeSeriesPointDouble] = []

    var body: some View {
        ZStack {
            EmotionStressStyle.page.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EmotionStressPageHeader(title: String(localized: "练习完成"), subtitle: String(localized: "\(max(1, durationSeconds / 60)) 分钟 · 平衡呼吸"))
                    VStack(spacing: 5) {
                        Text("完成").font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                        Text(String(format: "%d:%02d", durationSeconds / 60, durationSeconds % 60)).font(.title3.weight(.bold))
                    }.frame(width: 118, height: 118).background(EmotionStressStyle.mintFill, in: Circle()).frame(maxWidth: .infinity)
                    bodyChanges
                    EmotionStressCard(fill: EmotionStressStyle.mintFill) {
                        Text("恢复反馈").font(.subheadline.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                        Text(feedbackText).font(.subheadline.weight(.semibold))
                        Text("本次练习后，当前身体信号可用于观察放松趋势，不代表治疗效果。").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                    }
                    weeklyPractice
                    Button("返回情绪与压力") { dismiss() }.buttonStyle(BBPrimaryButtonStyle(isFullWidth: true))
                    Text("练习结果用于帮助观察趋势，不用于医疗诊断。").font(.caption).foregroundStyle(EmotionStressStyle.tertiary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 30)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { mindfulDays = (try? await HealthKitManager.shared.fetchDailyMindfulMinutes(days: 7)) ?? [] }
    }
    private var bodyChanges: some View {
        EmotionStressCard {
            VStack(spacing: 12) {
                Text("身体变化").font(.headline.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
                HStack { Text(""); Spacer(); Text("练习前"); Spacer(); Text("练习后") }.font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                comparison("压力", before?.stress.map(String.init), after?.stress.map(String.init))
                comparison("心率", before?.heartRate.map { "\($0) bpm" }, after?.heartRate.map { "\($0) bpm" })
                comparison("呼吸", before?.respiratoryRate.map { "\(Int($0.rounded())) 次/分" }, after?.respiratoryRate.map { "\(Int($0.rounded())) 次/分" })
            }
        }
    }
    private func comparison(_ title: String, _ lhs: String?, _ rhs: String?) -> some View {
        HStack { Text(title).font(.caption.weight(.bold)); Spacer(); Text(lhs ?? "--"); Spacer(); Text(rhs ?? "--").foregroundStyle(EmotionStressStyle.mint) }
            .font(.caption.weight(.semibold)).accessibilityElement(children: .combine)
    }
    private var feedbackText: String {
        guard let beforeStress = before?.stress, let afterStress = after?.stress else { return "练习已记录；等待更多身体信号后可比较前后变化。" }
        let delta = beforeStress - afterStress
        if delta > 0 { return "当前压力读数较练习前下降 \(delta)。" }
        return "当前压力读数暂无明确下降，建议结合后续趋势继续观察。"
    }
    private var weeklyPractice: some View {
        let total = Int(mindfulDays.map(\.value).reduce(0, +).rounded())
        let days = mindfulDays.filter { $0.value > 0 }.count
        return EmotionStressCard {
            Text("本周练习").font(.headline.weight(.bold))
            HStack(alignment: .firstTextBaseline) {
                Text("\(days) 天").font(.title.weight(.bold))
                Text("累计 \(total) 分钟").font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
            }
            ProgressView(value: min(1, Double(days) / 5)).tint(EmotionStressStyle.mintMuted)
            Text(days >= 5 ? "本周已有 5 天练习记录" : "距离本周 5 天练习目标还差 \(5 - days) 天").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
        }
    }
}

#Preview { NavigationStack { BalancedBreathingView() } }
