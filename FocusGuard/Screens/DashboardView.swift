import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings
import FocusGuardKit

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.today
        let summary = Analytics.summary(for: today, data: model.data)
        let yesterday = Analytics.summary(for: today.adding(days: -1), data: model.data)

        NavigationStack {
            ScrollView {
                VStack(spacing: FGSpacing.l) {
                    ReflectionPrompt()
                    actions
                    ActiveSessionsCard()
                    UsageReportCard(days: 2)
                    requestStats(summary, yesterday: yesterday)
                    repeatedCard(summary)
                    goalCard(summary)
                }
                .padding()
            }
            .background(FGColor.background)
            .navigationTitle("今日")
        }
    }

    private var actions: some View {
        VStack(spacing: FGSpacing.m) {
            Button {
                model.requestDraft = RequestDraftSeed(targetID: model.data.targets.count == 1 ? model.data.targets[0].id : nil)
            } label: {
                Label("利用を申請する", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.data.targets.isEmpty)

            Button(role: .destructive) {
                model.showEmergency = true
            } label: {
                Label("緊急解除", systemImage: "exclamationmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func requestStats(_ s: DaySummary, yesterday y: DaySummary) -> some View {
        Card(title: "申請の記録", systemImage: "square.and.pencil") {
            Grid(alignment: .leading, horizontalSpacing: FGSpacing.l, verticalSpacing: FGSpacing.m) {
                GridRow {
                    StatTile(label: "許可した時間", value: minutesText(s.grantedMinutes),
                             note: y.hasData ? diffText(s.grantedMinutes - y.grantedMinutes) : "昨日の記録なし")
                    StatTile(label: "計測できた使用時間", value: s.measuredMinutes.map(minutesText) ?? "—",
                             note: s.measuredMinutes == nil ? "計測データなし" : "制限中アプリの解除中のみ")
                }
                GridRow {
                    StatTile(label: "申請", value: "\(s.requestCount)回")
                    StatTile(label: "承認 / 再質問 / 不承認", value: "\(s.approvedRounds) / \(s.clarifyRounds) / \(s.deniedRounds)")
                }
                GridRow {
                    StatTile(label: "申請の取りやめ", value: "\(s.abandonedCount)回")
                    StatTile(label: "ブロック画面で閉じた", value: "\(s.shieldClosedCount)回")
                }
                GridRow {
                    StatTile(label: "緊急解除", value: "\(s.emergencyCount)回",
                             note: s.emergencyCount > 0 ? "計\(minutesText(s.emergencyMinutes))" : nil)
                    Color.clear
                }
            }
            Text("「取りやめ」や「閉じた」は、使うのを思いとどまった可能性を示す目安です。理由までは分からないため、必ずしも衝動を抑えられたとは限りません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func repeatedCard(_ s: DaySummary) -> some View {
        if !s.repeated.isEmpty {
            Card(title: "同じ目的での繰り返し", systemImage: "arrow.triangle.2.circlepath") {
                ForEach(s.repeated) { r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.label).font(.subheadline.weight(.medium))
                            Text(model.target(r.targetID)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(r.count)回・\(minutesText(r.minutes))").monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func goalCard(_ s: DaySummary) -> some View {
        if let status = Analytics.goalStatus(s, settings: model.data.settings) {
            Card(title: "1日の目標", systemImage: "flag") {
                switch status {
                case .achieved(let used, let goal):
                    ProgressView(value: Double(used), total: Double(max(goal, 1)))
                    Text("目標 \(minutesText(goal)) のうち \(minutesText(used))。達成ペースです。")
                case .exceeded(let used, let goal):
                    ProgressView(value: 1).tint(FGColor.deny)
                    Text("目標 \(minutesText(goal)) を \(minutesText(used - goal)) 超えています。")
                }
            }
        }
    }

    private func diffText(_ d: Int) -> String {
        d == 0 ? "昨日と同じ" : (d > 0 ? "昨日より\(minutesText(d))多い" : "昨日より\(minutesText(-d))少ない")
    }
}

/// 解除中のアプリと残り時間
struct ActiveSessionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.data.activeSessions()
        if !active.isEmpty {
            Card(title: "解除中", systemImage: "lock.open") {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: FGSpacing.m) {
                        ForEach(active) { s in
                            row(s, now: ctx.date)
                        }
                    }
                }
                Text("使用時間が許可した分に達するか、期限が来ると自動で制限に戻ります。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ s: UsageSession, now: Date) -> some View {
        let name = s.targetID == nil ? "すべての対象" : (model.target(s.targetID)?.name ?? "対象")
        let remaining = max(0, Int(s.wallClockEnd.timeIntervalSince(now)))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.headline)
                if s.isEmergency {
                    Text("緊急").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(FGColor.emergency.opacity(0.15), in: Capsule()).foregroundStyle(FGColor.emergency)
                }
                Spacer()
                Text(String(format: "期限まで %d:%02d", remaining / 60, remaining % 60)).monospacedDigit()
            }
            Text("許可 \(minutesText(s.grantedMinutes))" + (s.measuredMinutes.map { "・使用 約\($0)分" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("今すぐ制限に戻す") { model.endSessionNow(s.id) }
                    .buttonStyle(.bordered)
                if !s.isEmergency, let tid = s.targetID {
                    Button("延長を申請") {
                        let purpose = model.data.records.first { $0.sessionID == s.id }?.request.purpose ?? ""
                        model.requestDraft = RequestDraftSeed(targetID: tid, extendsSessionID: s.id, purpose: purpose)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
        }
    }
}

/// iOS のスクリーンタイムが記録した実際の使用時間（レポート拡張が描画。データは拡張の外に出ない）
struct UsageReportCard: View {
    @Environment(AppModel.self) private var model
    var days: Int

    var body: some View {
        Card(title: days <= 2 ? "実際の使用時間（スクリーンタイム）" : "1週間の使用時間（スクリーンタイム）", systemImage: "hourglass") {
            if model.authorizationStatus == .approved {
                DeviceActivityReport(DeviceActivityReport.Context(FGReport.usageSummary), filter: filter)
                    .frame(minHeight: days <= 2 ? 220 : 320)
            } else {
                Text("スクリーンタイムを許可すると表示されます。").foregroundStyle(.secondary)
            }
        }
    }

    private var filter: DeviceActivityFilter {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) ?? Date()
        var apps = Set<ApplicationToken>()
        var categories = Set<ActivityCategoryToken>()
        var domains = Set<WebDomainToken>()
        for t in model.data.targets {
            if let sel = SelectionCodec.decode(t.selectionData) {
                apps.formUnion(sel.applicationTokens)
                categories.formUnion(sel.categoryTokens)
                domains.formUnion(sel.webDomainTokens)
            }
        }
        let interval = DateInterval(start: start, end: Date())
        if apps.isEmpty && categories.isEmpty && domains.isEmpty {
            return DeviceActivityFilter(segment: .daily(during: interval), users: .all, devices: .init([.iPhone]))
        }
        return DeviceActivityFilter(segment: .daily(during: interval), users: .all, devices: .init([.iPhone]),
                                    applications: apps, categories: categories, webDomains: domains)
    }
}

/// 前日までの緊急解除の振り返り（罰はなく、記録と気づきのため）
struct ReflectionPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pending = Analytics.emergenciesNeedingReflection(today: model.today, data: model.data)
        let notice = Analytics.frequentEmergencyNotice(today: model.today, data: model.data)
        if let e = pending.first {
            Card(title: "緊急解除のふりかえり", systemImage: "text.bubble") {
                Text("\(e.day.shortLabel) \(e.date.formatted(date: .omitted, time: .shortened)) に「\(e.kind.label)」で緊急解除を使いました。振り返ると、どうでしたか？")
                    .font(.subheadline)
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                ForEach(EmergencyReflection.allCases, id: \.self) { r in
                    Button(r.label) {
                        model.mutate { $0.reflect(emergencyID: e.id, r) }
                    }
                    .buttonStyle(.bordered)
                }
                if pending.count > 1 {
                    Text("ほかに\(pending.count - 1)件あります").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
