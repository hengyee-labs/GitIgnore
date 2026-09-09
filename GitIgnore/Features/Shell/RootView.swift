import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("orbit.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("orbit.uiFontLatin") private var uiFontLatin = ""
    @AppStorage("orbit.uiFontCJK") private var uiFontCJK = ""
    @AppStorage("orbit.uiFontSize") private var uiFontSize = 13.0
    @AppStorage("orbit.sidebarWidth") private var sidebarWidth = 282.0
    @AppStorage("orbit.sidebarCollapsed") private var isSidebarCollapsed = true
    @AppStorage("orbit.inspectorWidth") private var inspectorWidth = 460.0
    @State private var appearancePresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fontPalette: OrbitFontPalette {
        OrbitFontPalette(latin: uiFontLatin, cjk: uiFontCJK, baseSize: uiFontSize)
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppAppearance(rawValue: appearanceRawValue) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var shouldShowInspector: Bool {
        guard !appState.isDiffFocusPresented else { return false }
        switch appState.selectedSection {
        case .changes:
            guard let file = appState.selectedFile else { return false }
            if file.hasConflict { return true }
            if file.path.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") { return false }
            return appState.isLoadingDiff || appState.selectedFileDiff != nil
        case .history:
            return appState.selectedCommit != nil
        default:
            return false
        }
    }

    var body: some View {
        @Bindable var state = appState

        GeometryReader { geometry in
            shell(width: geometry.size.width, selection: $state.selectedSection)
                .onChange(of: geometry.size.width) { _, width in
                    if width < 980, !isSidebarCollapsed {
                        withAnimation(OrbitMotion.inspector(reduceMotion: reduceMotion)) {
                            isSidebarCollapsed = true
                        }
                    }
                }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background { OrbitWindowBackdrop() }
        .tint(OrbitDesign.accent)
        .environment(\.orbitFontPalette, fontPalette)
        .font(fontPalette.font(.body))
        .preferredColorScheme(preferredColorScheme)
        .frame(minWidth: 860, minHeight: 640)
        .task {
            inspectorWidth = min(max(inspectorWidth, 360), 640)
            if uiFontLatin.isEmpty, let legacyFont = UserDefaults.standard.string(forKey: "orbit.uiFontFamily"), !legacyFont.isEmpty {
                uiFontLatin = legacyFont
            }
            await OrbitTypography.activateConfiguredFamilies(latin: uiFontLatin, cjk: uiFontCJK)
            await appState.loadEnvironment()
        }
        .onChange(of: appState.feedback?.id) { _, _ in
            announceFeedbackIfNeeded()
        }
        .onChange(of: uiFontLatin) { _, _ in
            Task { await OrbitTypography.activateConfiguredFamilies(latin: uiFontLatin, cjk: uiFontCJK) }
        }
        .onChange(of: uiFontCJK) { _, _ in
            Task { await OrbitTypography.activateConfiguredFamilies(latin: uiFontLatin, cjk: uiFontCJK) }
        }
        .overlay(alignment: .bottomTrailing) {
            feedbackOverlay
        }
        .overlay(alignment: .top) {
            if appState.isLoadingRepository || appState.isPerformingGitAction {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(OrbitDesign.accent)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $state.isCommandPalettePresented) {
            CommandPaletteView()
                .environment(appState)
                .presentationBackground(OrbitDesign.canvas)
        }
        .sheet(item: $state.safePullRequest) { request in
            SafePullSheet(request: request)
                .environment(appState)
                .presentationBackground(OrbitDesign.canvas)
        }
        .sheet(item: $state.workflows.safeBranchSwitchRequest) { request in
            SafeBranchSwitchSheet(request: request)
                .environment(appState)
                .presentationBackground(OrbitDesign.canvas)
        }
        .sheet(item: $state.workflows.safeOperationRequest) { request in
            SafeOperationSheet(request: request)
                .environment(appState)
                .presentationBackground(OrbitDesign.canvas)
        }
        .sheet(item: $state.presentedConflictFile) { file in
            MergeEditorView(file: file)
                .environment(appState)
                .presentationBackground(OrbitDesign.canvas)
        }
    }

    private func shell(width: CGFloat, selection: Binding<SidebarSection>) -> some View {
        let maximumInspectorWidth = min(640.0, max(360.0, Double(width) * 0.44))
        return HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView(selection: selection)
                    .frame(width: sidebarWidth)
                WorkspaceResizeHandle(width: $sidebarWidth, limits: 230...360, direction: .increasing)
            }

            VStack(spacing: 0) {
                RepositoryToolbar(
                    isSidebarCollapsed: $isSidebarCollapsed,
                    appearancePresented: $appearancePresented,
                    appearanceRawValue: appearanceRawValue
                )
                Divider().overlay(OrbitDesign.separator)

                HStack(spacing: 0) {
                    contentHost
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    WorkspaceResizeHandle(width: $inspectorWidth, limits: 360...maximumInspectorWidth, direction: .decreasing)
                        .frame(width: shouldShowInspector ? 6 : 0)
                        .opacity(shouldShowInspector ? 1 : 0)
                        .allowsHitTesting(shouldShowInspector)

                    InspectorView()
                        .frame(width: inspectorWidth)
                        .frame(width: shouldShowInspector ? inspectorWidth : 0, alignment: .trailing)
                        .clipped()
                        .opacity(shouldShowInspector ? 1 : 0)
                        .offset(x: shouldShowInspector || reduceMotion ? 0 : 8)
                        .allowsHitTesting(shouldShowInspector)
                        .accessibilityHidden(!shouldShowInspector)
                }
                .animation(OrbitMotion.inspector(reduceMotion: reduceMotion), value: shouldShowInspector)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var feedbackOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            if let feedback = appState.feedback {
                FeedbackCard(feedback: feedback) { appState.clearFeedback() }
                    .padding(22)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    .task(id: feedback.id) {
                        guard feedback.kind != .failure else { return }
                        try? await Task.sleep(for: .seconds(3.2))
                        appState.clearFeedback()
                    }
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86),
            value: appState.feedback?.id
        )
    }

    private func announceFeedbackIfNeeded() {
        guard let feedback = appState.feedback, let application = NSApp else { return }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(feedback.title)。\(feedback.message)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    @ViewBuilder
    private var contentHost: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if appState.isDiffFocusPresented {
                    DiffFocusView()
                } else {
                    selectedContent
                }
            }
                .id(appState.isDiffFocusPresented ? "diff-focus" : "section-\(appState.selectedSection)")
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 7)),
                            removal: .opacity
                        )
                )
        }
        .animation(OrbitMotion.page(reduceMotion: reduceMotion), value: appState.selectedSection)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewView()
        case .changes:
            ChangesView()
        case .history:
            HistoryView()
        case .branches:
            BranchesView()
        case .stashes:
            StashesView()
        case .worktrees:
            WorktreesView()
        case .pullRequests, .issues:
            RemoteResourceView(section: appState.selectedSection)
        }
    }
}

private struct DiffFocusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = ReviewMode.reader

    var body: some View {
        VStack(spacing: 0) {
            focusHeader
            Divider().overlay(OrbitDesign.separator)
            focusContent
        }
        .background(OrbitDesign.canvas)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 8)))
    }

    private var focusHeader: some View {
        HStack(spacing: 12) {
            Button {
                appState.dismissDiffFocus()
            } label: {
                Label(AppLanguage.text("返回列表", "Back to List"), systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)

            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(OrbitDesign.accent)
                .frame(width: 28, height: 28)
                .background(OrbitDesign.selectionFill, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .orbitFont(.headline)
                    .lineLimit(1)
                Text(filePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if appState.selectedFile != nil {
                Picker(AppLanguage.text("查看方式", "Review Mode"), selection: $mode) {
                    ForEach(ReviewMode.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(OrbitDesign.surface)
    }

    @ViewBuilder
    private var focusContent: some View {
        if let file = appState.selectedFile, let diff = appState.selectedFileDiff {
            if diff.supportsInlinePreview {
                if mode == .reader {
                    OrbitDiffViewer(diff: diff, title: AppLanguage.text("工作区变更", "Workspace Diff"), expandsVertically: true)
                        .padding(14)
                } else {
                    ScrollView {
                        HunkDiffView(diff: diff, file: file)
                            .padding(16)
                    }
                }
            } else {
                SpecialDiffStateView(diff: diff)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if let diff = appState.selectedCommitFileDiff {
            OrbitDiffViewer(diff: diff, title: AppLanguage.text("提交文件变更", "Commit File Diff"), expandsVertically: true)
                .padding(14)
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(AppLanguage.text("正在准备 Diff…", "Preparing Diff…"))
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filePath: String {
        appState.selectedFile?.path ?? appState.selectedCommitFilePath ?? ""
    }

    private var fileName: String {
        let value = (filePath as NSString).lastPathComponent
        return value.isEmpty ? AppLanguage.text("文件变更", "File Diff") : value
    }

    private enum ReviewMode: String, CaseIterable, Identifiable {
        case reader
        case actions
        var id: Self { self }
        var title: String { self == .reader ? AppLanguage.text("阅读", "Read") : AppLanguage.text("区块操作", "Hunks") }
        var symbol: String { self == .reader ? "doc.text.magnifyingglass" : "square.stack.3d.up" }
    }
}

struct AppearancePopover: View {
    @AppStorage("orbit.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(OrbitGlassPreferences.storageKey) private var glassEffectsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLanguage.text("外观与字体", "Appearance & Fonts"))
                .orbitFont(.headline)

            Picker(AppLanguage.text("主题", "Theme"), selection: $appearanceRawValue) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle(AppLanguage.text("原生窗口材质", "Native window material"), isOn: $glassEffectsEnabled)
                .toggleStyle(.switch)
            Text(AppLanguage.text("仅在窗口边缘、侧栏和工具栏使用轻量 macOS 材质，内容区保持清晰实体背景。", "Use lightweight macOS material only on window chrome, sidebar, and toolbar. Content stays clear and solid."))
                .orbitFont(.caption2)
                .foregroundStyle(OrbitDesign.secondaryText)

            Divider()
            Text(AppLanguage.text("字体支持分别设置拉丁字母和中日韩文字，并在完整设置中预览。", "Fonts can be configured separately for Latin and CJK scripts in Settings."))
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
            SettingsLink {
                Text(AppLanguage.text("打开字体与偏好设置…", "Open font and preference settings…"))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(width: 300)
    }
}

private struct InspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.selectedSection {
            case .changes:
                if let file = appState.selectedFile {
                    FileInspector(file: file)
                } else {
                    ContextInspector()
                }
            case .history:
                if let commit = appState.selectedCommit {
                    CommitInspector(commit: commit)
                        .id(commit.id)
                } else {
                    ContextInspector()
                }
            default:
                ContextInspector()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitDesign.canvas)
        .overlay(alignment: .topTrailing) {
            Button {
                appState.dismissInspector()
            } label: {
                Image(systemName: "chevron.right")
                    .orbitFont(.caption2, weight: .bold)
                    .frame(width: 28, height: 28)
                    .background(OrbitDesign.surface, in: Circle())
                    .overlay { Circle().stroke(OrbitDesign.separator, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(OrbitDesign.secondaryText)
            .help(AppLanguage.text("收起右侧预览", "Hide inspector"))
            .padding(12)
        }
    }
}

@MainActor
func inspectorEyebrow(_ title: String) -> some View {
    Text(title)
        .orbitFont(.caption2, weight: .bold)
        .tracking(1.2)
        .foregroundStyle(OrbitDesign.accent)
}

@MainActor
func detailRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title.uppercased())
            .orbitFont(.caption2, weight: .bold)
            .tracking(0.8)
            .foregroundStyle(OrbitDesign.secondaryText)
        Group {
            if monospaced {
                Text(value).font(.caption.monospaced())
            } else {
                Text(value).orbitFont(.caption)
            }
        }
        .foregroundStyle(OrbitDesign.primaryText)
        .textSelection(.enabled)
        .lineLimit(3)
    }
}

private struct FeedbackCard: View {
    let feedback: AppFeedback
    let dismiss: () -> Void
    @State private var showsDiagnostics = false

    private var color: Color {
        switch feedback.kind {
        case .success: OrbitDesign.accent
        case .warning: OrbitDesign.amber
        case .failure: OrbitDesign.coral
        }
    }

    private var symbol: String {
        switch feedback.kind {
        case .success: "checkmark"
        case .warning: "exclamationmark"
        case .failure: "xmark"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OrbitIconBadge(systemName: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title).orbitFont(.caption, weight: .bold)
                Text(feedback.message)
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let details = feedback.technicalDetails {
                    HStack(spacing: 12) {
                            Button(AppLanguage.text("查看诊断信息", "View Diagnostics")) { showsDiagnostics = true }
                            Button(AppLanguage.text("复制诊断信息", "Copy Diagnostics")) { copy(details) }
                    }
                    .buttonStyle(.plain)
                    .orbitFont(.caption2, weight: .semibold)
                    .foregroundStyle(color)
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 6)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .orbitFont(.caption2, weight: .bold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(AppLanguage.text("关闭", "Close"))
        }
        .padding(12)
        .frame(minWidth: 270, maxWidth: 360, alignment: .leading)
        .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.42), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 5)
        .sheet(isPresented: $showsDiagnostics) {
            DiagnosticDetailsView(feedback: feedback)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct DiagnosticDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let feedback: AppFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                OrbitIconBadge(systemName: "stethoscope", color: OrbitDesign.coral, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguage.text("诊断信息", "Diagnostics")).orbitFont(.title3, weight: .bold)
                    Text(feedback.title).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                Button(AppLanguage.text("关闭", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }

            Text(feedback.message)
                .orbitFont(.callout)
                .textSelection(.enabled)

            ScrollView {
                Text(feedback.technicalDetails ?? AppLanguage.text("没有更多诊断信息。", "No additional diagnostics."))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }

            HStack {
                Spacer()
                Button(AppLanguage.text("复制诊断信息", "Copy Diagnostics")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(feedback.technicalDetails ?? feedback.message, forType: .string)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 680, height: 460)
        .background(OrbitDesign.canvas)
    }
}

private struct FeaturePlaceholderView: View {
    let section: SidebarSection

    var body: some View {
        VStack(spacing: 18) {
            OrbitIconBadge(systemName: section.symbol, color: OrbitDesign.violet, size: 54)
            VStack(spacing: 6) {
                Text(section.title)
                    .orbitFont(.title2, weight: .bold)
                Text(AppLanguage.text("这个模块会在接入真实 Git 数据后展开。", "This module expands when real Git data is available."))
                    .orbitFont(.subheadline)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitDesign.canvas)
        .navigationTitle(section.title)
    }
}
