import SwiftUI
import FocusGuardKit

/// 申請と緊急解除の履歴（振り返り用。日付が変わっても消えない）
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var filterTargetID: UUID?

    var body: some View {
        let records = model.data.records
            .filter { filterTargetID == nil || $0.request.targetID == filterTargetID }
            .sorted { $0.request.createdAt > $1.request.createdAt }
        let byDay = Dictionary(grouping: records, by: \.day).sorted { $0.key > $1.key }
        let emergencies = model.data.emergencies.sorted { $0.date > $1.date }

        NavigationStack {
            List {
                if model.data.targets.count > 1 {
                    Picker("対象", selection: $filterTargetID) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(model.data.targets) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                if records.isEmpty && emergencies.isEmpty {
                    ContentUnavailableView("まだ記録がありません", systemImage: "tray",
                                           description: Text("利用申請をすると、ここに目的と結果が残ります。"))
                }
                ForEach(byDay, id: \.key) { entry in
                    Section("\(entry.key.shortLabel)（\(entry.value.count)件）") {
                        ForEach(entry.value) { r in
                            NavigationLink {
                                RecordDetailView(record: r)
                            } label: {
                                RecordRow(record: r, targetName: model.target(r.request.targetID)?.name ?? "削除した対象")
                            }
                        }
                    }
                }
                if !emergencies.isEmpty {
                    Section("緊急解除") {
                        ForEach(emergencies.prefix(50)) { e in
                            HStack {
                                Image(systemName: e.kind.symbol).foregroundStyle(FGColor.emergency)
                                VStack(alignment: .leading) {
                                    Text("\(e.kind.label)・\(minutesText(e.minutes))")
                                    Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(e.reflection?.label ?? "未振り返り").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("履歴")
        }
    }
}

struct RecordRow: View {
    let record: RequestRecord
    let targetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.status.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(record.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(record.status.color)
                Text(targetName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(record.request.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(record.request.purpose.isEmpty ? "（目的の入力前）" : record.request.purpose).lineLimit(2)
            Text("申告 \(minutesText(record.request.minutes))" + (record.rounds.count > 1 ? "・審査\(record.rounds.count)回" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RecordDetailView: View {
    @Environment(AppModel.self) private var model
    let record: RequestRecord

    var body: some View {
        let session = model.data.sessions.first { $0.id == record.sessionID }
        let cluster = model.data.clusters.first { $0.id == record.clusterID }
        List {
            Section("申請") {
                LabeledContent("目的", value: record.request.purpose)
                LabeledContent("今使う理由", value: record.request.reason)
                LabeledContent("申告した時間", value: minutesText(record.request.minutes))
                if let cluster { LabeledContent("目的のまとまり", value: cluster.label) }
                if let c = record.category { LabeledContent("分類", value: c.label) }
                if record.request.extendsSessionID != nil { Text("延長の申請").foregroundStyle(.secondary) }
            }
            if !record.request.clarifications.isEmpty {
                Section("追加の説明") {
                    ForEach(Array(record.request.clarifications.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q. " + item.element.question).font(.subheadline.weight(.medium))
                            Text("A. " + item.element.answer)
                        }
                    }
                }
            }
            Section("結果") {
                LabeledContent("状態", value: record.status.label)
                LabeledContent("審査の経過", value: record.rounds.map(\.label).joined(separator: " → "))
                if let stage = record.abandonedAt { LabeledContent("取りやめた段階", value: stage.label) }
                if let session {
                    LabeledContent("許可した時間", value: minutesText(session.grantedMinutes))
                    LabeledContent("計測できた使用時間", value: session.measuredMinutes.map { "約\($0)分" } ?? "計測データなし")
                    if let reason = session.endReason { LabeledContent("終了", value: reason.label) }
                }
            }
            if let result = record.lastResult {
                Section("最後の審査の内訳") {
                    ForEach(result.checks, id: \.criterion) { c in
                        Label {
                            VStack(alignment: .leading) {
                                Text(c.criterion.label)
                                Text(c.message).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: c.status.symbol).foregroundStyle(c.status.color)
                        }
                    }
                    ForEach(result.denialReasons, id: \.self) { Text($0).font(.caption) }
                }
            }
        }
        .navigationTitle(record.day.shortLabel)
    }
}
