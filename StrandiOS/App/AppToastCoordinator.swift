#if os(iOS)
import Combine
import SwiftUI

extension View {
    func appToastCoordinator(center: AppToastCenter,
                             model: AppModel,
                             live: LiveState,
                             health: HealthKitBridge) -> some View {
        modifier(AppToastCoordinator(center: center, model: model, live: live, health: health))
    }
}

private struct AppToastCoordinator: ViewModifier {
    @ObservedObject var center: AppToastCenter
    @ObservedObject var model: AppModel
    @ObservedObject var live: LiveState
    @ObservedObject var health: HealthKitBridge
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    @State private var sawBackfill = false
    @State private var sawHealthSync = false
    @State private var lastWhoopSummary: String?
    @State private var lastAppleSummary: String?
    @State private var lastXiaomiSummary: String?

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: unitSystemRaw) ?? .metric
    }

    func body(content: Content) -> some View {
        content
            .appIslandToast(center: center)
            .onAppear {
                lastWhoopSummary = model.whoopImportSummary
                lastAppleSummary = model.appleHealthImportSummary
                lastXiaomiSummary = model.xiaomiImportSummary
            }
            .onReceive(live.$backfilling.removeDuplicates()) { isBackfilling in
                if isBackfilling {
                    sawBackfill = true
                    showBackfill(chunks: live.syncChunksThisSession)
                } else if sawBackfill {
                    sawBackfill = false
                    center.show(AppToast(
                        key: "strap-sync",
                        symbol: "checkmark.circle.fill",
                        title: "History synced",
                        message: "Your strap history is caught up.",
                        tone: .success,
                        displayMode: .timed(3.2)
                    ))
                }
            }
            .onReceive(live.$syncChunksThisSession.removeDuplicates()) { chunks in
                guard live.backfilling else { return }
                showBackfill(chunks: chunks)
            }
            .onReceive(live.$lastSyncError.compactMap { $0 }) { error in
                center.show(AppToast(
                    key: "strap-sync",
                    symbol: "exclamationmark.triangle.fill",
                    title: "Sync paused",
                    message: error,
                    tone: .warning,
                    displayMode: .timed(5.5)
                ))
            }
            .onReceive(health.$syncing.removeDuplicates()) { syncing in
                if syncing {
                    sawHealthSync = true
                    center.show(AppToast(
                        key: "apple-health-sync",
                        symbol: "heart.text.square.fill",
                        title: "Apple Health syncing",
                        message: "Pulling the latest health samples.",
                        tone: .syncing,
                        showsProgress: true,
                        displayMode: .sticky
                    ))
                } else if sawHealthSync {
                    sawHealthSync = false
                    let failed = health.lastError != nil
                    center.show(AppToast(
                        key: "apple-health-sync",
                        symbol: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        title: failed ? "Apple Health needs attention" : "Apple Health updated",
                        message: failed ? (health.lastError ?? "The sync could not finish.") : "Fresh readings are in NOOP.",
                        tone: failed ? .warning : .success,
                        displayMode: .timed(failed ? 5.5 : 3.5)
                    ))
                }
            }
            .onReceive(health.$lastError.compactMap { $0 }) { error in
                center.show(AppToast(
                    key: "apple-health-sync",
                    symbol: "exclamationmark.triangle.fill",
                    title: "Apple Health sync failed",
                    message: error,
                    tone: .warning,
                    displayMode: .timed(5.5)
                ))
            }
            .onReceive(model.$appleHealthImportProgress.compactMap { $0 }.removeDuplicates()) { progress in
                let count: String
                if let completed = progress.completed, let total = progress.total {
                    count = " \(completed)/\(total)"
                } else {
                    count = ""
                }
                center.show(AppToast(
                    key: "apple-health-import",
                    symbol: progress.isComplete ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath",
                    title: progress.step,
                    message: (progress.detail ?? "Working on Apple Health data.") + count,
                    tone: progress.isComplete ? .success : .syncing,
                    showsProgress: !progress.isComplete,
                    displayMode: progress.isComplete ? .timed(3.8) : .sticky
                ))
            }
            .onReceive(model.$whoopImportSummary.compactMap { $0 }) { summary in
                guard lastWhoopSummary != summary else { return }
                lastWhoopSummary = summary
                showImportSummary(summary, source: .whoop)
            }
            .onReceive(model.$appleHealthImportSummary.compactMap { $0 }) { summary in
                guard lastAppleSummary != summary else { return }
                lastAppleSummary = summary
                showImportSummary(summary, source: .appleHealth)
            }
            .onReceive(model.$xiaomiImportSummary.compactMap { $0 }) { summary in
                guard lastXiaomiSummary != summary else { return }
                lastXiaomiSummary = summary
                showImportSummary(summary, source: .xiaomi)
            }
            .onReceive(NotificationCenter.default.publisher(for: ScaleIntegrationPrefs.renphoReadingSavedNotification)) { note in
                guard let reading = note.object as? RenphoScaleSource.Reading else { return }
                let weight = UnitFormatter.massFromKilograms(reading.weightKg, system: unitSystem)
                center.show(AppToast(
                    key: "renpho-scale",
                    symbol: "scalemass.fill",
                    title: "Scale reading saved",
                    message: "\(weight) is now in your timeline.",
                    tone: .success,
                    displayMode: .timed(3.6)
                ))
            }
    }

    private func showBackfill(chunks: Int) {
        let message = chunks > 0 ? "\(chunks) chunks pulled so far." : "Pulling stored strap history."
        center.show(AppToast(
            key: "strap-sync",
            symbol: "antenna.radiowaves.left.and.right",
            title: "Syncing strap history",
            message: message,
            tone: .syncing,
            showsProgress: true,
            displayMode: .sticky
        ))
    }

    private func showImportSummary(_ summary: String, source: DataSourceImportKind) {
        let failed = model.importFailed(source)
        center.show(AppToast(
            key: importKey(source),
            symbol: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            title: importTitle(source: source, failed: failed),
            message: summary,
            tone: failed ? .warning : .success,
            displayMode: .timed(failed ? 5.5 : 4.0)
        ))
    }

    private func importKey(_ source: DataSourceImportKind) -> String {
        switch source {
        case .whoop: "whoop-import"
        case .appleHealth: "apple-health-import"
        case .xiaomi: "xiaomi-import"
        }
    }

    private func importTitle(source: DataSourceImportKind, failed: Bool) -> String {
        switch (source, failed) {
        case (.whoop, false): "WHOOP import complete"
        case (.whoop, true): "WHOOP import failed"
        case (.appleHealth, false): "Apple Health import complete"
        case (.appleHealth, true): "Apple Health import failed"
        case (.xiaomi, false): "Mi Band import complete"
        case (.xiaomi, true): "Mi Band import failed"
        }
    }
}
#endif
