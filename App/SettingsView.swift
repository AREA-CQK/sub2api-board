import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: BoardViewModel
    @State private var isSavingAndRefreshing = false
    @State private var saveResultMessage: String?

    var body: some View {
        Form {
            Section("连接") {
                TextField("服务地址", text: $model.settings.serverURL)
                Picker("App 与 Widget 刷新间隔", selection: $model.settings.refreshIntervalSeconds) {
                    ForEach(BoardSettings.refreshIntervalSecondOptions, id: \.self) { seconds in
                        Text(refreshIntervalTitle(seconds)).tag(seconds)
                    }
                }
            }
            Section("Widget 账号") {
                if model.accounts.isEmpty {
                    HStack { Text("尚未读取账号"); Spacer(); Button("读取") { Task { await model.loadAccounts() } } }
                } else {
                    List(model.accounts) { account in
                        Toggle(isOn: selectedBinding(account.id)) {
                            HStack {
                                Circle().fill(account.status == "active" ? BoardTheme.healthy : BoardTheme.critical).frame(width: 7, height: 7)
                                Text(account.name).font(.body.monospaced()).lineLimit(1)
                                Spacer()
                                Text(account.platform.uppercased())
                                    .font(.caption.monospaced())
                                    .foregroundStyle(BoardTheme.secondaryText)
                            }
                        }
                    }
                    .frame(height: 210)
                }
                Text("最多选择 6 个；未选择时默认展示前 6 个启用账号。")
                    .font(.caption.monospaced()).foregroundStyle(BoardTheme.secondaryText)
            }
            HStack {
                if let saveResultMessage {
                    Text(saveResultMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Spacer()
                Button {
                    Task {
                        isSavingAndRefreshing = true
                        saveResultMessage = nil
                        let succeeded = await model.saveSettingsAndRefresh()
                        saveResultMessage = succeeded
                            ? "已保存并刷新 · \(Date().formatted(date: .omitted, time: .standard))"
                            : "保存或刷新失败"
                        isSavingAndRefreshing = false
                    }
                } label: {
                    HStack(spacing: 7) {
                        if isSavingAndRefreshing {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSavingAndRefreshing ? "正在保存并刷新" : "保存并刷新")
                    }
                }
                .buttonStyle(.borderedProminent).tint(BoardTheme.accent)
                .disabled(isSavingAndRefreshing)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(BoardTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(BoardTheme.accent)
        .task { if model.accounts.isEmpty { await model.loadAccounts() } }
    }

    private func selectedBinding(_ id: Int) -> Binding<Bool> {
        Binding {
            model.settings.selectedAccountIDs.contains(id)
        } set: { selected in
            if selected, !model.settings.selectedAccountIDs.contains(id), model.settings.selectedAccountIDs.count < 6 {
                model.settings.selectedAccountIDs.append(id)
            } else if !selected {
                model.settings.selectedAccountIDs.removeAll { $0 == id }
            }
            _ = model.saveSettings()
        }
    }

    private func refreshIntervalTitle(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分钟"
    }
}
