import Foundation

// MARK: - 目的の分類

/// 使用目的の大まかな分類。娯楽であることだけを理由に不承認にはしない。
/// 本人が設定した「時間帯ルール」で許可する分類を決めるときに使う。
public enum PurposeCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case communication, information, study, work, shopping, creation, navigation, entertainment, other

    public var label: String {
        switch self {
        case .communication: return "連絡"
        case .information: return "調べもの"
        case .study: return "学習"
        case .work: return "仕事"
        case .shopping: return "買い物・予約"
        case .creation: return "投稿・制作"
        case .navigation: return "移動・地図"
        case .entertainment: return "娯楽・息抜き"
        case .other: return "その他"
        }
    }
}

// MARK: - 本人が設定するルール

/// 1日の中の時間帯（分単位）。開始 > 終了 のときは日をまたぐ（例: 22:00〜7:00）。
public struct TimeWindow: Codable, Hashable, Sendable {
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = max(0, min(1439, startMinute))
        self.endMinute = max(0, min(1439, endMinute))
    }

    public func contains(minuteOfDay m: Int) -> Bool {
        if startMinute == endMinute { return false }
        if startMinute < endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return contains(minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    public var label: String {
        func f(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }
        return "\(f(startMinute))〜\(f(endMinute))"
    }
}

/// 「この時間帯は、指定した目的以外では使わない」というルール。
public struct RestrictedWindow: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var window: TimeWindow
    public var allowedCategories: Set<PurposeCategory>

    public init(id: UUID = UUID(), window: TimeWindow, allowedCategories: Set<PurposeCategory>) {
        self.id = id
        self.window = window
        self.allowedCategories = allowedCategories
    }
}

/// 目的ごとの1日の上限（例: DM返信 最大20分）。label と意味が近い申請を同じ枠として数える。
public struct PurposeCap: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var maxMinutesPerDay: Int

    public init(id: UUID = UUID(), label: String, maxMinutesPerDay: Int) {
        self.id = id
        self.label = label
        self.maxMinutesPerDay = maxMinutesPerDay
    }
}

/// 制限の対象（ユーザーが名前を付けたアプリのまとまり。例: 「Instagram」）。
/// 実際のアプリの指定（FamilyActivitySelection）は端末内でしか読めない値なので Data のまま保持する。
public struct GuardTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var selectionData: Data?
    public var dailyCapMinutes: Int?
    public var purposeCaps: [PurposeCap]
    public var maxMinutesPerSession: Int?
    public var restrictedWindows: [RestrictedWindow]
    /// 文章で書いた本人ルール（例: 「試験前の週はYouTubeは授業動画だけ」）。オンデバイスAIだけが参照する。
    public var personalRules: [String]

    public init(id: UUID = UUID(), name: String, selectionData: Data? = nil, dailyCapMinutes: Int? = nil,
                purposeCaps: [PurposeCap] = [], maxMinutesPerSession: Int? = nil,
                restrictedWindows: [RestrictedWindow] = [], personalRules: [String] = []) {
        self.id = id
        self.name = name
        self.selectionData = selectionData
        self.dailyCapMinutes = dailyCapMinutes
        self.purposeCaps = purposeCaps
        self.maxMinutesPerSession = maxMinutesPerSession
        self.restrictedWindows = restrictedWindows
        self.personalRules = personalRules
    }
}

public enum LimitMode: String, Codable, CaseIterable, Sendable {
    /// 毎回の審査だけで管理する（1日の累計上限は使わない）
    case reviewOnly
    /// 審査に加えて、アプリごと・目的ごとの1日の累計上限を使う
    case reviewWithDailyCaps

    public var label: String {
        switch self {
        case .reviewOnly: return "毎回の審査だけ"
        case .reviewWithDailyCaps: return "審査＋1日の上限"
        }
    }
}

public struct FocusSettings: Codable, Hashable, Sendable {
    public var limitMode: LimitMode
    /// 1日の目標（制限対象アプリの合計分数）。未設定なら達成状況は表示しない。
    public var dailyGoalMinutes: Int?
    /// 削減量の基準値（分/日）。未設定なら過去の実データの平均を使い、データが無ければ表示しない。
    public var baselineDailyMinutes: Int?
    /// 同じ目的が1日にこの回数を超えたら、新しい用事があるかを質問する
    public var repeatQuestionThreshold: Int
    /// 再質問は1件の申請につき最大この回数まで
    public var maxClarifications: Int
    public var emergencyDefaultMinutes: Int
    public var useOnDeviceAI: Bool
    public var hasCompletedOnboarding: Bool

    public init(limitMode: LimitMode = .reviewOnly, dailyGoalMinutes: Int? = nil, baselineDailyMinutes: Int? = nil,
                repeatQuestionThreshold: Int = 3, maxClarifications: Int = 2, emergencyDefaultMinutes: Int = 15,
                useOnDeviceAI: Bool = true, hasCompletedOnboarding: Bool = false) {
        self.limitMode = limitMode
        self.dailyGoalMinutes = dailyGoalMinutes
        self.baselineDailyMinutes = baselineDailyMinutes
        self.repeatQuestionThreshold = repeatQuestionThreshold
        self.maxClarifications = maxClarifications
        self.emergencyDefaultMinutes = emergencyDefaultMinutes
        self.useOnDeviceAI = useOnDeviceAI
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

// MARK: - 申請と審査

public struct Clarification: Codable, Hashable, Sendable {
    public var question: String
    public var answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public struct UsageRequest: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var targetID: UUID
    public var purpose: String
    public var reason: String
    public var minutes: Int
    public var createdAt: Date
    public var clarifications: [Clarification]
    /// 延長申請のとき、延長する利用セッション
    public var extendsSessionID: UUID?

    public init(id: UUID = UUID(), targetID: UUID, purpose: String, reason: String, minutes: Int,
                createdAt: Date = Date(), clarifications: [Clarification] = [], extendsSessionID: UUID? = nil) {
        self.id = id
        self.targetID = targetID
        self.purpose = purpose
        self.reason = reason
        self.minutes = minutes
        self.createdAt = createdAt
        self.clarifications = clarifications
        self.extendsSessionID = extendsSessionID
    }

    /// 再質問への回答も含めた、判定に使う全文
    public var answersText: String { clarifications.map(\.answer).joined(separator: "。") }
}

public enum Verdict: String, Codable, Sendable {
    case approve, clarify, deny

    public var label: String {
        switch self {
        case .approve: return "承認"
        case .clarify: return "再質問"
        case .deny: return "不承認"
        }
    }
}

/// 審査基準（仕様の5項目）
public enum Criterion: String, Codable, CaseIterable, Sendable {
    case specificity, endCondition, duration, history, rules

    public var label: String {
        switch self {
        case .specificity: return "目的の具体性"
        case .endCondition: return "終了条件"
        case .duration: return "時間の妥当性"
        case .history: return "過去の利用との関係"
        case .rules: return "あなたのルール"
        }
    }
}

public enum CheckStatus: String, Codable, Sendable, Comparable {
    case pass, warn, fail

    private var rank: Int { self == .pass ? 0 : (self == .warn ? 1 : 2) }
    public static func < (l: CheckStatus, r: CheckStatus) -> Bool { l.rank < r.rank }
}

public struct CheckResult: Codable, Hashable, Sendable {
    public var criterion: Criterion
    public var status: CheckStatus
    public var message: String
    /// この項目で追加説明を求めるときの質問
    public var question: String?

    public init(criterion: Criterion, status: CheckStatus, message: String, question: String? = nil) {
        self.criterion = criterion
        self.status = status
        self.message = message
        self.question = question
    }
}

public enum ReviewSource: String, Codable, Sendable {
    case rules, onDeviceAI

    public var label: String {
        switch self {
        case .rules: return "ルール判定（端末内）"
        case .onDeviceAI: return "オンデバイスAI＋ルール判定"
        }
    }
}

public struct ReviewResult: Codable, Hashable, Sendable {
    public var verdict: Verdict
    public var checks: [CheckResult]
    public var question: String?
    public var denialReasons: [String]
    public var grantedMinutes: Int
    /// 不承認のときに、この時間なら申請できるという目安
    public var suggestedMinutes: Int?
    public var category: PurposeCategory
    public var source: ReviewSource

    public init(verdict: Verdict, checks: [CheckResult], question: String?, denialReasons: [String],
                grantedMinutes: Int, suggestedMinutes: Int?, category: PurposeCategory, source: ReviewSource) {
        self.verdict = verdict
        self.checks = checks
        self.question = question
        self.denialReasons = denialReasons
        self.grantedMinutes = grantedMinutes
        self.suggestedMinutes = suggestedMinutes
        self.category = category
        self.source = source
    }
}

public enum RequestStatus: String, Codable, Sendable {
    case approved, denied, clarifying, abandoned
}

/// 申請をどこで取りやめたか
public enum AbandonStage: String, Codable, Sendable {
    case beforeSubmit, duringClarification

    public var label: String {
        switch self {
        case .beforeSubmit: return "送信前"
        case .duringClarification: return "再質問の途中"
        }
    }
}

public struct RequestRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID { request.id }
    public var request: UsageRequest
    public var day: DayKey
    public var status: RequestStatus
    /// 審査の各回の結果（再質問 → 承認 など）
    public var rounds: [Verdict]
    public var lastResult: ReviewResult?
    public var clusterID: UUID?
    public var category: PurposeCategory?
    public var abandonedAt: AbandonStage?
    public var sessionID: UUID?

    public init(request: UsageRequest, day: DayKey, status: RequestStatus, rounds: [Verdict] = [],
                lastResult: ReviewResult? = nil, clusterID: UUID? = nil, category: PurposeCategory? = nil,
                abandonedAt: AbandonStage? = nil, sessionID: UUID? = nil) {
        self.request = request
        self.day = day
        self.status = status
        self.rounds = rounds
        self.lastResult = lastResult
        self.clusterID = clusterID
        self.category = category
        self.abandonedAt = abandonedAt
        self.sessionID = sessionID
    }
}

// MARK: - 利用セッション

public enum SessionEndReason: String, Codable, Sendable {
    case usageLimitReached, windowEnded, endedByUser, extended

    public var label: String {
        switch self {
        case .usageLimitReached: return "許可時間を使い切った"
        case .windowEnded: return "利用期限が来た"
        case .endedByUser: return "自分で終了"
        case .extended: return "延長した"
        }
    }
}

/// 制限を一時的に解除している期間。
public struct UsageSession: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// nil は「すべての対象」（緊急解除で全体を解除したとき）
    public var targetID: UUID?
    public var requestID: UUID?
    public var isEmergency: Bool
    public var startedAt: Date
    public var grantedMinutes: Int
    /// 使わなくてもこの時刻には再び制限する（iOSの監視間隔の最小値15分を考慮した期限）
    public var wallClockEnd: Date
    public var endedAt: Date?
    public var endReason: SessionEndReason?
    /// iOSの使用時間しきい値イベントで計測できた実際の使用分数（取れた範囲のみ）
    public var measuredMinutes: Int?

    public init(id: UUID = UUID(), targetID: UUID?, requestID: UUID?, isEmergency: Bool, startedAt: Date,
                grantedMinutes: Int, wallClockEnd: Date, endedAt: Date? = nil, endReason: SessionEndReason? = nil,
                measuredMinutes: Int? = nil) {
        self.id = id
        self.targetID = targetID
        self.requestID = requestID
        self.isEmergency = isEmergency
        self.startedAt = startedAt
        self.grantedMinutes = grantedMinutes
        self.wallClockEnd = wallClockEnd
        self.endedAt = endedAt
        self.endReason = endReason
        self.measuredMinutes = measuredMinutes
    }

    public func isActive(at now: Date) -> Bool { endedAt == nil && now < wallClockEnd }

    /// 1日の累計に数える分数（計測できた値があればそれ、なければ許可時間）
    public var countedMinutes: Int {
        if let m = measuredMinutes { return min(m, grantedMinutes) }
        return grantedMinutes
    }
}

// MARK: - 緊急解除

public enum EmergencyKind: String, Codable, CaseIterable, Sendable {
    case call, health, safety, other

    public var label: String {
        switch self {
        case .call: return "電話・連絡"
        case .health: return "健康・医療"
        case .safety: return "安全・移動"
        case .other: return "その他の緊急"
        }
    }

    public var symbol: String {
        switch self {
        case .call: return "phone"
        case .health: return "cross.case"
        case .safety: return "exclamationmark.shield"
        case .other: return "exclamationmark.triangle"
        }
    }
}

public enum EmergencyReflection: String, Codable, CaseIterable, Sendable {
    case necessary, partly, notNecessary

    public var label: String {
        switch self {
        case .necessary: return "本当に必要だった"
        case .partly: return "一部は通常の申請でよかった"
        case .notNecessary: return "緊急ではなかった"
        }
    }
}

public struct EmergencyRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var day: DayKey
    public var kind: EmergencyKind
    public var targetID: UUID?
    public var minutes: Int
    public var sessionID: UUID?
    public var reflection: EmergencyReflection?

    public init(id: UUID = UUID(), date: Date, day: DayKey, kind: EmergencyKind, targetID: UUID?, minutes: Int,
                sessionID: UUID? = nil, reflection: EmergencyReflection? = nil) {
        self.id = id
        self.date = date
        self.day = day
        self.kind = kind
        self.targetID = targetID
        self.minutes = minutes
        self.sessionID = sessionID
        self.reflection = reflection
    }
}

// MARK: - 目的のまとまり（言い回しが違っても同じ目的とみなす単位）

public struct PurposeCluster: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var targetID: UUID
    public var label: String
    public var samples: [String]

    public init(id: UUID = UUID(), targetID: UUID, label: String, samples: [String]) {
        self.id = id
        self.targetID = targetID
        self.label = label
        self.samples = samples
    }
}

// MARK: - ブロック画面での操作

public enum ShieldEventKind: String, Codable, Sendable {
    /// ブロック画面で「閉じる」を選んだ
    case closed
    /// ブロック画面から申請へ進んだ
    case requested
}

public struct ShieldEvent: Codable, Hashable, Sendable {
    public var date: Date
    public var day: DayKey
    public var kind: ShieldEventKind
    public var targetID: UUID?

    public init(date: Date, day: DayKey, kind: ShieldEventKind, targetID: UUID?) {
        self.date = date
        self.day = day
        self.kind = kind
        self.targetID = targetID
    }
}

// MARK: - 保存データ全体

public struct FocusData: Codable, Sendable {
    public var schemaVersion: Int
    public var settings: FocusSettings
    public var targets: [GuardTarget]
    /// 制限から常に外すアプリ（電話・連絡・健康・安全など）。FamilyActivitySelection を Data で保持。
    public var exemptSelectionData: Data?
    public var records: [RequestRecord]
    public var sessions: [UsageSession]
    public var emergencies: [EmergencyRecord]
    public var clusters: [PurposeCluster]
    public var shieldEvents: [ShieldEvent]
    /// ブロック画面から申請へ進んだとき、どの対象だったか（アプリ本体が開いたら読み取って消す）
    public var pendingShieldTargetID: UUID?
    public var pendingShieldAt: Date?

    public init(schemaVersion: Int = 1, settings: FocusSettings = FocusSettings(), targets: [GuardTarget] = [],
                exemptSelectionData: Data? = nil, records: [RequestRecord] = [], sessions: [UsageSession] = [],
                emergencies: [EmergencyRecord] = [], clusters: [PurposeCluster] = [], shieldEvents: [ShieldEvent] = [],
                pendingShieldTargetID: UUID? = nil, pendingShieldAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.targets = targets
        self.exemptSelectionData = exemptSelectionData
        self.records = records
        self.sessions = sessions
        self.emergencies = emergencies
        self.clusters = clusters
        self.shieldEvents = shieldEvents
        self.pendingShieldTargetID = pendingShieldTargetID
        self.pendingShieldAt = pendingShieldAt
    }

    public func target(_ id: UUID?) -> GuardTarget? {
        guard let id else { return nil }
        return targets.first { $0.id == id }
    }
}
