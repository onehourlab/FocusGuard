import Foundation

/// 申請文の正規化・意味のまとまり（概念）の抽出・類似度。
/// 端末内だけで動き、同じ入力には必ず同じ結果を返す（審査の一貫性のため）。
public enum TextNormalizer {
    /// 全角/半角・大文字小文字・カタカナ/ひらがなの違い、空白と記号を取り除く。
    public static func normalize(_ text: String) -> String {
        var t = text.precomposedStringWithCompatibilityMapping.lowercased()
        // カタカナ → ひらがな（「メッセージ」と「めっせーじ」を同じに扱う）
        t = t.applyingTransform(.hiraganaToKatakana, reverse: true) ?? t
        let scalars = t.unicodeScalars.filter { s in
            !CharacterSet.whitespacesAndNewlines.contains(s)
                && !CharacterSet.punctuationCharacters.contains(s)
                && !CharacterSet.symbols.contains(s)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// 比較用：数字・「分」・よくある語尾を取り除いた形（「5分」「10分」の違いで別物扱いしない）
    public static func comparable(_ text: String, removing names: [String] = []) -> String {
        var t = normalize(text)
        for name in names.map(normalize) where name.count >= 2 {
            t = t.replacingOccurrences(of: name, with: "")
        }
        t = t.replacingOccurrences(of: "[0-9]+分?", with: "", options: .regularExpression)
        for filler in ["するため", "したいため", "したいので", "ため", "します", "したい", "するので", "ので", "から", "です", "ます"] {
            t = t.replacingOccurrences(of: filler, with: "")
        }
        return t
    }

    static func bigrams(_ s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 2 else { return chars.isEmpty ? [] : [String(chars)] }
        var out = Set<String>()
        for i in 0..<(chars.count - 1) { out.insert(String(chars[i...i + 1])) }
        return out
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}

/// 申請文に含まれる意味のまとまり。action（何をするか）と topic（何について・誰と）に分ける。
public struct Concept: Hashable, Sendable {
    public enum Kind: Sendable { case action, topic }
    public let id: String
    public let label: String
    public let kind: Kind
    let words: [String]

    var weight: Double { kind == .action ? 2 : 1 }
}

public enum ConceptLexicon {
    public static let all: [Concept] = [
        // 何をするか
        Concept(id: "reply", label: "連絡・返信", kind: .action,
                words: ["返信", "返す", "返事", "返答", "レス", "リプ", "送信", "送る", "連絡", "既読", "電話", "通話"]),
        Concept(id: "watch", label: "視聴", kind: .action,
                words: ["視聴", "観る", "観た", "動画を見", "動画をみ", "配信を見", "再生", "見終", "聴く", "聞く"]),
        Concept(id: "browse", label: "閲覧", kind: .action,
                words: ["閲覧", "眺め", "タイムライン", "ストーリー", "フィード", "投稿を見", "投稿をみ", "見て回"]),
        Concept(id: "search", label: "調べもの", kind: .action,
                words: ["調べ", "検索", "探す", "探し", "調査"]),
        Concept(id: "check", label: "確認", kind: .action,
                words: ["確認", "チェック"]),
        Concept(id: "post", label: "投稿", kind: .action,
                words: ["投稿する", "投稿し", "アップ", "載せ", "発信", "ポスト"]),
        Concept(id: "buy", label: "購入・予約", kind: .action,
                words: ["買う", "買い", "購入", "注文", "予約", "支払", "申し込", "申込"]),
        Concept(id: "play", label: "遊び", kind: .action,
                words: ["ゲーム", "遊ぶ", "遊び", "プレイ"]),
        Concept(id: "navigate", label: "移動", kind: .action,
                words: ["地図", "道を", "乗換", "乗り換え", "経路"]),
        // 何について・誰と
        Concept(id: "friend", label: "友人", kind: .topic,
                words: ["友達", "友人", "知り合い", "クラスメイト", "先輩", "後輩", "同級生"]),
        Concept(id: "family", label: "家族", kind: .topic,
                words: ["家族", "母", "父", "親", "兄", "姉", "弟", "妹", "祖父", "祖母"]),
        Concept(id: "message", label: "メッセージ", kind: .topic,
                words: ["dm", "ダイレクトメッセージ", "メッセージ", "チャット", "トーク", "ライン"]),
        Concept(id: "video", label: "動画", kind: .topic,
                words: ["動画", "ビデオ", "配信", "番組"]),
        Concept(id: "study", label: "学習", kind: .topic,
                words: ["勉強", "学習", "授業", "講義", "課題", "復習", "予習", "試験", "テスト", "宿題", "レポート"]),
        Concept(id: "work", label: "仕事", kind: .topic,
                words: ["仕事", "業務", "会議", "打ち合わせ", "取引先", "上司", "バイト", "職場", "シフト"]),
        Concept(id: "news", label: "ニュース・情報", kind: .topic,
                words: ["ニュース", "天気", "情報", "運行"]),
        Concept(id: "relax", label: "息抜き", kind: .topic,
                words: ["息抜き", "休憩", "リラックス", "気分転換", "推し", "趣味"]),
        Concept(id: "photo", label: "写真", kind: .topic,
                words: ["写真", "画像"]),
        Concept(id: "event", label: "予定", kind: .topic,
                words: ["イベント", "予定", "待ち合わせ", "集合"])
    ]

    private static let normalizedWords: [(Concept, [String])] = all.map { c in
        (c, c.words.map(TextNormalizer.normalize))
    }

    public static func concepts(in text: String) -> Set<Concept> {
        let n = TextNormalizer.normalize(text)
        var found = Set<Concept>()
        for (c, words) in normalizedWords where words.contains(where: { n.contains($0) }) {
            found.insert(c)
        }
        return found
    }

    /// 行動そのものに区切りがある（返信・検索・購入など）か
    static let boundedActions: Set<String> = ["reply", "search", "check", "post", "buy", "navigate"]

    /// 目的のおおよその時間幅（分）。これを大きく超えると理由を質問する。
    static func typicalRange(for concepts: Set<Concept>) -> ClosedRange<Int> {
        let ids = Set(concepts.map(\.id))
        if ids.contains("study") || ids.contains("work") { return 1...120 }
        if ids.contains("watch") { return 3...90 }
        if ids.contains("play") || ids.contains("relax") { return 5...60 }
        if ids.contains("buy") || ids.contains("post") { return 2...30 }
        if ids.contains("search") { return 1...20 }
        if ids.contains("browse") { return 1...20 }
        if ids.contains("reply") || ids.contains("check") || ids.contains("navigate") { return 1...15 }
        return 1...60
    }

    public static func category(for concepts: Set<Concept>) -> PurposeCategory {
        let ids = Set(concepts.map(\.id))
        if ids.contains("study") { return .study }
        if ids.contains("work") { return .work }
        if ids.contains("reply") || ids.contains("message") { return .communication }
        if ids.contains("buy") { return .shopping }
        if ids.contains("post") { return .creation }
        if ids.contains("navigate") { return .navigation }
        if ids.contains("search") || ids.contains("news") || ids.contains("check") { return .information }
        if !ids.isDisjoint(with: ["watch", "browse", "play", "relax", "video"]) { return .entertainment }
        return .other
    }
}

/// 目的同士の類似度。言い回しが違っても、同じ行動・同じ相手なら近いと判定する。
public enum PurposeMatcher {
    public static let sameThreshold = 0.6

    public static func similarity(_ a: String, _ b: String, removing names: [String] = []) -> Double {
        let ca = ConceptLexicon.concepts(in: a)
        let cb = ConceptLexicon.concepts(in: b)
        let ta = TextNormalizer.comparable(a, removing: names)
        let tb = TextNormalizer.comparable(b, removing: names)
        let textScore = TextNormalizer.jaccard(TextNormalizer.bigrams(ta), TextNormalizer.bigrams(tb))
        if ta == tb && !ta.isEmpty { return 1 }
        guard !ca.isEmpty, !cb.isEmpty else { return textScore }

        let actionsA = ca.filter { $0.kind == .action }
        let actionsB = cb.filter { $0.kind == .action }
        // 両方に「何をするか」があり、まったく違う行動なら別の目的
        if !actionsA.isEmpty && !actionsB.isEmpty && actionsA.isDisjoint(with: actionsB) {
            return min(textScore, 0.3)
        }
        let shared = ca.intersection(cb).reduce(0) { $0 + $1.weight }
        let smaller = min(ca.reduce(0) { $0 + $1.weight }, cb.reduce(0) { $0 + $1.weight })
        let conceptScore = smaller > 0 ? shared / smaller : 0
        return max(conceptScore * 0.85 + textScore * 0.15, textScore)
    }

    /// 既存のまとまりのうち、最も近いもの（しきい値以上）を返す
    public static func bestCluster(for purpose: String, targetID: UUID, clusters: [PurposeCluster],
                                   removing names: [String] = []) -> PurposeCluster? {
        var best: (PurposeCluster, Double)?
        for c in clusters where c.targetID == targetID {
            let score = ([c.label] + c.samples).map { similarity(purpose, $0, removing: names) }.max() ?? 0
            if score >= sameThreshold, score > (best?.1 ?? 0) { best = (c, score) }
        }
        return best?.0
    }

    /// 新しいまとまりの見出し（概念があれば概念名、なければ目的の先頭）
    public static func label(for purpose: String) -> String {
        let concepts = ConceptLexicon.concepts(in: purpose)
        let topics = concepts.filter { $0.kind == .topic }.map(\.label).sorted()
        let actions = concepts.filter { $0.kind == .action }.map(\.label).sorted()
        let parts = topics + actions
        if !parts.isEmpty { return parts.joined(separator: "・") }
        let trimmed = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 16 ? String(trimmed.prefix(16)) + "…" : trimmed
    }
}

/// 文章の具体性・終了条件・あいまいさの判定（ルールベース）
public enum TextHeuristics {
    static let vagueWords = ["なんとなく", "何となく", "暇", "ひま", "特にない", "とくにない", "別に", "べつに", "適当",
                             "なんでも", "気分", "癖", "くせ", "ついつい", "なにか", "何か", "いろいろ", "色々", "ちょっと見",
                             "見たいから", "なんか"].map(TextNormalizer.normalize)

    static let fillerWords = ["するため", "したいため", "ため", "する", "したい", "使う", "使いたい", "見る", "見たい",
                              "ちょっと", "少し", "アプリ", "開く", "分", "です", "ます", "ので", "から", "を", "に", "で", "の", "が", "は"]
        .map(TextNormalizer.normalize)

    static let endCues = ["まで", "終わったら", "終わる", "終えたら", "したら", "済んだら", "済ませ", "次第", "見終", "読み終",
                          "返したら", "送ったら", "調べたら", "わかったら", "分かったら", "確認したら", "決まったら",
                          "閉じる", "やめる", "1回", "一回", "だけ返"]
        .map(TextNormalizer.normalize)

    static let countPattern = "[0-9一二三四五六七八九十]+(本|件|通|話|回|ページ|章|人|個|問|枚|つ)"

    public static func containsVagueWord(_ text: String) -> Bool {
        let n = TextNormalizer.normalize(text)
        return vagueWords.contains { n.contains($0) }
    }

    /// あいまいな語・つなぎの語・数字・アプリ名を除いた「中身」の文字数
    public static func substanceLength(_ text: String, removing names: [String] = []) -> Int {
        var t = TextNormalizer.normalize(text)
        for name in names.map(TextNormalizer.normalize) where name.count >= 2 {
            t = t.replacingOccurrences(of: name, with: "")
        }
        for w in vagueWords + fillerWords { t = t.replacingOccurrences(of: w, with: "") }
        t = t.replacingOccurrences(of: "[0-9]+", with: "", options: .regularExpression)
        return t.count
    }

    public static func hasEndCue(_ text: String) -> Bool {
        let n = TextNormalizer.normalize(text)
        if endCues.contains(where: { n.contains($0) }) { return true }
        return n.range(of: countPattern, options: .regularExpression) != nil
    }
}
