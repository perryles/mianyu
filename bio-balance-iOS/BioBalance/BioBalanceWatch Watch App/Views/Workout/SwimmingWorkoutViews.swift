import SwiftUI
import WatchKit

private enum SwimmingPoolPreset: CaseIterable {
    case meters25
    case meters50
    case yards25
    case custom
}

/// Watch 端游泳训练入口、实时页面和保存结果页面。
/// 会话状态与训练数据均由 SwimmingWorkoutManager 持有。
struct SwimmingWorkoutFlowView: View {
    let manager: SwimmingWorkoutManager

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocation: SwimmingWorkoutLocation = .pool
    @State private var selectedPreset: SwimmingPoolPreset = .meters25
    @State private var customLengthText = "25"
    @State private var customUnit: SwimmingPoolLengthUnit = .meters
    @State private var isRequestingAuthorization = false
    @State private var confirmsEnd = false

    private var selectedPoolLength: SwimmingPoolLength? {
        switch selectedPreset {
        case .meters25:
            return .meters25
        case .meters50:
            return .meters50
        case .yards25:
            return .yards25
        case .custom:
            let normalized = customLengthText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized) else { return nil }
            return SwimmingPoolLength(value: value, unit: customUnit)
        }
    }

    private var selectedConfiguration: SwimmingSessionConfiguration? {
        switch selectedLocation {
        case .pool:
            return selectedPoolLength.map(SwimmingSessionConfiguration.pool)
        case .openWater:
            return .openWater
        }
    }

    private var isSessionInProgress: Bool {
        switch manager.phase {
        case .preparing, .running, .paused, .ending:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    var body: some View {
        Group {
            switch manager.phase {
            case .idle where manager.isRecoveringActiveSession:
                statusView(title: "正在检查训练", detail: "确认是否恢复进行中的游泳")
            case .idle:
                setupView
            case .preparing:
                statusView(title: "训练准备中", detail: "正在启动游泳训练")
            case .running:
                workoutView(isPaused: false)
                    .task {
                        await refreshMetricsWhileVisible()
                    }
            case .paused:
                workoutView(isPaused: true)
                    .task {
                        await refreshMetricsWhileVisible()
                    }
            case .ending:
                statusView(title: "正在保存", detail: "正在保存游泳训练结果")
            case .finished:
                resultView
            case .failed:
                failureView
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("游泳训练")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSessionInProgress || manager.phase == .finished)
        .confirmationDialog("结束游泳训练？", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("结束并保存", role: .destructive) {
                manager.end()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedLocation == .pool ? "泳池训练" : "开放水域")
                        .font(.watchAppSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(selectedLocation == .pool ? "开始前设置泳池长度" : "使用 GPS 记录开放水域路线")
                        .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                }

                HStack(spacing: 7) {
                    locationButton(.pool, title: String(localized: "泳池"))
                    locationButton(.openWater, title: String(localized: "开放水域"))
                }

                if selectedLocation == .pool {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("泳池长度")
                            .font(.watchAppSystem(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))

                        HStack(spacing: 7) {
                            presetButton(.meters25, title: String(localized: "25 米"))
                            presetButton(.meters50, title: String(localized: "50 米"))
                        }
                        HStack(spacing: 7) {
                            presetButton(.yards25, title: String(localized: "25 码"))
                            presetButton(.custom, title: String(localized: "自定义"))
                        }

                        if selectedPreset == .custom {
                            HStack(spacing: 8) {
                                TextField("长度", text: $customLengthText)
                                    .font(.watchAppSystem(size: 17, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityLabel("自定义泳池长度")
                                HStack(spacing: 6) {
                                    lengthUnitButton(.meters, title: "米")
                                    lengthUnitButton(.yards, title: "码")
                                }
                                .accessibilityLabel("泳池长度单位")
                            }
                        }

                        if selectedPoolLength == nil {
                            Text("请输入有效的泳池长度")
                                .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.orange)
                                .accessibilityLabel("请输入有效的泳池长度")
                        }
                    }
                    .padding(11)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if manager.authorizationRequiresRequest {
                    Button {
                        Task {
                            isRequestingAuthorization = true
                            await manager.requestAuthorization()
                            isRequestingAuthorization = false
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if isRequestingAuthorization {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "heart.text.square.fill")
                            }
                            Text(isRequestingAuthorization ? String(localized: "正在授权") : String(localized: "授权健康数据"))
                                .font(.watchAppSystem(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.mint)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingAuthorization)
                }

                Button {
                    guard let configuration = selectedConfiguration else { return }
                    Task { await manager.start(configuration: configuration) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.pool.swim")
                        Text("开始游泳")
                    }
                    .font(.watchAppSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.mint, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selectedConfiguration == nil)
                .opacity(selectedConfiguration == nil ? 0.45 : 1)
                .accessibilityLabel("开始游泳训练")
                .accessibilityHint(selectedLocation == .pool ? "使用所选泳池长度开始记录训练" : "使用 GPS 记录开放水域游泳训练")

                if let error = manager.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func locationButton(_ location: SwimmingWorkoutLocation, title: String) -> some View {
        let selected = selectedLocation == location
        return Button {
            selectedLocation = location
        } label: {
            Text(title)
                .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.mint : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private func presetButton(_ preset: SwimmingPoolPreset, title: String) -> some View {
        let selected = selectedPreset == preset
        return Button {
            selectedPreset = preset
            switch preset {
            case .meters25, .meters50:
                customUnit = .meters
            case .yards25:
                customUnit = .yards
            case .custom:
                break
            }
        } label: {
            Text(title)
                .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    selected ? Color.mint : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(selected ? Color.mint : Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private func lengthUnitButton(_ unit: SwimmingPoolLengthUnit, title: String) -> some View {
        let selected = customUnit == unit
        return Button {
            customUnit = unit
        } label: {
            Text(title)
                .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? Color.mint : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? String(localized: "已选择") : String(localized: "未选择"))
    }

    private func workoutView(isPaused: Bool) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text(isPaused ? "已暂停" : "游泳中")
                        .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isPaused ? .orange : .mint)
                    Text(formattedDuration(manager.metrics.duration) ?? "--:--")
                        .font(.watchAppSystem(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("训练时长，\(formattedDuration(manager.metrics.duration) ?? String(localized: "暂无"))")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                metricsGrid

                HStack(spacing: 8) {
                    Button {
                        if isPaused {
                            manager.resume()
                        } else {
                            manager.pause()
                        }
                    } label: {
                        Label(isPaused ? "继续" : "暂停", systemImage: isPaused ? "play.fill" : "pause.fill")
                            .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(isPaused ? Color.mint : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .foregroundStyle(isPaused ? .black : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isPaused ? "继续记录游泳训练" : "暂时停止训练计时")

                    Button(role: .destructive) {
                        confirmsEnd = true
                    } label: {
                        Label("结束", systemImage: "stop.fill")
                            .font(.watchAppSystem(size: 12, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.red.opacity(0.19), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .foregroundStyle(.red.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("结束并保存这次游泳训练")
                }

                if canEnableWaterLock {
                    Button {
                        WKInterfaceDevice.current().enableWaterLock()
                    } label: {
                        Label("开启水锁", systemImage: "drop.fill")
                            .font(.watchAppSystem(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("锁定屏幕触控，旋转数码表冠解锁")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func refreshMetricsWhileVisible() async {
        while !Task.isCancelled {
            manager.refreshMetricsForDisplay()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private var canEnableWaterLock: Bool {
        let device = WKInterfaceDevice.current()
        return manager.phase == .running
            && device.waterResistanceRating == .wr50
            && !device.isWaterLockEnabled
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            SwimmingMetricCard(title: "距离", value: formattedDistance(manager.metrics.distanceMeters), unit: "米")
            if manager.sessionLocation == .pool {
                SwimmingMetricCard(title: "趟数", value: manager.metrics.lapCount.map { String($0) }, unit: "趟")
            }
            SwimmingMetricCard(title: "实时心率", value: formattedInteger(manager.metrics.currentHeartRateBPM), unit: "bpm")
            SwimmingMetricCard(title: "平均心率", value: formattedInteger(manager.metrics.averageHeartRateBPM), unit: "bpm")
            SwimmingMetricCard(title: "活动能量", value: formattedEnergy(manager.metrics.activeEnergyKilocalories), unit: "千卡")
            SwimmingMetricCard(title: "划水次数", value: manager.metrics.strokeCount.map { String($0) }, unit: "次")
            SwimmingMetricCard(title: "平均配速", value: formattedPace(manager.metrics.averagePaceSecondsPer100Meters), unit: "/100 米")
        }
    }

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.mint)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("训练已保存")
                        .font(.watchAppSystem(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("训练结果已保存到健康记录")
                        .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                }
                metricsGrid
                Button {
                    manager.reset()
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.watchAppSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("返回眠屿手表首页")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    private var failureView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("游泳训练未能完成")
                    .font(.watchAppSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(manager.errorMessage ?? String(localized: "游泳训练暂不可用"))
                    .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("训练错误，\(manager.errorMessage ?? String(localized: "游泳训练暂不可用"))")
                metricsGrid
                if manager.canRetrySave {
                    Button {
                        manager.retrySave()
                    } label: {
                        Text("重试保存")
                            .font(.watchAppSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("再次尝试保存这次游泳训练")
                }

                Button {
                    manager.reset()
                } label: {
                    Text("重新设置")
                        .font(.watchAppSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    private func statusView(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.mint)
            Text(title)
                .font(.watchAppSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func formattedDuration(_ duration: TimeInterval?) -> String? {
        SwimmingMetricsCalculator.durationText(duration)
    }

    private func formattedDistance(_ distance: Double?) -> String? {
        guard let distance, distance.isFinite, distance >= 0 else { return nil }
        return distance.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func formattedInteger(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func formattedEnergy(_ energy: Double?) -> String? {
        guard let energy, energy.isFinite, energy >= 0 else { return nil }
        return energy.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func formattedPace(_ seconds: Double?) -> String? {
        SwimmingMetricsCalculator.paceText(seconds)
    }
}

private struct SwimmingMetricCard: View {
    let title: LocalizedStringKey
    let value: String?
    let unit: LocalizedStringKey

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.watchAppSystem(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value ?? "--")
                .font(.watchAppSystem(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(value == nil ? .white.opacity(0.48) : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(unit)
                .font(.watchAppSystem(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 61)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
