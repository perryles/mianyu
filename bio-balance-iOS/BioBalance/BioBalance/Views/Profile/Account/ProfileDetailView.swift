/// ProfileDetailView 由 ProfileView 我的信息入口调用，作为「我的信息」详情编辑页。
/// 负责展示昵称、Watch 头像配饰与来自 Apple 健康的基础数据。

import SwiftUI

/// ProfileDetailView 由 ProfileView 调用，作为「我的信息」详情编辑页。
/// 负责展示昵称、Watch 头像配饰与来自 Apple 健康的基础数据。
struct ProfileDetailView: View {
    @AppStorage("userNickname") private var storedNickname: String = ""
    @AppStorage("watchThemeId") private var watchThemeId: String = "joey"

    @State private var isLoadingHealthProfile = false
    @State private var healthSexText = String(localized: "读取中")
    @State private var healthAgeText = ""

    private let cardBorder = Theme.Colors.surfaceBorder
    private let ink = Color(hex: "2E3135")
    private let accessoryColumns = [
        GridItem(.adaptive(minimum: 50, maximum: 58), spacing: 18)
    ]

    var body: some View {
        ProfileSettingsPage(
            title: "我的信息",
            subtitle: "管理昵称、头像配饰和健康资料。"
        ) {
            VStack(spacing: 16) {
                heroAvatar
                    .padding(.top, 2)
                nicknameCard
                avatarAccessoryCard
                healthDataCard
                appleHealthFootnote
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .onAppear {
            AppGroupManager.shared.saveWatchThemeId(watchThemeId)
            if !isLoadingHealthProfile {
                loadHealthProfile()
            }
        }
    }

    private var heroAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Theme.Colors.mintGreen.opacity(0.16))
                .frame(width: 132, height: 132)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )

            ProfileAccessoryPortrait(accessory: selectedAccessory)
                .frame(width: 116, height: 116)
                .clipShape(Circle())

            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 48, height: 48)

                Circle()
                    .fill(Color(hex: "6B6E73"))
                    .frame(width: 35, height: 35)

                Image(systemName: "camera.fill")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(x: 2, y: -6)
        }
        .frame(maxWidth: .infinity)
    }

    private var nicknameCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            profileSectionHeader(title: "昵称")

            HStack(spacing: 12) {
                TextField("你的昵称", text: $storedNickname)
                    .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)

                Spacer(minLength: 0)

                Image(systemName: "pencil")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(ink)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 23)
        .padding(.bottom, 25)
        .background(cardBackground)
    }

    private var avatarAccessoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                profileSectionHeader(title: "头像配饰")

                Spacer(minLength: 0)

                Text("仅在手表端显示")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "9B9EA2"))
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 22) {
                    selectedAccessoryPreview

                    Spacer(minLength: 0)

                    accessoryGrid
                        .frame(width: 188)
                }

                VStack(alignment: .leading, spacing: 20) {
                    selectedAccessoryPreview
                        .frame(maxWidth: .infinity, alignment: .center)

                    accessoryGrid
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 23)
        .padding(.bottom, 28)
        .background(cardBackground)
    }

    private var selectedAccessoryPreview: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.mintGreen.opacity(0.12))
                .frame(width: 104, height: 104)
                .overlay(
                    Circle()
                        .stroke(selectedAccessory.outline.opacity(0.82), lineWidth: 2)
                )

            ProfileAccessoryPortrait(accessory: selectedAccessory)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        }
    }

    private var accessoryGrid: some View {
        LazyVGrid(columns: accessoryColumns, spacing: 16) {
            ForEach(ProfileAvatarAccessory.allCases) { accessory in
                Button {
                    selectAccessory(accessory)
                } label: {
                    accessoryOption(accessory)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var healthDataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            profileSectionHeader(title: "我的数据")

            VStack(spacing: 16) {
                healthDataRow(title: "年龄", value: healthAgeText)
                healthDataRow(title: "性别", value: healthSexText)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 26)
        .padding(.top, 23)
        .padding(.bottom, 26)
        .background(cardBackground)
    }

    private var appleHealthFootnote: some View {
        HStack(spacing: 8) {
            Text("年龄性别数据来自")
                .foregroundColor(Color(hex: "9AA1A8"))

            Text("苹果健康")
                .foregroundColor(Color(hex: "5579D7"))
                .underline()
        }
        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
        .padding(.top, 2)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            )
    }

    private func profileSectionHeader(title: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.mintGreen.opacity(0.18))
                    .frame(width: 34, height: 34)

                Image(systemName: "person.crop.square.fill")
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(Theme.Colors.mintGreen)
            }

            Text(title)
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(ink)
        }
    }

    private func accessoryOption(_ accessory: ProfileAvatarAccessory) -> some View {
        let isSelected = accessory.id == selectedAccessory.id

        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "E7F8FF"))
                    .frame(width: 50, height: 50)

                ProfileAccessoryPortrait(accessory: accessory)
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())

                if isSelected {
                    Circle()
                        .fill(Color(hex: "20C27A"))
                        .frame(width: 21, height: 21)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.appSystem(size: 11, weight: .black))
                                .foregroundColor(.white)
                        )
                        .offset(x: -16, y: 27)
                } else {
                    Circle()
                        .fill(Color(hex: "EAF7FB"))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "CADCE4"), lineWidth: 2)
                        )
                        .offset(y: 35)
                }
            }
            .frame(width: 50, height: 67)
        }
        .accessibilityLabel(accessory.name)
    }

    private func healthDataRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "6B6F75"))

            Spacer(minLength: 20)

            if value.isEmpty {
                Text("")
            } else {
                Text(value)
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var selectedAccessory: ProfileAvatarAccessory {
        ProfileAvatarAccessory.allCases.first { $0.id == watchThemeId } ?? .joey
    }

    private func selectAccessory(_ accessory: ProfileAvatarAccessory) {
        watchThemeId = accessory.id
        AppGroupManager.shared.saveWatchThemeId(accessory.id)
        HealthDataManager.shared.syncWatchThemeSelection(accessory.id)
    }

    private func loadHealthProfile() {
        isLoadingHealthProfile = true
        Task {
            let manager = HealthKitManager.shared
            let age = await manager.fetchChronologicalAge()
            let sex = await manager.fetchBiologicalSexDisplayText()

            await MainActor.run {
                healthAgeText = age.map { "\($0) 岁" } ?? ""
                healthSexText = sex ?? String(localized: "未设定")
                isLoadingHealthProfile = false
            }
        }
    }
}

private enum ProfileAvatarAccessory: String, CaseIterable, Identifiable {
    case joey
    case bubble
    case flowercat
    case bearjoy
    case tiger
    case piggy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .joey: return "周伊 Joey"
        case .bubble: return "压力泡泡"
        case .flowercat: return "焦绿猫"
        case .bearjoy: return "小熊 joy"
        case .tiger: return "虎虎"
        case .piggy: return "猪傻傻"
        }
    }

    var fill: Color {
        switch self {
        case .joey: return Color(hex: "DDF2F9")
        case .bubble: return Color(hex: "E7F8FF")
        case .flowercat: return Color(hex: "FFF2F7")
        case .bearjoy: return Color(hex: "FFF5E7")
        case .tiger: return Color(hex: "F5F6FF")
        case .piggy: return Color(hex: "FFF4F5")
        }
    }

    var outline: Color {
        switch self {
        case .joey: return Color(hex: "7796A5")
        case .bubble: return Color(hex: "68D4A2")
        case .flowercat: return Color(hex: "FF9BC3")
        case .bearjoy: return Color(hex: "D8A35A")
        case .tiger: return Color(hex: "8F94FF")
        case .piggy: return Color(hex: "FF9FA8")
        }
    }
}

private struct ProfileAccessoryPortrait: View {
    let accessory: ProfileAvatarAccessory

    var body: some View {
        ZStack {
            Circle()
                .fill(accessory.fill)

            switch accessory {
            case .joey:
                Image("ProfileHeaderMascot")
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            case .bubble:
                ProfileBubbleAvatar()
                    .padding(6)
            case .flowercat:
                ProfileFlowerCatAvatar()
                    .padding(5)
            case .bearjoy:
                ProfileBearAvatar()
                    .padding(6)
            case .tiger:
                ProfileTigerAvatar()
                    .padding(5)
            case .piggy:
                ProfilePigAvatar()
                    .padding(6)
            }
        }
    }
}

private struct ProfileBubbleAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "70D5A6"))

            Circle()
                .fill(Color.white.opacity(0.26))
                .frame(width: 16, height: 16)
                .offset(x: 15, y: -13)

            HStack(spacing: 8) {
                Capsule().fill(Color(hex: "6B8190")).frame(width: 6, height: 14)
                ProfileArcEyeShape()
                    .stroke(Color(hex: "6B8190"), lineWidth: 2.2)
                    .frame(width: 13, height: 9)
                    .scaleEffect(x: -1, y: 1)
            }
            .offset(y: -4)

            ProfileSmileShape()
                .stroke(Color(hex: "6B8190"), lineWidth: 2.2)
                .frame(width: 17, height: 9)
                .offset(y: 10)
        }
    }
}

private struct ProfileFlowerCatAvatar: View {
    var body: some View {
        ZStack {
            ProfileCatHeadShape()
                .fill(Color.white)
            ProfileCatHeadShape()
                .stroke(Color(hex: "42464D").opacity(0.8), lineWidth: 2)

            HStack(spacing: 24) {
                ProfileFlowerShape().fill(Color(hex: "FF8FB8")).frame(width: 15, height: 15)
                ProfileFlowerShape().fill(Color(hex: "FF8FB8")).frame(width: 15, height: 15)
            }
            .offset(y: -15)

            ProfileFaceMarks()
        }
    }
}

private struct ProfileBearAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "E8BD82"))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "5C4A3A").opacity(0.72), lineWidth: 2)

            Circle().fill(Color(hex: "F8D7A8")).frame(width: 16, height: 16).offset(x: -17, y: -16)
            Circle().fill(Color(hex: "F8D7A8")).frame(width: 16, height: 16).offset(x: 17, y: -16)
            ProfileFaceMarks()
            Capsule().fill(Color(hex: "F28C6F")).frame(width: 18, height: 11).offset(y: 12)
        }
    }
}

private struct ProfileTigerAvatar: View {
    var body: some View {
        ZStack {
            ProfileCatHeadShape()
                .fill(Color.white)
            ProfileCatHeadShape()
                .stroke(Color(hex: "343840").opacity(0.82), lineWidth: 2)

            HStack(spacing: 16) {
                Rectangle().fill(Color(hex: "FFB457")).frame(width: 5, height: 20).rotationEffect(.degrees(-18))
                Rectangle().fill(Color(hex: "FFB457")).frame(width: 5, height: 22)
                Rectangle().fill(Color(hex: "FFB457")).frame(width: 5, height: 20).rotationEffect(.degrees(18))
            }
            .offset(y: -19)

            ProfileFaceMarks()
        }
    }
}

private struct ProfilePigAvatar: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: "FFD6DC"))
                .frame(width: 58, height: 48)
            Ellipse()
                .stroke(Color(hex: "5C4A50").opacity(0.72), lineWidth: 2)
                .frame(width: 58, height: 48)

            Ellipse()
                .fill(Color(hex: "FFA9B5"))
                .frame(width: 24, height: 16)
                .offset(y: 6)

            HStack(spacing: 5) {
                Circle().fill(Color(hex: "5C4A50")).frame(width: 3, height: 3)
                Circle().fill(Color(hex: "5C4A50")).frame(width: 3, height: 3)
            }
            .offset(y: 6)

            ProfileFaceMarks()
                .offset(y: -5)
        }
    }
}

private struct ProfileFaceMarks: View {
    var body: some View {
        ZStack {
            HStack(spacing: 16) {
                Circle().fill(Color(hex: "4C6070")).frame(width: 5, height: 8)
                ProfileArcEyeShape()
                    .stroke(Color(hex: "4C6070"), lineWidth: 2)
                    .frame(width: 11, height: 8)
                    .scaleEffect(x: -1, y: 1)
            }
            .offset(y: -3)

            ProfileSmileShape()
                .stroke(Color(hex: "4C6070"), lineWidth: 2)
                .frame(width: 14, height: 8)
                .offset(y: 9)
        }
    }
}

nonisolated private struct ProfileCatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.09))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.04))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.13))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.27, y: rect.minY + rect.height * 0.04), control: CGPoint(x: rect.maxX - rect.width * 0.13, y: rect.minY + rect.height * 0.13))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct ProfileFlowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<5 {
            let angle = Double(index) * .pi * 2 / 5
            let center = CGPoint(
                x: rect.midX + cos(angle) * rect.width * 0.22,
                y: rect.midY + sin(angle) * rect.height * 0.22
            )
            path.addEllipse(in: CGRect(x: center.x - rect.width * 0.16, y: center.y - rect.height * 0.16, width: rect.width * 0.32, height: rect.height * 0.32))
        }
        path.addEllipse(in: CGRect(x: rect.midX - rect.width * 0.10, y: rect.midY - rect.height * 0.10, width: rect.width * 0.20, height: rect.height * 0.20))
        return path
    }
}

nonisolated private struct ProfileArcEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

nonisolated private struct ProfileSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

#Preview {
    ProfileDetailView()
}
