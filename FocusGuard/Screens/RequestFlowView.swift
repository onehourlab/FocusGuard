import SwiftUI
import FocusGuardKit

/// 利用申請：対象 → 目的 → 時間 → 理由 → 審査 → 結果（再質問なら回答して再審査）
/// 1画面に1つの問いだけを出し、あえて少しずつ考えてもらう。
struct RequestFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let seed: RequestDraftSeed

    enum Step: Equatable { case target, purpose, minutes, reason, reviewing, result }

    @State private var step: Step = .target
    @State private var requestID = UUID()
    @State private var createdAt = Date()
    @State private var targetID: UUID?
    @State private var purpose = ""
    @State private var minutes = 5
    @State private var reason = ""
    @State private var clarifications: [Clarification] = []
    @State private var answer = ""
    @State private var result: ReviewResult?
    @FocusState private var focused: Bool

    init(seed: RequestDraftSeed) {
        self.seed = seed
        _targetID = State(initialValue: seed.targetID)
        _purpose = State(initialValue: seed.purpose)
        _step = State(initialValue: seed.targetID == nil ? .target : .purpose)
    }

    private var isExtension: Bool { seed.extendsSessionID != nil }
    private var target: GuardTarget? { model.target(targetID) }

    private var request: UsageRequest {
        UsageRequest(id: requestID, targetID: targetID ?? UUID(), purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                     reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), minutes: minutes, createdAt: createdAt,
                     clarifications: clarifications, extendsSessionID: seed.extendsSessionID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FGSpacing.l) {
                    switch step {
                    case .target: targetStep
                    case .purpose: purposeStep
                    case .minutes: minutesStep
                    case .reason: reasonStep
                    case .reviewing: reviewing
                    case .result: resultStep
                    }
                }
                .padding()
                .animation(.default, value: step)
            }
            .background(FGColor.background)
            .navigationTitle(isExtension ? "延長の申請" : "利用の申請")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result?.verdict == .approve ? "閉じる" : "やめておく") { close() }
                        .disabled(step == .reviewing)
                }
            }
        }
    }

    // MARK: 各ステップ

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: FGSpacing.m) {
            Text("どのアプリを使いますか？").font(.title2.bold())
            ForEach(model.data.targets) { t in
                Button {
                    targetID = t.id
                    step = .purpose
                } label: {
                    HStack {
                        Label(t.name, systemImage: "app.badge")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(FGColor.card, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: FGSpacing.m) {
            stepHeader(1, isExtension ? "延長して何をしますか？" : "何のために使いますか？")
            Text("誰に・何を・どうするのか、何をしたら終わりにするのかを書いてください。")
                .foregroundStyle(.secondary)
            editor($purpose, placeholder: isExtension ? "例：授業動画の残り1本を最後まで見る" : "例：友達からのDMに返信したら閉じる")
            hint(["友達からのDMに返信したら閉じる", "授業動画を1本見る", "明日の天気と電車の運行情報を調べる"])
            nextButton(enabled: !purpose.trimmed.isEmpty) { step = .minutes }
        }
    }

    private var minutesStep: some View {
        VStack(alignment: .leading, spacing: FGSpacing.m) {
            stepHeader(2, "何分必要ですか？")
            Text("時間になると自動で制限に戻ります。延長するには、もう一度理由を書いて審査を受けます。")
                .foregroundStyle(.secondary)
            HStack {
                Text(minutesText(minutes)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                Stepper("", value: $minutes, in: 1...ReviewEngine.maxMinutesPerRequest).labelsHidden()
            }
            HStack {
                ForEach([3, 5, 10, 15, 30, 60], id: \.self) { m in
                    Button("\(m)") { minutes = m }
                        .buttonStyle(.bordered)
                        .tint(minutes == m ? FGColor.accent : .gray)
                }
            }
            if let note = remainingNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
            nextButton(enabled: minutes >= 1) { step = .reason }
        }
    }

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: FGSpacing.m) {
            stepHeader(3, isExtension ? "なぜ延長が必要ですか？" : "なぜ今使う必要がありますか？")
            Text(isExtension ? "最初の時間で終わらなかった理由を書いてください。" : "あとでは駄目な理由があれば書いてください。")
                .foregroundStyle(.secondary)
            editor($reason, placeholder: isExtension ? "例：動画が思ったより長く、残り5分だった" : "例：集合時間の返事を待たせているため")
            summaryBox
            Button {
                submit()
            } label: {
                Label("審査を受ける", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(reason.trimmed.isEmpty)
        }
    }

    private var reviewing: some View {
        VStack(spacing: FGSpacing.l) {
            ProgressView().controlSize(.large)
            Text("内容を確認しています…").font(.headline)
            Text(model.data.settings.useOnDeviceAI ? model.aiAvailability.message : "ルール判定で審査しています（端末内）。")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    @ViewBuilder
    private var resultStep: some View {
        if let result {
            ReviewResultView(result: result, minutes: minutes, targetName: target?.name ?? "")
            switch result.verdict {
            case .approve:
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            case .clarify:
                VStack(alignment: .leading, spacing: FGSpacing.m) {
                    editor($answer, placeholder: "ここに回答を書く")
                    Button {
                        clarifications.append(Clarification(question: result.question ?? "", answer: answer.trimmed))
                        answer = ""
                        submit()
                    } label: {
                        Label("回答して再審査", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(answer.trimmed.isEmpty)
                }
            case .deny:
                VStack(spacing: FGSpacing.m) {
                    if let s = result.suggestedMinutes, s > 0 {
                        Button("\(minutesText(s))で申請し直す") {
                            restart(minutes: s)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("内容を書き直す") { restart(minutes: minutes) }
                        .buttonStyle(.bordered)
                    Button("緊急解除へ", role: .destructive) {
                        dismiss()
                        model.showEmergency = true
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 部品

    private func stepHeader(_ n: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(target?.name ?? "")・\(n) / 3").font(.caption).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
        }
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(3...6)
            .focused($focused)
            .padding()
            .background(FGColor.card, in: RoundedRectangle(cornerRadius: 12))
            .onAppear { focused = true }
    }

    private func hint(_ examples: [String]) -> some View {
        Text("書き方の例：" + examples.joined(separator: "／"))
            .font(.caption).foregroundStyle(.secondary)
    }

    private func nextButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("次へ").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!enabled)
    }

    private var summaryBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("申請内容").font(.caption).foregroundStyle(.secondary)
            Text("\(target?.name ?? "")を\(minutesText(minutes))：\(purpose.trimmed)")
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FGColor.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var remainingNote: String? {
        guard model.data.settings.limitMode == .reviewWithDailyCaps, let t = target, let cap = t.dailyCapMinutes else { return nil }
        let today = model.today
        let used = model.data.sessions
            .filter { !$0.isEmergency && $0.targetID == t.id && DayKey($0.startedAt) == today }
            .reduce(0) { $0 + $1.countedMinutes }
        return "本日の「\(t.name)」は残り\(max(0, cap - used))分です（上限\(cap)分）。"
    }

    // MARK: 操作

    private func submit() {
        focused = false
        step = .reviewing
        let req = request
        Task {
            let r = await model.review(req)
            result = r
            step = r == nil ? .reason : .result
        }
    }

    /// 不承認のあと書き直す：新しい申請として始め直す（前の申請は不承認として残る）
    private func restart(minutes newMinutes: Int) {
        requestID = UUID()
        createdAt = Date()
        clarifications = []
        result = nil
        minutes = newMinutes
        step = .purpose
    }

    private func close() {
        let started = !purpose.trimmed.isEmpty && purpose.trimmed != seed.purpose.trimmed || !reason.trimmed.isEmpty
        switch result?.verdict {
        case .clarify?:
            model.abandon(request, stage: .duringClarification)
        case nil where started:
            model.abandon(request, stage: .beforeSubmit)
        default:
            break
        }
        dismiss()
    }
}

/// 審査結果と、5つの基準それぞれの説明
struct ReviewResultView: View {
    let result: ReviewResult
    let minutes: Int
    let targetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            HStack(spacing: FGSpacing.m) {
                Image(systemName: result.verdict.symbol).font(.largeTitle).foregroundStyle(result.verdict.color)
                VStack(alignment: .leading) {
                    Text(result.verdict.label).font(.title.bold())
                    Text(headline).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let q = result.question {
                Card(title: "追加で教えてください", systemImage: "questionmark.bubble") {
                    Text(q).font(.body.weight(.medium))
                }
            }
            if !result.denialReasons.isEmpty {
                Card(title: "通常の解除をしない理由", systemImage: "info.circle") {
                    ForEach(result.denialReasons, id: \.self) { Text("・" + $0) }
                }
            }
            Card(title: "判定の内訳", systemImage: "list.bullet.clipboard") {
                ForEach(result.checks, id: \.criterion) { c in
                    HStack(alignment: .top) {
                        Image(systemName: c.status.symbol).foregroundStyle(c.status.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.criterion.label).font(.subheadline.weight(.semibold))
                            Text(c.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("判定：\(result.source.label)／分類：\(result.category.label)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        switch result.verdict {
        case .approve: return "\(targetName)を\(minutesText(result.grantedMinutes))使えます。時間になると自動で制限に戻ります。"
        case .clarify: return "もう少し教えてください。"
        case .deny: return "今回は通常の解除を行いません。"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
