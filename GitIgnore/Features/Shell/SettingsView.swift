import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("orbit.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("orbit.profile.displayName") private var displayName = "Heng Yee"
    @AppStorage("orbit.profile.avatarData") private var avatarData = ""
    @AppStorage("orbit.uiFontLatin") private var uiFontLatin = ""
    @AppStorage("orbit.uiFontCJK") private var uiFontCJK = ""
    @AppStorage("orbit.uiFontSize") private var uiFontSize = 13.0
    @AppStorage("orbit.interfaceDensity") private var interfaceDensity = OrbitDensity.comfortable.rawValue
    @AppStorage(OrbitGlassPreferences.storageKey) private var glassEffectsEnabled = true
    @AppStorage(AppIconController.storageKey) private var appIconChoice = AppIconChoice.lightCommitPulse.rawValue
    @AppStorage("orbit.sidebarFooter.enabled") private var footerEnabled = true
    @AppStorage("orbit.sidebarFooter.message") private var footerMessage = "保持专注，\n让每次提交都有意义。"
    @AppStorage("orbit.sidebarFooter.wraps") private var footerWraps = true
    @AppStorage("orbit.sidebarFooter.maxLines") private var footerMaxLines = 2
    @AppStorage(RemoteCheckPreferences.notificationsKey) private var remoteNotificationsEnabled = true
    @AppStorage(RemoteCheckPreferences.timeoutKey) private var remoteTimeoutSeconds = RemoteCheckPreferences.defaultTimeout
    @AppStorage("orbit.commit.template") private var commitTemplate = ""
    @AppStorage("orbit.settings.selectedPane") private var selectedPane: SettingsPane = .profile
    @State private var notificationPermission: NotificationPermissionState = .notRequested
    @State private var isRequestingNotificationPermission = false
    @State private var notificationPermissionMessage: String?
    @State private var showsPerformanceDiagnostics = false
    @State private var fontFamilies: [String] = []

    private var cjkPreviewFont: Font {
        OrbitTypography.ui(size: uiFontSize, latin: uiFontCJK, cjk: uiFontCJK)
    }

    private var fontPalette: OrbitFontPalette {
        OrbitFontPalette(latin: uiFontLatin, cjk: uiFontCJK, baseSize: uiFontSize)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider().overlay(OrbitDesign.separator)
            settingsDetail
        }
        .environment(\.orbitFontPalette, fontPalette)
        .font(fontPalette.font(.body))
        .frame(minWidth: 900, minHeight: 660)
        .background(OrbitDesign.canvas)
        .task {
            notificationPermission = await RemoteUpdateNotifier.permissionState()
        }
        .task(id: "\(uiFontLatin)|\(uiFontCJK)") {
            await OrbitTypography.activateConfiguredFamilies(latin: uiFontLatin, cjk: uiFontCJK)
            fontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }
        .alert(AppLanguage.text("通知权限", "Notification Permission"), isPresented: Binding(
            get: { notificationPermissionMessage != nil },
            set: { if !$0 { notificationPermissionMessage = nil } }
        )) {
            Button(AppLanguage.text("打开系统设置", "Open System Settings")) { openNotificationSettings() }
            Button(AppLanguage.text("关闭", "Close"), role: .cancel) {}
        } message: {
            Text(notificationPermissionMessage ?? "")
        }
        .sheet(isPresented: $showsPerformanceDiagnostics) {
            PerformanceDiagnosticsView()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLanguage.text("设置", "Settings"))
                    .orbitFont(.title3, weight: .bold)
                    .foregroundStyle(OrbitDesign.primaryText)
                Text(AppLanguage.text("偏好、外观和工具配置", "Preferences, appearance, and tools"))
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 4)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarButton(
                        pane: pane,
                        isSelected: selectedPane == pane
                    ) {
                        selectedPane = pane
                    }
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(notificationPermissionColor)
                        .frame(width: 7, height: 7)
                    Text(notificationPermission.title)
                        .orbitFont(.caption2, weight: .semibold)
                }
                Text(AppLanguage.text("设置会立即应用到当前窗口。", "Changes apply immediately to this window."))
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitDesign.separator, lineWidth: 1) }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 224)
        .background { OrbitChromeBackground(region: .sidebar) }
    }

    private var settingsDetail: some View {
        ZStack(alignment: .topLeading) {
            OrbitDesign.canvas
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsTitle
                    selectedPaneContent
                }
                .frame(maxWidth: 820, alignment: .topLeading)
                .padding(24)
            }
            .id(selectedPane)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .offset(y: 6))
            )
        }
        .animation(OrbitMotion.page(reduceMotion: reduceMotion), value: selectedPane)
    }

    private var settingsTitle: some View {
        HStack(alignment: .center, spacing: 13) {
            OrbitIconBadge(systemName: selectedPane.symbol, color: selectedPane.tint, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedPane.title)
                    .orbitFont(.title2, weight: .bold)
                    .foregroundStyle(OrbitDesign.primaryText)
                Text(selectedPane.subtitle)
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            Text(AppLanguage.text("实时应用", "Live"))
                .orbitFont(.caption2, weight: .bold)
                .foregroundStyle(OrbitDesign.accent)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(OrbitDesign.accent.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selectedPane {
        case .profile:
            profilePane
        case .icon:
            iconPane
        case .appearance:
            appearancePane
        case .fonts:
            fontsPane
        case .sidebar:
            sidebarPane
        case .remote:
            remotePane
        case .git:
            gitPane
        }
    }

    private var profilePane: some View {
        settingsPanel(
            title: AppLanguage.text("个人资料", "Profile"),
            subtitle: AppLanguage.text("名称和头像会同步到侧栏、概览和提交身份区域。", "Name and avatar are reflected in the sidebar, overview, and identity surfaces."),
            systemName: "person.crop.circle"
        ) {
            HStack(spacing: 16) {
                CurrentUserAvatarView(size: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLanguage.text("个人头像", "Avatar"))
                        .orbitFont(.subheadline, weight: .semibold)
                    Text(AppLanguage.text("通过设置统一更换，头像区域本身不再承担点击事件。", "Manage it from Settings; the avatar itself is no longer a hidden button."))
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                AvatarPickerButton(avatarData: $avatarData)
                if !avatarData.isEmpty {
                    Button(AppLanguage.text("恢复文字头像", "Reset")) {
                        avatarData = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            controlRow(
                title: AppLanguage.text("显示名称", "Display Name"),
                subtitle: AppLanguage.text("用于欢迎语、侧栏身份和提交信息辅助展示。", "Used in greetings, sidebar identity, and commit identity hints.")
            ) {
                TextField(AppLanguage.text("输入显示名称", "Enter display name"), text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
        }
    }

    private var iconPane: some View {
        settingsPanel(
            title: AppLanguage.text("应用图标", "App Icon"),
            subtitle: AppLanguage.text("全局图标会同步到 Dock、应用切换器、通知和运行窗口。", "The global icon is synchronized to Dock, app switcher, notifications, and live windows."),
            systemName: "app.dashed"
        ) {
            iconCollection(
                title: AppLanguage.text("浅色系列", "Light Set"),
                subtitle: AppLanguage.text("适合浅色桌面与明亮壁纸", "For light desktops and bright wallpapers"),
                choices: AppIconChoice.lightChoices
            )

            Divider()

            iconCollection(
                title: AppLanguage.text("深色系列", "Dark Set"),
                subtitle: AppLanguage.text("适合深色桌面与夜间工作", "For dark desktops and night work"),
                choices: AppIconChoice.darkChoices
            )

            Text(AppLanguage.text(
                "选择后会立即设置运行时图标，并持久化到应用图标资源；macOS 仍可能需要重启应用或刷新 Dock 才显示缓存更新。",
                "Selection updates the runtime icon and persists the app icon resource. macOS may still need an app restart or Dock refresh to clear cached imagery."
            ))
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearancePane: some View {
        settingsPanel(
            title: AppLanguage.text("外观", "Appearance"),
            subtitle: AppLanguage.text("保持内容清晰，材质只服务于窗口层级，不做廉价玻璃感。", "Keep content clear; material is used for hierarchy, not decorative haze."),
            systemName: "circle.lefthalf.filled"
        ) {
            controlRow(
                title: AppLanguage.text("界面语言", "Language"),
                subtitle: AppLanguage.text("默认中文；Git 通用术语保持 Fetch、Pull、Push、Stage、Stash。", "Chinese by default; Git terms stay as Fetch, Pull, Push, Stage, and Stash.")
            ) {
                Picker(AppLanguage.text("界面语言", "Language"), selection: $languageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            controlRow(
                title: AppLanguage.text("主题", "Theme"),
                subtitle: AppLanguage.text("跟随系统、浅色和深色都会使用同一套清晰底色体系。", "System, Light, and Dark share the same clear surface hierarchy.")
            ) {
                Picker(AppLanguage.text("主题", "Theme"), selection: $appearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            controlRow(
                title: AppLanguage.text("内容密度", "Density"),
                subtitle: AppLanguage.text("长列表建议使用紧凑模式；舒适模式保留更多呼吸感。", "Use Compact for long lists; Comfortable keeps more breathing room.")
            ) {
                Picker(AppLanguage.text("内容密度", "Density"), selection: $interfaceDensity) {
                    ForEach(OrbitDensity.allCases) { density in
                        Text(density.title).tag(density.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            controlRow(
                title: AppLanguage.text("原生窗口材质", "Native Material"),
                subtitle: AppLanguage.text("只影响侧栏和工具栏；代码、Diff 和列表始终保持实体背景。", "Only affects sidebar and toolbar; code, Diff, and lists stay on solid surfaces.")
            ) {
                Toggle("", isOn: $glassEffectsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var fontsPane: some View {
        settingsPanel(
            title: AppLanguage.text("字体", "Fonts"),
            subtitle: AppLanguage.text("英文和中文字体分开设置，主窗口会使用字体级联实时刷新。", "Configure Latin and CJK fonts separately; the main window refreshes through font cascading."),
            systemName: "textformat"
        ) {
            controlRow(
                title: AppLanguage.text("英文 / 拉丁文字体", "Latin Font"),
                subtitle: AppLanguage.text("用于英文、数字和大部分 Git 标识。", "Used for English, numbers, and most Git labels.")
            ) {
                fontPicker(
                    title: AppLanguage.text("英文 / 拉丁文字体", "Latin Font"),
                    selection: $uiFontLatin,
                    systemTitle: AppLanguage.text("系统默认 · SF Pro", "System Default · SF Pro")
                )
                .frame(width: 280)
            }

            controlRow(
                title: AppLanguage.text("中文 / CJK 字体", "CJK Font"),
                subtitle: AppLanguage.text("用于中文、日文和韩文字符。", "Used for Chinese, Japanese, and Korean characters.")
            ) {
                fontPicker(
                    title: AppLanguage.text("中文 / CJK 字体", "CJK Font"),
                    selection: $uiFontCJK,
                    systemTitle: AppLanguage.text("系统默认 · PingFang SC", "System Default · PingFang SC")
                )
                .frame(width: 280)
            }

            controlRow(
                title: AppLanguage.text("界面字号", "UI Size"),
                subtitle: AppLanguage.text("影响主界面、设置和工具栏的阅读尺寸。", "Affects the main UI, Settings, and toolbar reading size.")
            ) {
                HStack(spacing: 10) {
                    Slider(value: $uiFontSize, in: 11...22, step: 1)
                    Text("\(Int(uiFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .frame(width: 48, alignment: .trailing)
                }
                .frame(width: 280)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(AppLanguage.text("实时预览", "Live Preview"))
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                HStack(spacing: 18) {
                    Text("GitIgnore / Fetch Pull Stage")
                        .font(OrbitTypography.ui(size: uiFontSize, latin: uiFontLatin, cjk: uiFontCJK))
                    Text("中文界面预览")
                        .font(cjkPreviewFont)
                    Spacer()
                }
                .padding(14)
                .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
            }
        }
    }

    private var sidebarPane: some View {
        settingsPanel(
            title: AppLanguage.text("侧栏签名", "Sidebar Signature"),
            subtitle: AppLanguage.text("底部文案可以多行展示，图标支持内置选择和上传。", "Footer copy supports multiple lines, built-in icons, and uploads."),
            systemName: "quote.bubble"
        ) {
            controlRow(
                title: AppLanguage.text("显示侧栏签名", "Show Signature"),
                subtitle: AppLanguage.text("关闭后侧栏底部只保留必要状态，不显示装饰文案。", "When off, the sidebar footer keeps only essential state.")
            ) {
                Toggle("", isOn: $footerEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppLanguage.text("签名文案", "Signature Copy"))
                        .orbitFont(.caption, weight: .semibold)
                    Spacer()
                    Text("\(footerMessage.count) / 120")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                TextEditor(text: $footerMessage)
                    .orbitFont(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 92)
                    .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
                    .disabled(!footerEnabled)
                    .onChange(of: footerMessage) { _, newValue in
                        if newValue.count > 120 { footerMessage = String(newValue.prefix(120)) }
                    }
            }

            HStack(spacing: 18) {
                Toggle(AppLanguage.text("允许自动换行", "Allow wrapping"), isOn: $footerWraps)
                    .disabled(!footerEnabled)
                Stepper(
                    AppLanguage.text("最多 \(footerMaxLines) 行", "Max \(footerMaxLines) lines"),
                    value: $footerMaxLines,
                    in: 1...4
                )
                .disabled(!footerEnabled || !footerWraps)
            }

            footerPreview

            Divider()

            SidebarFooterIconSettings()
        }
    }

    private var remotePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPanel(
                title: AppLanguage.text("远程协作", "Remote Collaboration"),
                subtitle: AppLanguage.text("为代码评审和问题追踪配置服务识别和只读凭据。", "Configure provider detection and read-only credentials for code review and issues."),
                systemName: "person.2.wave.2"
            ) {
                RemoteCollaborationSettingsView(remoteInfo: appState.remoteInfo)
            }

            settingsPanel(
                title: AppLanguage.text("远程检测与通知", "Remote Checks & Notifications"),
                subtitle: AppLanguage.text("打开或切换仓库时检测可 Pull 数量，失败或超时也发通知。", "Check Pull availability when opening or switching repositories, and notify on failure or timeout."),
                systemName: "bell.badge"
            ) {
                controlRow(
                    title: AppLanguage.text("发送系统通知", "Send System Notifications"),
                    subtitle: AppLanguage.text("检测到可拉取提交、网络不通或超时时使用 macOS 通知。", "Use macOS notifications for Pull availability, network failure, and timeout.")
                ) {
                    Toggle("", isOn: $remoteNotificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: remoteNotificationsEnabled) { _, enabled in
                            if enabled { Task { await requestNotificationPermission() } }
                        }
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill(notificationPermissionColor)
                        .frame(width: 8, height: 8)
                    Text(AppLanguage.text("macOS 通知权限", "macOS Notification Permission"))
                        .orbitFont(.callout, weight: .medium)
                    Spacer()
                    Text(notificationPermission.title)
                        .orbitFont(.caption, weight: .semibold)
                        .foregroundStyle(notificationPermissionColor)

                    if notificationPermission == .notRequested {
                        Button {
                            Task { await requestNotificationPermission() }
                        } label: {
                            if isRequestingNotificationPermission {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(AppLanguage.text("立即请求权限", "Request Now"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isRequestingNotificationPermission)
                    }
                }

                controlRow(
                    title: AppLanguage.text("远程检测超时", "Remote Check Timeout"),
                    subtitle: AppLanguage.text("超过时间后停止后台 Fetch 并提示原因。", "Stop background Fetch and explain the reason after this timeout.")
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $remoteTimeoutSeconds, in: 5...120, step: 5)
                        Text(AppLanguage.text("\(Int(remoteTimeoutSeconds)) 秒", "\(Int(remoteTimeoutSeconds))s"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(OrbitDesign.secondaryText)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .frame(width: 280)
                }

                HStack(spacing: 10) {
                    Button(notificationPermission == .denied
                           ? AppLanguage.text("前往系统设置允许通知", "Allow Notifications in System Settings")
                           : AppLanguage.text("打开 macOS 通知设置", "Open macOS Notification Settings")) {
                        openNotificationSettings()
                    }
                    .buttonStyle(.bordered)

                    if notificationPermission == .allowed || notificationPermission == .limited {
                        Button(AppLanguage.text("发送测试通知", "Send Test Notification")) {
                            Task {
                                do { try await RemoteUpdateNotifier.sendTestNotification() }
                                catch { notificationPermissionMessage = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var gitPane: some View {
        settingsPanel(
            title: AppLanguage.text("Git 与诊断", "Git & Diagnostics"),
            subtitle: AppLanguage.text("保留系统 Git 兼容性，并集中查看性能、缓存和慢操作。", "Keep system Git compatibility and inspect performance, caches, and slow operations."),
            systemName: "arrow.triangle.branch"
        ) {
            LabeledContent(AppLanguage.text("Git 程序", "Git Binary"), value: "/usr/bin/git")
            Text(AppLanguage.text(
                "GitIgnore 使用系统 Git，以兼容现有 SSH、GPG、Credential Helper、Hooks 和 LFS 配置。",
                "GitIgnore uses system Git to stay compatible with existing SSH, GPG, Credential Helper, Hooks, and LFS configuration."
            ))
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            Button(AppLanguage.text("查看性能诊断…", "View Performance Diagnostics…"), systemImage: "gauge.with.dots.needle.67percent") {
                showsPerformanceDiagnostics = true
            }
            .buttonStyle(.borderedProminent)

            Text(AppLanguage.text("默认提交模板", "Default commit template"))
                .orbitFont(.caption, weight: .semibold)
            TextEditor(text: $commitTemplate)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 120)
                .padding(6)
                .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
            Text(AppLanguage.text("保存后会作为提交编辑器的默认正文模板。", "Used as the default commit body template."))
                .orbitFont(.caption2)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
    }

    private var footerPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLanguage.text("实时预览", "Live Preview"))
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
            HStack(alignment: .center, spacing: 10) {
                SidebarFooterIcon(size: 30)
                Text(footerDisplayMessage)
                    .orbitFont(.caption, weight: .medium)
                    .lineSpacing(2)
                    .lineLimit(footerWraps ? footerMaxLines : 1)
                Spacer()
                CurrentUserAvatarView(size: 30)
            }
            .padding(12)
            .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitDesign.separator, lineWidth: 1) }
            .opacity(footerEnabled ? 1 : 0.45)
        }
    }

    private var notificationPermissionColor: Color {
        switch notificationPermission {
        case .allowed, .limited: OrbitDesign.accent
        case .denied: OrbitDesign.coral
        case .notRequested: OrbitDesign.amber
        }
    }

    private func requestNotificationPermission() async {
        isRequestingNotificationPermission = true
        defer { isRequestingNotificationPermission = false }
        do {
            let allowed = try await RemoteUpdateNotifier.requestAuthorization()
            notificationPermission = await RemoteUpdateNotifier.permissionState()
            if !allowed || notificationPermission == .notRequested {
                notificationPermissionMessage = AppLanguage.text(
                    "macOS 没有完成通知授权。请在系统设置的“通知”中允许 GitIgnore；如果列表中仍未出现，需要使用 Apple Development 证书重新签名应用。",
                    "macOS did not grant notification permission. Allow GitIgnore in System Settings > Notifications. If it still does not appear, sign the app with an Apple Development certificate."
                )
            }
        } catch {
            notificationPermission = await RemoteUpdateNotifier.permissionState()
            notificationPermissionMessage = error.localizedDescription
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func fontPicker(title: String, selection: Binding<String>, systemTitle: String) -> some View {
        Picker(title, selection: selection) {
            Text(systemTitle).tag("")
            ForEach(fontFamilies, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func settingsPanel<Content: View>(
        title: String,
        subtitle: String,
        systemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemName)
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.accent)
                    .frame(width: 28, height: 28)
                    .background(OrbitDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).orbitFont(.headline, weight: .semibold)
                    Text(subtitle)
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(OrbitPanelBackground(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func controlRow<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .orbitFont(.callout, weight: .medium)
                    .foregroundStyle(OrbitDesign.primaryText)
                Text(subtitle)
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            control()
        }
        .padding(.vertical, 3)
    }

    private func appIconButton(_ choice: AppIconChoice) -> some View {
        let isSelected = appIconChoice == choice.rawValue
        return Button {
            guard !isSelected else { return }
            withAnimation(OrbitMotion.page(reduceMotion: reduceMotion)) {
                appIconChoice = choice.rawValue
            }
            AppIconController.apply(
                rawValue: choice.rawValue,
                persistToBundle: true,
                refreshSystemCaches: true
            )
        } label: {
            VStack(spacing: 7) {
                Image(choice.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(isSelected ? OrbitDesign.accent.opacity(0.68) : OrbitDesign.separator, lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .orbitFont(.caption, weight: .semibold)
                                .foregroundStyle(.white, OrbitDesign.accent)
                                .background(Circle().fill(OrbitDesign.canvas).padding(1))
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
                        }
                    }
                Text(choice.title)
                    .orbitFont(.caption2, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? OrbitDesign.primaryText : OrbitDesign.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? OrbitDesign.selectionFill : OrbitDesign.recessedSurface.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(choice.title)
    }

    private func iconCollection(title: String, subtitle: String, choices: [AppIconChoice]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).orbitFont(.subheadline, weight: .semibold)
                Text(subtitle).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(choices) { choice in
                    appIconButton(choice)
                }
            }
        }
    }

    private var footerDisplayMessage: String {
        let value = footerMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty
            ? AppLanguage.text("保持专注，让每次提交都有意义。", "Stay focused. Make every commit meaningful.")
            : value
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case profile
    case icon
    case appearance
    case fonts
    case sidebar
    case remote
    case git

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: AppLanguage.text("个人资料", "Profile")
        case .icon: AppLanguage.text("应用图标", "App Icon")
        case .appearance: AppLanguage.text("外观与语言", "Appearance & Language")
        case .fonts: AppLanguage.text("字体", "Fonts")
        case .sidebar: AppLanguage.text("侧栏", "Sidebar")
        case .remote: AppLanguage.text("远程与通知", "Remote & Notifications")
        case .git: AppLanguage.text("Git 与诊断", "Git & Diagnostics")
        }
    }

    var subtitle: String {
        switch self {
        case .profile: AppLanguage.text("名称、头像和身份展示。", "Name, avatar, and identity display.")
        case .icon: AppLanguage.text("选择全局应用图标。", "Choose the global app icon.")
        case .appearance: AppLanguage.text("主题、语言、密度和材质。", "Theme, language, density, and material.")
        case .fonts: AppLanguage.text("分别设置英文和中文字体。", "Set Latin and CJK fonts separately.")
        case .sidebar: AppLanguage.text("侧栏签名、文案和图标。", "Sidebar footer copy and icon.")
        case .remote: AppLanguage.text("远程协作、检测超时和系统通知。", "Remote collaboration, timeout, and notifications.")
        case .git: AppLanguage.text("Git 运行环境和性能诊断。", "Git runtime and performance diagnostics.")
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .icon: "app.dashed"
        case .appearance: "circle.lefthalf.filled"
        case .fonts: "textformat"
        case .sidebar: "sidebar.left"
        case .remote: "bell.badge"
        case .git: "arrow.triangle.branch"
        }
    }

    var tint: Color {
        switch self {
        case .profile: OrbitDesign.accent
        case .icon: OrbitDesign.violet
        case .appearance: OrbitDesign.blue
        case .fonts: OrbitDesign.accentSoft
        case .sidebar: OrbitDesign.amber
        case .remote: OrbitDesign.coral
        case .git: OrbitDesign.secondaryText
        }
    }
}

private struct SettingsSidebarButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(isSelected ? OrbitDesign.accent : OrbitDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(isSelected ? OrbitDesign.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))

                Text(pane.title)
                    .orbitFont(.caption, weight: isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? OrbitDesign.primaryText : OrbitDesign.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                isSelected ? OrbitDesign.selectionFill : (isHovering ? OrbitDesign.hoverFill.opacity(0.68) : .clear),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? OrbitDesign.accent.opacity(0.24) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(OrbitMotion.page(reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .padding(.horizontal, 10)
    }
}
