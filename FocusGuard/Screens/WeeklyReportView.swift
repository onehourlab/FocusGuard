import SwiftUI
import Charts
import FocusGuardKit

/// 週次レポート。記録が無い日はグラフに出さず、数字を推測で埋めない。
struct WeeklyReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.today
        let week = Analytics.days(endingOn: today, count: 7, data: model.data)
        let withData = week.filter(\.hasData)
        let baseline = Analytics.baseline(before: today.adding(days: -6), data: model.data, lookbackDays: 28)

        NavigationStack {
            ScrollView {
                VStack(spacing: FGSpacing.l) {
                    UsageReportCard(days: 7)
                    Card(title: "許可した時間（制限対象アプリ）", systemImage: "chart.bar") {
                        if withData.isEmpty {
                            Text("この1週間の記録はまだありません。").foregroundStyle(.secondary)
                        } else {
                            Chart(withData) { d in
                                BarMark(x: .value("日付", d.day.shortLabel), y: .value("分", d.countedMinutes))
                                    .foregroundStyle(FGColor.accent)
                            }
                            .chartXScale(domain: week.map(\.day.shortLabel))
                            .frame(height: 180)
                            Text("記録がある日だけを表示しています。計測できた使用時間がある日はその値、ない日は許可した時間です。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    reductionCard(withData, baseline: baseline)
                    Card(title: "申請と取りやめ", systemImage: "square.and.pencil") {
                        if withData.isEmpty {
                            Text("記録なし").foregroundStyle(.secondary)
                        } else {
                            Chart {
                                ForEach(withData) { d in
                                    LineMark(x: .value("日付", d.day.shortLabel), y: .value("回", d.requestCount))
                                        .foregroundStyle(by: .value("種類", "申請"))
                                    LineMark(x: .value("日付", d.day.shortLabel), y: .value("回", d.abandonedCount))
                                        .foregroundStyle(by: .value("種類", "取りやめ"))
                                    LineMark(x: .value("日付", d.day.shortLabel), y: .value("回", d.emergencyCount))
                                        .foregroundStyle(by: .value("種類", "緊急解除"))
                                }
                            }
                            .chartXScale(domain: week.map(\.day.shortLabel))
                            .frame(height: 160)
                        }
                        weekTotals(week)
                    }
                    repeatedCard(week)
                }
                .padding()
            }
            .background(FGColor.background)
            .navigationTitle("1週間のレポート")
        }
    }

    @ViewBuilder
    private func reductionCard(_ days: [DaySummary], baseline: (minutes: Int, source: String)?) -> some View {
        Card(title: "削減量", systemImage: "arrow.down.right") {
            if let baseline, !days.isEmpty {
                let avg = days.reduce(0) { $0 + $1.countedMinutes } / days.count
                let diff = baseline.minutes - avg
                Text(diff >= 0 ? "1日あたり \(minutesText(diff)) 減" : "1日あたり \(minutesText(-diff)) 増")
                    .font(.title2.bold())
                Text("基準：\(baseline.source) \(minutesText(baseline.minutes))/日 ・ 今週：記録のある\(days.count)日の平均 \(minutesText(avg))/日")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("比べられる基準がまだありません。設定で基準値を入れるか、記録が貯まると表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weekTotals(_ week: [DaySummary]) -> some View {
        let req = week.reduce(0) { $0 + $1.requestCount }
        let ab = week.reduce(0) { $0 + $1.abandonedCount }
        let closed = week.reduce(0) { $0 + $1.shieldClosedCount }
        let em = week.reduce(0) { $0 + $1.emergencyCount }
        return Grid(alignment: .leading, horizontalSpacing: FGSpacing.l, verticalSpacing: FGSpacing.s) {
            GridRow {
                StatTile(label: "申請", value: "\(req)回")
                StatTile(label: "取りやめ", value: "\(ab)回")
            }
            GridRow {
                StatTile(label: "ブロック画面で閉じた", value: "\(closed)回")
                StatTile(label: "緊急解除", value: "\(em)回")
            }
        }
    }

    @ViewBuilder
    private func repeatedCard(_ week: [DaySummary]) -> some View {
        let merged = Dictionary(grouping: week.flatMap(\.repeated), by: \.clusterID)
            .map { (id, items) in
                RepeatedPurpose(clusterID: id, targetID: items[0].targetID, label: items[0].label,
                                count: items.reduce(0) { $0 + $1.count }, minutes: items.reduce(0) { $0 + $1.minutes })
            }
            .sorted { $0.count > $1.count }
        if !merged.isEmpty {
            Card(title: "同じ目的での繰り返し（1日2回以上の日）", systemImage: "arrow.triangle.2.circlepath") {
                ForEach(Array(merged.prefix(5))) { item in
                    HStack {
                        Text(item.label)
                        Spacer()
                        Text("\(item.count)回・\(minutesText(item.minutes))").monospacedDigit()
                    }
                }
            }
        }
    }
}
