/// CollaborativeTodoListView 由好友详情页调用，作为「协作待办」清单视图。
/// 负责通过 SharedHealthDataStore 展示共享待办列表及其完成状态。

import SwiftUI

struct CollaborativeTodoListView: View {
    let ownerUserRecordName: String?
    let ownerDisplayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var sharingStore = SharedHealthDataStore.shared
    @State private var list: SharedTodoList?

    var body: some View {
        List {
            if let list {
                Section("共享权限") {
                    Text("这份待办由对方通过 iCloud 共享，仅供查看。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    LabeledContent("清单", value: list.title)
                }

                Section("待办条目") {
                    if list.items.isEmpty {
                        Text("这份共享待办还没有条目。")
                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    } else {
                        ForEach(list.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.isCompleted ? Theme.Colors.mintGreen : Theme.Colors.textTertiary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                        Text(item.summaryText)
                                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(Theme.Colors.textSecondary)
                                        if let note = item.note {
                                            Text(note)
                                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                                .foregroundColor(Theme.Colors.textTertiary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            } else {
                Section {
                    ProgressView("正在加载共享待办…")
                }
            }
        }
        .navigationTitle("\(ownerDisplayName)的待办")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.appSystem(size: 15, weight: .bold))
                }
            }
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        list = await sharingStore.fetchCollaborativeTodoList(ownerUserRecordName: ownerUserRecordName)
    }
}
