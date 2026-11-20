import ManagedSettings
import Foundation
import FocusGuardKit

/// ブロック画面のボタン操作。
/// - 「利用を申請する」: どの対象かを保存し、通知を出す（タップで Focus Guard の申請画面が開く）。
/// - 「今はやめておく」: 思いとどまった可能性のある操作として記録する。
final class ShieldActionExtension: ShieldActionDelegate {
    private let store = FocusStore.shared()

    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let targetID = TargetLookup.targetID(for: application, in: store.load())
        completionHandler(respond(action, targetID: targetID))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let targetID = TargetLookup.targetID(for: webDomain, in: store.load())
        completionHandler(respond(action, targetID: targetID))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let targetID = TargetLookup.targetID(for: category, in: store.load())
        completionHandler(respond(action, targetID: targetID))
    }

    private func respond(_ action: ShieldAction, targetID: UUID?) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            let name = store.update { data -> String? in
                data.recordShieldEvent(.requested, targetID: targetID)
                return data.target(targetID)?.name
            }
            LocalNotifier.postOpenRequest(targetName: name, targetID: targetID)
            return .close
        case .secondaryButtonPressed:
            store.update { $0.recordShieldEvent(.closed, targetID: targetID) }
            return .close
        @unknown default:
            return .close
        }
    }
}
