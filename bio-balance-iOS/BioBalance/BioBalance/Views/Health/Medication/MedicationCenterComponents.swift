import SwiftUI

struct MedicationCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content
    var body: some View { BBCard(style: .standard, tint: tint, content: content) }
}

struct MedicationSectionHeader: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(Theme.Colors.textTertiary) }
        }
    }
}

struct MedicationStatusBadge: View {
    let status: MedicationCenterDoseStatus
    private var color: Color {
        switch status {
        case .taken: return Theme.Colors.mintGreen
        case .upcoming: return Theme.Colors.accentBlue
        case .pending: return Theme.Colors.accentOrange
        case .missed: return Theme.Colors.accentRed
        case .skipped: return Theme.Colors.textTertiary
        }
    }
    var body: some View { BBStatusBadge(title: status.title, tint: color, size: .regular) }
}

struct MedicationRow: View {
    let item: MedicationScheduleItem
    var showChevron = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(item.time).font(.subheadline.bold()).foregroundStyle(Theme.Colors.textSecondary).frame(width: 50, alignment: .leading)
                Circle().fill(statusColor.opacity(0.16)).frame(width: 34, height: 34).overlay(Image(systemName: statusSymbol).font(.caption.bold()).foregroundStyle(statusColor))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.subheadline.bold()).foregroundStyle(Theme.Colors.textPrimary).lineLimit(2)
                    Text("\(item.dose) · \(item.timing)").font(.caption).foregroundStyle(Theme.Colors.textTertiary).lineLimit(2)
                }
                Spacer(minLength: 4)
                MedicationStatusBadge(status: item.status)
                if showChevron { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.Colors.textTertiary) }
            }
            .contentShape(Rectangle()).frame(minHeight: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.time)，\(item.name)，\(item.dose)，\(item.timing)，\(item.status.title)")
    }
    private var statusColor: Color {
        switch item.status { case .taken: Theme.Colors.mintGreen; case .upcoming: Theme.Colors.accentBlue; case .pending: Theme.Colors.accentOrange; case .missed: Theme.Colors.accentRed; case .skipped: Theme.Colors.textTertiary }
    }
    private var statusSymbol: String { item.status == .taken ? "checkmark" : "circle" }
}

struct MedicationPrimaryButton: View {
    let title: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void
    var body: some View { BBPrimaryButton(title: title, action: action, isFullWidth: true, isLoading: isLoading, isDisabled: isDisabled).frame(minHeight: 48) }
}

extension View {
    func medicationPage(title: String, subtitle: String? = nil) -> some View {
        self
            .background(HealthDetailPageBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.clear, for: .navigationBar)
            .accessibilityHint(subtitle ?? "")
    }
}
