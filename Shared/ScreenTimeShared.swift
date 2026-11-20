import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import FocusGuardKit

// アプリ本体・監視拡張・Shield拡張で共通に使う、Screen Time API まわりの処理。

/// ManagedSettingsStore・監視名・イベント名の命名規則
enum FGNames {
    static func store(for targetID: UUID) -> ManagedSettingsStore.Name {
        ManagedSettingsStore.Name("fg.target.\(targetID.uuidString)")
    }

    static let sessionPrefix = "fg.session."
    static let eventPrefix = "fg.usage."

    static func activity(for sessionID: UUID) -> DeviceActivityName {
        DeviceActivityName(sessionPrefix + sessionID.uuidString)
    }

    static func sessionID(from activity: DeviceActivityName) -> UUID? {
        guard activity.rawValue.hasPrefix(sessionPrefix) else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(sessionPrefix.count)))
    }

    static func event(minute: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name(eventPrefix + String(minute))
    }

    static func minute(from event: DeviceActivityEvent.Name) -> Int? {
        guard event.rawValue.hasPrefix(eventPrefix) else { return nil }
        return Int(event.rawValue.dropFirst(eventPrefix.count))
    }
}

/// FamilyActivitySelection を Data として保存・復元する（中身は端末外に出ない不透明なトークン）
enum SelectionCodec {
    static func decode(_ data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    static func isEmpty(_ s: FamilyActivitySelection?) -> Bool {
        guard let s else { return true }
        return s.applicationTokens.isEmpty && s.categoryTokens.isEmpty && s.webDomainTokens.isEmpty
    }
}

/// 保存データから「今どの対象を制限すべきか」を決め、ManagedSettings に反映する。
/// アプリ本体と監視拡張のどちらから呼んでも同じ結果になる（状態ではなく保存データが正）。
enum ShieldController {
    static func reconcile(_ data: FocusData, now: Date = Date()) {
        let active = data.activeSessions(now: now)
        let globalUnlock = active.contains { $0.targetID == nil }
        let exempt = SelectionCodec.decode(data.exemptSelectionData)
        for target in data.targets {
            let unlocked = globalUnlock || active.contains { $0.targetID == target.id }
            if unlocked {
                lift(target.id)
            } else {
                apply(target, exempt: exempt)
            }
        }
    }

    static func apply(_ target: GuardTarget, exempt: FamilyActivitySelection?) {
        let store = ManagedSettingsStore(named: FGNames.store(for: target.id))
        guard let sel = SelectionCodec.decode(target.selectionData) else {
            store.clearAllSettings()
            return
        }
        let exemptApps = exempt?.applicationTokens ?? []
        let apps = sel.applicationTokens.subtracting(exemptApps)
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = sel.categoryTokens.isEmpty
            ? nil
            : .specific(sel.categoryTokens, except: exemptApps)
        store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
        store.shield.webDomainCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
    }

    static func lift(_ targetID: UUID) {
        ManagedSettingsStore(named: FGNames.store(for: targetID)).clearAllSettings()
    }

    /// 対象を削除したときなど、使わなくなった制限を消す
    static func removeAll(targetIDs: [UUID]) {
        for id in targetIDs { lift(id) }
    }
}

/// 解除期間の監視（使用時間しきい値で再制限・期限で再制限）
enum SessionMonitor {
    static func start(_ session: UsageSession, data: FocusData) throws {
        let cal = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(parts, from: session.startedAt),
            intervalEnd: cal.dateComponents(parts, from: session.wallClockEnd),
            repeats: false)

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if !session.isEmergency, let target = data.target(session.targetID),
           let sel = SelectionCodec.decode(target.selectionData), !SelectionCodec.isEmpty(sel) {
            for m in SessionPlanner.thresholds(grantedMinutes: session.grantedMinutes) {
                events[FGNames.event(minute: m)] = makeEvent(sel, minutes: m)
            }
        }
        try DeviceActivityCenter().startMonitoring(FGNames.activity(for: session.id), during: schedule, events: events)
    }

    /// 解除した時点からの使用時間だけを数える（それ以前の当日の使用は含めない）
    private static func makeEvent(_ sel: FamilyActivitySelection, minutes: Int) -> DeviceActivityEvent {
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(applications: sel.applicationTokens, categories: sel.categoryTokens,
                                       webDomains: sel.webDomainTokens, threshold: DateComponents(minute: minutes),
                                       includesPastActivity: false)
        }
        return DeviceActivityEvent(applications: sel.applicationTokens, categories: sel.categoryTokens,
                                   webDomains: sel.webDomainTokens, threshold: DateComponents(minute: minutes))
    }

    static func stop(_ sessionID: UUID) {
        DeviceActivityCenter().stopMonitoring([FGNames.activity(for: sessionID)])
    }

    /// 終わったセッションの監視を片付ける
    static func stopFinished(_ data: FocusData, now: Date = Date()) {
        let activeNames = Set(data.activeSessions(now: now).map { FGNames.activity(for: $0.id) })
        let stale = DeviceActivityCenter().activities.filter {
            $0.rawValue.hasPrefix(FGNames.sessionPrefix) && !activeNames.contains($0)
        }
        if !stale.isEmpty { DeviceActivityCenter().stopMonitoring(stale) }
    }
}

/// ブロックされたアプリのトークンから、どの対象かを探す
enum TargetLookup {
    static func targetID(for app: ApplicationToken, in data: FocusData) -> UUID? {
        data.targets.first { SelectionCodec.decode($0.selectionData)?.applicationTokens.contains(app) ?? false }?.id
    }

    static func targetID(for domain: WebDomainToken, in data: FocusData) -> UUID? {
        data.targets.first { SelectionCodec.decode($0.selectionData)?.webDomainTokens.contains(domain) ?? false }?.id
    }

    static func targetID(for category: ActivityCategoryToken, in data: FocusData) -> UUID? {
        data.targets.first { SelectionCodec.decode($0.selectionData)?.categoryTokens.contains(category) ?? false }?.id
    }
}

/// レポート拡張と本体で共有する識別子（DeviceActivityReport.Context の文字列）
enum FGReport {
    static let usageSummary = "usageSummary"
}
