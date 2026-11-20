import Foundation

/// 解除期間（セッション）の作り方。iOS の DeviceActivity の制約に合わせる。
public enum SessionPlanner {
    /// DeviceActivitySchedule の最短の監視間隔（これより短いと iOS がエラーにする）
    public static let minimumMonitorMinutes = 15

    /// 使わなくても再び制限する時刻。使用時間で再制限するのが基本で、これは使い忘れ時の上限。
    public static func wallClockEnd(start: Date, grantedMinutes: Int) -> Date {
        start.addingTimeInterval(TimeInterval(max(grantedMinutes + 1, minimumMonitorMinutes) * 60))
    }

    /// 実際の使用時間を計測するための「使用時間しきい値」（分）。最後の値で再制限する。
    public static func thresholds(grantedMinutes: Int) -> [Int] {
        let g = max(1, grantedMinutes)
        let step = g <= 30 ? 1 : (g <= 120 ? 5 : 10)
        var values = Array(stride(from: step, to: g, by: step))
        values.append(g)
        return values
    }
}

/// 保存データへの変更はすべてここを通す（アプリと拡張で同じ処理にするため）。
public extension FocusData {
    static let retentionDays = 400

    // MARK: 申請

    /// 審査結果を記録する。承認なら目的のまとまりを決め、セッションを開始する。
    @discardableResult
    mutating func recordReview(_ request: UsageRequest, result: ReviewResult, now: Date = Date(),
                               calendar: Calendar = .current) -> RequestRecord {
        let day = DayKey(request.createdAt, calendar: calendar)
        var record = records.first { $0.id == request.id }
            ?? RequestRecord(request: request, day: day, status: .clarifying)
        record.request = request
        record.rounds.append(result.verdict)
        record.lastResult = result
        record.category = result.category
        record.abandonedAt = nil
        switch result.verdict {
        case .approve:
            record.status = .approved
            record.clusterID = assignCluster(for: request)
            if let sid = request.extendsSessionID {
                endSession(sid, reason: .extended, now: now)
            }
            let session = startSession(targetID: request.targetID, requestID: request.id,
                                       minutes: result.grantedMinutes, emergency: false, now: now)
            record.sessionID = session.id
        case .clarify:
            record.status = .clarifying
        case .deny:
            record.status = .denied
        }
        upsert(record)
        return record
    }

    /// 申請を途中でやめた。送信前でも、目的を入力し始めていれば記録する。
    mutating func recordAbandon(_ request: UsageRequest, stage: AbandonStage, calendar: Calendar = .current) {
        let day = DayKey(request.createdAt, calendar: calendar)
        var record = records.first { $0.id == request.id } ?? RequestRecord(request: request, day: day, status: .abandoned)
        // 承認済み・不承認の申請は「取りやめ」に数えない
        guard record.status != .approved, record.status != .denied else { return }
        record.request = request
        record.status = .abandoned
        record.abandonedAt = stage
        upsert(record)
    }

    private mutating func upsert(_ record: RequestRecord) {
        if let i = records.firstIndex(where: { $0.id == record.id }) {
            records[i] = record
        } else {
            records.append(record)
        }
    }

    private mutating func assignCluster(for request: UsageRequest) -> UUID {
        let names = [target(request.targetID)?.name ?? ""]
        if let c = PurposeMatcher.bestCluster(for: request.purpose, targetID: request.targetID, clusters: clusters, removing: names),
           let i = clusters.firstIndex(where: { $0.id == c.id }) {
            if !clusters[i].samples.contains(request.purpose) {
                clusters[i].samples.append(request.purpose)
                if clusters[i].samples.count > 12 { clusters[i].samples.removeFirst() }
            }
            return c.id
        }
        let c = PurposeCluster(targetID: request.targetID, label: PurposeMatcher.label(for: request.purpose), samples: [request.purpose])
        clusters.append(c)
        return c.id
    }

    // MARK: セッション

    @discardableResult
    mutating func startSession(targetID: UUID?, requestID: UUID?, minutes: Int, emergency: Bool, now: Date = Date()) -> UsageSession {
        let s = UsageSession(targetID: targetID, requestID: requestID, isEmergency: emergency, startedAt: now,
                             grantedMinutes: minutes, wallClockEnd: SessionPlanner.wallClockEnd(start: now, grantedMinutes: minutes))
        sessions.append(s)
        return s
    }

    mutating func endSession(_ id: UUID, reason: SessionEndReason, now: Date = Date()) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].endedAt == nil else { return }
        sessions[i].endedAt = min(now, sessions[i].wallClockEnd)
        sessions[i].endReason = reason
        if reason == .usageLimitReached { sessions[i].measuredMinutes = sessions[i].grantedMinutes }
    }

    /// 使用時間しきい値イベントで計測できた分数を記録する（大きい方だけ採用）
    mutating func recordMeasuredUsage(sessionID: UUID, minutes: Int) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[i].measuredMinutes = max(sessions[i].measuredMinutes ?? 0, min(minutes, sessions[i].grantedMinutes))
    }

    /// 期限を過ぎたのに終了していないセッションを閉じる（監視拡張が動かなかった場合の後始末）
    mutating func closeExpiredSessions(now: Date = Date()) -> [UsageSession] {
        var closed: [UsageSession] = []
        for i in sessions.indices where sessions[i].endedAt == nil && now >= sessions[i].wallClockEnd {
            sessions[i].endedAt = sessions[i].wallClockEnd
            sessions[i].endReason = .windowEnded
            closed.append(sessions[i])
        }
        return closed
    }

    func activeSessions(now: Date = Date()) -> [UsageSession] {
        sessions.filter { $0.isActive(at: now) }
    }

    // MARK: 緊急解除（AI・通信・待ち時間なし）

    @discardableResult
    mutating func recordEmergency(kind: EmergencyKind, targetID: UUID?, minutes: Int, now: Date = Date(),
                                  calendar: Calendar = .current) -> (EmergencyRecord, UsageSession) {
        let session = startSession(targetID: targetID, requestID: nil, minutes: minutes, emergency: true, now: now)
        let record = EmergencyRecord(date: now, day: DayKey(now, calendar: calendar), kind: kind, targetID: targetID,
                                     minutes: minutes, sessionID: session.id)
        emergencies.append(record)
        return (record, session)
    }

    mutating func reflect(emergencyID: UUID, _ reflection: EmergencyReflection) {
        guard let i = emergencies.firstIndex(where: { $0.id == emergencyID }) else { return }
        emergencies[i].reflection = reflection
    }

    // MARK: ブロック画面

    mutating func recordShieldEvent(_ kind: ShieldEventKind, targetID: UUID?, now: Date = Date(), calendar: Calendar = .current) {
        shieldEvents.append(ShieldEvent(date: now, day: DayKey(now, calendar: calendar), kind: kind, targetID: targetID))
        if kind == .requested {
            pendingShieldTargetID = targetID
            pendingShieldAt = now
        }
    }

    /// ブロック画面から申請へ進んだ対象を受け取る（10分以上前のものは無視）
    mutating func takePendingShieldTarget(now: Date = Date()) -> UUID? {
        defer { pendingShieldTargetID = nil; pendingShieldAt = nil }
        guard let at = pendingShieldAt, now.timeIntervalSince(at) < 600 else { return nil }
        return pendingShieldTargetID
    }

    // MARK: 保守

    /// 古い記録を削除する（振り返り用に retentionDays 日は残す）
    mutating func prune(now: Date = Date(), calendar: Calendar = .current) {
        let cutoff = DayKey(now, calendar: calendar).adding(days: -Self.retentionDays, calendar: calendar)
        let cutoffDate = cutoff.startDate(calendar: calendar)
        records.removeAll { $0.day < cutoff }
        sessions.removeAll { $0.startedAt < cutoffDate && $0.endedAt != nil }
        emergencies.removeAll { $0.day < cutoff }
        shieldEvents.removeAll { $0.day < cutoff }
    }
}
