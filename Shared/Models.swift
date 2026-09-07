import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: Value?
}

struct APIErrorEnvelope: Decodable {
    let code: Int?
    let message: String?
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

enum LoginInput {
    static func normalizeEmail(_ value: String) -> String {
        let invisibleEdges = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "\u{200B}\u{FEFF}")
        )
        return value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: invisibleEdges)
            .lowercased()
    }

    static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !value.contains(where: { $0.isWhitespace }) else { return false }
        return true
    }
}

struct LoginResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let requires2FA: Bool?
    let tempToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case requires2FA = "requires_2fa"
        case tempToken = "temp_token"
    }
}

struct TOTPRequest: Encodable {
    let tempToken: String
    let totpCode: String
    enum CodingKeys: String, CodingKey { case tempToken = "temp_token"; case totpCode = "totp_code" }
}

struct RefreshRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

struct AuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct DashboardSnapshotResponse: Decodable {
    let generatedAt: Date
    let stats: DashboardStats?
    let trend: [TrendPoint]?
    enum CodingKeys: String, CodingKey { case generatedAt = "generated_at"; case stats, trend }
}

struct DashboardTrendResponse: Decodable {
    let trend: [TrendPoint]
}

struct DashboardStats: Codable, Equatable {
    let totalUsers: Int
    let activeUsers: Int
    let totalAccounts: Int
    let normalAccounts: Int
    let errorAccounts: Int
    let rateLimitAccounts: Int
    let totalRequests: Int
    let totalTokens: Int
    let totalActualCost: Double
    let todayRequests: Int
    let todayTokens: Int
    let todayActualCost: Double
    let rpm: Double
    let tpm: Double
    let averageDurationMS: Double
    let statsStale: Bool?
    var todayNewUsers: Int? = nil
    var hourlyActiveUsers: Int? = nil
    var totalAPIKeys: Int? = nil
    var activeAPIKeys: Int? = nil
    var overloadAccounts: Int? = nil
    var totalInputTokens: Int? = nil
    var totalOutputTokens: Int? = nil
    var totalCacheCreationTokens: Int? = nil
    var totalCacheReadTokens: Int? = nil
    var totalCost: Double? = nil
    var totalAccountCost: Double? = nil
    var todayInputTokens: Int? = nil
    var todayOutputTokens: Int? = nil
    var todayCacheCreationTokens: Int? = nil
    var todayCacheReadTokens: Int? = nil
    var todayCost: Double? = nil
    var todayAccountCost: Double? = nil
    var uptime: Double? = nil

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users", activeUsers = "active_users"
        case totalAccounts = "total_accounts", normalAccounts = "normal_accounts"
        case errorAccounts = "error_accounts", rateLimitAccounts = "ratelimit_accounts"
        case totalRequests = "total_requests", totalTokens = "total_tokens"
        case totalActualCost = "total_actual_cost", todayRequests = "today_requests"
        case todayTokens = "today_tokens", todayActualCost = "today_actual_cost"
        case rpm, tpm, averageDurationMS = "average_duration_ms", statsStale = "stats_stale"
        case todayNewUsers = "today_new_users", hourlyActiveUsers = "hourly_active_users"
        case totalAPIKeys = "total_api_keys", activeAPIKeys = "active_api_keys"
        case overloadAccounts = "overload_accounts"
        case totalInputTokens = "total_input_tokens", totalOutputTokens = "total_output_tokens"
        case totalCacheCreationTokens = "total_cache_creation_tokens", totalCacheReadTokens = "total_cache_read_tokens"
        case totalCost = "total_cost", totalAccountCost = "total_account_cost"
        case todayInputTokens = "today_input_tokens", todayOutputTokens = "today_output_tokens"
        case todayCacheCreationTokens = "today_cache_creation_tokens", todayCacheReadTokens = "today_cache_read_tokens"
        case todayCost = "today_cost", todayAccountCost = "today_account_cost", uptime
    }
}

struct TrendPoint: Codable, Equatable {
    let date: String
    let requests: Int
    let totalTokens: Int
    let actualCost: Double
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var cacheCreationTokens: Int? = nil
    var cacheReadTokens: Int? = nil
    var cost: Double? = nil
    enum CodingKeys: String, CodingKey {
        case date, requests, totalTokens = "total_tokens", actualCost = "actual_cost"
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens", cacheReadTokens = "cache_read_tokens", cost
    }
}

struct PaginatedAccounts: Decodable {
    let items: [Account]
    let total: Int
}

struct Account: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let platform: String
    let status: String
    let schedulable: Bool
    let quotaLimit: Double?
    let quotaUsed: Double?
    let quotaDailyLimit: Double?
    let quotaDailyUsed: Double?
    let quotaWeeklyLimit: Double?
    let quotaWeeklyUsed: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, status, schedulable
        case quotaLimit = "quota_limit", quotaUsed = "quota_used"
        case quotaDailyLimit = "quota_daily_limit", quotaDailyUsed = "quota_daily_used"
        case quotaWeeklyLimit = "quota_weekly_limit", quotaWeeklyUsed = "quota_weekly_used"
    }
}

struct AccountTestResponse: Decodable, Equatable, Sendable {
    let success: Bool
    let message: String
    let latencyMS: Int?
    let firstTokenMS: Int?
    let generationMS: Int?
    let outputTokens: Int?
    let tokensPerSecond: Double?
    let tokenCountEstimated: Bool?

    enum CodingKeys: String, CodingKey {
        case success, message
        case latency
        case latencyMS = "latency_ms"
        case firstTokenMS = "first_token_ms"
        case generationMS = "generation_ms"
        case outputTokens = "output_tokens"
        case tokensPerSecond = "tokens_per_second"
        case tokenCountEstimated = "token_count_estimated"
    }

    init(
        success: Bool,
        message: String,
        latencyMS: Int?,
        firstTokenMS: Int? = nil,
        generationMS: Int? = nil,
        outputTokens: Int? = nil,
        tokensPerSecond: Double? = nil,
        tokenCountEstimated: Bool? = nil
    ) {
        self.success = success
        self.message = message
        self.latencyMS = latencyMS
        self.firstTokenMS = firstTokenMS
        self.generationMS = generationMS
        self.outputTokens = outputTokens
        self.tokensPerSecond = tokensPerSecond
        self.tokenCountEstimated = tokenCountEstimated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        latencyMS = try Self.decodeLatency(from: container, forKey: .latency)
            ?? Self.decodeLatency(from: container, forKey: .latencyMS)
        firstTokenMS = try Self.decodeLatency(from: container, forKey: .firstTokenMS)
        generationMS = try Self.decodeLatency(from: container, forKey: .generationMS)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        tokensPerSecond = try container.decodeIfPresent(Double.self, forKey: .tokensPerSecond)
        tokenCountEstimated = try container.decodeIfPresent(Bool.self, forKey: .tokenCountEstimated)
    }

    private static func decodeLatency(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        return nil
    }
}

struct AccountTestStreamEvent: Decodable, Equatable, Sendable {
    let type: String
    let text: String?
    let model: String?
    let success: Bool?
    let error: String?
    let latencyMS: Int?
    let firstTokenMS: Int?
    let generationMS: Int?
    let outputTokens: Int?
    let tokensPerSecond: Double?
    let tokenCountEstimated: Bool?

    enum CodingKeys: String, CodingKey {
        case type, text, model, success, error
        case latencyMS = "latency_ms"
        case firstTokenMS = "first_token_ms"
        case generationMS = "generation_ms"
        case outputTokens = "output_tokens"
        case tokensPerSecond = "tokens_per_second"
        case tokenCountEstimated = "token_count_estimated"
    }
}

struct AccountPerformanceTestRequest: Encodable {
    let prompt: String
    let mode: String
}

struct AccountPerformanceResult: Identifiable, Equatable, Sendable {
    let accountID: Int
    let accountName: String
    let platform: String
    let success: Bool
    let message: String
    let upstreamLatencyMS: Int?
    let firstTokenMS: Int?
    let generationMS: Int?
    let outputTokens: Int?
    let tokensPerSecond: Double?
    let tokenCountEstimated: Bool?
    let requestDurationMS: Double
    let testedAt: Date

    var id: Int { accountID }

    init(
        accountID: Int,
        accountName: String,
        platform: String,
        success: Bool,
        message: String,
        upstreamLatencyMS: Int?,
        firstTokenMS: Int? = nil,
        generationMS: Int? = nil,
        outputTokens: Int? = nil,
        tokensPerSecond: Double? = nil,
        tokenCountEstimated: Bool? = nil,
        requestDurationMS: Double,
        testedAt: Date
    ) {
        self.accountID = accountID
        self.accountName = accountName
        self.platform = platform
        self.success = success
        self.message = message
        self.upstreamLatencyMS = upstreamLatencyMS
        self.firstTokenMS = firstTokenMS
        self.generationMS = generationMS
        self.outputTokens = outputTokens
        self.tokensPerSecond = tokensPerSecond
        self.tokenCountEstimated = tokenCountEstimated
        self.requestDurationMS = requestDurationMS
        self.testedAt = testedAt
    }
}

struct PerformanceTestReport: Equatable, Sendable {
    let startedAt: Date
    let totalDurationMS: Double
    let results: [AccountPerformanceResult]

    var successCount: Int { results.count(where: \.success) }

    var averageUpstreamLatencyMS: Double? {
        let values = results.filter(\.success).compactMap(\.upstreamLatencyMS)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var averageRequestDurationMS: Double? {
        let values = results.filter(\.success).map(\.requestDurationMS)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageFirstTokenMS: Double? {
        let values = results.filter(\.success).compactMap(\.firstTokenMS)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var averageTokensPerSecond: Double? {
        let values = results.filter(\.success).compactMap(\.tokensPerSecond)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var estimatedTokenRateCount: Int {
        results.count { $0.success && $0.tokensPerSecond != nil && $0.tokenCountEstimated == true }
    }

    var fastestResult: AccountPerformanceResult? {
        results
            .filter(\.success)
            .compactMap { result in result.upstreamLatencyMS.map { (result, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    var fastestRequestResult: AccountPerformanceResult? {
        results.filter(\.success).min { $0.requestDurationMS < $1.requestDurationMS }
    }

    var fastestGenerationResult: AccountPerformanceResult? {
        results
            .filter(\.success)
            .compactMap { result in result.tokensPerSecond.map { (result, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }
}

struct BatchUsageRequest: Encodable {
    let accountIDs: [Int]
    let force = false
    enum CodingKeys: String, CodingKey { case accountIDs = "account_ids"; case force }
}

struct BatchUsageResponse: Decodable {
    let usage: [String: AccountUsage]
    let errors: [String: String]
}

struct AccountUsage: Codable, Equatable {
    let source: String?
    let updatedAt: Date?
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayFable: UsageWindow?
    let thirtyDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case source, updatedAt = "updated_at", fiveHour = "five_hour", sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet", sevenDayFable = "seven_day_fable"
        case thirtyDay = "thirty_day"
    }

    init(
        source: String? = nil,
        updatedAt: Date?,
        fiveHour: UsageWindow?,
        sevenDay: UsageWindow?,
        sevenDaySonnet: UsageWindow? = nil,
        sevenDayFable: UsageWindow? = nil,
        thirtyDay: UsageWindow?
    ) {
        self.source = source
        self.updatedAt = updatedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayFable = sevenDayFable
        self.thirtyDay = thirtyDay
    }
}

struct UsageWindow: Codable, Equatable {
    let utilization: Double
    let resetsAt: Date?
    let remainingSeconds: Int?
    let windowStats: WindowStats?
    let usedRequests: Int?
    let limitRequests: Int?

    enum CodingKeys: String, CodingKey {
        case utilization, resetsAt = "resets_at", remainingSeconds = "remaining_seconds"
        case windowStats = "window_stats", usedRequests = "used_requests", limitRequests = "limit_requests"
    }

    init(
        utilization: Double,
        resetsAt: Date?,
        remainingSeconds: Int? = nil,
        windowStats: WindowStats? = nil,
        usedRequests: Int? = nil,
        limitRequests: Int? = nil
    ) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.remainingSeconds = remainingSeconds
        self.windowStats = windowStats
        self.usedRequests = usedRequests
        self.limitRequests = limitRequests
    }
}

struct BatchTodayStatsResponse: Decodable {
    let stats: [String: WindowStats]
}

struct WindowStats: Codable, Equatable {
    let requests: Int
    let tokens: Int
    let cost: Double
    let standardCost: Double?
    let userCost: Double?

    enum CodingKeys: String, CodingKey {
        case requests, tokens, cost, standardCost = "standard_cost", userCost = "user_cost"
    }

    init(requests: Int, tokens: Int, cost: Double, standardCost: Double? = nil, userCost: Double? = nil) {
        self.requests = requests
        self.tokens = tokens
        self.cost = cost
        self.standardCost = standardCost
        self.userCost = userCost
    }
}

struct AccountMetric: Codable, Identifiable, Equatable {
    let account: Account
    let usage: AccountUsage?
    let today: WindowStats?
    let error: String?
    var id: Int { account.id }

    var primaryWindow: (name: String, value: Double, reset: Date?)? {
        if let value = usage?.fiveHour { return ("5 小时", value.utilization, value.resetsAt) }
        if let value = usage?.sevenDay { return ("7 天", value.utilization, value.resetsAt) }
        if let limit = account.quotaDailyLimit, limit > 0 {
            return ("日额度", (account.quotaDailyUsed ?? 0) / limit * 100, nil)
        }
        if let limit = account.quotaLimit, limit > 0 {
            return ("总额度", (account.quotaUsed ?? 0) / limit * 100, nil)
        }
        return nil
    }

    var usageWindows: [(name: String, window: UsageWindow)] {
        var windows: [(String, UsageWindow)] = []
        if let value = usage?.fiveHour { windows.append(("5h", value)) }
        if let value = usage?.sevenDay { windows.append(("7d", value)) }
        if let value = usage?.sevenDaySonnet { windows.append(("7d S", value)) }
        if let value = usage?.sevenDayFable { windows.append(("7d F", value)) }
        if let value = usage?.thirtyDay { windows.append(("30d", value)) }
        return windows
    }
}

struct BoardSnapshot: Codable, Equatable {
    let generatedAt: Date
    let dashboard: DashboardStats
    let trend: [TrendPoint]
    let accounts: [AccountMetric]
}

enum CompactFormat {
    static func number(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }

    static func money(_ value: Double) -> String { String(format: "$%.2f", value) }

    static func duration(milliseconds: Double) -> String {
        milliseconds >= 1_000
            ? String(format: "%.2fs", milliseconds / 1_000)
            : "\(Int(milliseconds.rounded()))ms"
    }

    static func uptime(_ seconds: Double) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }

    static func resetTime(for window: UsageWindow, now: Date = Date()) -> String {
        if window.utilization <= 0 { return "现在" }
        let seconds = window.resetsAt.map { Int($0.timeIntervalSince(now)) } ?? window.remainingSeconds
        guard let seconds else { return "--" }
        if seconds <= 0 { return "待刷新" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
