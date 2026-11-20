import DeviceActivity
import SwiftUI

/// iOS のスクリーンタイムが記録した実際の使用時間を表示するレポート拡張。
/// Apple のプライバシー設計により、ここで読んだ使用時間はこの拡張の外（本体アプリや通信）へ出せない。
@main
struct FocusReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        UsageSummaryReport { summary in
            UsageSummaryView(summary: summary)
        }
    }
}

extension DeviceActivityReport.Context {
    static let usageSummary = Self("usageSummary")
}

struct UsageSummary {
    struct Day: Identifiable {
        var id: Date { date }
        var date: Date
        var duration: TimeInterval
    }

    struct App: Identifiable {
        var id: String { name }
        var name: String
        var duration: TimeInterval
        var pickups: Int
    }

    var days: [Day]
    var todayApps: [App]

    var today: TimeInterval? {
        let start = Calendar.current.startOfDay(for: Date())
        return days.first { $0.date == start }?.duration
    }

    var yesterday: TimeInterval? {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) else { return nil }
        return days.first { $0.date == start }?.duration
    }
}

struct UsageSummaryReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .usageSummary
    let content: (UsageSummary) -> UsageSummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var byDay: [Date: TimeInterval] = [:]
        var apps: [String: (TimeInterval, Int)] = [:]

        for await device in data {
            for await segment in device.activitySegments {
                let day = cal.startOfDay(for: segment.dateInterval.start)
                byDay[day, default: 0] += segment.totalActivityDuration
                guard day == todayStart else { continue }
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? "不明なアプリ"
                        let current = apps[name] ?? (0, 0)
                        apps[name] = (current.0 + app.totalActivityDuration, current.1 + app.numberOfPickups)
                    }
                }
            }
        }
        let days = byDay.map { UsageSummary.Day(date: $0.key, duration: $0.value) }.sorted { $0.date < $1.date }
        let topApps = apps.map { UsageSummary.App(name: $0.key, duration: $0.value.0, pickups: $0.value.1) }
            .sorted { $0.duration > $1.duration }
        return UsageSummary(days: days, todayApps: Array(topApps.prefix(5)))
    }
}

struct UsageSummaryView: View {
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("今日").font(.caption).foregroundStyle(.secondary)
                    Text(summary.today.map(format) ?? "データなし").font(.title.weight(.semibold)).monospacedDigit()
                }
                Spacer()
                if let t = summary.today, let y = summary.yesterday {
                    let diff = t - y
                    Text(diff >= 0 ? "昨日より \(format(diff)) 多い" : "昨日より \(format(-diff)) 少ない")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("昨日のデータなし").font(.caption).foregroundStyle(.secondary)
                }
            }
            if summary.days.count > 2 {
                let maxValue = max(summary.days.map(\.duration).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(summary.days) { d in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.indigo)
                                .frame(height: max(2, CGFloat(d.duration / maxValue) * 90))
                            Text(d.date.formatted(.dateTime.month(.defaultDigits).day())).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120, alignment: .bottom)
            }
            ForEach(summary.todayApps) { app in
                HStack {
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Text("\(format(app.duration))・\(app.pickups)回").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m >= 60 ? "\(m / 60)時間\(m % 60)分" : "\(m)分"
    }
}
