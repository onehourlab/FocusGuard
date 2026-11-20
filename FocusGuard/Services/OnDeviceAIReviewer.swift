import Foundation
import FocusGuardKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// オンデバイスAI（Apple Foundation Models）による文章の読み取り。
/// - 外部APIは使わない（料金・通信なし）。対応端末でない場合はルール判定だけで審査する。
/// - AIは申請文の「意味の読み取り」だけを行い、承認・不承認は ReviewEngine の決まった規則で決める。
enum OnDeviceAIReviewer {
    enum Availability: Equatable {
        case available
        case unavailable(String)

        var message: String {
            switch self {
            case .available: return "オンデバイスAIを使って審査します（端末内で処理・通信なし）。"
            case .unavailable(let reason): return reason + " その間はルール判定だけで審査します。"
            }
        }
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("この端末はApple Intelligenceに対応していません。")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("設定でApple Intelligenceをオンにすると使えます。")
            case .unavailable(.modelNotReady):
                return .unavailable("AIモデルを準備中です。")
            case .unavailable:
                return .unavailable("オンデバイスAIを利用できません。")
            }
        }
        #endif
        return .unavailable("オンデバイスAIはiOS 26以降のApple Intelligence対応端末で使えます。")
    }

    /// 失敗・非対応・時間切れのときは nil（ルール判定だけで審査）
    static func assess(_ request: UsageRequest, target: GuardTarget, recentPurposes: [String]) async -> SemanticAssessment? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return await withTaskGroup(of: SemanticAssessment?.self) { group in
                group.addTask { await runModel(request, target: target, recentPurposes: recentPurposes) }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func runModel(_ request: UsageRequest, target: GuardTarget, recentPurposes: [String]) async -> SemanticAssessment? {
        let instructions = """
        あなたはスマートフォンの利用申請を読み取る審査補助です。申請者本人が書いた文章から、次の点を判定します。
        - 目的の具体性：誰に・何を・どうするかが分かるか。
        - 終了条件：何をしたら終わりにするかが書かれているか。返信・検索・購入のように行動自体に区切りがあれば「ある」とする。
        - 時間：この目的に妥当な最大の分数。
        - 本人ルール：本人が書いたルールに明らかに反する場合だけ、そのルールの文をそのまま挙げる。推測で挙げない。
        娯楽や息抜きであることだけを理由に不足と判定してはいけません。人の本当の意図は分からないので、文章に書かれていることだけで判断します。
        質問は、不足している点を1つだけ、やさしい日本語で短く聞いてください。
        """
        let rules = target.personalRules.isEmpty ? "（なし）" : target.personalRules.map { "・" + $0 }.joined(separator: "\n")
        let answers = request.clarifications.isEmpty ? "（なし）"
            : request.clarifications.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n")
        let recent = recentPurposes.isEmpty ? "（なし）" : recentPurposes.prefix(5).map { "・" + $0 }.joined(separator: "\n")
        let prompt = """
        対象アプリ: \(target.name)
        使用目的: \(request.purpose)
        今使う必要がある理由: \(request.reason)
        申告した時間: \(request.minutes)分
        追加の説明:
        \(answers)
        本人ルール:
        \(rules)
        本日の同じアプリでの過去の目的:
        \(recent)
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: AIJudgement.self,
                                                     options: GenerationOptions(sampling: .greedy))
            let j = response.content
            let q = j.question.trimmingCharacters(in: .whitespacesAndNewlines)
            return SemanticAssessment(
                specificity: max(0, min(2, j.specificity)),
                hasEndCondition: j.hasEndCondition,
                reasonableMaxMinutes: max(1, min(180, j.reasonableMaxMinutes)),
                category: PurposeCategory(rawValue: j.category),
                conflictingRules: j.conflictingRules,
                question: q.isEmpty ? nil : q)
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIJudgement {
    @Guide(description: "目的の具体性。0=何をするのか分からない、1=やや不足、2=誰に・何を・どうするかが分かる", .range(0...2))
    var specificity: Int

    @Guide(description: "何をしたら終わりにするかが書かれている、または行動自体に自然な区切りがあるなら true")
    var hasEndCondition: Bool

    @Guide(description: "この目的に妥当と考えられる最大の分数", .range(1...180))
    var reasonableMaxMinutes: Int

    @Guide(description: "目的の分類", .anyOf(["communication", "information", "study", "work", "shopping",
                                          "creation", "navigation", "entertainment", "other"]))
    var category: String

    @Guide(description: "本人ルールのうち、この申請が明らかに反しているもの。ルールの文をそのまま書く。無ければ空の配列")
    var conflictingRules: [String]

    @Guide(description: "具体性か終了条件が不足しているときに本人へ聞く短い日本語の質問。不足が無ければ空文字")
    var question: String
}
#endif
