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
        XCTAssertEqual(BoardSettings.refreshMinuteOptions, [1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60])
        XCTAssertEqual(BoardSettings(refreshMinutes: 1).effectiveRefreshMinutes, 1)
        XCTAssertEqual(BoardSettings(refreshMinutes: 3).effectiveRefreshMinutes, 15)
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

    func testServerURLAppendsAPIVersion() {
        XCTAssertEqual(BoardSettings(serverURL: "https://example.com/", selectedAccountIDs: [], refreshMinutes: 15).apiBaseURL?.absoluteString, "https://example.com/api/v1")
        XCTAssertEqual(BoardSettings(serverURL: "https://example.com/api/v1", selectedAccountIDs: [], refreshMinutes: 15).apiBaseURL?.absoluteString, "https://example.com/api/v1")
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
