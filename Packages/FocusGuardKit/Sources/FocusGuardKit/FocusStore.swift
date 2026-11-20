import Foundation

/// App Group 内の JSON ファイルに保存する。アプリ本体と拡張が同時に書いても壊れないよう、
/// NSFileCoordinator で読み書きをまとめて排他する。
public final class FocusStore: @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Info.plist の FGAppGroupID から App Group のファイルを使う。取れない場合は（テストなど）一時フォルダ。
    public static func shared(bundle: Bundle = .main) -> FocusStore {
        let groupID = bundle.object(forInfoDictionaryKey: "FGAppGroupID") as? String
        let base = groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.temporaryDirectory
        return FocusStore(fileURL: base.appendingPathComponent("focusguard.json"))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() -> FocusData {
        var result = FocusData()
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
            result = Self.read(url)
        }
        return result
    }

    /// 読み込み → 変更 → 保存 を1回の排他の中で行う
    @discardableResult
    public func update<T>(_ body: (inout FocusData) -> T) -> T {
        var output: T?
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordError) { url in
            var data = Self.read(url)
            output = body(&data)
            Self.write(data, to: url)
        }
        if let output { return output }
        // 排他が取れなかった場合も処理は行う（データを失わないことを優先）
        var data = Self.read(fileURL)
        let r = body(&data)
        Self.write(data, to: fileURL)
        return r
    }

    private static func read(_ url: URL) -> FocusData {
        guard let raw = try? Data(contentsOf: url) else { return FocusData() }
        if let decoded = try? decoder.decode(FocusData.self, from: raw) { return decoded }
        // 読めないファイルは消さずに退避する
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("focusguard-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
        return FocusData()
    }

    private static func write(_ data: FocusData, to url: URL) {
        guard let raw = try? encoder.encode(data) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        // 監視拡張はロック中にも動くため「初回ロック解除後は読み書き可」の保護にする
        try? raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? raw.write(to: url, options: [.atomic])
        #endif
    }
}
