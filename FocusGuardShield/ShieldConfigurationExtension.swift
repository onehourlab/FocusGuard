import ManagedSettings
import ManagedSettingsUI
import UIKit
import FocusGuardKit

/// 制限中のアプリを開いたときに出るブロック画面の見た目。
/// iOS の制約で文字入力はできないため、「利用を申請する」で Focus Guard 本体へ誘導する。
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(name: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(name: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(name: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(name: webDomain.domain)
    }

    private func make(name: String?) -> ShieldConfiguration {
        let data = FocusStore.shared().load()
        let today = DayKey(Date())
        let summary = Analytics.summary(for: today, data: data)
        var subtitle = "何のために・何分・なぜ今？\n使う場合は Focus Guard で申請してください。\n緊急時は Focus Guard の緊急解除がすぐに使えます。"
        if summary.requestCount > 0 || summary.abandonedCount > 0 {
            subtitle += "\n\n今日の申請 \(summary.requestCount)回・取りやめ \(summary.abandonedCount)回"
        }
        let accent = UIColor.systemIndigo
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemBackground.withAlphaComponent(0.6),
            icon: UIImage(systemName: "hourglass"),
            title: ShieldConfiguration.Label(text: "\(name ?? "このアプリ")を開く前に", color: .label),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "利用を申請する", color: .white),
            primaryButtonBackgroundColor: accent,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "今はやめておく", color: accent))
    }
}
