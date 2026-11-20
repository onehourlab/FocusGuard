import XCTest
@testable import FocusGuardKit

final class LedgerAndAnalyticsTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    func date(_ hour: Int, _ minute: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func approved(_ minutes: Int) -> ReviewResult {
        ReviewResult(verdict: .approve, checks: [], question: nil, denialReasons: [], grantedMinutes: minutes,
                     suggestedMinutes: nil, category: .communication, source: .rules)
    }

    // MARK: 類似判定

    func testSimilarMessagingPurposesMatch() {
        let a = "友達からのDMに返信するため5分"
        let b = "Instagramでメッセージを返すため5分"
        let c = "友達に返信するため5分"
        for (x, y) in [(a, b), (a, c), (b, c)] {
            XCTAssertGreaterThanOrEqual(PurposeMatcher.similarity(x, y, removing: ["Instagram"]), PurposeMatcher.sameThreshold, "\(x) / \(y)")
        }
    }

    func testDifferentPurposesDoNotMatch() {
        XCTAssertLessThan(PurposeMatcher.similarity("友達のDMに返信する", "授業の動画を見る"), PurposeMatcher.sameThreshold)
        XCTAssertLessThan(PurposeMatcher.similarity("ストーリーを眺める", "コンサートのチケットを予約する"), PurposeMatcher.sameThreshold)
        XCTAssertLessThan(PurposeMatcher.similarity("友達にDM返信", "家族にDM返信"), PurposeMatcher.sameThreshold, "相手が違えば別の目的")
    }

    func testNormalizationIgnoresWidthAndKana() {
        XCTAssertEqual(TextNormalizer.normalize("ＤＭ　メッセージ！"), TextNormalizer.normalize("dmめっせーじ"))
    }

    // MARK: 記録

    func testApprovalStartsSessionAndWallClockRespectsMinimumInterval() {
        var data = FocusData(targets: [GuardTarget(name: "Instagram")])
        let req = UsageRequest(targetID: data.targets[0].id, purpose: "友達のDMに返信", reason: "待たせているので",
                               minutes: 5, createdAt: date(12))
        let record = data.recordReview(req, result: approved(5), now: date(12), calendar: calendar)
        XCTAssertEqual(record.status, .approved)
        let session = data.sessions.first { $0.id == record.sessionID }!
        XCTAssertEqual(session.grantedMinutes, 5)
        XCTAssertEqual(session.wallClockEnd.timeIntervalSince(date(12)), 15 * 60, "iOSの監視は最短15分")
        XCTAssertEqual(SessionPlanner.thresholds(grantedMinutes: 5), [1, 2, 3, 4, 5])
        XCTAssertEqual(SessionPlanner.thresholds(grantedMinutes: 40).last, 40)
    }

    func testExtensionEndsPreviousSession() {
        var data = FocusData(targets: [GuardTarget(name: "YouTube")])
        let tid = data.targets[0].id
        let first = UsageRequest(targetID: tid, purpose: "授業動画を1本見る", reason: "課題のため", minutes: 20, createdAt: date(10))
        let r1 = data.recordReview(first, result: approved(20), now: date(10), calendar: calendar)
        let ext = UsageRequest(targetID: tid, purpose: "授業動画の続きを最後まで見る", reason: "残り5分だった",
                               minutes: 5, createdAt: date(10, 20), extendsSessionID: r1.sessionID)
        data.recordReview(ext, result: approved(5), now: date(10, 20), calendar: calendar)
        XCTAssertEqual(data.sessions.first { $0.id == r1.sessionID }?.endReason, .extended)
        XCTAssertEqual(data.activeSessions(now: date(10, 21)).count, 1)
    }

    func testUsageLimitEventRecordsMeasuredMinutes() {
        var data = FocusData(targets: [GuardTarget(name: "X")])
        let s = data.startSession(targetID: data.targets[0].id, requestID: nil, minutes: 10, emergency: false, now: date(9))
        data.recordMeasuredUsage(sessionID: s.id, minutes: 4)
        data.recordMeasuredUsage(sessionID: s.id, minutes: 3)
        XCTAssertEqual(data.sessions[0].measuredMinutes, 4, "小さい値で上書きしない")
        data.endSession(s.id, reason: .usageLimitReached, now: date(9, 30))
        XCTAssertEqual(data.sessions[0].measuredMinutes, 10)
    }

    func testExpiredSessionsAreClosed() {
        var data = FocusData()
        data.startSession(targetID: nil, requestID: nil, minutes: 5, emergency: true, now: date(9))
        XCTAssertEqual(data.closeExpiredSessions(now: date(9, 10)).count, 0)
        XCTAssertEqual(data.closeExpiredSessions(now: date(9, 16)).count, 1)
        XCTAssertTrue(data.activeSessions(now: date(9, 16)).isEmpty)
    }

    func testAbandonIsCountedButNeverOverridesApproval() {
        var data = FocusData(targets: [GuardTarget(name: "TikTok")])
        let tid = data.targets[0].id
        let a = UsageRequest(targetID: tid, purpose: "おすすめを見る", reason: "", minutes: 10, createdAt: date(22))
        data.recordAbandon(a, stage: .beforeSubmit, calendar: calendar)
        let b = UsageRequest(targetID: tid, purpose: "友達に返信", reason: "待たせている", minutes: 5, createdAt: date(22))
        data.recordReview(b, result: approved(5), now: date(22), calendar: calendar)
        data.recordAbandon(b, stage: .duringClarification, calendar: calendar)
        let s = Analytics.summary(for: DayKey(date(22), calendar: calendar), data: data, calendar: calendar)
        XCTAssertEqual(s.abandonedCount, 1)
        XCTAssertEqual(s.requestCount, 1)
        XCTAssertEqual(s.approvedRounds, 1)
    }

    // MARK: 緊急解除

    func testEmergencyNeverBlockedAndPromptsReflectionLater() {
        var data = FocusData(targets: [GuardTarget(name: "LINE")])
        for i in 0..<5 {
            let (rec, session) = data.recordEmergency(kind: .call, targetID: nil, minutes: 15, now: date(8 + i), calendar: calendar)
            XCTAssertTrue(session.isEmergency)
            XCTAssertEqual(rec.sessionID, session.id)
        }
        XCTAssertEqual(data.emergencies.count, 5, "回数が多くても解除できる")
        let today = DayKey(date(12), calendar: calendar)
        XCTAssertTrue(Analytics.emergenciesNeedingReflection(today: today, data: data, calendar: calendar).isEmpty, "当日は振り返りを求めない")
        let tomorrow = today.adding(days: 1, calendar: calendar)
        XCTAssertEqual(Analytics.emergenciesNeedingReflection(today: tomorrow, data: data, calendar: calendar).count, 5)
        XCTAssertNotNil(Analytics.frequentEmergencyNotice(today: tomorrow, data: data, calendar: calendar))
        let summary = Analytics.summary(for: today, data: data, calendar: calendar)
        XCTAssertEqual(summary.emergencyCount, 5)
        XCTAssertEqual(summary.grantedMinutes, 0, "緊急解除は通常の利用時間に数えない")
    }

    // MARK: 集計

    func testNoFabricatedNumbersWithoutData() {
        let data = FocusData()
        let today = DayKey(date(12), calendar: calendar)
        XCTAssertNil(Analytics.baseline(before: today, data: data, calendar: calendar))
        let s = Analytics.summary(for: today, data: data, calendar: calendar)
        XCTAssertFalse(s.hasData)
        XCTAssertNil(s.measuredMinutes)
        XCTAssertNil(Analytics.goalStatus(s, settings: FocusSettings()))
    }

    func testBaselineUsesOnlyDaysWithData() {
        var data = FocusData(targets: [GuardTarget(name: "X")])
        let tid = data.targets[0].id
        data.startSession(targetID: tid, requestID: nil, minutes: 20, emergency: false, now: date(9, day: 17))
        data.startSession(targetID: tid, requestID: nil, minutes: 40, emergency: false, now: date(9, day: 18))
        let b = Analytics.baseline(before: DayKey(date(9, day: 20), calendar: calendar), data: data, calendar: calendar)
        XCTAssertEqual(b?.minutes, 30)
        data.settings.baselineDailyMinutes = 90
        XCTAssertEqual(Analytics.baseline(before: DayKey(date(9, day: 20), calendar: calendar), data: data, calendar: calendar)?.minutes, 90)
    }

    func testRepeatedPurposesInSummary() {
        var data = FocusData(targets: [GuardTarget(name: "Instagram")])
        let tid = data.targets[0].id
        for (i, p) in ["友達からのDMに返信する", "メッセージを返す", "友達に返信する"].enumerated() {
            let req = UsageRequest(targetID: tid, purpose: p, reason: "r\(i)", minutes: 5, createdAt: date(9 + i))
            data.recordReview(req, result: approved(5), now: date(9 + i), calendar: calendar)
        }
        let s = Analytics.summary(for: DayKey(date(12), calendar: calendar), data: data, calendar: calendar)
        XCTAssertEqual(s.repeated.first?.count, 3)
        XCTAssertEqual(s.repeated.first?.minutes, 15)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fg-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FocusStore(fileURL: url)
        store.update { $0.targets.append(GuardTarget(name: "YouTube", dailyCapMinutes: 30)) }
        XCTAssertEqual(store.load().targets.first?.dailyCapMinutes, 30)
    }
}
