import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var model: BoardViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var totpCode = ""

    var body: some View {
        VStack(spacing: 22) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            VStack(spacing: 5) {
                Text("Sub2API Board").font(.title.bold())
                Text("连接你的 Sub2API 管理后台").foregroundStyle(.secondary)
            }
            Form {
                TextField("服务地址", text: $model.settings.serverURL, prompt: Text("https://sub2api.example.com"))
                    .textContentType(.URL)
                if model.needsTOTP {
                    TextField("两步验证码", text: $totpCode).textContentType(.oneTimeCode)
                } else {
                    TextField("管理员邮箱", text: $email)
                        .textContentType(.emailAddress)
                        .onSubmit { email = LoginInput.normalizeEmail(email) }
                    SecureField("密码", text: $password).textContentType(.password)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            Button {
                Task {
                    if model.needsTOTP { await model.completeTOTP(code: totpCode) }
                    else { await model.login(email: email, password: password) }
                }
            } label: {
                HStack { if model.isLoading { ProgressView().controlSize(.small) }; Text(model.needsTOTP ? "验证并登录" : "登录") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(model.isLoading || model.settings.serverURL.isEmpty || (model.needsTOTP ? totpCode.count < 6 : email.isEmpty || password.isEmpty))
            Text("登录令牌保存在 macOS Keychain 中，Widget 不保存账号密码。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(width: 460)
    }
}
