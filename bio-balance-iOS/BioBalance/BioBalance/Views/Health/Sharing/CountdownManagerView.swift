/// CountdownManagerView 由社交共享页调用，作为「倒数管理」页面。
/// 负责管理本地倒数事件项的标题、日期、备注和置顶。

import SwiftUI

struct CountdownManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [LocalCountdownItem] = []
    @State private var editingItem: LocalCountdownItem?
    @State private var draftTitle = ""
    @State private var draftDate = Date()
    @State private var draftNote = ""
    @State private var draftPinned = false
    @State private var draftShared = false
    @State private var showingEditor = false

    private let store = CountdownStore.shared

    var body: some View {
        List {
            if items.isEmpty {
                Section {
                    Text("还没有倒数日。先创建一个，再决定要不要共享给好友。")
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            } else {
                Section {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                                    Text(relativeText(for: item))
                                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { item.isShared },
                                    set: { store.setShared($0, id: item.id); reload() }
                                ))
                                .labelsHidden()
                            }

                            if let note = item.note {
                                Text(note)
                                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }

                            HStack(spacing: 12) {
                                Button("编辑") {
                                    beginEdit(item)
                                }
                                .buttonStyle(.plain)

                                Button(item.isPinned ? "取消置顶" : "置顶") {
                                    store.setPinned(!item.isPinned, id: item.id)
                                    reload()
                                }
                                .buttonStyle(.plain)

                                Button("删除", role: .destructive) {
                                    store.delete(id: item.id)
                                    reload()
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("倒数日")
                }
            }
        }
        .navigationTitle("管理倒数日")
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
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                Form {
                    Section("内容") {
                        TextField("标题", text: $draftTitle)
                        DatePicker("日期", selection: $draftDate, displayedComponents: .date)
                        TextField("备注", text: $draftNote, axis: .vertical)
                    }

                    Section("设置") {
                        Toggle("置顶", isOn: $draftPinned)
                        Toggle("共享给好友", isOn: $draftShared)
                    }
                }
                .navigationTitle(editingItem == nil ? "新建倒数日" : "编辑倒数日")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { showingEditor = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            store.upsert(
                                id: editingItem?.id,
                                title: draftTitle,
                                targetDate: draftDate,
                                note: draftNote,
                                isPinned: draftPinned,
                                isShared: draftShared
                            )
                            showingEditor = false
                            reload()
                        }
                        .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }

    private func reload() {
        items = store.items()
    }

    private func beginCreate() {
        editingItem = nil
        draftTitle = ""
        draftDate = Date()
        draftNote = ""
        draftPinned = false
        draftShared = false
        showingEditor = true
    }

    private func beginEdit(_ item: LocalCountdownItem) {
        editingItem = item
        draftTitle = item.title
        draftDate = item.targetDate
        draftNote = item.note ?? ""
        draftPinned = item.isPinned
        draftShared = item.isShared
        showingEditor = true
    }

    private func relativeText(for item: LocalCountdownItem) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: item.targetDate)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        switch days {
        case 1...:
            return String(localized: "还有 \(days) 天")
        case 0:
            return String(localized: "就是今天")
        default:
            return String(localized: "已过去 \(abs(days)) 天")
        }
    }
}