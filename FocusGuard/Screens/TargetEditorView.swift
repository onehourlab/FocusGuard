import SwiftUI
import FamilyControls
import FocusGuardKit

/// 制限対象の編集：アプリの選択、1日の上限、目的ごとの上限、1回の上限、時間帯ルール、文章のルール
struct TargetEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var target: GuardTarget
    @State private var selection: FamilyActivitySelection
    @State private var showPicker = false
    @State private var newRule = ""
    @State private var confirmDelete = false
    let isNew: Bool

    init(target: GuardTarget, isNew: Bool) {
        _target = State(initialValue: target)
        _selection = State(initialValue: SelectionCodec.decode(target.selectionData) ?? FamilyActivitySelection())
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section {
                TextField("名前（例：Instagram）", text: $target.name)
                Button {
                    showPicker = true
                } label: {
                    Label(SelectionCodec.isEmpty(selection) ? "アプリを選ぶ" : "選択を変更", systemImage: "apps.iphone")
                }
                if !SelectionCodec.isEmpty(selection) {
                    ForEach(Array(selection.applicationTokens), id: \.self) { token in
                        Label(token)
                    }
                    if !selection.categoryTokens.isEmpty {
                        Text("カテゴリ \(selection.categoryTokens.count)件").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("対象")
            } footer: {
                Text("同じ目的で使うアプリはまとめて1つの対象にできます。")
            }

            Section {
                optionalStepper("1日の上限", value: $target.dailyCapMinutes, defaultValue: 30, range: 5...600, step: 5)
                if model.data.settings.limitMode == .reviewOnly {
                    Text("現在は「毎回の審査だけ」のため、1日の上限は使われません（設定で切り替え）。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach($target.purposeCaps) { $cap in
                    HStack {
                        TextField("目的（例：DM返信）", text: $cap.label)
                        Stepper("\(cap.maxMinutesPerDay)分", value: $cap.maxMinutesPerDay, in: 1...600)
                            .fixedSize()
                    }
                }
                .onDelete { target.purposeCaps.remove(atOffsets: $0) }
                Button {
                    target.purposeCaps.append(PurposeCap(label: "", maxMinutesPerDay: 10))
                } label: {
                    Label("目的ごとの上限を追加", systemImage: "plus")
                }
            } header: {
                Text("1日の上限（任意）")
            } footer: {
                Text("目的ごとの上限は、言い回しが違っても意味が近い申請をまとめて数えます。")
            }

            Section {
                optionalStepper("1回の上限", value: $target.maxMinutesPerSession, defaultValue: 15, range: 1...180, step: 1)
            } header: {
                Text("1回あたり（任意）")
            }

            Section {
                ForEach($target.restrictedWindows) { $w in
                    WindowEditor(window: $w)
                }
                .onDelete { target.restrictedWindows.remove(atOffsets: $0) }
                Button {
                    target.restrictedWindows.append(RestrictedWindow(window: TimeWindow(startMinute: 22 * 60, endMinute: 7 * 60),
                                                                     allowedCategories: [.communication, .study]))
                } label: {
                    Label("時間帯ルールを追加", systemImage: "plus")
                }
            } header: {
                Text("時間帯ルール")
            } footer: {
                Text("指定した時間帯は、選んだ目的の申請だけを承認します。最初は確認の質問をし、説明を受けても当てはまらない場合に不承認にします。")
            }

            Section {
                ForEach(target.personalRules, id: \.self) { Text($0) }
                    .onDelete { target.personalRules.remove(atOffsets: $0) }
                HStack {
                    TextField("例：試験前の週は授業動画だけ", text: $newRule)
                    Button("追加") {
                        let r = newRule.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !r.isEmpty, !target.personalRules.contains(r) { target.personalRules.append(r) }
                        newRule = ""
                    }
                    .disabled(newRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("自分で決めたルール（文章）")
            } footer: {
                Text("オンデバイスAIが使える端末で参照します。AIがルールに反すると判断した場合は、まず理由を質問します。")
            }

            if !isNew {
                Section {
                    Button("この対象を削除", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "制限するアプリを追加" : target.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(target.name.trimmingCharacters(in: .whitespaces).isEmpty || SelectionCodec.isEmpty(selection))
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .confirmationDialog("「\(target.name)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                model.deleteTarget(target.id)
                dismiss()
            }
        }
    }

    private func save() {
        target.name = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.selectionData = SelectionCodec.encode(selection)
        target.purposeCaps.removeAll { $0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        model.saveTarget(target)
        dismiss()
    }

    @ViewBuilder
    private func optionalStepper(_ title: String, value: Binding<Int?>, defaultValue: Int,
                                 range: ClosedRange<Int>, step: Int) -> some View {
        Toggle(title, isOn: Binding(get: { value.wrappedValue != nil },
                                    set: { value.wrappedValue = $0 ? defaultValue : nil }))
        if let v = value.wrappedValue {
            Stepper("\(title)：\(minutesText(v))", value: Binding(get: { v }, set: { value.wrappedValue = $0 }),
                    in: range, step: step)
        }
    }
}

private struct WindowEditor: View {
    @Binding var window: RestrictedWindow

    var body: some View {
        VStack(alignment: .leading, spacing: FGSpacing.s) {
            HStack {
                DatePicker("開始", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("終了", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
            }
            .labelsHidden()
            Text("\(window.window.label) に許可する目的").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(PurposeCategory.allCases, id: \.self) { c in
                        let on = window.allowedCategories.contains(c)
                        Button(c.label) {
                            if on { window.allowedCategories.remove(c) } else { window.allowedCategories.insert(c) }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? FGColor.accent : .gray)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<TimeWindow, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = window.window[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                window.window[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}
