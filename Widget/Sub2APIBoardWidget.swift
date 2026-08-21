import AppIntents
import SwiftUI
import WidgetKit

struct RefreshBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "刷新 Sub2API 数据"
    static let description = IntentDescription("立即读取账号额度和看板数据。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let settings = SharedStore.loadSettings()
        let snapshot = try await Sub2APIClient().fetchBoard(settings: settings)
        try SharedStore.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let snapshot: BoardSnapshot?
    let error: String?
}

struct BoardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), snapshot: .preview, error: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(BoardEntry(date: Date(), snapshot: SharedStore.loadSnapshot() ?? .preview, error: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        Task {
            let settings = SharedStore.loadSettings()
            do {
                let snapshot = try await Sub2APIClient().fetchBoard(settings: settings)
                try SharedStore.saveSnapshot(snapshot)
                let interval = TimeInterval(settings.effectiveRefreshMinutes * 60)
                completion(Timeline(entries: [BoardEntry(date: Date(), snapshot: snapshot, error: nil)], policy: .after(Date().addingTimeInterval(interval))))
            } catch {
                let cached = SharedStore.loadSnapshot()
                let interval = TimeInterval(settings.effectiveRefreshMinutes * 60)
                completion(Timeline(entries: [BoardEntry(date: Date(), snapshot: cached, error: error.localizedDescription)], policy: .after(Date().addingTimeInterval(interval))))
            }
        }
    }
}

struct BoardWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: BoardEntry
    var familyOverride: WidgetFamily?

    init(entry: BoardEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: SmallBoardView(snapshot: snapshot, hasError: entry.error != nil)
                case .systemLarge: LargeBoardView(snapshot: snapshot, hasError: entry.error != nil)
                default: MediumBoardView(snapshot: snapshot, hasError: entry.error != nil)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud").font(.title2)
                    Text("打开 Sub2API Board 完成登录").font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(BoardTheme.primaryText)
        .preferredColorScheme(.dark)
        .containerBackground(for: .widget) { BoardTheme.canvas }
    }
}

private struct SmallBoardView: View {
    let snapshot: BoardSnapshot
    let hasError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(snapshot: snapshot, hasError: hasError, showsTimestamp: false)
            TimelineView(.periodic(from: .now, by: 3)) { context in
                if let metric = rotatingAccounts(snapshot.accounts, visibleCount: 1, at: context.date).first {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Circle().fill(accountColor(metric)).frame(width: 6, height: 6)
                            Text(metric.account.name)
                                .font(.caption.weight(.semibold).monospaced())
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(metric.account.platform.uppercased())
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(BoardTheme.secondaryText)
                        }
                        if let quota = accountQuota(metric) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(Int(quota.utilization.rounded()))")
                                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                                    .foregroundStyle(quota.color)
                                    .minimumScaleFactor(0.7)
                                Text("% 已用")
                                    .font(.caption2.weight(.semibold).monospaced())
                                    .foregroundStyle(quota.color)
                                Spacer(minLength: 0)
                            }
                            WidgetProgressBar(value: quota.utilization, color: quota.color)
                            HStack {
                                Text(quota.name.uppercased())
                                Spacer()
                                Text("RESET \(quota.resetText)")
                            }
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(BoardTheme.secondaryText)
                        } else {
                            Text("暂无额度数据").font(.caption).foregroundStyle(BoardTheme.secondaryText)
                        }
                    }
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(snapshot.dashboard.errorAccounts == 0 ? Color.green : Color.red).frame(width: 6, height: 6)
                        Text("账号 \(snapshot.dashboard.normalAccounts)/\(snapshot.dashboard.totalAccounts)")
                    }
                    .font(.caption2).foregroundStyle(BoardTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Rectangle().fill(BoardTheme.border).frame(height: 1)
            HStack {
                Label(CompactFormat.number(snapshot.dashboard.todayRequests), systemImage: "arrow.up.arrow.down")
                Spacer()
                Label(CompactFormat.number(snapshot.dashboard.todayTokens), systemImage: "cube")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(BoardTheme.secondaryText)
        }
    }
}

private struct MediumBoardView: View {
    let snapshot: BoardSnapshot
    let hasError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(snapshot: snapshot, hasError: hasError)
            HStack(spacing: 10) {
                Label(CompactFormat.number(snapshot.dashboard.todayRequests), systemImage: "arrow.up.arrow.down")
                Label(CompactFormat.number(snapshot.dashboard.todayTokens), systemImage: "cube")
                Text(CompactFormat.money(snapshot.dashboard.todayActualCost))
                Spacer(minLength: 0)
                Text("\(Int(snapshot.dashboard.rpm)) RPM")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(BoardTheme.secondaryText)
            Rectangle().fill(BoardTheme.border).frame(height: 1)
            TimelineView(.periodic(from: .now, by: 3)) { context in
                if let metric = rotatingAccounts(snapshot.accounts, visibleCount: 1, at: context.date).first {
                    VStack(alignment: .leading, spacing: 3) {
                        DetailedAccountSection(metric: metric, maxWindows: 3)
                        if snapshot.accounts.count > 1 {
                            Text("每 3 秒轮换 · 共 \(snapshot.accounts.count) 个账号")
                                .font(.caption2.monospaced())
                                .foregroundStyle(BoardTheme.secondaryText)
                        }
                    }
                } else {
                    Text("在 App 中选择账号")
                        .font(.caption)
                        .foregroundStyle(BoardTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LargeBoardView: View {
    let snapshot: BoardSnapshot
    let hasError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(snapshot: snapshot, hasError: hasError)
            HStack(spacing: 8) {
                WidgetMetric(title: "今日请求", value: CompactFormat.number(snapshot.dashboard.todayRequests))
                WidgetMetric(title: "今日 Token", value: CompactFormat.number(snapshot.dashboard.todayTokens))
                WidgetMetric(title: "实际费用", value: CompactFormat.money(snapshot.dashboard.todayActualCost))
            }
            Rectangle().fill(BoardTheme.border).frame(height: 1)
            HStack(spacing: 8) {
                Text("ACCOUNT // QUOTA USAGE")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(BoardTheme.accent)
                Spacer()
                Text("ONLINE \(snapshot.dashboard.normalAccounts) · ERROR \(snapshot.dashboard.errorAccounts)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            TimelineView(.periodic(from: .now, by: 3)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rotatingAccounts(snapshot.accounts, visibleCount: 2, at: context.date)) { metric in
                        DetailedAccountSection(metric: metric, maxWindows: 4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct WidgetHeader: View {
    let snapshot: BoardSnapshot
    let hasError: Bool
    var showsTimestamp = true

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Image("BrandMark").resizable().scaledToFit().frame(width: 16, height: 16)
                Text("Sub2API")
            }
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(BoardTheme.accent)
            Spacer()
            if showsTimestamp {
                Text(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            HStack(spacing: 7) {
                Image(systemName: hasError ? "exclamationmark.icloud" : "checkmark.icloud")
                    .font(.caption2)
                    .foregroundStyle(hasError ? BoardTheme.warning : BoardTheme.secondaryText)
                Button(intent: RefreshBoardIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BoardTheme.accent)
                .accessibilityLabel("刷新数据")
            }
        }
    }
}

private struct WidgetMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(BoardTheme.secondaryText)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(BoardTheme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(BoardTheme.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(BoardTheme.border, lineWidth: 1))
    }
}

private struct CompactAccountRow: View {
    let metric: AccountMetric
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(accountColor(metric)).frame(width: 6, height: 6)
            Text(metric.account.name).font(.caption.monospaced()).lineLimit(1)
            Spacer(minLength: 6)
            if let window = metric.primaryWindow {
                WidgetProgressBar(value: window.value, color: BoardTheme.quotaColor(utilization: window.value))
                    .frame(width: 48)
                Text("用 \(Int(window.value.rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BoardTheme.quotaColor(utilization: window.value))
                    .frame(width: 42, alignment: .trailing)
            } else {
                Text("--").font(.caption2).foregroundStyle(BoardTheme.secondaryText)
            }
        }
    }
}

private struct DetailedAccountSection: View {
    let metric: AccountMetric
    let maxWindows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(accountColor(metric)).frame(width: 6, height: 6)
                Text(metric.account.name).font(.caption.weight(.semibold).monospaced()).lineLimit(1)
                Text(metric.account.platform.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(BoardTheme.secondaryText)
                Spacer(minLength: 4)
                if metric.usage?.source == "passive" {
                    Text("PASSIVE").font(.caption2.monospaced()).foregroundStyle(BoardTheme.secondaryText)
                }
            }

            if metric.usageWindows.isEmpty {
                Text(metric.error ?? "暂无窗口数据")
                    .font(.caption2)
                    .foregroundStyle(metric.error == nil ? BoardTheme.secondaryText : BoardTheme.warning)
                    .lineLimit(1)
            } else {
                ForEach(Array(metric.usageWindows.prefix(maxWindows).enumerated()), id: \.offset) { _, item in
                    UsageWindowRow(name: item.name, window: item.window)
                }
            }
        }
    }
}

private struct UsageWindowRow: View {
    let name: String
    let window: UsageWindow

    private var color: Color { BoardTheme.quotaColor(utilization: window.utilization) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let stats = window.windowStats, stats.requests > 0 || stats.tokens > 0 {
                WindowStatsLine(stats: stats)
            }
            HStack(spacing: 6) {
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(color)
                    .frame(width: 32, alignment: .leading)
                WidgetProgressBar(value: window.utilization, color: color)
                Text("用 \(Int(window.utilization.rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 46, alignment: .trailing)
                Text(CompactFormat.resetTime(for: window))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BoardTheme.secondaryText)
                    .frame(width: 45, alignment: .trailing)
            }
        }
    }

}

private struct WidgetProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5).fill(BoardTheme.track)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(value, 0), 100) / 100)
            }
        }
        .frame(height: 7)
        .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(BoardTheme.border.opacity(0.8), lineWidth: 0.5))
    }
}

private struct WindowStatsLine: View {
    let stats: WindowStats

    var body: some View {
        HStack(spacing: 6) {
            stat("\(CompactFormat.number(stats.requests)) req")
            separator
            stat(CompactFormat.number(stats.tokens))
            separator
            stat("A \(CompactFormat.money(stats.cost))")
            if let userCost = stats.userCost {
                separator
                stat("U \(CompactFormat.money(userCost))")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced).monospacedDigit())
        .foregroundStyle(BoardTheme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }

    private func stat(_ value: String) -> some View { Text(value).fixedSize() }

    private var separator: some View {
        Rectangle().fill(BoardTheme.border).frame(width: 1, height: 11)
    }
}

private func accountColor(_ metric: AccountMetric) -> Color {
    metric.account.status == "active" && metric.account.schedulable ? BoardTheme.healthy : BoardTheme.critical
}

private struct AccountQuota {
    let name: String
    let utilization: Double
    let resetText: String

    var color: Color { BoardTheme.quotaColor(utilization: utilization) }
}

private func accountQuota(_ metric: AccountMetric) -> AccountQuota? {
    if let item = metric.usageWindows.max(by: { $0.window.utilization < $1.window.utilization }) {
        return AccountQuota(
            name: item.name,
            utilization: item.window.utilization,
            resetText: CompactFormat.resetTime(for: item.window)
        )
    }

    if let primary = metric.primaryWindow {
        return AccountQuota(
            name: primary.name,
            utilization: primary.value,
            resetText: "--"
        )
    }

    return nil
}

private func accountUtilization(_ metric: AccountMetric) -> Double? {
    metric.usageWindows.map(\.window.utilization).max() ?? metric.primaryWindow?.value
}

private func sortedAccounts(_ accounts: [AccountMetric]) -> [AccountMetric] {
    accounts.sorted { lhs, rhs in
        let left = accountUtilization(lhs)
        let right = accountUtilization(rhs)
        let leftGroup = utilizationGroup(left)
        let rightGroup = utilizationGroup(right)
        if leftGroup != rightGroup { return leftGroup < rightGroup }
        if left != right { return (left ?? 0) > (right ?? 0) }
        return lhs.account.id < rhs.account.id
    }
}

private func utilizationGroup(_ value: Double?) -> Int {
    guard let value else { return 1 }
    return value >= 100 ? 2 : 0
}

private func rotatingAccounts(_ accounts: [AccountMetric], visibleCount: Int, at date: Date) -> [AccountMetric] {
    let sorted = sortedAccounts(accounts)
    guard !sorted.isEmpty else { return [] }
    let count = min(visibleCount, sorted.count)
    let page = Int(date.timeIntervalSince1970 / 3)
    let start = (page * count) % sorted.count
    return (0..<count).map { sorted[(start + $0) % sorted.count] }
}

struct Sub2APIBoardWidget: Widget {
    let kind = AppConfiguration.widgetKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoardTimelineProvider()) { entry in BoardWidgetView(entry: entry) }
            .configurationDisplayName("Sub2API 看板")
            .description("查看账号额度、今日用量和系统总览。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LegacySub2APIBoardWidget: Widget {
    let kind = AppConfiguration.legacyWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoardTimelineProvider()) { entry in BoardWidgetView(entry: entry) }
            .configurationDisplayName("Sub2API 看板")
            .description("查看账号额度、今日用量和系统总览。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension BoardSnapshot {
    static let preview = BoardSnapshot(
        generatedAt: Date(),
        dashboard: DashboardStats(totalUsers: 24, activeUsers: 8, totalAccounts: 12, normalAccounts: 11, errorAccounts: 1, rateLimitAccounts: 0, totalRequests: 128_450, totalTokens: 24_800_000, totalActualCost: 186.42, todayRequests: 3_284, todayTokens: 842_000, todayActualCost: 12.84, rpm: 18, tpm: 4_820, averageDurationMS: 1260, statsStale: false),
        trend: [],
        accounts: [
            AccountMetric(account: Account(id: 1, name: "Claude Team A", platform: "anthropic", status: "active", schedulable: true, quotaLimit: nil, quotaUsed: nil, quotaDailyLimit: nil, quotaDailyUsed: nil, quotaWeeklyLimit: nil, quotaWeeklyUsed: nil), usage: AccountUsage(updatedAt: Date(), fiveHour: UsageWindow(utilization: 42, resetsAt: nil, remainingSeconds: 4_800, windowStats: WindowStats(requests: 128, tokens: 684_000, cost: 3.42, userCost: 3.42)), sevenDay: UsageWindow(utilization: 67, resetsAt: nil, remainingSeconds: 345_600, windowStats: WindowStats(requests: 842, tokens: 4_260_000, cost: 21.30, userCost: 21.30)), thirtyDay: nil), today: nil, error: nil),
            AccountMetric(account: Account(id: 2, name: "Codex Pro", platform: "openai", status: "active", schedulable: true, quotaLimit: nil, quotaUsed: nil, quotaDailyLimit: nil, quotaDailyUsed: nil, quotaWeeklyLimit: nil, quotaWeeklyUsed: nil), usage: AccountUsage(updatedAt: Date(), fiveHour: UsageWindow(utilization: 76, resetsAt: nil, remainingSeconds: 2_100, windowStats: WindowStats(requests: 96, tokens: 512_000, cost: 2.56, userCost: 2.56)), sevenDay: UsageWindow(utilization: 31, resetsAt: nil, remainingSeconds: 518_400, windowStats: WindowStats(requests: 614, tokens: 3_180_000, cost: 15.90, userCost: 15.90)), thirtyDay: nil), today: nil, error: nil)
        ]
    )
}
