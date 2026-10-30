/// SharedTodoManagerView 由社交共享页调用，作为「共享待办」管理页面。
/// 负责管理本地共享待办项的增删改查和列表标题编辑。

import SwiftUI

struct SharedTodoManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sharingStore = SharedHealthDataStore.shared
    @State private var list = SharedTodoStore.shared.loadList()
    @State private var editingItem: LocalSharedTodoItem?
    @State private var draftListTitle = ""
    @State private var draftItemTitle = ""
    @State private var draftItemCompleted = false
    @State private var draftItemNote = ""
    @State private var draftItemDueDate = Date()
    @State private var draftHasDueDate = false
    @State private var showingItemEditor = false

    private let store = SharedTodoStore.shared

    var body: some View {
        List {
            Section("共享设置") {
                TextField("清单标题", text: $draftListTitle)
                    .onSubmit {
                        sharingStore.updateSharedTodoListTitle(draftListTitle)
                        reload()
                    }

                Toggle("只读共享给好友", isOn: Binding(
                    get: { list.isShared },
                    set: {
                        sharingStore.setSharedTodoListEnabled($0)
                        reload()
                    }
                ))

                Text("健康摘要、位置、行动记录、倒数日和这份待办清单对受邀好友均为只读；你可以在本机管理后继续共享更新。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Section("待办清单") {
                if list.items.isEmpty {
                    Text("还没有待办。先创建一条，再决定是否只读共享给好友。")
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
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text(itemSummary(item))
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

                            HStack(spacing: 12) {
                                Button("编辑") {
                                    beginEdit(item)
                                }
                                .buttonStyle(.plain)

                                Button(item.isCompleted ? "标记未完成" : "标记完成") {
                                    Task {
                                        await sharingStore.upsertSharedTodoItem(
                                            id: item.id,
                                            title: item.title,
                                            isCompleted: !item.isCompleted,
                                            note: item.note,
                                            dueDate: item.dueDate
                                        )
                                        reload()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button("删除", role: .destructive) {
                                    Task {
                                        await sharingStore.deleteSharedTodoItem(id: item.id)
                                        reload()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("共享待办")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.appSystem(size: 15, weight: .bold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    beginCreate()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showingItemEditor) {
            NavigationStack {
                Form {
                    Section("条目") {
                        TextField("标题", text: $draftItemTitle)
                        Toggle("已完成", isOn: $draftItemCompleted)
                        Toggle("设置截止日", isOn: $draftHasDueDate)
                        if draftHasDueDate {
                            DatePicker("截止日", selection: $draftItemDueDate, displayedComponents: .date)
                        }
                        TextField("备注", text: $draftItemNote, axis: .vertical)
                    }
                }
                .navigationTitle(editingItem == nil ? "新建待办" : "编辑待办")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { showingItemEditor = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            Task {
                                await sharingStore.upsertSharedTodoItem(
                                    id: editingItem?.id,
                                    title: draftItemTitle,
                                    isCompleted: draftItemCompleted,
                                    note: draftItemNote,
                                    dueDate: draftHasDueDate ? draftItemDueDate : nil
                                )
                                reload()
                                showingItemEditor = false
                            }
                        }
                        .disabled(draftItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }

    private func reload() {
        list = store.loadList()
        draftListTitle = list.title
    }

    private func beginCreate() {
        editingItem = nil
        draftItemTitle = ""
        draftItemCompleted = false
        draftItemNote = ""
        draftItemDueDate = Date()
        draftHasDueDate = false
        showingItemEditor = true
    }

    private func beginEdit(_ item: LocalSharedTodoItem) {
        editingItem = item
        draftItemTitle = item.title
        draftItemCompleted = item.isCompleted
        draftItemNote = item.note ?? ""
        draftItemDueDate = item.dueDate ?? Date()
        draftHasDueDate = item.dueDate != nil
        showingItemEditor = true
    }

    private func itemSummary(_ item: LocalSharedTodoItem) -> String {
        var parts = [item.isCompleted ? "已完成" : "待完成"]
        if let dueDate = item.dueDate {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("Md")
            parts.append("截止 \(formatter.string(from: dueDate))")
        }
        if let creator = item.createdByUserRecordName, !creator.isEmpty {
            parts.append("创建者 \(creator)")
        }
        return parts.joined(separator: " · ")
    }
}
