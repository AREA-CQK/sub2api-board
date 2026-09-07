import XCTest
@testable import Sub2APIBoard

final class ModelDecodingTests: XCTestCase {
    func testRemoteServerRequiresHTTPS() {
        XCTAssertNil(BoardSettings(serverURL: "http://example.com").apiBaseURL)
        XCTAssertEqual(
            BoardSettings(serverURL: "https://example.com/").apiBaseURL?.absoluteString,
            "https://example.com/api/v1"
        )
    }

    func testLocalDevelopmentAllowsHTTP() {
        XCTAssertEqual(
            BoardSettings(serverURL: "http://127.0.0.1:8080").apiBaseURL?.absoluteString,
            "http://127.0.0.1:8080/api/v1"
        )
        XCTAssertNil(BoardSettings(serverURL: "https://user:password@example.com").apiBaseURL)
        XCTAssertNil(BoardSettings(serverURL: "https://example.com?redirect=evil").apiBaseURL)
    }

    func testWidgetRefreshOptionsAndFallback() {
        XCTAssertEqual(BoardSettings.refreshIntervalSecondOptions, [15, 30, 45, 60, 300, 600, 900, 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300, 3600])
        XCTAssertEqual(BoardSettings(refreshIntervalSeconds: 15).effectiveRefreshIntervalSeconds, 15)
        XCTAssertEqual(BoardSettings(refreshIntervalSeconds: 180).effectiveRefreshIntervalSeconds, 900)
    }

    func testLegacyRefreshMinutesMigrateToSeconds() throws {
        let legacy = #"{"serverURL":"https://example.com","selectedAccountIDs":[1,2],"refreshMinutes":5}"#.data(using: .utf8)!
        let settings = try JSONDecoder.sub2api.decode(BoardSettings.self, from: legacy)
        XCTAssertEqual(settings.refreshIntervalSeconds, 300)

        let encoded = try JSONEncoder.sub2api.encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["refreshIntervalSeconds"] as? Int, 300)
        XCTAssertNil(object["refreshMinutes"])
    }

    func testDashboardSnapshotDecodesCurrentBackendContract() throws {
        let json = #"""
        {"code":0,"message":"success","data":{"generated_at":"2026-08-19T01:00:00Z","stats":{"total_users":10,"today_new_users":2,"active_users":4,"hourly_active_users":3,"total_api_keys":7,"active_api_keys":6,"total_accounts":5,"normal_accounts":4,"error_accounts":1,"ratelimit_accounts":0,"overload_accounts":0,"total_requests":100,"total_input_tokens":900,"total_output_tokens":500,"total_cache_creation_tokens":100,"total_cache_read_tokens":500,"total_tokens":2000,"total_cost":1.50,"total_actual_cost":1.25,"total_account_cost":0.80,"today_requests":8,"today_input_tokens":70,"today_output_tokens":40,"today_cache_creation_tokens":10,"today_cache_read_tokens":40,"today_tokens":160,"today_cost":0.15,"today_actual_cost":0.12,"today_account_cost":0.08,"rpm":2,"tpm":30,"average_duration_ms":850,"uptime":90061,"stats_stale":false},"trend":[{"date":"2026-08-19","requests":8,"input_tokens":70,"output_tokens":40,"cache_creation_tokens":10,"cache_read_tokens":40,"total_tokens":160,"cost":0.15,"actual_cost":0.12}]}}
        """#.data(using: .utf8)!
        let envelope = try JSONDecoder.sub2api.decode(APIEnvelope<DashboardSnapshotResponse>.self, from: json)
        XCTAssertEqual(envelope.data?.stats?.todayRequests, 8)
        XCTAssertEqual(envelope.data?.stats?.errorAccounts, 1)
        XCTAssertEqual(envelope.data?.stats?.totalAPIKeys, 7)
        XCTAssertEqual(envelope.data?.stats?.todayAccountCost, 0.08)
        XCTAssertEqual(envelope.data?.trend?.first?.inputTokens, 70)
    }

    func testAccountPrimaryWindowPrefersFiveHourUsage() {
        let account = Account(id: 7, name: "A", platform: "anthropic", status: "active", schedulable: true, quotaLimit: 100, quotaUsed: 80, quotaDailyLimit: nil, quotaDailyUsed: nil, quotaWeeklyLimit: nil, quotaWeeklyUsed: nil)
        let usage = AccountUsage(updatedAt: nil, fiveHour: UsageWindow(utilization: 32, resetsAt: nil), sevenDay: UsageWindow(utilization: 70, resetsAt: nil), thirtyDay: nil)
        let metric = AccountMetric(account: account, usage: usage, today: nil, error: nil)
        XCTAssertEqual(metric.primaryWindow?.name, "5 小时")
        XCTAssertEqual(metric.primaryWindow?.value, 32)
    }

    func testOpenAIAccountDecodesCachedResetCredits() throws {
        let json = #"""
        {"id":7,"name":"Codex","platform":"openai","type":"oauth","status":"active","schedulable":true,"quota_limit":null,"quota_used":null,"quota_daily_limit":null,"quota_daily_used":null,"quota_weekly_limit":null,"quota_weekly_used":null,"extra":{"codex_reset_credit_snapshot":{"available_count":2,"credits":[{"expires_at":"2026-09-21T07:41:00Z"},{"expires_at":"2026-10-01T07:41:00Z"}]}}}
        """#.data(using: .utf8)!
        let account = try JSONDecoder.sub2api.decode(Account.self, from: json)

        XCTAssertEqual(account.accountType, "oauth")
        XCTAssertTrue(account.supportsResetCreditQuery)
        let credits = try XCTUnwrap(account.extra?.codexResetCreditSnapshot)
        XCTAssertEqual(credits.availableCount, 2)
        XCTAssertEqual(credits.credits.count, 2)
    }

    func testCachedResetCreditsDropExpiredEntriesAndClampCount() throws {
        let json = #"{"available_count":2,"credits":[{"expires_at":"2026-08-01T00:00:00Z"},{"expires_at":"2026-10-01T00:00:00Z"}]}"#.data(using: .utf8)!
        let credits = try JSONDecoder.sub2api.decode(OpenAIResetCredits.self, from: json)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-07T00:00:00Z"))
        let normalized = try XCTUnwrap(credits.normalizedForCache(now: now))

        XCTAssertEqual(normalized.availableCount, 1)
        XCTAssertEqual(normalized.credits.count, 1)
    }

    func testOpenAIQuotaRefreshDecodesResetCreditContract() throws {
        let json = #"{"rate_limit_reset_credits":{"available_count":2,"credits":[{"expires_at":"2026-09-21T07:41:00Z"}]},"cache_persisted":true}"#.data(using: .utf8)!
        let response = try JSONDecoder.sub2api.decode(OpenAIQuotaRefreshResponse.self, from: json)

        XCTAssertEqual(response.rateLimitResetCredits?.availableCount, 2)
        XCTAssertEqual(response.rateLimitResetCredits?.credits.count, 1)
        XCTAssertEqual(response.cachePersisted, true)
    }

    func testBoardRefreshPreservesQueriedResetCredits() throws {
        let account = Account(
            id: 7,
            name: "Codex",
            platform: "openai",
            status: "active",
            schedulable: true,
            quotaLimit: nil,
            quotaUsed: nil,
            quotaDailyLimit: nil,
            quotaDailyUsed: nil,
            quotaWeeklyLimit: nil,
            quotaWeeklyUsed: nil,
            accountType: "oauth"
        )
        let dashboard = DashboardStats(
            totalUsers: 0,
            activeUsers: 0,
            totalAccounts: 1,
            normalAccounts: 1,
            errorAccounts: 0,
            rateLimitAccounts: 0,
            totalRequests: 0,
            totalTokens: 0,
            totalActualCost: 0,
            todayRequests: 0,
            todayTokens: 0,
            todayActualCost: 0,
            rpm: 0,
            tpm: 0,
            averageDurationMS: 0,
            statsStale: false
        )
        let expiry = try XCTUnwrap(ISO8601DateFormatter().date(from: "2099-10-01T00:00:00Z"))
        let cached = BoardSnapshot(
            generatedAt: Date(),
            dashboard: dashboard,
            trend: [],
            accounts: [
                AccountMetric(
                    account: account,
                    usage: nil,
                    today: nil,
                    error: nil,
                    resetCredits: OpenAIResetCredits(
                        availableCount: 1,
                        credits: [OpenAIResetCredit(expiresAt: expiry)]
                    )
                )
            ]
        )
        let refreshed = BoardSnapshot(
            generatedAt: Date(),
            dashboard: dashboard,
            trend: [],
            accounts: [AccountMetric(account: account, usage: nil, today: nil, error: nil)]
        )

        let merged = refreshed.preservingResetCredits(from: cached)

        XCTAssertEqual(merged.accounts.first?.resetCredits?.availableCount, 1)
        XCTAssertEqual(merged.accounts.first?.resetCredits?.earliestExpiration, expiry)
    }

    func testAccountTestResponseDecodesPerformanceContract() throws {
        let json = #"{"success":true,"message":"测试成功","latency":842,"first_token_ms":842,"generation_ms":3600,"output_tokens":128,"tokens_per_second":35.56,"token_count_estimated":false,"details":{"model":"claude-sonnet-4"}}"#.data(using: .utf8)!
        let response = try JSONDecoder.sub2api.decode(AccountTestResponse.self, from: json)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "测试成功")
        XCTAssertEqual(response.latencyMS, 842)
        XCTAssertEqual(response.firstTokenMS, 842)
        XCTAssertEqual(response.generationMS, 3600)
        XCTAssertEqual(response.outputTokens, 128)
        XCTAssertEqual(try XCTUnwrap(response.tokensPerSecond), 35.56, accuracy: 0.001)
        XCTAssertEqual(response.tokenCountEstimated, false)
    }

    func testAccountTestResponseDecodesLegacyLatencyMSContract() throws {
        let json = #"{"success":true,"message":"ok","latency_ms":842.4}"#.data(using: .utf8)!
        let response = try JSONDecoder.sub2api.decode(AccountTestResponse.self, from: json)

        XCTAssertEqual(response.latencyMS, 842)
    }

    func testAccountTestParserDecodesEventStreamCompletion() throws {
        let stream = #"""
        event: message
        data: {"type":"test_start","text":"开始测试"}

        data: {"type":"response_received","text":"已收到响应"}

        data: {"type":"test_complete","text":"测试成功！模型: gpt-5","model":"gpt-5","success":true}

        """#.data(using: .utf8)!
        let response = try AccountTestResponseParser.parse(data: stream, contentType: "text/event-stream; charset=utf-8")

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "测试成功！模型: gpt-5")
        XCTAssertNil(response.latencyMS)
        XCTAssertNil(response.tokensPerSecond)
    }

    func testAccountTestParserDecodesEventStreamPerformanceMetrics() throws {
        let stream = #"""
        data: {"type":"content","text":"Hello"}

        data: {"type":"test_complete","success":true,"latency_ms":820,"first_token_ms":820,"generation_ms":3600,"output_tokens":128,"tokens_per_second":35.56,"token_count_estimated":true}

        """#.data(using: .utf8)!
        let response = try AccountTestResponseParser.parse(data: stream, contentType: "text/event-stream")

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.latencyMS, 820)
        XCTAssertEqual(response.firstTokenMS, 820)
        XCTAssertEqual(response.generationMS, 3600)
        XCTAssertEqual(response.outputTokens, 128)
        XCTAssertEqual(try XCTUnwrap(response.tokensPerSecond), 35.56, accuracy: 0.001)
        XCTAssertEqual(response.tokenCountEstimated, true)
    }

    func testAccountTestParserDecodesEventStreamError() throws {
        let stream = #"""
        data: {"type":"error","error":"上游认证失败"}

        """#.data(using: .utf8)!
        let response = try AccountTestResponseParser.parse(data: stream, contentType: "text/event-stream")

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.message, "上游认证失败")
    }

    func testAccountTestParserDecodesLegacyEnvelope() throws {
        let json = #"{"code":0,"message":"success","data":{"success":true,"message":"ok","latency_ms":520}}"#.data(using: .utf8)!
        let response = try AccountTestResponseParser.parse(data: json, contentType: "application/json")

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.latencyMS, 520)
    }

    func testAccountTestParserReportsMissingEventStreamCompletion() {
        let stream = #"""
        data: {"type":"request_sent","text":"请求已发送"}

        """#.data(using: .utf8)!

        XCTAssertThrowsError(try AccountTestResponseParser.parse(data: stream, contentType: "text/event-stream")) { error in
            XCTAssertEqual(error.localizedDescription, "测速响应未包含完成状态")
        }
    }

    func testAccountTestStreamAccumulatorMeasuresLegacyBackendStream() throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        var accumulator = AccountTestStreamAccumulator(startedAt: startedAt)
        accumulator.consume(
            line: #"data: {"type":"content","text":"abcdefgh"}"#,
            receivedAt: startedAt.addingTimeInterval(1)
        )
        accumulator.consume(
            line: #"data: {"type":"test_complete","success":true}"#,
            receivedAt: startedAt.addingTimeInterval(3)
        )

        let response = try accumulator.finish()
        XCTAssertEqual(response.firstTokenMS, 1_000)
        XCTAssertEqual(response.generationMS, 2_000)
        XCTAssertEqual(response.outputTokens, 2)
        XCTAssertEqual(try XCTUnwrap(response.tokensPerSecond), 1, accuracy: 0.001)
        XCTAssertEqual(response.tokenCountEstimated, true)
    }

    func testAccountTestStreamAccumulatorPrefersServerMetrics() throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        var accumulator = AccountTestStreamAccumulator(startedAt: startedAt)
        accumulator.consume(
            line: #"data: {"type":"content","text":"abcdefgh"}"#,
            receivedAt: startedAt.addingTimeInterval(1)
        )
        accumulator.consume(
            line: #"data: {"type":"test_complete","success":true,"first_token_ms":750,"generation_ms":4000,"output_tokens":120,"tokens_per_second":30,"token_count_estimated":false}"#,
            receivedAt: startedAt.addingTimeInterval(3)
        )

        let response = try accumulator.finish()
        XCTAssertEqual(response.firstTokenMS, 750)
        XCTAssertEqual(response.generationMS, 4_000)
        XCTAssertEqual(response.outputTokens, 120)
        XCTAssertEqual(response.tokensPerSecond, 30)
        XCTAssertEqual(response.tokenCountEstimated, false)
    }

    func testPerformanceReportCalculatesSuccessfulLatencyOnly() {
        let successful = AccountPerformanceResult(accountID: 1, accountName: "A", platform: "anthropic", success: true, message: "ok", upstreamLatencyMS: 800, firstTokenMS: 780, generationMS: 2_000, outputTokens: 80, tokensPerSecond: 40, tokenCountEstimated: false, requestDurationMS: 900, testedAt: Date())
        let failed = AccountPerformanceResult(accountID: 2, accountName: "B", platform: "openai", success: false, message: "failed", upstreamLatencyMS: nil, requestDurationMS: 400, testedAt: Date())
        let report = PerformanceTestReport(startedAt: Date(), totalDurationMS: 900, results: [successful, failed])

        XCTAssertEqual(report.successCount, 1)
        XCTAssertEqual(report.averageUpstreamLatencyMS, 800)
        XCTAssertEqual(report.averageRequestDurationMS, 900)
        XCTAssertEqual(report.averageFirstTokenMS, 780)
        XCTAssertEqual(report.averageTokensPerSecond, 40)
        XCTAssertEqual(report.estimatedTokenRateCount, 0)
        XCTAssertEqual(report.fastestResult?.accountID, 1)
        XCTAssertEqual(report.fastestRequestResult?.accountID, 1)
        XCTAssertEqual(report.fastestGenerationResult?.accountID, 1)
    }

    func testServerURLAppendsAPIVersion() {
        XCTAssertEqual(BoardSettings(serverURL: "https://example.com/", selectedAccountIDs: [], refreshIntervalSeconds: 900).apiBaseURL?.absoluteString, "https://example.com/api/v1")
        XCTAssertEqual(BoardSettings(serverURL: "https://example.com/api/v1", selectedAccountIDs: [], refreshIntervalSeconds: 900).apiBaseURL?.absoluteString, "https://example.com/api/v1")
    }

    func testUsageDateAcceptsFractionalSeconds() throws {
        let json = #"{"updated_at":"2026-08-19T01:00:00.123456789Z","five_hour":null,"seven_day":null,"thirty_day":null}"#.data(using: .utf8)!
        let usage = try JSONDecoder.sub2api.decode(AccountUsage.self, from: json)
        XCTAssertNotNil(usage.updatedAt)
    }

    func testUsageWindowDecodesWebMetrics() throws {
        let json = #"""
        {"source":"passive","updated_at":"2026-08-19T01:00:00Z","five_hour":{"utilization":42,"resets_at":"2026-08-19T03:00:00Z","remaining_seconds":7200,"used_requests":27,"limit_requests":100,"window_stats":{"requests":27,"tokens":797200,"cost":0.96,"standard_cost":0.80,"user_cost":0.96}},"seven_day":null,"seven_day_sonnet":null,"seven_day_fable":null,"thirty_day":null}
        """#.data(using: .utf8)!

        let usage = try JSONDecoder.sub2api.decode(AccountUsage.self, from: json)
        XCTAssertEqual(usage.source, "passive")
        XCTAssertEqual(usage.fiveHour?.remainingSeconds, 7200)
        XCTAssertEqual(usage.fiveHour?.usedRequests, 27)
        XCTAssertEqual(usage.fiveHour?.limitRequests, 100)
        XCTAssertEqual(usage.fiveHour?.windowStats?.requests, 27)
        XCTAssertEqual(usage.fiveHour?.windowStats?.tokens, 797_200)
        XCTAssertEqual(usage.fiveHour?.windowStats?.cost, 0.96)
        XCTAssertEqual(usage.fiveHour?.windowStats?.standardCost, 0.80)
        XCTAssertEqual(usage.fiveHour?.windowStats?.userCost, 0.96)
    }

    func testLoginEmailNormalizationRemovesPasteArtifacts() {
        XCTAssertEqual(
            LoginInput.normalizeEmail(" \u{200B}Ａdmin@Example.com\u{FEFF} "),
            "admin@example.com"
        )
        XCTAssertTrue(LoginInput.isValidEmail("admin@example.com"))
        XCTAssertFalse(LoginInput.isValidEmail("admin @example.com"))
    }
}
