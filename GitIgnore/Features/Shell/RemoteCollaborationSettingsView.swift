import SwiftUI

struct RemoteCollaborationSettingsView: View {
    let remoteInfo: GitRemoteInfo?

    @State private var providerChoice = ""
    @State private var tokenDraft = ""
    @State private var hasSavedToken = false
    @State private var statusMessage: String?
    @State private var statusSucceeded = false

    private var host: String? { remoteInfo?.webURL?.host?.lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let host {
                LabeledContent(text("当前服务", "Current Host")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(host).orbitFont(.callout, weight: .medium)
                        Text(remoteInfo?.url ?? "")
                            .orbitFont(.caption2)
                            .foregroundStyle(OrbitDesign.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Picker(text("平台类型", "Provider"), selection: $providerChoice) {
                    Text(text("自动识别", "Auto Detect")).tag("")
                    ForEach(RemoteHostingProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerChoice) { _, value in
                    updateProvider(value, for: host)
                }

                SecureField(
                    hasSavedToken
                        ? text("已保存凭据；输入新 Token 可替换", "Credential saved; enter a new token to replace it")
                        : text("访问令牌 Token", "Access Token"),
                    text: $tokenDraft
                )
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 9) {
                    Button(text("保存到 macOS 钥匙串", "Save to macOS Keychain")) {
                        saveToken(for: host)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasSavedToken {
                        Button(text("删除凭据", "Remove Credential"), role: .destructive) {
                            removeToken(for: host)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if hasSavedToken {
                        Label(text("凭据已保存", "Credential Saved"), systemImage: "checkmark.shield.fill")
                            .orbitFont(.caption, weight: .semibold)
                            .foregroundStyle(OrbitDesign.accent)
                    }
                }

                Text(permissionHint)
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: statusSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .orbitFont(.caption)
                    .foregroundStyle(statusSucceeded ? OrbitDesign.accent : OrbitDesign.coral)
                }
            } else {
                Label(
                    text("打开一个带 origin 的仓库后，可在这里配置代码评审和问题跟踪。", "Open a repository with an origin remote to configure code review and issue tracking."),
                    systemImage: "network.slash"
                )
                .orbitFont(.subheadline)
                .foregroundStyle(OrbitDesign.secondaryText)
            }

            Text(text(
                "公共仓库可以匿名读取；私有仓库的 Token 只保存在当前 Mac 的系统钥匙串，不会写入偏好设置或仓库文件。",
                "Public repositories can be read anonymously. Tokens for private repositories are stored only in this Mac's system Keychain, never in preferences or repository files."
            ))
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: host) { loadCredentialState() }
    }

    private var selectedProvider: RemoteHostingProvider? {
        if let selected = RemoteHostingProvider(rawValue: providerChoice) { return selected }
        switch remoteInfo?.provider {
        case "GitHub": return .github
        case "GitLab": return .gitlab
        case "Gitee": return .gitee
        default: return nil
        }
    }

    private var permissionHint: String {
        switch selectedProvider {
        case .github:
            text("GitHub：Fine-grained Token 仅授予当前仓库的 Pull requests 与 Issues 读取权限；经典 Token 可使用 repo 权限。", "GitHub: grant a fine-grained token read access to Pull requests and Issues for this repository only; classic tokens may use repo scope.")
        case .gitlab:
            text("GitLab：建议使用只读 read_api 权限。自建 GitLab 也会使用当前远程 Host。", "GitLab: use the read-only read_api scope. Self-hosted GitLab uses the current remote host.")
        case .gitee:
            text("Gitee：只授予读取 Pull Requests 与 Issues 所需的最小权限。", "Gitee: grant only the minimum permission required to read Pull Requests and Issues.")
        case nil:
            text("无法自动识别时，请先手动选择 GitHub、GitLab 或 Gitee。", "If auto detection fails, choose GitHub, GitLab, or Gitee manually.")
        }
    }

    private func loadCredentialState() {
        tokenDraft = ""
        statusMessage = nil
        statusSucceeded = false
        guard let host else {
            providerChoice = ""
            hasSavedToken = false
            return
        }
        providerChoice = RemoteCollaborationPreferences.providerOverride(for: host)?.rawValue ?? ""
        hasSavedToken = RemoteAccessTokenStore.token(for: host) != nil
    }

    private func updateProvider(_ value: String, for host: String) {
        let provider = value.isEmpty ? nil : RemoteHostingProvider(rawValue: value)
        RemoteCollaborationPreferences.setProviderOverride(provider, for: host)
        statusMessage = provider == nil
            ? text("已恢复自动识别。", "Automatic provider detection restored.")
            : text("已将 \(host) 识别为 \(provider?.title ?? "")。", "\(host) is now treated as \(provider?.title ?? "").")
        statusSucceeded = true
    }

    private func saveToken(for host: String) {
        do {
            try RemoteAccessTokenStore.setToken(tokenDraft, for: host)
            tokenDraft = ""
            hasSavedToken = true
            statusMessage = text("访问凭据已安全保存。返回代码评审或问题跟踪后刷新即可使用。", "Access credential saved securely. Refresh Code Review or Issues to use it.")
            statusSucceeded = true
        } catch {
            statusMessage = error.localizedDescription
            statusSucceeded = false
        }
    }

    private func removeToken(for host: String) {
        do {
            try RemoteAccessTokenStore.removeToken(for: host)
            tokenDraft = ""
            hasSavedToken = false
            statusMessage = text("已从 macOS 钥匙串删除访问凭据。", "Access credential removed from macOS Keychain.")
            statusSucceeded = true
        } catch {
            statusMessage = error.localizedDescription
            statusSucceeded = false
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        AppLanguage.text(chinese, english)
    }
}
