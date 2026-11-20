import SwiftUI
import FocusGuardKit

/// 色・余白の定義（ライト/ダーク両対応のためシステム色を基準にする）
enum FGColor {
    static let accent = Color.indigo
    static let approve = Color.green
    static let clarify = Color.orange
    static let deny = Color.red
    static let emergency = Color.red
    static let card = Color(.secondarySystemGroupedBackground)
    static let background = Color(.systemGroupedBackground)
    static let muted = Color.secondary
}

enum FGSpacing {
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FGSpacing.m) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FGSpacing.l)
        .background(FGColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Verdict {
    var color: Color {
        switch self {
        case .approve: return FGColor.approve
        case .clarify: return FGColor.clarify
        case .deny: return FGColor.deny
        }
    }

    var symbol: String {
        switch self {
        case .approve: return "checkmark.circle.fill"
        case .clarify: return "questionmark.circle.fill"
        case .deny: return "xmark.circle.fill"
        }
    }
}

extension CheckStatus {
    var color: Color {
        switch self {
        case .pass: return FGColor.approve
        case .warn: return FGColor.clarify
        case .fail: return FGColor.deny
        }
    }

    var symbol: String {
        switch self {
        case .pass: return "checkmark.circle"
        case .warn: return "exclamationmark.circle"
        case .fail: return "xmark.circle"
        }
    }
}

extension RequestStatus {
    var label: String {
        switch self {
        case .approved: return "承認"
        case .denied: return "不承認"
        case .clarifying: return "再質問中"
        case .abandoned: return "取りやめ"
        }
    }

    var color: Color {
        switch self {
        case .approved: return FGColor.approve
        case .denied: return FGColor.deny
        case .clarifying: return FGColor.clarify
        case .abandoned: return .gray
        }
    }
}

func minutesText(_ m: Int) -> String {
    m >= 60 ? "\(m / 60)時間\(m % 60 == 0 ? "" : "\(m % 60)分")" : "\(m)分"
}

func clockText(_ minuteOfDay: Int) -> String {
    String(format: "%d:%02d", minuteOfDay / 60, minuteOfDay % 60)
}
