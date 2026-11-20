import SwiftUI
import FamilyControls
import FocusGuardKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var notificationsGranted = false
    @State private var showExemptPicker = false
    @State private var exempt = FamilyActivitySelection()
    @State private var editingTarget: GuardTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: FGSpacing.xl) {
                ProgressView(value: Double(step + 1), total: 4)
                    .padding(.horizontal)
                ScrollView {
                    VStack(alignment: .leading, spacing: FGSpacing.l) {
                        switch step {
                        case 0: intro
                        case 1: permissions
                        case 2: exemptStep
                        default: targetStep
                        }
                    }
                    .padding()
                }
                footer
            }
            .navigationTitle("Focus Guard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .familyActivityPicker(isPresented: $showExemptPicker, selection: $exempt)
        .onChange(of: exempt) { _, newValue in model.saveExempt(newValue) }
        .sheet(item: $editingTarget) { t in
            NavigationStack { TargetEditorView(target: t, isNew: true) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            Text("開く前に、ひと呼吸。").font(.largeTitle.bold())
            Text("Focus Guard は、使う時間を減らすことよりも「目的を持って使う」ことを助けるアプリです。")
            VStack(alignment: .leading, spacing: FGSpacing.m) {
                Label("何のために使うのか", systemImage: "1.circle")
                Label("何分必要なのか", systemImage: "2.circle")
                Label("なぜ今使う必要があるのか", systemImage: "3.circle")
            }
            .font(.headline)
            Text("制限したアプリを使うには、この3つを文章で申請します。端末内のAIとルールが内容を確かめ、申告した時間だけ使えるようにします。あえて少し手間がかかるようにしています。")
                .foregroundStyle(.secondary)
            Label("緊急のときは、審査なし・待ち時間なし・通信なしで、すぐに解除できます。", systemImage: "exclamationmark.shield")
                .foregroundStyle(FGColor.emergency)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            Text("許可の設定").font(.title.bold())
            Card(title: "スクリーンタイム", systemImage: "hourglass") {
                Text("アプリを制限し、使用時間を測るために必要です。どのアプリを使ったかの情報は端末の外に送りません。")
                    .font(.subheadline)
                if model.authorizationStatus == .approved {
                    Label("許可済み", systemImage: "checkmark.circle.fill").foregroundStyle(FGColor.approve)
                } else {
                    Button("スクリーンタイムを許可する") {
                        Task { await model.requestScreenTimeAuthorization() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Card(title: "通知", systemImage: "bell") {
                Text("ブロック画面から申請画面へ移るときと、許可時間が終わったときに使います。")
                    .font(.subheadline)
                if notificationsGranted {
                    Label("許可済み", systemImage: "checkmark.circle.fill").foregroundStyle(FGColor.approve)
                } else {
                    Button("通知を許可する") {
                        Task { notificationsGranted = await LocalNotifier.requestAuthorization() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var exemptStep: some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            Text("常に使えるアプリ").font(.title.bold())
            Text("電話・メッセージ・地図・健康・防災など、緊急時に必要なアプリを選んでください。ここで選んだアプリは、制限の対象に含まれていても制限しません。")
            Button {
                showExemptPicker = true
            } label: {
                Label("常に許可するアプリを選ぶ", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            if !SelectionCodec.isEmpty(exempt) {
                Text("\(exempt.applicationTokens.count)個のアプリを選択中").foregroundStyle(.secondary)
            }
            Text("iPhone の「電話」アプリと緊急SOSは、Screen Time の制限を受けません。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            Text("制限するアプリ").font(.title.bold())
            Text("つい開いてしまうアプリを、名前を付けて登録します（例：「Instagram」「動画アプリ」）。あとから設定で追加・変更できます。")
            ForEach(model.data.targets) { t in
                Label(t.name, systemImage: "lock.app.dashed")
            }
            Button {
                editingTarget = GuardTarget(name: "")
            } label: {
                Label("制限するアプリを追加", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("戻る") { step -= 1 }
            }
            Spacer()
            if step < 3 {
                Button("次へ") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 1 && model.authorizationStatus != .approved)
            } else {
                Button("はじめる") {
                    model.updateSettings { $0.hasCompletedOnboarding = true }
                    model.refresh()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.data.targets.isEmpty)
            }
        }
        .padding()
    }
}
