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

    private let client = Sub2APIClient()
    private var tempToken: String?
    private var isRefreshing = false

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

    func refresh() async {
        guard !isRefreshing else { return }
        guard settings.apiBaseURL != nil else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return
        }
        isRefreshing = true
        isLoading = true
        errorMessage = nil
        defer {
            isRefreshing = false
            isLoading = false
        }
        do {
            try SharedStore.saveSettings(settings)
            async let newSnapshot = client.fetchBoard(settings: settings)
            async let newAccounts = client.fetchAccounts(settings: settings)
            let values = try await (newSnapshot, newAccounts)
            snapshot = values.0
            accounts = values.1
            try SharedStore.saveSnapshot(values.0)
            lastRefreshAt = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } catch APIError.unauthorized {
            isAuthenticated = false
            errorMessage = APIError.unauthorized.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAccounts() async {
        guard isAuthenticated else { return }
        do { accounts = try await client.fetchAccounts(settings: settings) }
        catch { errorMessage = error.localizedDescription }
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
        WidgetCenter.shared.reloadAllTimelines()
    }
}
