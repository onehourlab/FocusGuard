import Foundation

/// 同じ目的の繰り返し（1日分）
public struct RepeatedPurpose: Hashable, Sendable, Identifiable {
    public var id: UUID { clusterID }
    public var clusterID: UUID
    public var targetID: UUID
    public var label: String
    public var count: Int
    public var minutes: Int

    public init(clusterID: UUID, targetID: UUID, label: String, count: Int, minutes: Int) {
        self.clusterID = clusterID
        self.targetID = targetID
        self.label = label
        self.count = count
        self.minutes = minutes
    }
}

/// 1日分の集計。値が無いもの（計測できなかった実使用時間など）は nil にし、推測で埋めない。
public struct DaySummary: Hashable, Sendable, Identifiable {
    public var id: DayKey { day }
    public var day: DayKey
    public var requestCount: Int
    public var approvedRounds: Int
    public var clarifyRounds: Int
    public var deniedRounds: Int
    public var abandonedCount: Int
    public var shieldClosedCount: Int
    public var emergencyCount: Int
    public var emergencyMinutes: Int
    /// 申請で許可した時間（緊急解除を除く）
    public var grantedMinutes: Int
    /// iOSの使用時間しきい値で計測できた分数。計測できたセッションが無い日は nil
    public var measuredMinutes: Int?
    /// 1日の累計に数えた分数（計測値があれば計測値、なければ許可時間）
    public var countedMinutes: Int
    public var repeated: [RepeatedPurpose]
    public var perTargetRequests: [UUID: Int]

    /// その日に記録が1件でもあるか（無い日は「データなし」と表示する）
    public var hasData: Bool {
        requestCount > 0 || emergencyCount > 0 || shieldClosedCount > 0 || grantedMinutes > 0
    }
}

public enum GoalStatus: Hashable, Sendable {
    case achieved(used: Int, goal: Int)
    case exceeded(used: Int, goal: Int)
}

public enum Analytics {
    public static func summary(for day: DayKey, data: FocusData, calendar: Calendar = .current) -> DaySummary {
        let recs = data.records.filter { $0.day == day }
        let sessions = data.sessions.filter { DayKey($0.startedAt, calendar: calendar) == day }
        let normal = sessions.filter { !$0.isEmergency }
        let measuredSessions = normal.filter { $0.measuredMinutes != nil }
        let emergencies = data.emergencies.filter { $0.day == day }

        var repeated: [RepeatedPurpose] = []
        let approved = recs.filter { $0.status == .approved && $0.clusterID != nil }
        for (cid, group) in Dictionary(grouping: approved, by: { $0.clusterID! }) where group.count >= 2 {
            let ids = Set(group.compactMap(\.sessionID))
            let mins = normal.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.countedMinutes }
            let cluster = data.clusters.first { $0.id == cid }
            repeated.append(RepeatedPurpose(clusterID: cid, targetID: group[0].request.targetID,
                                            label: cluster?.label ?? group[0].request.purpose, count: group.count, minutes: mins))
        }
        repeated.sort { ($0.count, $0.minutes) > ($1.count, $1.minutes) }

        var perTarget: [UUID: Int] = [:]
        for r in recs where r.status != .abandoned || !r.rounds.isEmpty { perTarget[r.request.targetID, default: 0] += 1 }

        let allRounds = recs.flatMap(\.rounds)
        return DaySummary(
            day: day,
            requestCount: recs.filter { !$0.rounds.isEmpty }.count,
            approvedRounds: allRounds.filter { $0 == .approve }.count,
            clarifyRounds: allRounds.filter { $0 == .clarify }.count,
            deniedRounds: allRounds.filter { $0 == .deny }.count,
            abandonedCount: recs.filter { $0.status == .abandoned }.count,
            shieldClosedCount: data.shieldEvents.filter { $0.day == day && $0.kind == .closed }.count,
            emergencyCount: emergencies.count,
            emergencyMinutes: emergencies.reduce(0) { $0 + $1.minutes },
            grantedMinutes: normal.reduce(0) { $0 + $1.grantedMinutes },
            measuredMinutes: measuredSessions.isEmpty ? nil : measuredSessions.reduce(0) { $0 + ($1.measuredMinutes ?? 0) },
            countedMinutes: normal.reduce(0) { $0 + $1.countedMinutes },
            repeated: repeated,
            perTargetRequests: perTarget)
    }

    /// day を最後とする n 日分（古い順）
    public static func days(endingOn day: DayKey, count: Int, data: FocusData, calendar: Calendar = .current) -> [DaySummary] {
        (0..<count).reversed().map { summary(for: day.adding(days: -$0, calendar: calendar), data: data, calendar: calendar) }
    }

    /// 削減量の基準（分/日）。設定値 → 過去の実データの平均（データのある日だけ）の順。どちらも無ければ nil。
    public static func baseline(before day: DayKey, data: FocusData, lookbackDays: Int = 7,
                                calendar: Calendar = .current) -> (minutes: Int, source: String)? {
        if let b = data.settings.baselineDailyMinutes { return (b, "設定した基準値") }
        let past = (1...lookbackDays).map { summary(for: day.adding(days: -$0, calendar: calendar), data: data, calendar: calendar) }
            .filter(\.hasData)
        guard !past.isEmpty else { return nil }
        let avg = past.reduce(0) { $0 + $1.countedMinutes } / past.count
        return (avg, "過去\(past.count)日の平均")
    }

    public static func goalStatus(_ summary: DaySummary, settings: FocusSettings) -> GoalStatus? {
        guard let goal = settings.dailyGoalMinutes else { return nil }
        return summary.countedMinutes <= goal
            ? .achieved(used: summary.countedMinutes, goal: goal)
            : .exceeded(used: summary.countedMinutes, goal: goal)
    }

    /// 振り返りを促す緊急解除（今日より前・7日以内・未回答）
    public static func emergenciesNeedingReflection(today: DayKey, data: FocusData, calendar: Calendar = .current) -> [EmergencyRecord] {
        let from = today.adding(days: -7, calendar: calendar)
        return data.emergencies.filter { $0.day < today && $0.day >= from && $0.reflection == nil }
            .sorted { $0.date > $1.date }
    }

    /// 緊急解除が多い週かどうか（多くても解除はできる。振り返りの提案だけに使う）
    public static func frequentEmergencyNotice(today: DayKey, data: FocusData, calendar: Calendar = .current) -> String? {
        let from = today.adding(days: -6, calendar: calendar)
        let n = data.emergencies.filter { $0.day >= from && $0.day <= today }.count
        guard n >= 3 else { return nil }
        return "この7日間で緊急解除を\(n)回使いました。使った場面を振り返り、必要なアプリは「常に許可」に入れることも検討してください。"
    }
}
