import DeviceActivity
import Foundation
import FocusGuardKit

/// 解除期間の監視。アプリ本体が起動していなくても iOS が呼び出す。
/// - 使用時間しきい値（1分ごとなど）で実際の使用分数を記録し、許可時間に達したら再制限する。
/// - 期限（intervalDidEnd）が来たら、使っていなくても再制限する。
final class FocusMonitor: DeviceActivityMonitor {
    private let store = FocusStore.shared()

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let sid = FGNames.sessionID(from: activity), let minute = FGNames.minute(from: event) else { return }
        let now = Date()
        let (ended, oneLeft, name) = store.update { data -> (Bool, Bool, String?) in
            guard let s = data.sessions.first(where: { $0.id == sid }), s.endedAt == nil else { return (false, false, nil) }
            data.recordMeasuredUsage(sessionID: sid, minutes: minute)
            let targetName = data.target(s.targetID)?.name
            if minute >= s.grantedMinutes {
                data.endSession(sid, reason: .usageLimitReached, now: now)
                return (true, false, targetName)
            }
            return (false, s.grantedMinutes >= 3 && minute == s.grantedMinutes - 1, targetName)
        }
        if ended {
            ShieldController.reconcile(store.load(), now: now)
            DeviceActivityCenter().stopMonitoring([activity])
            LocalNotifier.postSessionEnded(targetName: name)
        } else if oneLeft {
            LocalNotifier.postOneMinuteLeft(targetName: name)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let sid = FGNames.sessionID(from: activity) else { return }
        let now = Date()
        let name: String?? = store.update { data -> String?? in
            guard let s = data.sessions.first(where: { $0.id == sid }), s.endedAt == nil else { return nil }
            data.endSession(sid, reason: .windowEnded, now: now)
            return .some(data.target(s.targetID)?.name)
        }
        // 期限の判定は保存データから行う（時計のずれで残った解除も閉じる）
        _ = store.update { $0.closeExpiredSessions(now: now.addingTimeInterval(1)) }
        ShieldController.reconcile(store.load(), now: now.addingTimeInterval(1))
        if let name { LocalNotifier.postSessionEnded(targetName: name) }
    }
}
