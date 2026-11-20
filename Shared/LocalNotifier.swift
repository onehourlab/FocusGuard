import Foundation
import UserNotifications

/// 端末内の通知（通信不要）。ブロック画面からアプリ本体へ移るときと、時間切れの知らせに使う。
enum LocalNotifier {
    static let openRequestCategory = "fg.openRequest"
    static let targetIDKey = "targetID"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// ブロック画面で「利用を申請する」を押したあとに出す。タップで申請画面が開く。
    static func postOpenRequest(targetName: String?, targetID: UUID?) {
        let content = UNMutableNotificationContent()
        content.title = "Focus Guard"
        content.body = targetName.map { "タップして「\($0)」の利用申請を始める" } ?? "タップして利用申請を始める"
        content.categoryIdentifier = openRequestCategory
        if let targetID { content.userInfo = [targetIDKey: targetID.uuidString] }
        content.interruptionLevel = .active
        let req = UNNotificationRequest(identifier: "fg.openRequest", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    static func postSessionEnded(targetName: String?) {
        post(id: "fg.sessionEnded", body: "\(targetName ?? "アプリ")の許可時間が終わりました。再び制限しています。")
    }

    static func postOneMinuteLeft(targetName: String?) {
        post(id: "fg.oneMinute", body: "\(targetName ?? "アプリ")の許可時間は残り約1分です。")
    }

    private static func post(id: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Focus Guard"
        content.body = body
        let req = UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }
}
