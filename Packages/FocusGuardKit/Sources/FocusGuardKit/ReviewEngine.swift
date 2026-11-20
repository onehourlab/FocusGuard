import Foundation

/// オンデバイスAI（Apple Foundation Models）が返す意味判定。
/// AIは「文章の読み取り」だけを担当し、承認・不承認の最終判断は ReviewEngine の決まった規則で行う。
public struct SemanticAssessment: Codable, Hashable, Sendable {
    /// 0 = 何をするのか不明確 / 1 = やや不足 / 2 = 具体的
    public var specificity: Int
    public var hasEndCondition: Bool
    /// この目的に妥当と考えられる最大の分数
    public var reasonableMaxMinutes: Int?
    public var category: PurposeCategory?
    /// 本人ルールのうち、この申請が反している可能性があるもの（本人ルールの文をそのまま）
    public var conflictingRules: [String]
    /// 追加で聞くべきこと（あれば）
    public var question: String?

    public init(specificity: Int, hasEndCondition: Bool, reasonableMaxMinutes: Int?, category: PurposeCategory?,
                conflictingRules: [String], question: String?) {
        self.specificity = specificity
        self.hasEndCondition = hasEndCondition
        self.reasonableMaxMinutes = reasonableMaxMinutes
        self.category = category
        self.conflictingRules = conflictingRules
        self.question = question
    }
}

public struct ReviewContext: Sendable {
    public var request: UsageRequest
    public var target: GuardTarget
    public var settings: FocusSettings
    public var records: [RequestRecord]
    public var sessions: [UsageSession]
    public var clusters: [PurposeCluster]
    public var now: Date
    public var calendar: Calendar
    public var assessment: SemanticAssessment?

    public init(request: UsageRequest, target: GuardTarget, settings: FocusSettings, records: [RequestRecord],
                sessions: [UsageSession], clusters: [PurposeCluster], now: Date = Date(),
                calendar: Calendar = .current, assessment: SemanticAssessment? = nil) {
        self.request = request
        self.target = target
        self.settings = settings
        self.records = records
        self.sessions = sessions
        self.clusters = clusters
        self.now = now
        self.calendar = calendar
        self.assessment = assessment
    }

    public init(request: UsageRequest, data: FocusData, now: Date = Date(), calendar: Calendar = .current,
                assessment: SemanticAssessment? = nil) throws {
        guard let target = data.target(request.targetID) else { throw ReviewError.unknownTarget }
        self.init(request: request, target: target, settings: data.settings, records: data.records,
                  sessions: data.sessions, clusters: data.clusters, now: now, calendar: calendar, assessment: assessment)
    }
}

public enum ReviewError: Error { case unknownTarget }

/// 申請の審査。同じ入力には必ず同じ結果を返し、各基準ごとに理由を示す。
public enum ReviewEngine {
    public static let maxMinutesPerRequest = 180
    static let recentRepeatWindow: TimeInterval = 10 * 60
    static let duplicateLookbackDays = 14

    private struct RuleFinding {
        var status: CheckStatus
        var message: String
        var question: String?
        /// true のときは説明を受けても変わらない（上限など）。即不承認。
        var isHard: Bool
        var suggestedMinutes: Int?
    }

    public static func review(_ ctx: ReviewContext) -> ReviewResult {
        let req = ctx.request
        let names = [ctx.target.name]
        let purposeText = req.purpose + "。" + req.answersText
        let allText = req.purpose + "。" + req.reason + "。" + req.answersText
        let concepts = ConceptLexicon.concepts(in: purposeText)
        let category = ctx.assessment?.category ?? ConceptLexicon.category(for: concepts)
        let hasAnswers = !req.clarifications.isEmpty
        let answersOK = hasAnswers
            && TextHeuristics.substanceLength(req.answersText, removing: names) >= 4
            && !TextHeuristics.containsVagueWord(req.answersText)

        let specificity = checkSpecificity(req, concepts: concepts, names: names, assessment: ctx.assessment)
        let end = checkEndCondition(allText: allText, concepts: concepts, category: category, assessment: ctx.assessment)
        let duration = checkDuration(req, concepts: concepts, assessment: ctx.assessment, answersOK: answersOK)
        let history = checkHistory(ctx, names: names, hasAnswers: hasAnswers, answersOK: answersOK)
        let rules = checkRules(ctx, category: category, hasAnswers: hasAnswers, names: names)

        let ruleStatus = rules.map(\.status).max() ?? .pass
        let ruleMessage = rules.isEmpty
            ? ruleSummary(ctx)
            : rules.map(\.message).joined(separator: " ")
        let ruleCheck = CheckResult(criterion: .rules, status: ruleStatus, message: ruleMessage,
                                    question: rules.first { $0.status == .fail && !$0.isHard }?.question)
        let checks = [specificity, end, duration, history, ruleCheck]

        // 1) 本人が決めた上限などに反する → 説明があっても不承認
        let hard = rules.filter { $0.isHard && $0.status == .fail }
        if !hard.isEmpty {
            let suggestion = hard.compactMap(\.suggestedMinutes).filter { $0 > 0 }.min()
            return ReviewResult(verdict: .deny, checks: checks, question: nil, denialReasons: hard.map(\.message),
                                grantedMinutes: 0, suggestedMinutes: suggestion, category: category,
                                source: ctx.assessment == nil ? .rules : .onDeviceAI)
        }

        // 2) 追加説明で解決できる不足 → 再質問（上限回数まで）。質問の優先順は ルール → 履歴 → 具体性 → 終了条件 → 時間
        let order: [CheckResult] = [ruleCheck, history, specificity, end, duration]
        let failing = order.filter { $0.status == .fail }
        if !failing.isEmpty {
            if req.clarifications.count < ctx.settings.maxClarifications {
                var question = failing.compactMap(\.question).first ?? "もう少し具体的に教えてください。"
                if let aiQ = ctx.assessment?.question?.trimmingCharacters(in: .whitespacesAndNewlines), !aiQ.isEmpty,
                   let first = failing.first, first.criterion == .specificity || first.criterion == .endCondition {
                    question = aiQ
                }
                return ReviewResult(verdict: .clarify, checks: checks, question: question, denialReasons: [],
                                    grantedMinutes: 0, suggestedMinutes: nil, category: category,
                                    source: ctx.assessment == nil ? .rules : .onDeviceAI)
            }
            var reasons = failing.map { "\($0.criterion.label)：\($0.message)" }
            reasons.append("追加の説明を\(req.clarifications.count)回受けても確認できなかったため、通常の解除は行いません。緊急の場合は緊急解除を使えます。")
            return ReviewResult(verdict: .deny, checks: checks, question: nil, denialReasons: reasons,
                                grantedMinutes: 0, suggestedMinutes: nil, category: category,
                                source: ctx.assessment == nil ? .rules : .onDeviceAI)
        }

        // 3) 承認：申告した時間だけ
        return ReviewResult(verdict: .approve, checks: checks, question: nil, denialReasons: [],
                            grantedMinutes: req.minutes, suggestedMinutes: nil, category: category,
                            source: ctx.assessment == nil ? .rules : .onDeviceAI)
    }

    // MARK: 1. 具体性（目的＋今使う理由）

    private static func checkSpecificity(_ req: UsageRequest, concepts: Set<Concept>, names: [String],
                                         assessment: SemanticAssessment?) -> CheckResult {
        let text = req.purpose + "。" + req.answersText
        let substance = TextHeuristics.substanceLength(text, removing: names)
        let topics = concepts.filter { $0.kind == .topic }
        let vagueOnly = TextHeuristics.containsVagueWord(req.purpose) && topics.isEmpty && substance < 6
        let reasonText = req.reason + "。" + req.answersText
        let reasonWeak = TextHeuristics.substanceLength(reasonText, removing: names) < 2
            || (TextHeuristics.containsVagueWord(req.reason) && req.clarifications.isEmpty)

        var status: CheckStatus
        if vagueOnly || substance < 3 {
            status = .fail
        } else if let a = assessment {
            status = a.specificity >= 2 ? .pass : (a.specificity == 1 ? .warn : .fail)
        } else if concepts.isEmpty && substance < 6 {
            status = .fail
        } else if topics.isEmpty && substance < 5 {
            status = .warn
        } else {
            status = .pass
        }

        if status != .fail && reasonWeak {
            return CheckResult(criterion: .specificity, status: .fail,
                               message: "「なぜ今使う必要があるのか」が読み取れません。",
                               question: "なぜ今使う必要があるのか教えてください（例：相手が返事を待っている、今日が締め切り）。")
        }
        switch status {
        case .pass:
            return CheckResult(criterion: .specificity, status: .pass, message: "何をするのかが具体的です。")
        case .warn:
            return CheckResult(criterion: .specificity, status: .warn, message: "目的は読み取れますが、対象（誰に・何を）がもう少しあると明確です。")
        case .fail:
            return CheckResult(criterion: .specificity, status: .fail,
                               message: "何をするのかがはっきりしません。",
                               question: "「\(req.purpose)」で具体的に何をしますか？　誰に・何を・どうするのかを教えてください。")
        }
    }

    // MARK: 2. 終了条件

    private static func checkEndCondition(allText: String, concepts: Set<Concept>, category: PurposeCategory,
                                          assessment: SemanticAssessment?) -> CheckResult {
        let ids = Set(concepts.map(\.id))
        let bounded = !ids.isDisjoint(with: ConceptLexicon.boundedActions)
        let cue = TextHeuristics.hasEndCue(allText)
        let openEnded = category == .entertainment || !ids.isDisjoint(with: ["watch", "browse", "play"])

        var status: CheckStatus = (cue || bounded) ? .pass : (openEnded ? .fail : .warn)
        if let a = assessment, !a.hasEndCondition {
            status = status == .pass ? .warn : .fail
        } else if let a = assessment, a.hasEndCondition, status == .warn {
            status = .pass
        }
        switch status {
        case .pass:
            return CheckResult(criterion: .endCondition, status: .pass,
                               message: cue ? "終わりにするタイミングが書かれています。" : "用事が済めば終わる内容です。")
        case .warn:
            return CheckResult(criterion: .endCondition, status: .warn, message: "終わりのタイミングがやや曖昧です。時間が来たら自動で制限に戻ります。")
        case .fail:
            return CheckResult(criterion: .endCondition, status: .fail,
                               message: "どこで終わりにするのかが書かれていません。",
                               question: "何をしたら終わりにしますか？（例：「2本見たら終わり」「返信を送ったら閉じる」）")
        }
    }

    // MARK: 3. 時間の妥当性

    private static func checkDuration(_ req: UsageRequest, concepts: Set<Concept>, assessment: SemanticAssessment?,
                                      answersOK: Bool) -> CheckResult {
        let range = ConceptLexicon.typicalRange(for: concepts)
        var upper = range.upperBound
        if let ai = assessment?.reasonableMaxMinutes {
            upper = min(max(ai, range.lowerBound), range.upperBound * 2)
        }
        let label = PurposeMatcher.label(for: req.purpose)
        if req.minutes <= upper {
            return CheckResult(criterion: .duration, status: .pass, message: "\(req.minutes)分は目的に対して妥当な範囲です（目安 \(upper)分以内）。")
        }
        if req.minutes <= upper * 2 || answersOK {
            return CheckResult(criterion: .duration, status: .warn, message: "\(req.minutes)分は目安（\(upper)分）より長めです。")
        }
        return CheckResult(criterion: .duration, status: .fail,
                           message: "\(req.minutes)分は目安（\(upper)分）の2倍を超えています。",
                           question: "「\(label)」に\(req.minutes)分は長めに見えます。その時間が必要な理由か、短くできるかを教えてください。")
    }

    // MARK: 4. 過去の利用との関係

    private static func checkHistory(_ ctx: ReviewContext, names: [String], hasAnswers: Bool, answersOK: Bool) -> CheckResult {
        let req = ctx.request
        let today = DayKey(ctx.now, calendar: ctx.calendar)
        let others = ctx.records.filter { $0.request.targetID == req.targetID && $0.id != req.id }
        let lookback = today.adding(days: -duplicateLookbackDays, calendar: ctx.calendar)

        let myText = TextNormalizer.comparable(req.purpose + req.reason, removing: names)
        let duplicate = !myText.isEmpty && others.contains {
            $0.day >= lookback && $0.status != .abandoned
                && TextNormalizer.comparable($0.request.purpose + $0.request.reason, removing: names) == myText
        }

        let cluster = PurposeMatcher.bestCluster(for: req.purpose, targetID: req.targetID, clusters: ctx.clusters, removing: names)
        let sameToday = others.filter { $0.day == today && $0.status == .approved && cluster != nil && $0.clusterID == cluster?.id }
        let sessionIDs = Set(sameToday.compactMap(\.sessionID))
        let sameSessions = ctx.sessions.filter { sessionIDs.contains($0.id) }
        let minutesToday = sameSessions.reduce(0) { $0 + $1.countedMinutes }
        let recentUsedUp = sameSessions.first {
            $0.endReason == .usageLimitReached
                && ctx.now.timeIntervalSince($0.endedAt ?? $0.wallClockEnd) < recentRepeatWindow
        }
        let extensionCount = req.extendsSessionID.map { sid in
            others.filter { $0.request.extendsSessionID == sid && $0.status == .approved }.count
        } ?? 0

        // 気になる点（同じ文章・延長の繰り返し・同じ目的の繰り返し・直後の再申請）を1つ選ぶ
        var issue: (message: String, question: String)?
        if duplicate {
            issue = ("以前の申請とまったく同じ文章です。",
                     "以前の申請とまったく同じ文章です。今回の用事が前回とどう違うのかを具体的に教えてください。")
        } else if extensionCount >= 2 {
            issue = ("この利用はすでに\(extensionCount)回延長しています。",
                     "この利用はすでに\(extensionCount)回延長しています。あと何が残っていて、それはいつ終わりますか？")
        } else if sameToday.count >= ctx.settings.repeatQuestionThreshold {
            issue = ("本日すでに同じ目的で\(sameToday.count)回（計\(minutesToday)分）利用しています。",
                     "本日はすでに同じ目的で\(sameToday.count)回利用しています。今回はどのような新しい用事がありますか？")
        } else if let s = recentUsedUp {
            let mins = max(1, Int(ctx.now.timeIntervalSince(s.endedAt ?? s.wallClockEnd) / 60))
            issue = ("\(mins)分前に同じ目的の許可時間を使い切ったばかりです。",
                     "\(mins)分前にも同じ目的で利用し、時間を使い切りました。前回で済まなかったことは何ですか？")
        }

        // 同じ目的の繰り返し自体は自然なこと。新しい用事が説明されれば通す。
        if let issue {
            if hasAnswers && answersOK {
                return CheckResult(criterion: .history, status: .warn, message: issue.message + "新しい用事の説明がありました。")
            }
            if hasAnswers {
                return CheckResult(criterion: .history, status: .fail, message: issue.message + "追加の説明から新しい用事が読み取れませんでした。",
                                   question: "前回までと違う、今回だけの用事を具体的に書いてください。")
            }
            return CheckResult(criterion: .history, status: .fail, message: issue.message, question: issue.question)
        }
        if !sameToday.isEmpty {
            return CheckResult(criterion: .history, status: .pass,
                               message: "本日この目的で\(sameToday.count + 1)回目です（これまで計\(minutesToday)分）。")
        }
        return CheckResult(criterion: .history, status: .pass, message: "過去の利用と矛盾する点はありません。")
    }

    // MARK: 5. 本人が設定したルール

    private static func checkRules(_ ctx: ReviewContext, category: PurposeCategory, hasAnswers: Bool,
                                   names: [String]) -> [RuleFinding] {
        let req = ctx.request
        let target = ctx.target
        var out: [RuleFinding] = []

        if req.minutes < 1 {
            out.append(RuleFinding(status: .fail, message: "時間は1分以上で申請してください。", isHard: true, suggestedMinutes: 1))
        }
        if req.minutes > maxMinutesPerRequest {
            out.append(RuleFinding(status: .fail, message: "1回の申請は最大\(maxMinutesPerRequest)分です。", isHard: true,
                                   suggestedMinutes: maxMinutesPerRequest))
        }
        if let cap = target.maxMinutesPerSession, req.minutes > cap {
            out.append(RuleFinding(status: .fail, message: "「\(target.name)」は1回\(cap)分までのルールです。", isHard: true,
                                   suggestedMinutes: cap))
        }

        // 時間帯ルール：最初は確認の質問、説明後も当てはまらなければ不承認
        for w in target.restrictedWindows where w.window.contains(ctx.now, calendar: ctx.calendar) {
            if !w.allowedCategories.contains(category) {
                let allowed = PurposeCategory.allCases.filter { w.allowedCategories.contains($0) }.map(\.label).joined(separator: "・")
                let msg = "\(w.window.label)は「\(allowed.isEmpty ? "なし" : allowed)」の目的だけに使うルールです（今回は「\(category.label)」と判定）。"
                out.append(RuleFinding(status: .fail, message: msg,
                                       question: hasAnswers ? nil : "\(msg)今回の用事がそのどれかに当たる場合は、どれに当たるのか説明してください。",
                                       isHard: hasAnswers, suggestedMinutes: nil))
            }
        }

        // 1日の累計上限（任意機能）
        if ctx.settings.limitMode == .reviewWithDailyCaps {
            let today = DayKey(ctx.now, calendar: ctx.calendar)
            let todaySessions = ctx.sessions.filter {
                !$0.isEmergency && $0.targetID == target.id && DayKey($0.startedAt, calendar: ctx.calendar) == today
            }
            if let cap = target.dailyCapMinutes {
                let used = todaySessions.reduce(0) { $0 + $1.countedMinutes }
                let remaining = cap - used
                if remaining <= 0 {
                    out.append(RuleFinding(status: .fail, message: "本日の「\(target.name)」の上限\(cap)分に達しています。", isHard: true))
                } else if req.minutes > remaining {
                    out.append(RuleFinding(status: .fail, message: "本日の「\(target.name)」は残り\(remaining)分です（上限\(cap)分）。",
                                           isHard: true, suggestedMinutes: remaining))
                }
            }
            let requestsByID = Dictionary(ctx.records.map { ($0.request.id, $0.request) }, uniquingKeysWith: { a, _ in a })
            for cap in target.purposeCaps
            where PurposeMatcher.similarity(req.purpose, cap.label, removing: names) >= PurposeMatcher.sameThreshold {
                let used = todaySessions.filter { s in
                    guard let rid = s.requestID, let r = requestsByID[rid] else { return false }
                    return PurposeMatcher.similarity(r.purpose, cap.label, removing: names) >= PurposeMatcher.sameThreshold
                }.reduce(0) { $0 + $1.countedMinutes }
                let remaining = cap.maxMinutesPerDay - used
                if remaining <= 0 {
                    out.append(RuleFinding(status: .fail, message: "「\(cap.label)」の本日の上限\(cap.maxMinutesPerDay)分に達しています。", isHard: true))
                } else if req.minutes > remaining {
                    out.append(RuleFinding(status: .fail, message: "「\(cap.label)」は本日残り\(remaining)分です。",
                                           isHard: true, suggestedMinutes: remaining))
                }
            }
        }

        // 文章で書いた本人ルール（AIの指摘は、実在するルール文と一致したものだけ採用）
        if let conflicts = ctx.assessment?.conflictingRules, !conflicts.isEmpty {
            let matched = target.personalRules.filter { rule in
                let r = TextNormalizer.normalize(rule)
                return conflicts.contains { c in
                    let n = TextNormalizer.normalize(c)
                    return !n.isEmpty && (r.contains(n) || n.contains(r))
                }
            }
            if let rule = matched.first {
                out.append(RuleFinding(status: .fail,
                                       message: hasAnswers ? "説明を受けても、あなたのルール「\(rule)」に合わないと判断しました。"
                                                           : "あなたのルール「\(rule)」に当てはまる可能性があります。",
                                       question: hasAnswers ? nil : "あなたのルール「\(rule)」に当てはまる可能性があります。今回がルールに沿っている理由を教えてください。",
                                       isHard: hasAnswers, suggestedMinutes: nil))
            }
        }
        return out
    }

    private static func ruleSummary(_ ctx: ReviewContext) -> String {
        var parts: [String] = []
        if ctx.settings.limitMode == .reviewWithDailyCaps, let cap = ctx.target.dailyCapMinutes {
            parts.append("1日の上限\(cap)分の範囲内")
        }
        if let cap = ctx.target.maxMinutesPerSession { parts.append("1回\(cap)分以内") }
        if !ctx.target.restrictedWindows.isEmpty { parts.append("時間帯ルールに適合") }
        return parts.isEmpty ? "設定したルールに反する点はありません。" : parts.joined(separator: "・") + "です。"
    }
}
