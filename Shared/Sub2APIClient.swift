import Foundation

enum APIError: LocalizedError {
    case invalidServerURL
    case unauthorized
    case server(String)
    case http(status: Int, path: String, message: String?)
    case invalidResponse
    case twoFactorRequired(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "服务地址无效，远程服务必须使用 HTTPS（本机调试可使用 HTTP）"
        case .unauthorized: return "登录已过期，请重新登录"
        case .server(let message): return message
        case .http(let status, let path, let message):
            return "请求失败（HTTP \(status)）：/api/v1/\(path)\(message.map { "，\($0)" } ?? "")"
        case .invalidResponse: return "服务器响应格式不符合当前 Sub2API 接口"
        case .twoFactorRequired: return "需要两步验证码"
        case .keychain(let status): return "无法访问 Keychain（\(status)）"
        }
    }
}

actor Sub2APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func login(settings: BoardSettings, email: String, password: String) async throws {
        let normalizedEmail = LoginInput.normalizeEmail(email)
        guard LoginInput.isValidEmail(normalizedEmail) else {
            throw APIError.server("邮箱格式无效，请检查是否包含空格或不可见字符")
        }
        let response: LoginResponse = try await send(settings: settings, path: "auth/login", method: "POST", body: LoginRequest(email: normalizedEmail, password: password), authenticated: false)
        if response.requires2FA == true, let temp = response.tempToken { throw APIError.twoFactorRequired(temp) }
        try persist(response)
    }

    func completeTOTP(settings: BoardSettings, tempToken: String, code: String) async throws {
        let response: LoginResponse = try await send(settings: settings, path: "auth/login/2fa", method: "POST", body: TOTPRequest(tempToken: tempToken, totpCode: code), authenticated: false)
        try persist(response)
    }

    func fetchAccounts(settings: BoardSettings) async throws -> [Account] {
        var page = 1
        var accounts: [Account] = []
        repeat {
            let response: PaginatedAccounts = try await send(settings: settings, path: "admin/accounts?page=\(page)&page_size=100", method: "GET", body: Optional<String>.none)
            accounts.append(contentsOf: response.items)
            if accounts.count >= response.total || response.items.isEmpty { break }
            page += 1
        } while page <= 10
        return accounts
    }

    func fetchBoard(settings: BoardSettings) async throws -> BoardSnapshot {
        async let dashboard = fetchDashboard(settings: settings)
        async let allAccounts = fetchAccounts(settings: settings)
        let (dashboardData, accounts) = try await (dashboard, allAccounts)

        let selected = settings.selectedAccountIDs.isEmpty
            ? Array(accounts.filter { $0.status != "inactive" }.prefix(6))
            : settings.selectedAccountIDs.compactMap { id in accounts.first { $0.id == id } }
        let ids = selected.map(\.id)
        async let usageData = fetchAccountUsage(settings: settings, accountIDs: ids)
        async let todayData = fetchTodayStats(settings: settings, accountIDs: ids)
        let (usageResult, today) = await (usageData, todayData)

        return BoardSnapshot(
            generatedAt: dashboardData.generatedAt,
            dashboard: dashboardData.stats,
            trend: dashboardData.trend,
            accounts: selected.map { account in
                AccountMetric(account: account, usage: usageResult.usage[String(account.id)], today: today[String(account.id)], error: usageResult.errors[String(account.id)])
            }
        )
    }

    private func fetchDashboard(settings: BoardSettings) async throws -> (generatedAt: Date, stats: DashboardStats, trend: [TrendPoint]) {
        do {
            let snapshot: DashboardSnapshotResponse = try await send(settings: settings, path: "admin/dashboard/snapshot-v2?include_stats=true&include_trend=true&include_model_stats=false&include_group_stats=false&include_users_trend=false", method: "GET", body: Optional<String>.none)
            guard let stats = snapshot.stats else { throw APIError.invalidResponse }
            return (snapshot.generatedAt, stats, snapshot.trend ?? [])
        } catch let error as APIError where error.shouldUseCompatibilityEndpoint {
            let stats: DashboardStats = try await send(settings: settings, path: "admin/dashboard/stats", method: "GET", body: Optional<String>.none)
            let trend: DashboardTrendResponse? = try? await send(settings: settings, path: "admin/dashboard/trend", method: "GET", body: Optional<String>.none)
            return (Date(), stats, trend?.trend ?? [])
        }
    }

    private func fetchAccountUsage(settings: BoardSettings, accountIDs: [Int]) async -> (usage: [String: AccountUsage], errors: [String: String]) {
        guard !accountIDs.isEmpty else { return ([:], [:]) }
        do {
            let response: BatchUsageResponse = try await send(settings: settings, path: "admin/accounts/usage/batch", method: "POST", body: BatchUsageRequest(accountIDs: accountIDs))
            return (response.usage, response.errors)
        } catch let error as APIError where error.shouldUseCompatibilityEndpoint {
            var usage: [String: AccountUsage] = [:]
            var errors: [String: String] = [:]
            for id in accountIDs {
                do {
                    let value = try await fetchCompatibleAccountUsage(settings: settings, accountID: id)
                    usage[String(id)] = value
                } catch {
                    errors[String(id)] = error.localizedDescription
                }
            }
            return (usage, errors)
        } catch {
            return ([:], ["request": error.localizedDescription])
        }
    }

    private func fetchCompatibleAccountUsage(settings: BoardSettings, accountID: Int) async throws -> AccountUsage {
        do {
            return try await send(
                settings: settings,
                path: "admin/accounts/\(accountID)/usage?source=passive",
                method: "GET",
                body: Optional<String>.none
            )
        } catch let error as APIError where error.shouldRetryActiveUsage {
            return try await send(
                settings: settings,
                path: "admin/accounts/\(accountID)/usage",
                method: "GET",
                body: Optional<String>.none
            )
        }
    }

    private func fetchTodayStats(settings: BoardSettings, accountIDs: [Int]) async -> [String: WindowStats] {
        guard !accountIDs.isEmpty else { return [:] }
        do {
            let response: BatchTodayStatsResponse = try await send(settings: settings, path: "admin/accounts/today-stats/batch", method: "POST", body: BatchUsageRequest(accountIDs: accountIDs))
            return response.stats
        } catch let error as APIError where error.shouldUseCompatibilityEndpoint {
            var result: [String: WindowStats] = [:]
            for id in accountIDs {
                if let value: WindowStats = try? await send(settings: settings, path: "admin/accounts/\(id)/today-stats", method: "GET", body: Optional<String>.none) {
                    result[String(id)] = value
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    private func persist(_ response: LoginResponse) throws {
        guard let access = response.accessToken,
              let refresh = response.refreshToken else { throw APIError.invalidResponse }
        try KeychainStore.save(AuthTokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))))
    }

    private func validAccessToken(settings: BoardSettings) async throws -> String {
        guard let tokens = try KeychainStore.load() else { throw APIError.unauthorized }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        let response: LoginResponse = try await send(settings: settings, path: "auth/refresh", method: "POST", body: RefreshRequest(refreshToken: tokens.refreshToken), authenticated: false)
        try persist(response)
        guard let access = response.accessToken else { throw APIError.invalidResponse }
        return access
    }

    private func send<Response: Decodable, Body: Encodable>(settings: BoardSettings, path: String, method: String, body: Body?, authenticated: Bool = true) async throws -> Response {
        guard let baseURL = settings.apiBaseURL, let url = URL(string: path, relativeTo: baseURL.appendingPathComponent(""))?.absoluteURL else { throw APIError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Locale.preferredLanguages.first ?? "zh-CN", forHTTPHeaderField: "Accept-Language")
        request.setValue("1", forHTTPHeaderField: "X-Admin-UI-Request")
        if authenticated { request.setValue("Bearer \(try await validAccessToken(settings: settings))", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder.sub2api.encode(body) }

        let (data, rawResponse) = try await session.data(for: request)
        guard let http = rawResponse as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder.sub2api.decode(APIErrorEnvelope.self, from: data)
            throw APIError.http(status: http.statusCode, path: path, message: envelope?.message)
        }
        let envelope = try JSONDecoder.sub2api.decode(APIEnvelope<Response>.self, from: data)
        guard envelope.code == 0, let value = envelope.data else { throw APIError.server(envelope.message ?? "请求失败") }
        return value
    }
}

private extension APIError {
    var isNotFound: Bool {
        if case .http(let status, _, _) = self { return status == 404 }
        return false
    }

    var shouldRetryActiveUsage: Bool {
        if case .http(let status, _, _) = self {
            return status == 400 || status == 404 || status == 500
        }
        return false
    }

    var shouldUseCompatibilityEndpoint: Bool {
        if case .http(let status, _, _) = self {
            return status == 400 || status == 404 || status == 500
        }
        return false
    }
}
