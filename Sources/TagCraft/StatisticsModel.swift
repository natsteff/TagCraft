import Foundation

@MainActor extension Model {
    func restoreStatistics() {
        guard noticeAcknowledged, !statisticsRestoreStarted else { return }
        statisticsRestoreStarted = true; statisticsLoading = true; statisticsError = ""
        let directory = SettingsFiles.directory
        Task {
            do {
                let opened = try await Task.detached { try StatisticsStorage.open(directory: directory) }.value
                statisticsStore = opened.store; statisticsReady = true
                refreshStoredStatistics()
                if opened.migrated { message = "Library statistics migrated to SQLite and verified. Original JSON retained as backup." }
            } catch {
                // A migration/database failure must not discard the existing report or rewrite JSON.
                stats = SettingsFiles.load("library-statistics.json")
                statisticsReady = false; statisticsLoading = false
                statisticsError = error.localizedDescription
                message = "SQLite statistics unavailable: " + error.localizedDescription + " Existing JSON is available for viewing; statistics updates are disabled until restart/retry."
            }
        }
    }
    func refreshStoredStatistics() {
        guard let store = statisticsStore else { return }
        statisticsLoading = true
        let root = library?.path
        Task {
            do {
                let snapshot = try await Task.detached { try store.snapshot(root: root) }.value
                if library?.path == root { stats = snapshot }
            } catch { message = error.localizedDescription }
            statisticsLoading = false
        }
    }
    func exportStatisticsInventory(_ snapshot: LibrarySnapshot) { statisticsReport(snapshot, action: .inventory) }
    func exportStatisticsHealth(_ snapshot: LibrarySnapshot) { statisticsReport(snapshot, action: .healthCSV) }
    func reviewStatisticsHealth(_ snapshot: LibrarySnapshot, reason: String? = nil) { statisticsReport(snapshot, action: .reviewHealth, reason: reason) }
    private enum ReportAction: Sendable { case inventory, healthCSV, reviewHealth }
    private func statisticsReport(_ snapshot: LibrarySnapshot, action: ReportAction, reason: String? = nil) {
        guard !busy else { return }
        let store = statisticsStore
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressDone = 0; progressTotal = 0; progressText = "Loading statistics report from local cache…"
        runningTask = Task {
            do {
                let report = try await Task.detached {
                    var report = snapshot
                    if let id = snapshot.databaseScanID {
                        guard let store else { throw TagError(message: "Statistics database is unavailable.") }
                        switch action {
                        case .inventory: report.records = try store.records(scanID: id, cancellation: cancel)
                        case .healthCSV, .reviewHealth: report.findings = try store.findings(scanID: id, reason: reason, cancellation: cancel)
                        }
                    }
                    if report.databaseScanID == nil, let reason { report.findings = report.findings?.filter { $0.reason == reason } }
                    try cancel.check()
                    return report
                }.value
                busy = false
                switch action {
                case .inventory: exportCSV(CSVReport.inventory(report), name: "TagCraft Inventory")
                case .healthCSV: exportCSV(CSVReport.quality(report.findings ?? [], root: report.root, updated: report.updated), name: "TagCraft Library Health")
                case .reviewHealth:
                    qualityFindings = report.findings ?? []; qualityRoot = report.root; qualityDate = report.updated; qualityMessage = ""
                    qualityReason = reason ?? ""; qualityAvailableReasons = snapshot.health?.map(\.name) ?? Array(Set((snapshot.findings ?? []).map(\.reason))).sorted()
                    qualityScopeSnapshot = snapshot; qualityLoading = false
                    showQuality = true
                }
            } catch { busy = false; message = cancel.isCancelled ? "Report loading cancelled." : error.localizedDescription }
        }
    }
}

@MainActor extension Model {
    func reloadQualityScope() {
        guard let snapshot = qualityScopeSnapshot else { return }
        let token = UUID(); qualityReloadToken = token
        let reason = qualityReason.isEmpty ? nil : qualityReason, store = statisticsStore
        qualityLoading = true; qualityMessage = ""
        Task {
            do {
                let findings = try await Task.detached {
                    if let id = snapshot.databaseScanID, let store { return try store.findings(scanID: id, reason: reason) }
                    return (snapshot.findings ?? []).filter { reason == nil || $0.reason == reason }
                }.value
                guard qualityReloadToken == token else { return }
                qualityFindings = findings; qualityLoading = false
            } catch {
                guard qualityReloadToken == token else { return }
                qualityFindings = []; qualityLoading = false; qualityMessage = error.localizedDescription
            }
        }
    }
}
