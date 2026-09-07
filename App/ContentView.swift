import AppKit
import Charts
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var model: BoardViewModel

    var body: some View {
        Group {
            if model.isAuthenticated {
                DashboardView()
            } else {
                LoginView()
            }
        }
        .background(BoardTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(BoardTheme.accent)
        .task(id: refreshSchedule) {
            await runAutoRefresh(schedule: refreshSchedule)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            guard model.isAuthenticated else { return }
            Task { await model.refresh() }
        }
        .alert("请求失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private var refreshSchedule: RefreshSchedule {
        RefreshSchedule(
            seconds: model.settings.effectiveRefreshIntervalSeconds,
            isActive: scenePhase == .active,
            isAuthenticated: model.isAuthenticated
        )
    }

    private func runAutoRefresh(schedule: RefreshSchedule) async {
        guard schedule.isActive, schedule.isAuthenticated else { return }
        await model.refresh()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(schedule.seconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
    }
}

private struct RefreshSchedule: Equatable {
    let seconds: Int
    let isActive: Bool
    let isAuthenticated: Bool
}

private struct DashboardView: View {
    @EnvironmentObject private var model: BoardViewModel
    @State private var chartMetric: TrendMetric = .requests
    @State private var hoveredDate: String?
    @State private var showsPerformanceTest = false

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    header(snapshot)
                    accountSection(snapshot.accounts)
                    statGrid(snapshot.dashboard)
                    trendChart(snapshot)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 18)
            } else if model.isLoading {
                ProgressView("正在加载 Sub2API 数据…")
                    .frame(maxWidth: .infinity, minHeight: 500)
            } else {
                ContentUnavailableView("暂无看板数据", systemImage: "chart.bar.xaxis", description: Text("点击刷新以读取最新数据"))
                    .frame(maxWidth: .infinity, minHeight: 500)
            }
        }
        .background(BoardTheme.canvas)
        .sheet(isPresented: $showsPerformanceTest) {
            PerformanceTestView()
                .environmentObject(model)
        }
    }

    private func header(_ snapshot: BoardSnapshot) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SUB2API // QUOTA CONSOLE")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(BoardTheme.accent)
                Text("运行总览").font(.title2.bold())
                Text("SYNC \((model.lastRefreshAt ?? snapshot.generatedAt).formatted(date: .omitted, time: .shortened))")
                    .font(.caption.monospaced()).foregroundStyle(BoardTheme.secondaryText)
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            if snapshot.dashboard.statsStale == true {
                Label("数据聚合延迟", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider().overlay(BoardTheme.border).frame(height: 22)
            HStack(spacing: 18) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(BoardTheme.accent)
                .disabled(model.isLoading)
                .help("立即刷新")

                Button {
                    showsPerformanceTest = true
                    Task { await model.runPerformanceTest() }
                } label: {
                    ZStack {
                        Image(systemName: "speedometer")
                            .opacity(model.isPerformanceTesting ? 0 : 1)
                        if model.isPerformanceTesting {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(BoardTheme.signal)
                .help("测试当前看板账号性能")

                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("设置")

                Button {
                    model.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("退出登录")
            }
        }
    }

    private func statGrid(_ stats: DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
            MetricTile(title: "今日请求", value: CompactFormat.number(stats.todayRequests), detail: "RPM \(CompactFormat.number(Int(stats.rpm)))", icon: "arrow.up.arrow.down")
            MetricTile(title: "今日 Token", value: CompactFormat.number(stats.todayTokens), detail: "TPM \(CompactFormat.number(Int(stats.tpm)))", icon: "cube")
            MetricTile(title: "今日实际费用", value: CompactFormat.money(stats.todayActualCost), detail: costDetail(stats), icon: "dollarsign.circle")
            MetricTile(title: "账号健康", value: "\(stats.normalAccounts)/\(stats.totalAccounts)", detail: stats.errorAccounts > 0 ? "\(stats.errorAccounts) 个异常" : "全部正常", icon: "heart.text.square")
            MetricTile(title: "累计请求", value: CompactFormat.number(stats.totalRequests), detail: "累计 Token \(CompactFormat.number(stats.totalTokens))", icon: "sum")
            MetricTile(title: "用户", value: CompactFormat.number(stats.totalUsers), detail: "今日活跃 \(CompactFormat.number(stats.activeUsers))", icon: "person.2")
            MetricTile(title: "API Key", value: optionalNumber(stats.totalAPIKeys), detail: stats.activeAPIKeys.map { "启用 \(CompactFormat.number($0))" } ?? "当前服务未提供", icon: "key")
            MetricTile(title: "平均响应", value: CompactFormat.duration(milliseconds: stats.averageDurationMS), detail: stats.uptime.map { "运行 \(CompactFormat.uptime($0))" } ?? "近 5 分钟性能", icon: "timer")
        }
    }

    private func trendChart(_ snapshot: BoardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("用量趋势").font(.headline)
                Spacer()
                Picker("趋势指标", selection: $chartMetric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Label(metric.title, systemImage: metric.icon).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            Chart(snapshot.trend, id: \.date) { point in
                AreaMark(x: .value("日期", point.date), y: .value(chartMetric.title, chartMetric.value(point)))
                    .foregroundStyle(BoardTheme.accent.opacity(0.13))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", point.date), y: .value(chartMetric.title, chartMetric.value(point)))
                    .foregroundStyle(BoardTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("日期", point.date), y: .value(chartMetric.title, chartMetric.value(point)))
                    .foregroundStyle(hoveredDate == point.date ? BoardTheme.warning : BoardTheme.accent)
                    .symbolSize(hoveredDate == point.date ? 70 : 24)
                if hoveredDate == point.date {
                    RuleMark(x: .value("日期", point.date))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, spacing: 6) {
                            VStack(spacing: 2) {
                                Text(point.date).font(.caption2).foregroundStyle(.secondary)
                                Text(chartMetric.format(point)).font(.caption.bold().monospacedDigit())
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { return }
                                let x = location.x - geometry[frame].origin.x
                                hoveredDate = proxy.value(atX: x, as: String.self)
                            case .ended:
                                hoveredDate = nil
                            }
                        }
                }
            }
            .frame(height: 176)
            Text("悬停查看单日数据 · 当前共 \(snapshot.trend.count) 个数据点")
                .font(.caption).foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func accountSection(_ accounts: [AccountMetric]) -> some View {
        let reservedWindowCount = max(accounts.map(\.usageWindows.count).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("账号额度").font(.headline)
                    Text("USAGE QUOTA // HIGHEST FIRST")
                        .font(.caption2.weight(.medium).monospaced())
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Spacer()
                SettingsLink { Text("管理").font(.caption) }.buttonStyle(.link)
            }
            if accounts.isEmpty {
                Text("尚未选择账号").foregroundStyle(.secondary).padding(.vertical, 18)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 12)], spacing: 12) {
                    ForEach(accounts) {
                        AccountUsageCard(metric: $0, reservedWindowCount: reservedWindowCount)
                    }
                }
            }
        }
    }

    private func costDetail(_ stats: DashboardStats) -> String {
        if let accountCost = stats.todayAccountCost {
            return "账号 \(CompactFormat.money(accountCost)) · 累计 \(CompactFormat.money(stats.totalActualCost))"
        }
        return "累计 \(CompactFormat.money(stats.totalActualCost))"
    }

    private func optionalNumber(_ value: Int?) -> String {
        value.map(CompactFormat.number) ?? "--"
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case requests, tokens, cost
    var id: String { rawValue }
    var title: String { switch self { case .requests: "请求"; case .tokens: "Token"; case .cost: "费用" } }
    var icon: String { switch self { case .requests: "arrow.up.arrow.down"; case .tokens: "cube"; case .cost: "dollarsign" } }
    func value(_ point: TrendPoint) -> Double {
        switch self { case .requests: Double(point.requests); case .tokens: Double(point.totalTokens); case .cost: point.actualCost }
    }
    func format(_ point: TrendPoint) -> String {
        switch self { case .requests: "\(CompactFormat.number(point.requests)) 次"; case .tokens: CompactFormat.number(point.totalTokens); case .cost: CompactFormat.money(point.actualCost) }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title.uppercased(), systemImage: icon)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(BoardTheme.secondaryText)
                Spacer()
                Circle().fill(BoardTheme.signal).frame(width: 5, height: 5)
            }
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .monospaced))
                .foregroundStyle(BoardTheme.primaryText)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(BoardTheme.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }
}

private struct PerformanceTestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: BoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI 配置测速")
                        .font(.title2.bold())
                    Text("并行测试当前看板账号到上游 AI 服务的连接性能")
                        .font(.caption.monospaced())
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if model.isPerformanceTesting {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在测试账号连接，请稍候…")
                        .font(.callout.monospaced())
                    Text("测试会向每个账号的上游服务发起一次轻量请求")
                        .font(.caption)
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
                .panelStyle()
            } else if let report = model.performanceTestReport {
                reportContent(report)
            } else {
                ContentUnavailableView(
                    "暂无测速结果",
                    systemImage: "speedometer",
                    description: Text("点击重新测速以检查当前账号配置")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }

            HStack {
                if let report = model.performanceTestReport, !model.isPerformanceTesting {
                    Text("TESTED \(report.startedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Spacer()
                Button {
                    Task { await model.runPerformanceTest() }
                } label: {
                    Label("重新测速", systemImage: "speedometer")
                }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.accent)
                .disabled(model.isPerformanceTesting)
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .background(BoardTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(BoardTheme.accent)
    }

    @ViewBuilder
    private func reportContent(_ report: PerformanceTestReport) -> some View {
        let hasFirstToken = report.averageFirstTokenMS != nil
        let hasUpstreamLatency = report.averageUpstreamLatencyMS != nil
        let averageLatency = report.averageFirstTokenMS
            ?? report.averageUpstreamLatencyMS
            ?? report.averageRequestDurationMS
        let fastestAccount = hasUpstreamLatency ? report.fastestResult : report.fastestRequestResult
        let averageTokensPerSecond = report.averageTokensPerSecond

        HStack(spacing: 10) {
            PerformanceMetricTile(
                title: "成功账号",
                value: "\(report.successCount)/\(report.results.count)",
                detail: report.successCount == report.results.count ? "全部可用" : "存在连接异常",
                color: report.successCount == report.results.count ? BoardTheme.healthy : BoardTheme.warning
            )
            PerformanceMetricTile(
                title: hasFirstToken ? "平均首 Token" : (hasUpstreamLatency ? "平均上游延迟" : "平均端到端"),
                value: averageLatency.map { CompactFormat.duration(milliseconds: $0) } ?? "--",
                detail: fastestAccount.map { "最快 · \($0.accountName)" } ?? "暂无成功结果",
                color: BoardTheme.signal
            )
            PerformanceMetricTile(
                title: averageTokensPerSecond == nil ? "并行总耗时" : "平均生成速度",
                value: averageTokensPerSecond.map {
                    "\(report.estimatedTokenRateCount > 0 ? "≈" : "")\(PerformanceFormat.tokenRate($0)) tok/s"
                } ?? CompactFormat.duration(milliseconds: report.totalDurationMS),
                detail: averageTokensPerSecond == nil
                    ? "旧版后端暂不返回 Token/s"
                    : (report.estimatedTokenRateCount > 0
                        ? "\(report.estimatedTokenRateCount) 个账号使用估算 Token"
                        : (report.fastestGenerationResult.map { "最快 · \($0.accountName)" } ?? "上游返回精确 Token")),
                color: BoardTheme.accent
            )
        }

        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(report.results) { result in
                    PerformanceResultRow(result: result)
                }
            }
        }
    }
}

private struct PerformanceMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(BoardTheme.secondaryText)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(BoardTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }
}

private struct PerformanceResultRow: View {
    let result: AccountPerformanceResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? BoardTheme.healthy : BoardTheme.critical)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(result.accountName)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    Text(result.platform.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.success ? BoardTheme.secondaryText : BoardTheme.critical)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            performanceValue(
                title: result.firstTokenMS == nil ? "上游延迟" : "首 Token",
                value: (result.firstTokenMS ?? result.upstreamLatencyMS)
                    .map { CompactFormat.duration(milliseconds: Double($0)) } ?? "--"
            )
            performanceValue(
                title: "Token/s",
                value: result.tokensPerSecond.map {
                    "\(result.tokenCountEstimated == true ? "≈" : "")\(PerformanceFormat.tokenRate($0))"
                } ?? "--"
            )
            performanceValue(
                title: "输出 Token",
                value: result.outputTokens.map {
                    "\(result.tokenCountEstimated == true ? "≈" : "")\($0)"
                } ?? "--"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BoardTheme.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BoardTheme.border, lineWidth: 1))
    }

    private func performanceValue(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(BoardTheme.secondaryText)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(BoardTheme.primaryText)
        }
        .frame(width: 82, alignment: .trailing)
    }

}

private enum PerformanceFormat {
    static func tokenRate(_ value: Double) -> String {
        String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }
}

private struct AccountUsageCard: View {
    let metric: AccountMetric
    let reservedWindowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(isHealthy ? BoardTheme.healthy : BoardTheme.critical).frame(width: 8, height: 8)
                Text(metric.account.name).font(.headline.monospaced()).lineLimit(1)
                Text(metric.account.platform.uppercased()).font(.caption2.monospaced()).foregroundStyle(BoardTheme.secondaryText)
                Spacer()
                Text(isHealthy ? "ONLINE" : "ERROR")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(isHealthy ? BoardTheme.healthy : BoardTheme.critical)
            }

            VStack(alignment: .leading, spacing: 6) {
                if metric.usageWindows.isEmpty {
                    Text(metric.error ?? "暂无额度数据")
                        .font(.callout).foregroundStyle(metric.error == nil ? Color.secondary : Color.orange)
                        .frame(maxWidth: .infinity, minHeight: AppUsageWindowRow.height, alignment: .leading)
                } else {
                    ForEach(Array(metric.usageWindows.enumerated()), id: \.offset) { _, item in
                        AppUsageWindowRow(name: item.name, window: item.window)
                    }
                }
                if occupiedWindowCount < reservedWindowCount {
                    ForEach(occupiedWindowCount..<reservedWindowCount, id: \.self) { _ in
                        Color.clear.frame(height: AppUsageWindowRow.height)
                    }
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private var isHealthy: Bool { metric.account.status == "active" && metric.account.schedulable }
    private var occupiedWindowCount: Int { max(metric.usageWindows.count, 1) }
}

private struct AppUsageWindowRow: View {
    static let height: CGFloat = 44

    let name: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let stats = window.windowStats, stats.requests > 0 || stats.tokens > 0 {
                HStack(spacing: 8) {
                    stat("\(CompactFormat.number(stats.requests)) req")
                    separator
                    stat("\(CompactFormat.number(stats.tokens)) Token")
                    separator
                    stat("账号 \(CompactFormat.money(stats.cost))")
                    if let userCost = stats.userCost { separator; stat("用户 \(CompactFormat.money(userCost))") }
                    Spacer(minLength: 0)
                }
                .font(.caption.monospacedDigit()).foregroundStyle(BoardTheme.secondaryText)
            } else {
                Color.clear.frame(height: 15)
            }
            HStack(spacing: 10) {
                Text(name.uppercased())
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(color)
                    .frame(width: 42, alignment: .leading)
                QuotaProgressBar(value: window.utilization, color: color)
                Text("已用 \(Int(window.utilization.rounded()))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 82, alignment: .trailing)
                Text("重置 \(CompactFormat.resetTime(for: window))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BoardTheme.secondaryText)
                    .frame(width: 92, alignment: .trailing)
            }
        }
        .frame(height: Self.height, alignment: .top)
    }

    private var color: Color { BoardTheme.quotaColor(utilization: window.utilization) }
    private func stat(_ value: String) -> some View { Text(value).lineLimit(1) }
    private var separator: some View { Rectangle().fill(.quaternary).frame(width: 1, height: 14) }
}

private struct QuotaProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(BoardTheme.track)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(value, 0), 100) / 100)
            }
        }
        .frame(height: 10)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(BoardTheme.border.opacity(0.8), lineWidth: 1))
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(14)
            .background(BoardTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(BoardTheme.border, lineWidth: 1))
    }
}
