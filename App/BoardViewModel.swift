import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class BoardViewModel: ObservableObject {
    @Published var settings = SharedStore.loadSettings()
    @Published var snapshot = SharedStore.loadSnapshot()
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var isAuthenticated = (try? KeychainStore.load()) != nil
    @Published var errorMessage: String?
    @Published var needsTOTP = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isPerformanceTesting = false
    @Published private(set) var performanceTestReport: PerformanceTestReport?

    private let client = Sub2APIClient()
    private var tempToken: String?
    private var refreshTask: Task<Bool, Never>?
    private var refreshTaskID: UUID?

    func login(email: String, password: String) async {
        guard saveSettings() else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await client.login(settings: settings, email: email, password: password)
            isAuthenticated = true
            needsTOTP = false
            await refresh()
        } catch APIError.twoFactorRequired(let token) {
            tempToken = token
            needsTOTP = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func completeTOTP(code: String) async {
        guard let tempToken else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await client.completeTOTP(settings: settings, tempToken: tempToken, code: code)
            self.tempToken = nil
            needsTOTP = false
            isAuthenticated = true
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @discardableResult
    func refresh(forceAfterCurrent: Bool = false) async -> Bool {
        if let currentTask = refreshTask, let currentTaskID = refreshTaskID {
            let result = await currentTask.value
            if refreshTaskID == currentTaskID {
                refreshTask = nil
                refreshTaskID = nil
            }
            if forceAfterCurrent {
                return await refresh()
            }
            return result
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            await self?.performRefresh() ?? false
        }
        refreshTask = task
        refreshTaskID = taskID
        let result = await task.value
        if refreshTaskID == taskID {
            refreshTask = nil
            refreshTaskID = nil
        }
        return result
    }

    @discardableResult
    func saveSettingsAndRefresh() async -> Bool {
        guard saveSettings() else { return false }
        return await refresh(forceAfterCurrent: true)
    }

    private func performRefresh() async -> Bool {
        guard settings.apiBaseURL != nil else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try SharedStore.saveSettings(settings)
            async let newSnapshot = client.fetchBoard(settings: settings)
            async let newAccounts = client.fetchAccounts(settings: settings)
            let values = try await (newSnapshot, newAccounts)
            snapshot = values.0
            accounts = values.1
            try SharedStore.saveSnapshot(values.0)
            let refreshedAt = Date()
            lastRefreshAt = refreshedAt
            SharedStore.recordWidgetRefreshSuccess(at: refreshedAt)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch APIError.unauthorized {
            isAuthenticated = false
            errorMessage = APIError.unauthorized.localizedDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadAccounts() async {
        guard isAuthenticated else { return }
        do { accounts = try await client.fetchAccounts(settings: settings) }
        catch { errorMessage = error.localizedDescription }
    }

    func runPerformanceTest() async {
        guard !isPerformanceTesting else { return }
        guard let targetAccounts = snapshot?.accounts.map(\.account), !targetAccounts.isEmpty else {
            errorMessage = "当前看板没有可测速的账号"
            return
        }

        isPerformanceTesting = true
        performanceTestReport = nil
        let startedAt = Date()
        let currentSettings = settings
        let currentClient = client
        let accountOrder = Dictionary(uniqueKeysWithValues: targetAccounts.enumerated().map { ($1.id, $0) })

        var results = await withTaskGroup(of: AccountPerformanceResult.self, returning: [AccountPerformanceResult].self) { group in
            for account in targetAccounts {
                group.addTask {
                    await currentClient.testAccount(settings: currentSettings, account: account)
                }
            }

            var values: [AccountPerformanceResult] = []
            for await result in group {
                values.append(result)
            }
            return values
        }
        results.sort { (accountOrder[$0.accountID] ?? .max) < (accountOrder[$1.accountID] ?? .max) }

        performanceTestReport = PerformanceTestReport(
            startedAt: startedAt,
            totalDurationMS: Date().timeIntervalSince(startedAt) * 1_000,
            results: results
        )
        isPerformanceTesting = false
    }

    @discardableResult
    func saveSettings() -> Bool {
        guard settings.apiBaseURL != nil else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return false
        }
        do {
            try SharedStore.saveSettings(settings)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() {
        KeychainStore.clear()
        SharedStore.clearSnapshot()
        isAuthenticated = false
        snapshot = nil
        accounts = []
        performanceTestReport = nil
        isPerformanceTesting = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}
