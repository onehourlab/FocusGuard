import SwiftUI
import FocusGuardKit

/// 緊急解除：AI審査・通信・待ち時間なし。種類を1つ選ぶだけで、すぐに全対象を解除する。
/// 回数で使えなくなることはない。代わりに記録を残し、翌日以降に振り返りを促す。
struct EmergencyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 15
    @State private var scopeTargetID: UUID?
    @State private var done: EmergencyKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FGSpacing.l) {
                    if let done {
                        unlocked(done)
                    } else {
                        chooser
                    }
                }
                .padding()
            }
            .background(FGColor.background)
            .navigationTitle("緊急解除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done == nil ? "キャンセル" : "閉じる") { dismiss() }
                }
            }
            .onAppear { minutes = model.data.settings.emergencyDefaultMinutes }
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            Text("審査なしで、すぐに解除します。")
                .font(.title3.bold())
            Text("通信やAIは使いません。使ったことは記録され、あとで振り返りをお願いすることがあります。")
                .font(.subheadline).foregroundStyle(.secondary)

            Picker("解除する時間", selection: $minutes) {
                ForEach([5, 15, 30, 60], id: \.self) { Text("\($0)分").tag($0) }
            }
            .pickerStyle(.segmented)

            if model.data.targets.count > 1 {
                Picker("対象", selection: $scopeTargetID) {
                    Text("すべての対象").tag(UUID?.none)
                    ForEach(model.data.targets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            Text("何のための緊急ですか？（押すとすぐに解除されます）")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FGSpacing.m) {
                ForEach(EmergencyKind.allCases, id: \.self) { kind in
                    Button {
                        model.emergencyUnlock(kind: kind, targetID: scopeTargetID, minutes: minutes)
                        done = kind
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: kind.symbol).font(.title2)
                            Text(kind.label).font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(FGColor.emergency.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(FGColor.emergency)
                    }
                    .buttonStyle(.plain)
                }
            }

            Card(title: "毎回の緊急解除が必要なアプリは", systemImage: "lightbulb") {
                Text("電話・連絡・健康・安全のために使うアプリは、設定の「常に許可するアプリ」に入れておくと、解除の操作そのものが要らなくなります。")
                    .font(.footnote)
            }
            todayCount
        }
    }

    private func unlocked(_ kind: EmergencyKind) -> some View {
        VStack(alignment: .leading, spacing: FGSpacing.l) {
            Label("解除しました", systemImage: "lock.open.fill")
                .font(.title.bold()).foregroundStyle(FGColor.emergency)
            Text("「\(kind.label)」として\(minutesText(minutes))解除しています。時間が来ると自動で制限に戻ります。")
            Text("用事が済んだら、ホームの「今すぐ制限に戻す」で早めに戻せます。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("閉じる") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var todayCount: some View {
        let n = model.data.emergencies.filter { $0.day == model.today }.count
        if n > 0 {
            Text("今日の緊急解除：\(n)回（回数による制限はありません）")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
