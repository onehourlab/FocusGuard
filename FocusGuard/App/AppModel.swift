import Foundation
import SwiftUI
import Observation
import FamilyControls
import FocusGuardKit

/// 画面から使う操作の窓口。保存は FocusStore（アプリと拡張で共有）を通し、Screen Time の制限状態は
/// 毎回保存データから決め直す（ShieldController.reconcile）。
@MainActor
@Observable
final class AppModel {
    let store: FocusStore
    private(set) var data: FocusData
    var authorizationStatus: AuthorizationStatus = .notDetermined
    var aiAvailability: OnDeviceAIReviewer.Availability = OnDeviceAIReviewer.availability
    /// 申請画面を開く要求（ブロック画面・通知・ホームのボタンから）
    var requestDraft: RequestDraftSeed?
    var showEmergency = false
    var lastError: String?

    init(store: FocusStore = .shared()) {
        self.store = store
        self.data = store.load()
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    var today: DayKey { DayKey(Date()) }

    func target(_ id: UUID?) -> GuardTarget? { data.target(id) }

    // MARK: 読み込みと制限状態の同期

    /// 起動時・前面に戻ったとき。期限切れの解除を閉じ、制限状態を保存データに合わせる。
    func refresh() {
        let now = Date()
        store.update { d in
            _ = d.closeExpiredSessions(now: now)
            d.prune(now: now)
        }
        data = store.load()
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        aiAvailability = OnDeviceAIReviewer.availability
        if authorizationStatus == .approved {
            ShieldController.reconcile(data, now: now)
            SessionMonitor.stopFinished(data, now: now)
        }
        // ブロック画面から申請へ進んでいた場合
        let pending = store.update { $0.takePendingShieldTarget(now: now) }
        if let pending {
            requestDraft = RequestDraftSeed(targetID: pending)
        }
        data = store.load()
    }

    func mutate(_ body: (inout FocusData) -> Void) {
        store.update(body)
        data = store.load()
    }

    // MARK: 権限

    func requestScreenTimeAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            lastError = "スクリーンタイムの許可を得られませんでした。設定アプリの「スクリーンタイム」を確認してください。"
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        refresh()
    }

    // MARK: 申請と審査

    func review(_ request: UsageRequest) async -> ReviewResult? {
        data = store.load()
        guard let target = data.target(request.targetID) else { return nil }
        var assessment: SemanticAssessment?
        if data.settings.useOnDeviceAI {
            let recent = data.records
                .filter { $0.request.targetID == target.id && $0.day == today && $0.id != request.id && $0.status == .approved }
                .map(\.request.purpose)
            assessment = await OnDeviceAIReviewer.assess(request, target: target, recentPurposes: recent)
        }
        data = store.load()
        guard let ctx = try? ReviewContext(request: request, data: data, now: Date(), assessment: assessment) else { return nil }
        let result = ReviewEngine.review(ctx)
        let now = Date()
        let record = store.update { $0.recordReview(request, result: result, now: now) }
        data = store.load()
        if result.verdict == .approve, let sid = record.sessionID {
            begin(sessionID: sid)
        }
        if let old = request.extendsSessionID { SessionMonitor.stop(old) }
        return result
    }

    func abandon(_ request: UsageRequest, stage: AbandonStage) {
        mutate { $0.recordAbandon(request, stage: stage) }
    }

    // MARK: 解除期間

    private func begin(sessionID: UUID) {
        guard let session = data.sessions.first(where: { $0.id == sessionID }) else { return }
        ShieldController.reconcile(data)
        do {
            try SessionMonitor.start(session, data: data)
        } catch {
            // 監視を始められない場合は解除を取り消す（制限が戻らなくなるのを防ぐ）
            mutate { $0.endSession(sessionID, reason: .endedByUser) }
            ShieldController.reconcile(data)
            lastError = "使用時間の監視を開始できなかったため、解除を取り消しました（\(error.localizedDescription)）。"
        }
    }

    func endSessionNow(_ id: UUID) {
        mutate { $0.endSession(id, reason: .endedByUser) }
        SessionMonitor.stop(id)
        ShieldController.reconcile(data)
    }

    /// 緊急解除：AI審査なし・通信なし・待ち時間なし。記録だけ残す。
    func emergencyUnlock(kind: EmergencyKind, targetID: UUID?, minutes: Int) {
        let now = Date()
        let session = store.update { $0.recordEmergency(kind: kind, targetID: targetID, minutes: minutes, now: now).1 }
        data = store.load()
        ShieldController.reconcile(data, now: now)
        // 監視を開始できなくても解除は維持する（安全優先）。期限はアプリを開いたときにも確認する。
        try? SessionMonitor.start(session, data: data)
    }

    // MARK: 設定

    func saveTarget(_ target: GuardTarget) {
        mutate { d in
            if let i = d.targets.firstIndex(where: { $0.id == target.id }) {
                d.targets[i] = target
            } else {
                d.targets.append(target)
            }
        }
        ShieldController.reconcile(data)
    }

    func deleteTarget(_ id: UUID) {
        mutate { d in
            d.targets.removeAll { $0.id == id }
        }
        ShieldController.removeAll(targetIDs: [id])
    }

    func saveExempt(_ selection: FamilyActivitySelection) {
        mutate { $0.exemptSelectionData = SelectionCodec.encode(selection) }
        ShieldController.reconcile(data)
    }

    func updateSettings(_ body: (inout FocusSettings) -> Void) {
        mutate { body(&$0.settings) }
    }

    func deleteAllHistory() {
        mutate { d in
            d.records = []
            d.emergencies = []
            d.clusters = []
            d.shieldEvents = []
            d.sessions = d.sessions.filter { $0.isActive(at: Date()) }
        }
    }
}

/// 申請画面の初期値
struct RequestDraftSeed: Identifiable, Equatable {
    let id = UUID()
    var targetID: UUID?
    var extendsSessionID: UUID?
    var purpose: String = ""
}
