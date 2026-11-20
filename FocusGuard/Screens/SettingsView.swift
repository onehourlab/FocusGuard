import SwiftUI
import FamilyControls
import FocusGuardKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editingTarget: GuardTarget?
    @State private var newTarget: GuardTarget?
    @State private var showExemptPicker = false
    @State private var exempt = FamilyActivitySelection()
    @State private var confirmDelete = false

    var body: some View {
        let settings = model.data.settings
        NavigationStack {
            Form {
                Section {
                    ForEach(model.data.targets) { t in
                        Button {
                            editingTarget = t
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).foregroundStyle(.primary)
                                Text(targetSummary(t)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        newTarget = GuardTarget(name: "")
                    } label: {
                        Label("制限するアプリを追加", systemImage: "plus")
                    }
                } header: {
                    Text("制限するアプリ")
                }

                Section {
                    Button {
                        showExemptPicker = true
                    } label: {
                        Label("常に許可するアプリを選ぶ", systemImage: "checkmark.shield")
                    }
                    Text("電話・連絡・健康・安全に関わるアプリは、ここに入れると制限されません（\(exempt.applicationTokens.count)個選択中）。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("制限から外すアプリ")
                }

                Section {
                    Picker("管理の方法", selection: binding(\.limitMode)) {
                        ForEach(LimitMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(settings.limitMode == .reviewOnly
                         ? "毎回の申請で審査します。1日の累計上限は使いません（1回ごとの申告時間は常に守られます）。"
                         : "審査に加えて、アプリごと・目的ごとに設定した1日の上限を超える申請は承認しません。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Stepper("同じ目的で\(settings.repeatQuestionThreshold)回使ったあとは質問", value: binding(\.repeatQuestionThreshold), in: 1...10)
                    Stepper("再質問は最大\(settings.maxClarifications)回", value: binding(\.maxClarifications), in: 1...4)
                } header: {
                    Text("審査")
                }

                Section {
                    Toggle("オンデバイスAIを使う", isOn: binding(\.useOnDeviceAI))
                    Text(model.aiAvailability.message).font(.footnote).foregroundStyle(.secondary)
                    Text("外部のAIサービスは使いません。申請文は端末の外に送信されません。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("AI")
                }

                Section {
                    optionalMinutes("1日の目標", keyPath: \.dailyGoalMinutes, defaultValue: 60)
                    optionalMinutes("削減量の基準値", keyPath: \.baselineDailyMinutes, defaultValue: 120)
                    Text("基準値を入れない場合は、過去の実際の記録の平均と比べます。記録が無いうちは削減量を表示しません。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("目標")
                }

                Section {
                    Picker("緊急解除の標準時間", selection: binding(\.emergencyDefaultMinutes)) {
                        ForEach([5, 15, 30, 60], id: \.self) { Text("\($0)分").tag($0) }
                    }
                } header: {
                    Text("緊急解除")
                }

                Section {
                    LabeledContent("スクリーンタイム", value: model.authorizationStatus == .approved ? "許可済み" : "未許可")
                    if model.authorizationStatus != .approved {
                        Button("スクリーンタイムを許可する") { Task { await model.requestScreenTimeAuthorization() } }
                    }
                    Button("申請と緊急解除の履歴を削除", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("データ")
                } footer: {
                    Text("データはこの端末の中だけに保存されます。")
                }
            }
            .navigationTitle("設定")
            .sheet(item: $editingTarget) { t in
                NavigationStack { TargetEditorView(target: t, isNew: false) }
            }
            .sheet(item: $newTarget) { t in
                NavigationStack { TargetEditorView(target: t, isNew: true) }
            }
            .familyActivityPicker(isPresented: $showExemptPicker, selection: $exempt)
            .onChange(of: exempt) { _, v in model.saveExempt(v) }
            .onAppear {
                if let saved = SelectionCodec.decode(model.data.exemptSelectionData) { exempt = saved }
            }
            .confirmationDialog("履歴を削除しますか？元に戻せません。", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { model.deleteAllHistory() }
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<FocusSettings, T>) -> Binding<T> {
        Binding(get: { model.data.settings[keyPath: keyPath] },
                set: { v in model.updateSettings { $0[keyPath: keyPath] = v } })
    }

    @ViewBuilder
    private func optionalMinutes(_ title: String, keyPath: WritableKeyPath<FocusSettings, Int?>, defaultValue: Int) -> some View {
        let value = model.data.settings[keyPath: keyPath]
        Toggle(title, isOn: Binding(get: { value != nil },
                                    set: { on in model.updateSettings { $0[keyPath: keyPath] = on ? defaultValue : nil } }))
        if let v = value {
            Stepper("\(title)：\(minutesText(v))/日", value: Binding(get: { v }, set: { n in model.updateSettings { $0[keyPath: keyPath] = n } }),
                    in: 5...600, step: 5)
        }
    }

    private func targetSummary(_ t: GuardTarget) -> String {
        var parts: [String] = []
        if let sel = SelectionCodec.decode(t.selectionData) {
            parts.append("アプリ\(sel.applicationTokens.count)・カテゴリ\(sel.categoryTokens.count)")
        } else {
            parts.append("アプリ未選択")
        }
        if let c = t.dailyCapMinutes { parts.append("1日\(c)分") }
        if let c = t.maxMinutesPerSession { parts.append("1回\(c)分まで") }
        if !t.purposeCaps.isEmpty { parts.append("目的別上限\(t.purposeCaps.count)") }
        if !t.restrictedWindows.isEmpty { parts.append("時間帯ルール\(t.restrictedWindows.count)") }
        if !t.personalRules.isEmpty { parts.append("ルール文\(t.personalRules.count)") }
        return parts.joined(separator: "・")
    }
}
