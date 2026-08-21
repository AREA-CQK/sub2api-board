import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: BoardViewModel

    var body: some View {
        Form {
            Section("连接") {
                TextField("服务地址", text: $model.settings.serverURL)
                Picker("Widget 刷新间隔", selection: $model.settings.refreshMinutes) {
                    ForEach(BoardSettings.refreshMinuteOptions, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
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
                Spacer()
                Button("保存并刷新") {
                    guard model.saveSettings() else { return }
                    Task { await model.refresh() }
                }
                .buttonStyle(.borderedProminent).tint(BoardTheme.accent)
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
}
