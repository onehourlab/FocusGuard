import XCTest
@testable import FocusGuardKit

final class ReviewEngineTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    func date(_ hour: Int, _ minute: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func makeData(target: GuardTarget = GuardTarget(name: "Instagram"), settings: FocusSettings = FocusSettings()) -> FocusData {
        FocusData(settings: settings, targets: [target])
    }

    func review(_ req: UsageRequest, _ data: FocusData, at now: Date, assessment: SemanticAssessment? = nil) -> ReviewResult {
        let ctx = try! ReviewContext(request: req, data: data, now: now, calendar: calendar, assessment: assessment)
        return ReviewEngine.review(ctx)
    }

    // MARK: 基本

    func testSpecificMessagingRequestIsApproved() {
        let data = makeData()
        let req = UsageRequest(targetID: data.targets[0].id, purpose: "友達からのDMに返信する",
                               reason: "友達が返事を待っているから", minutes: 5, createdAt: date(12))
        let r = review(req, data, at: date(12))
        XCTAssertEqual(r.verdict, .approve, r.checks.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(r.grantedMinutes, 5)
        XCTAssertEqual(r.category, .communication)
        XCTAssertEqual(r.checks.count, Criterion.allCases.count, "5つの基準すべてに説明がある")
    }

    func testVaguePurposeAsksQuestionInsteadOfDenying() {
        let data = makeData()
        let req = UsageRequest(targetID: data.targets[0].id, purpose: "なんとなく", reason: "暇だから", minutes: 10, createdAt: date(12))
        let r = review(req, data, at: date(12))
        XCTAssertEqual(r.verdict, .clarify)
        XCTAssertNotNil(r.question)
    }

    func testEntertainmentIsNotDeniedJustForBeingEntertainment() {
        let data = makeData(target: GuardTarget(name: "YouTube"))
        let open = UsageRequest(targetID: data.targets[0].id, purpose: "YouTubeでゲーム実況の動画を見る",
                                reason: "休憩時間なので息抜きしたい", minutes: 20, createdAt: date(15))
        let r1 = review(open, data, at: date(15))
        XCTAssertEqual(r1.verdict, .clarify, "終了条件が無いので質問する（拒否はしない）")
        XCTAssertEqual(r1.checks.first { $0.criterion == .endCondition }?.status, .fail)

        let bounded = UsageRequest(targetID: data.targets[0].id, purpose: "YouTubeでゲーム実況の動画を2本見たら終わり",
                                   reason: "休憩時間なので息抜きしたい", minutes: 20, createdAt: date(15))
        let r2 = review(bounded, data, at: date(15))
        XCTAssertEqual(r2.verdict, .approve, r2.checks.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(r2.category, .entertainment)
    }

    func testAnsweringClarificationLeadsToApproval() {
        let data = makeData(target: GuardTarget(name: "YouTube"))
        var req = UsageRequest(targetID: data.targets[0].id, purpose: "YouTubeでゲーム実況の動画を見る",
                               reason: "休憩時間なので息抜きしたい", minutes: 20, createdAt: date(15))
        let r1 = review(req, data, at: date(15))
        req.clarifications.append(Clarification(question: r1.question ?? "", answer: "新作の動画を1本見たら閉じます"))
        XCTAssertEqual(review(req, data, at: date(15)).verdict, .approve)
    }

    func testStillVagueAfterMaxClarificationsIsDenied() {
        let data = makeData()
        var req = UsageRequest(targetID: data.targets[0].id, purpose: "なんとなく", reason: "暇だから", minutes: 10, createdAt: date(12))
        req.clarifications = [Clarification(question: "q1", answer: "なんとなく"), Clarification(question: "q2", answer: "暇")]
        let r = review(req, data, at: date(12))
        XCTAssertEqual(r.verdict, .deny)
        XCTAssertFalse(r.denialReasons.isEmpty, "不承認には具体的な理由を付ける")
    }

    func testTooLongDurationAsksWhy() {
        let data = makeData()
        let req = UsageRequest(targetID: data.targets[0].id, purpose: "友達からのDMに返信する",
                               reason: "返事を待たせているので", minutes: 60, createdAt: date(12))
        let r = review(req, data, at: date(12))
        XCTAssertEqual(r.verdict, .clarify)
        XCTAssertEqual(r.checks.first { $0.criterion == .duration }?.status, .fail)
    }

    func testSameInputGivesSameResult() {
        let data = makeData()
        let req = UsageRequest(targetID: data.targets[0].id, purpose: "ストーリーを見る", reason: "気になったから",
                               minutes: 10, createdAt: date(12))
        XCTAssertEqual(review(req, data, at: date(12)), review(req, data, at: date(12)))
    }

    // MARK: 過去の利用との比較

    func testRepeatedSamePurposeTriggersQuestionThenApproval() {
        var data = makeData()
        let tid = data.targets[0].id
        let past = [
            ("友達からのDMに返信するため", "友達が返事を待っているから"),
            ("Instagramでメッセージを返すため", "相手から質問が来たので"),
            ("友達に返信するため", "既読をつけたままなので")
        ]
        for (i, p) in past.enumerated() {
            let req = UsageRequest(targetID: tid, purpose: p.0, reason: p.1, minutes: 5, createdAt: date(9 + i))
            let r = review(req, data, at: date(9 + i))
            XCTAssertEqual(r.verdict, .approve, "\(p.0): " + r.checks.map(\.message).joined(separator: " / "))
            data.recordReview(req, result: r, now: date(9 + i), calendar: calendar)
        }
        XCTAssertEqual(Set(data.records.compactMap(\.clusterID)).count, 1, "言い回しが違っても同じ目的にまとめる")

        var fourth = UsageRequest(targetID: tid, purpose: "友達に返信", reason: "新しくメッセージが届いたので",
                                  minutes: 5, createdAt: date(13))
        let r4 = review(fourth, data, at: date(13))
        XCTAssertEqual(r4.verdict, .clarify, "同じ目的の繰り返しは一律に拒否せず質問する")
        XCTAssertEqual(r4.question, "本日はすでに同じ目的で3回利用しています。今回はどのような新しい用事がありますか？")

        fourth.clarifications.append(Clarification(question: r4.question!, answer: "サークルの集合場所を部長に伝える必要がある"))
        XCTAssertEqual(review(fourth, data, at: date(13)).verdict, .approve)
    }

    func testRepeatCountResetsOnNextDay() {
        var data = makeData()
        let tid = data.targets[0].id
        let reasons = ["返事を待たせているので", "質問が来たので", "予定を聞かれたので"]
        for i in 0..<3 {
            let req = UsageRequest(targetID: tid, purpose: "友達からのDMに返信する", reason: reasons[i],
                                   minutes: 5, createdAt: date(9 + i))
            data.recordReview(req, result: review(req, data, at: date(9 + i)), now: date(9 + i), calendar: calendar)
        }
        let tomorrow = UsageRequest(targetID: tid, purpose: "友達からのDMに返信する", reason: "朝に連絡が来ていたので",
                                    minutes: 5, createdAt: date(9, day: 21))
        XCTAssertEqual(review(tomorrow, data, at: date(9, day: 21)).verdict, .approve)
        XCTAssertEqual(data.records.count, 3, "過去の記録は振り返り用に残る")
    }

    func testCopiedTextIsQuestioned() {
        var data = makeData()
        let tid = data.targets[0].id
        let first = UsageRequest(targetID: tid, purpose: "友達からのDMに返信する", reason: "友達が返事を待っているから",
                                 minutes: 5, createdAt: date(9))
        data.recordReview(first, result: review(first, data, at: date(9)), now: date(9), calendar: calendar)
        let copy = UsageRequest(targetID: tid, purpose: "友達からのDMに返信する", reason: "友達が返事を待っているから",
                                minutes: 5, createdAt: date(20))
        let r = review(copy, data, at: date(20))
        XCTAssertEqual(r.verdict, .clarify)
        XCTAssertTrue(r.question?.contains("同じ文章") ?? false)
    }

    // MARK: 本人ルール

    func testDailyCapDeniesWithRemainingSuggestion() {
        var target = GuardTarget(name: "YouTube")
        target.dailyCapMinutes = 30
        var data = makeData(target: target, settings: FocusSettings(limitMode: .reviewWithDailyCaps))
        let first = UsageRequest(targetID: target.id, purpose: "授業の動画を1本見る", reason: "明日の小テストの範囲だから",
                                 minutes: 25, createdAt: date(10))
        let r1 = review(first, data, at: date(10))
        XCTAssertEqual(r1.verdict, .approve, r1.checks.map(\.message).joined(separator: "\n"))
        data.recordReview(first, result: r1, now: date(10), calendar: calendar)

        let second = UsageRequest(targetID: target.id, purpose: "別の授業の動画を1本見る", reason: "復習が残っているので",
                                  minutes: 10, createdAt: date(11))
        let r2 = review(second, data, at: date(11))
        XCTAssertEqual(r2.verdict, .deny)
        XCTAssertEqual(r2.suggestedMinutes, 5)
    }

    func testReviewOnlyModeIgnoresDailyCaps() {
        var target = GuardTarget(name: "YouTube")
        target.dailyCapMinutes = 1
        let data = makeData(target: target, settings: FocusSettings(limitMode: .reviewOnly))
        let req = UsageRequest(targetID: target.id, purpose: "授業の動画を1本見る", reason: "明日の小テストの範囲だから",
                               minutes: 25, createdAt: date(10))
        XCTAssertEqual(review(req, data, at: date(10)).verdict, .approve)
    }

    func testPurposeCap() {
        var target = GuardTarget(name: "Instagram")
        target.dailyCapMinutes = 30
        target.purposeCaps = [PurposeCap(label: "DM返信", maxMinutesPerDay: 10)]
        var data = makeData(target: target, settings: FocusSettings(limitMode: .reviewWithDailyCaps))
        let a = UsageRequest(targetID: target.id, purpose: "友達からのDMに返信する", reason: "返事を待たせているので",
                             minutes: 8, createdAt: date(10))
        data.recordReview(a, result: review(a, data, at: date(10)), now: date(10), calendar: calendar)
        let b = UsageRequest(targetID: target.id, purpose: "先輩にメッセージを返す", reason: "集合時間を聞かれたので",
                             minutes: 5, createdAt: date(11))
        let r = review(b, data, at: date(11))
        XCTAssertEqual(r.verdict, .deny)
        XCTAssertEqual(r.suggestedMinutes, 2)
    }

    func testPerSessionCap() {
        var target = GuardTarget(name: "X")
        target.maxMinutesPerSession = 10
        let data = makeData(target: target)
        let req = UsageRequest(targetID: target.id, purpose: "電車の運行情報を調べる", reason: "帰りの電車が止まっているので",
                               minutes: 15, createdAt: date(18))
        let r = review(req, data, at: date(18))
        XCTAssertEqual(r.verdict, .deny)
        XCTAssertEqual(r.suggestedMinutes, 10)
    }

    func testRestrictedWindowAsksFirstThenDenies() {
        var target = GuardTarget(name: "YouTube")
        target.restrictedWindows = [RestrictedWindow(window: TimeWindow(startMinute: 22 * 60, endMinute: 7 * 60),
                                                     allowedCategories: [.study, .communication])]
        let data = makeData(target: target)
        var req = UsageRequest(targetID: target.id, purpose: "好きな配信者の動画を1本見たら終わり",
                               reason: "新作が出たので", minutes: 15, createdAt: date(23))
        let r1 = review(req, data, at: date(23))
        XCTAssertEqual(r1.verdict, .clarify)
        req.clarifications.append(Clarification(question: r1.question!, answer: "寝る前の楽しみにしたい"))
        XCTAssertEqual(review(req, data, at: date(23)).verdict, .deny)
        // 時間帯の外なら問題なし
        let day = UsageRequest(targetID: target.id, purpose: "好きな配信者の動画を1本見たら終わり",
                               reason: "新作が出たので", minutes: 15, createdAt: date(17))
        XCTAssertEqual(review(day, data, at: date(17)).verdict, .approve)
    }

    func testAIRuleConflictMustQuoteARealRule() {
        var target = GuardTarget(name: "YouTube")
        target.personalRules = ["夜はYouTubeを見ない"]
        let data = makeData(target: target)
        let req = UsageRequest(targetID: target.id, purpose: "授業の動画を1本見る", reason: "明日の小テストの範囲だから",
                               minutes: 20, createdAt: date(21))
        let made = SemanticAssessment(specificity: 2, hasEndCondition: true, reasonableMaxMinutes: 30, category: .study,
                                      conflictingRules: ["存在しないルール"], question: nil)
        XCTAssertEqual(review(req, data, at: date(21), assessment: made).verdict, .approve, "実在しないルールの指摘は採用しない")

        let real = SemanticAssessment(specificity: 2, hasEndCondition: true, reasonableMaxMinutes: 30, category: .study,
                                      conflictingRules: ["夜はYouTubeを見ない"], question: nil)
        let r = review(req, data, at: date(21), assessment: real)
        XCTAssertEqual(r.verdict, .clarify, "AIのルール指摘はまず質問にする")
        XCTAssertEqual(r.source, .onDeviceAI)
    }
}
