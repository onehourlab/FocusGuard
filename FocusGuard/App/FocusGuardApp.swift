import SwiftUI
import UserNotifications
import FocusGuardKit

@main
struct FocusGuardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(FGColor.accent)
                .onAppear {
                    delegate.onOpenRequest = { targetID in
                        model.requestDraft = RequestDraftSeed(targetID: targetID)
                    }
                    model.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
    }
}

/// 通知タップ（ブロック画面からの申請）を受け取る
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onOpenRequest: (@MainActor (UUID?) -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard response.notification.request.content.categoryIdentifier == LocalNotifier.openRequestCategory else { return }
        let id = (info[LocalNotifier.targetIDKey] as? String).flatMap(UUID.init(uuidString:))
        // 起動直後でまだ画面が無い場合は、Shield拡張が保存した pendingShieldTargetID を refresh() が拾う
        await MainActor.run { onOpenRequest?(id) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
