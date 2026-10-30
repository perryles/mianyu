/// PeriodSheetView 由经期记录入口调用，作为「周期记录」弹层。
/// 负责按分区（日志/症状/事件/验孕/基础体温/点滴）录入当天经期数据。

import SwiftUI

/// 周期视图 由上级页面或路由调用，作为习惯模块里的界面或内容组件。
/// 负责展示行为打卡、日常记录与习惯分析内容。
struct PeriodSheetView: View {
    enum FocusSection: String {
        case dayLog
        case symptoms
        case events
        case pregnancyTest
        case basalTemperature
        case spotting
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PeriodViewModel
    var focusSection: FocusSection = .dayLog
    @State private var showsSymptomNote = false
    @FocusState private var basalTemperatureFocused: Bool

    private let periodTint = Color(hex: "F46B5A")
    private let fertileTint = Color(hex: "4C7DFF")
    private let symptomTint = Color(hex: "B53368")
    private let symptomInk = Color(hex: "343841")
    private let topAnchorID = "period-sheet-top"
    private let dayLogAnchorID = "period-sheet-day-log"
    private let symptomsAnchorID = "period-sheet-symptoms"
    private let eventsAnchorID = "period-sheet-events"
    private let pregnancyTestAnchorID = "period-sheet-pregnancy-test"
    private let basalTemperatureAnchorID = "period-sheet-basal-temperature"
    private let spottingAnchorID = "period-sheet-spotting"

    var body: some View {
        NavigationStack {
            ZStack {
                sheetBackground

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            Color.clear
                                .frame(height: 0)
                                .id(topAnchorID)

                            if focusSection == .dayLog {
                                flowFocusCard
                                    .id(dayLogAnchorID)
                            } else if focusSection == .symptoms {
                                symptomsFocusCard
                                    .id(symptomsAnchorID)
                            } else if focusSection == .pregnancyTest {
                                pregnancyTestFocusCard
                                    .id(pregnancyTestAnchorID)
                            } else if focusSection == .basalTemperature {
                                basalTemperatureFocusCard
                                    .id(basalTemperatureAnchorID)
                            } else if focusSection == .spotting {
                                spottingFocusCard
                                    .id(spottingAnchorID)
                            } else {
                                eventsFocusCard
                                    .id(eventsAnchorID)
                            }

                            if let message = viewModel.errorMessage, !message.isEmpty {
                                Text(message)
                                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: 720)
                        .padding(Theme.Layout.padding)
                        .padding(.top, 8)
                        .padding(.bottom, 56)
                    }
                    .onAppear {
                        viewModel.reload()
                        showsSymptomNote = !viewModel.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        DispatchQueue.main.async {
                            scrollToFocusSection(with: proxy, animated: false)
                        }
                    }
                    .onChange(of: focusSection) { _, _ in
                        scrollToFocusSection(with: proxy, animated: true)
                    }
                }
            }
            .navigationTitle(focusNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.locale, Locale.autoupdatingCurrent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancelAndDismiss() }
                }
                if focusSection == .basalTemperature {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { basalTemperatureFocused = false }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                focusedSaveBar
            }
        }
    }

    private var focusNavigationTitle: String {
        switch focusSection {
        case .dayLog: return String(localized: "记录经期")
        case .symptoms: return String(localized: "记录当前症状")
        case .events: return String(localized: "记录生育信号")
        case .pregnancyTest: return String(localized: "记录妊娠测试")
        case .basalTemperature: return String(localized: "记录基础体温")
        case .spotting: return String(localized: "记录点滴出血")
        }
    }

    private var symptomsFocusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            symptomsHeroCard
            wellnessStateCard
            symptomPickerCard
            intensityCard
            symptomNoteCard
        }
    }

    @ViewBuilder
    private var sheetBackground: some View {
        switch focusSection {
        case .dayLog:
            LinearGradient(
                colors: [Color(hex: "FFF1EF"), Color(hex: "F6F8F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        case .symptoms:
            LinearGradient(
                colors: [Color(hex: "FFF5F7"), Color(hex: "F4F8F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        case .events:
            LinearGradient(
                colors: [Color(hex: "EEF5FF"), Color(hex: "F5F9F7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        case .pregnancyTest:
            LinearGradient(
                colors: [Color(hex: "FFF1F7"), Color(hex: "F8F7F3")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        case .basalTemperature:
            LinearGradient(
                colors: [Color(hex: "ECF8F6"), Color(hex: "F7F9F7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        case .spotting:
            LinearGradient(
                colors: [Color(hex: "FFF6EA"), Color(hex: "F9F7F4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var symptomsHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(symptomTint)
                    .frame(width: 44, height: 44)
                    .background(symptomTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("今天的症状")
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(symptomInk)

                    Text("记录经期外状态、阶段波动和当天症状。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .overlay(Theme.Colors.surfaceBorder)

            DatePicker(
                "记录日期",
                selection: Binding(
                    get: { viewModel.selectedLogDate },
                    set: { viewModel.selectLog(date: $0) }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            .datePickerStyle(.compact)
            .tint(symptomTint)
            .accessibilityIdentifier("period.symptoms.date")
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [Color.white, Color(hex: "FFF8FA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: symptomTint.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private var wellnessStateCard: some View {
        symptomSectionCard(title: "今日女性状态", systemImage: "heart.text.square.fill") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(FemaleWellnessState.allCases) { state in
                    let isSelected = viewModel.femaleWellnessState == state
                    Button {
                        viewModel.femaleWellnessState = state
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: state.systemImage)
                                .font(.appSystem(size: 15, weight: .black))
                            Text(state.title)
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundColor(isSelected ? .white : Color(hex: "59606A"))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            isSelected ? symptomTint : Color(hex: "F6F5F3"),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.title)
                    .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
                    .accessibilityIdentifier("period.symptoms.state.\(state.rawValue)")
                }
            }
        }
    }

    private var symptomPickerCard: some View {
        symptomSectionCard(title: "今天的症状", systemImage: "cross.case.fill") {
            HStack {
                Text(viewModel.selectedSymptoms.isEmpty ? "未选择" : "已选择")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer(minLength: 8)

                Text("\(viewModel.selectedSymptoms.count)/\(FemaleSymptom.allCases.count)")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(symptomTint)
                    .monospacedDigit()
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(FemaleSymptom.allCases) { symptom in
                    symptomButton(symptom)
                }
            }
        }
    }

    private func symptomButton(_ symptom: FemaleSymptom) -> some View {
        let isSelected = viewModel.selectedSymptoms.contains(symptom)

        return Button {
            viewModel.toggleSymptom(symptom)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symptom.systemImage)
                    .font(.appSystem(size: 16, weight: .black))
                Text(symptom.title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "565D66"))
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                isSelected ? symptomTint : Color(hex: "F6F5F3"),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(symptomTint.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symptom.title)
        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
        .accessibilityIdentifier("period.symptoms.item.\(symptom.rawValue)")
    }

    private var intensityCard: some View {
        symptomSectionCard(title: "疼痛与情绪", systemImage: "dial.medium.fill") {
            symptomIntensityControl(
                title: "疼痛等级",
                systemImage: "waveform.path.ecg",
                value: $viewModel.painLevel,
                tint: periodTint,
                identifier: "pain"
            )

            symptomIntensityControl(
                title: "情绪波动",
                systemImage: "heart.fill",
                value: $viewModel.moodLevel,
                tint: Color(hex: "657BD9"),
                identifier: "mood"
            )
        }
    }

    private func symptomIntensityControl(
        title: String,
        systemImage: String,
        value: Binding<Int>,
        tint: Color,
        identifier: String
    ) -> some View {
        let selectedIntensity = PeriodSymptomIntensity(level: value.wrappedValue)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(tint)
                Text(title)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(symptomInk)
                Spacer(minLength: 8)
                Text(selectedIntensity.title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(tint)
            }

            HStack(spacing: 7) {
                ForEach(PeriodSymptomIntensity.allCases) { intensity in
                    let isSelected = selectedIntensity == intensity
                    Button {
                        value.wrappedValue = intensity.rawValue
                    } label: {
                        Text(intensity.title)
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .white : Color(hex: "656B73"))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                isSelected ? tint : Color(hex: "F4F4F2"),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) · \(intensity.title)")
                    .accessibilityIdentifier("period.symptoms.\(identifier).\(intensity.rawValue)")
                }
            }
        }
        .padding(12)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var symptomNoteCard: some View {
        VStack(spacing: 10) {
            Button {
                showsSymptomNote.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.appSystem(size: 14, weight: .black))
                    Text("补充备注")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Image(systemName: showsSymptomNote ? "chevron.up" : "chevron.down")
                        .font(.appSystem(size: 11, weight: .black))
                }
                .foregroundColor(Color(hex: "666D76"))
                .frame(minHeight: 48)
                .padding(.horizontal, 14)
                .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("period.symptoms.note.toggle")

            if showsSymptomNote {
                TextEditor(text: $viewModel.note)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
                    )
                    .accessibilityIdentifier("period.symptoms.note.editor")
            }
        }
    }

    private func symptomSectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(symptomInk)
            content()
        }
        .padding(15)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    }

    private var symptomsSaveBar: some View {
        Button {
            saveAndDismiss()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appSystem(size: 16, weight: .bold))
                    Text("保存症状记录")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(symptomTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("period.symptoms.save")
    }

    private var flowFocusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.appSystem(size: 20, weight: .black))
                        .foregroundColor(periodTint)
                        .frame(width: 46, height: 46)
                        .background(periodTint.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("今天有出血吗？")
                            .font(.appSystem(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(symptomInk)
                        Text("先确认今天是否处于经期，再选择大致月经量。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                DatePicker(
                    "记录日期",
                    selection: selectedLogDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .datePickerStyle(.compact)
                .tint(periodTint)
                .accessibilityIdentifier("period.flow.date")
            }
            .padding(17)
            .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: periodTint.opacity(0.08), radius: 16, x: 0, y: 8)

            HStack(spacing: 10) {
                flowPresenceButton(
                    title: "有出血",
                    systemImage: "drop.fill",
                    isSelected: viewModel.flowLevel > 0,
                    identifier: "bleeding"
                ) {
                    if viewModel.flowLevel == 0 {
                        viewModel.flowLevel = 2
                    }
                }

                flowPresenceButton(
                    title: "未出血",
                    systemImage: "circle.slash",
                    isSelected: viewModel.flowLevel == 0,
                    identifier: "no-bleeding"
                ) {
                    viewModel.flowLevel = 0
                }
            }

            if viewModel.flowLevel > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("月经量")
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(symptomInk)

                    HStack(spacing: 9) {
                        flowAmountButton(title: "量少", level: 1, dropCount: 1)
                        flowAmountButton(title: "中等", level: 2, dropCount: 2)
                        flowAmountButton(title: "量多", level: 3, dropCount: 3)
                    }
                }
                .padding(16)
                .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Label("未出血也会保存为当天记录。", systemImage: "checkmark.circle.fill")
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "617068"))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var eventsFocusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.appSystem(size: 18, weight: .black))
                        .foregroundColor(fertileTint)
                        .frame(width: 44, height: 44)
                        .background(fertileTint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("生育信号")
                            .font(.appSystem(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(symptomInk)
                        Text("只记录你主动选择的项目，可随时留空。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                DatePicker(
                    "记录日期",
                    selection: selectedLogDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .datePickerStyle(.compact)
                .tint(fertileTint)
                .accessibilityIdentifier("period.events.date")
            }
            .padding(17)
            .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button {
                viewModel.hasSexualActivity.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.hasSexualActivity ? "checkmark.circle.fill" : "circle")
                        .font(.appSystem(size: 22, weight: .black))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今天有性行为")
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        Text(viewModel.hasSexualActivity ? "已记录" : "未记录")
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "heart.fill")
                        .font(.appSystem(size: 16, weight: .bold))
                }
                .foregroundColor(viewModel.hasSexualActivity ? .white : Color(hex: "4E5967"))
                .padding(.horizontal, 16)
                .frame(minHeight: 68)
                .background(
                    viewModel.hasSexualActivity ? fertileTint : Color.white.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("period.events.sexual-activity")

            eventChoiceSection(
                title: "排卵测试",
                systemImage: "checkmark.seal.fill",
                options: [
                    ("未记录", ""),
                    ("阴性", "negative"),
                    ("阳性", "positive"),
                    ("峰值", "peak"),
                    ("待确认", "inconclusive")
                ],
                selection: $viewModel.ovulationTestResult,
                identifier: "ovulation"
            )

            eventChoiceSection(
                title: "宫颈黏液",
                systemImage: "drop.fill",
                options: [
                    ("未记录", ""),
                    ("偏干", "dry"),
                    ("黏稠", "sticky"),
                    ("乳霜样", "creamy"),
                    ("水样", "watery"),
                    ("蛋清样", "eggWhite")
                ],
                selection: $viewModel.cervicalMucusQuality,
                identifier: "mucus"
            )
        }
    }

    private var pregnancyTestFocusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "cross.vial.fill")
                        .font(.appSystem(size: 20, weight: .black))
                        .foregroundColor(symptomTint)
                        .frame(width: 46, height: 46)
                        .background(symptomTint.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text("妊娠测试结果")
                            .font(.appSystem(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(symptomInk)
                        Text("选择与试纸或检测设备一致的结果。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                DatePicker(
                    "检测日期",
                    selection: selectedLogDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .datePickerStyle(.compact)
                .tint(symptomTint)
                .accessibilityIdentifier("period.pregnancy-test.date")
            }
            .padding(18)
            .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: symptomTint.opacity(0.07), radius: 18, x: 0, y: 9)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                spacing: 10
            ) {
                pregnancyTestChoice(
                    title: "未记录",
                    detail: "尚未检测",
                    systemImage: "circle.dashed",
                    value: "",
                    tint: Color(hex: "7B818A")
                )
                pregnancyTestChoice(
                    title: "阴性",
                    detail: "未检测到",
                    systemImage: "minus.circle.fill",
                    value: "negative",
                    tint: Color(hex: "3F9D7D")
                )
                pregnancyTestChoice(
                    title: "阳性",
                    detail: "检测到结果",
                    systemImage: "plus.circle.fill",
                    value: "positive",
                    tint: symptomTint
                )
                pregnancyTestChoice(
                    title: "待确认",
                    detail: "结果不清晰",
                    systemImage: "questionmark.circle.fill",
                    value: "inconclusive",
                    tint: Color(hex: "C58A33")
                )
            }

            Label("家庭检测结果仅作记录，如有疑问请咨询专业人员。", systemImage: "info.circle.fill")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "74717A"))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var basalTemperatureFocusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 18) {
                Image(systemName: "thermometer.medium")
                    .font(.appSystem(size: 30, weight: .black))
                    .foregroundColor(Color(hex: "2E9C8B"))
                    .frame(width: 70, height: 70)
                    .background(Color(hex: "DDF4EF"), in: Circle())

                VStack(spacing: 5) {
                    Text("基础体温")
                        .font(.appSystem(size: 23, weight: .black, design: .rounded))
                        .foregroundColor(symptomInk)
                    Text("建议在醒来后、起床活动前测量。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("36.5", text: $viewModel.basalBodyTemperatureText)
                        .font(.appSystem(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(symptomInk)
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .focused($basalTemperatureFocused)
                        .accessibilityIdentifier("period.temperature.input")

                    Text("°C")
                        .font(.appSystem(size: 19, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "5D6F6B"))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 82)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("可记录 30.0–45.0°C")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(
                        basalTemperatureEntry.isValid || viewModel.basalBodyTemperatureText.isEmpty
                            ? Theme.Colors.textSecondary
                            : Color(hex: "B94B55")
                    )

                DatePicker(
                    "测量日期",
                    selection: selectedLogDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .datePickerStyle(.compact)
                .tint(Color(hex: "2E9C8B"))
                .accessibilityIdentifier("period.temperature.date")
            }
            .padding(20)
            .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color(hex: "2E9C8B").opacity(0.08), radius: 18, x: 0, y: 9)

            Label("每天尽量在相近时间、相近条件下测量，趋势会更有参考价值。", systemImage: "chart.line.uptrend.xyaxis")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "60716D"))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .onAppear { basalTemperatureFocused = viewModel.basalBodyTemperatureText.isEmpty }
    }

    private var spottingFocusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: "drop.triangle.fill")
                        .font(.appSystem(size: 22, weight: .black))
                        .foregroundColor(Color(hex: "C67842"))
                        .frame(width: 52, height: 52)
                        .background(Color(hex: "FBE8D5"), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("点滴出血")
                            .font(.appSystem(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(symptomInk)
                        Text("记录经期之外出现的少量出血。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                DatePicker(
                    "记录日期",
                    selection: selectedLogDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .datePickerStyle(.compact)
                .tint(Color(hex: "C67842"))
                .accessibilityIdentifier("period.spotting.date")
            }
            .padding(18)
            .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text("是否记录点滴出血？")
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(symptomInk)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                spottingChoice(
                    title: "未记录",
                    detail: "今天不添加",
                    systemImage: "circle.slash",
                    isSelected: !viewModel.hasIntermenstrualBleeding,
                    identifier: "none"
                ) {
                    viewModel.hasIntermenstrualBleeding = false
                }

                spottingChoice(
                    title: "已记录",
                    detail: "今天出现过",
                    systemImage: "drop.fill",
                    isSelected: viewModel.hasIntermenstrualBleeding,
                    identifier: "recorded"
                ) {
                    viewModel.hasIntermenstrualBleeding = true
                }
            }

            Label("如果出血量明显增加、持续时间较长或伴随强烈不适，请及时寻求专业帮助。", systemImage: "cross.case.fill")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "796857"))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var selectedLogDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.selectedLogDate },
            set: { viewModel.selectLog(date: $0) }
        )
    }

    private var basalTemperatureEntry: PeriodBasalTemperatureEntry {
        PeriodBasalTemperatureEntry(text: viewModel.basalBodyTemperatureText)
    }

    private func flowPresenceButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: 24, weight: .black))
                Text(title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : Color(hex: "59606A"))
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                isSelected ? periodTint : Color.white.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
        .accessibilityIdentifier("period.flow.\(identifier)")
    }

    private func flowAmountButton(title: String, level: Int, dropCount: Int) -> some View {
        let isSelected = level == 3 ? viewModel.flowLevel >= 3 : viewModel.flowLevel == level

        return Button {
            viewModel.flowLevel = level
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(0..<dropCount, id: \.self) { _ in
                        Image(systemName: "drop.fill")
                            .font(.appSystem(size: 10, weight: .black))
                    }
                }
                Text(title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : periodTint)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                isSelected ? periodTint : periodTint.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
        .accessibilityIdentifier("period.flow.level.\(level)")
    }

    private func eventChoiceSection(
        title: String,
        systemImage: String,
        options: [(String, String)],
        selection: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(symptomInk)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(options, id: \.1) { option in
                    let isSelected = selection.wrappedValue == option.1
                    Button {
                        selection.wrappedValue = option.1
                    } label: {
                        Text(option.0)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .white : Color(hex: "586472"))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                isSelected ? fertileTint : Color(hex: "F1F5F8"),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
                    .accessibilityIdentifier("period.events.\(identifier).\(option.1.isEmpty ? "none" : option.1)")
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func pregnancyTestChoice(
        title: String,
        detail: String,
        systemImage: String,
        value: String,
        tint: Color
    ) -> some View {
        let isSelected = viewModel.pregnancyTestResult == value

        return Button {
            viewModel.pregnancyTestResult = value
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 21, weight: .black))
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.appSystem(size: 15, weight: .black))
                    }
                }
                Text(title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                Text(detail)
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.82)
            }
            .foregroundColor(isSelected ? .white : tint)
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                isSelected ? tint : Color.white.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
        .accessibilityIdentifier("period.pregnancy-test.\(value.isEmpty ? "none" : value)")
    }

    private func spottingChoice(
        title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: 24, weight: .black))
                Text(title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                Text(detail)
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.82)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "946033"))
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(
                isSelected ? Color(hex: "C67842") : Color.white.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
        .accessibilityIdentifier("period.spotting.\(identifier)")
    }

    @ViewBuilder
    private var focusedSaveBar: some View {
        switch focusSection {
        case .dayLog:
            flowSaveBar
        case .symptoms:
            symptomsSaveBar
        case .events:
            eventsSaveBar
        case .pregnancyTest:
            pregnancyTestSaveBar
        case .basalTemperature:
            basalTemperatureSaveBar
        case .spotting:
            spottingSaveBar
        }
    }

    private var flowSaveBar: some View {
        Button(action: saveAndDismiss) {
            Label("保存经期记录", systemImage: "drop.fill")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(periodTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("period.flow.save")
    }

    private var eventsSaveBar: some View {
        Button(action: saveAndDismiss) {
            Label("保存生育信号", systemImage: "lock.shield.fill")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(fertileTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("period.events.save")
    }

    private var pregnancyTestSaveBar: some View {
        Button(action: saveAndDismiss) {
            Label("保存测试结果", systemImage: "checkmark.circle.fill")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(symptomTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("period.pregnancy-test.save")
    }

    private var basalTemperatureSaveBar: some View {
        Button(action: saveBasalTemperatureAndDismiss) {
            Label("保存基础体温", systemImage: "thermometer.medium")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    basalTemperatureEntry.isValid ? Color(hex: "2E9C8B") : Color(hex: "AEBAB7"),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!basalTemperatureEntry.isValid || viewModel.isSubmitting)
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("period.temperature.save")
    }

    private var spottingSaveBar: some View {
        Button(action: saveAndDismiss) {
            Label("保存点滴记录", systemImage: "drop.triangle.fill")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: "C67842"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("period.spotting.save")
    }

    private func scrollToFocusSection(with proxy: ScrollViewProxy, animated: Bool) {
        let targetID: String = switch focusSection {
        case .dayLog:
            dayLogAnchorID
        case .symptoms:
            symptomsAnchorID
        case .events:
            eventsAnchorID
        case .pregnancyTest:
            pregnancyTestAnchorID
        case .basalTemperature:
            basalTemperatureAnchorID
        case .spotting:
            spottingAnchorID
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(targetID, anchor: .top)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .top)
        }
    }

    private func saveAndDismiss() {
        viewModel.saveDayLog()
        dismiss()
    }

    private func saveBasalTemperatureAndDismiss() {
        guard basalTemperatureEntry.isValid else { return }
        viewModel.basalBodyTemperatureText = basalTemperatureEntry.normalizedText
        basalTemperatureFocused = false
        saveAndDismiss()
    }

    private func cancelAndDismiss() {
        viewModel.selectLog(date: viewModel.selectedLogDate)
        dismiss()
    }
}
