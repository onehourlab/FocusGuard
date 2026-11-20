import SwiftUI
import FocusGuardKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.data.settings.hasCompletedOnboarding {
                OnboardingView()
            } else {
                TabView {
                    DashboardView()
                        .tabItem { Label("今日", systemImage: "house") }
                    WeeklyReportView()
                        .tabItem { Label("レポート", systemImage: "chart.bar") }
                    HistoryView()
                        .tabItem { Label("履歴", systemImage: "list.bullet.rectangle") }
                    SettingsView()
                        .tabItem { Label("設定", systemImage: "gearshape") }
                }
            }
        }
        .sheet(item: $model.requestDraft) { seed in
            RequestFlowView(seed: seed)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.showEmergency) {
            EmergencyView()
        }
        .alert("お知らせ", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
