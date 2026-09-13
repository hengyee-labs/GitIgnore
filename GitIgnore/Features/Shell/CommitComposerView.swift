import SwiftUI

struct CommitComposerView: View {
    @Environment(AppState.self) private var appState
    let stagedCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var type: CommitType = .feature
    @State private var scope = ""
    @State private var summary = ""
    @State private var bodyText = ""
    @State private var isBreakingChange = false
    @State private var showsBody = false
    @State private var amend = false
    @State private var signOff = false
    @State private var breakingDescription = ""
    @State private var issueReference = ""
    @State private var coAuthor = ""
    @State private var forceExpanded = false
    @State private var showsAdvanced = true
    @AppStorage("gitignore.commit.scopeHistory") private var scopeHistoryData = ""
    @AppStorage("gitignore.commit.coauthorHistory") private var coauthorHistoryData = ""

    private var finalMessage: String {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopePart = normalizedScope.isEmpty ? "" : "(\(normalizedScope))"
        let breakingPart = isBreakingChange ? "!" : ""
        let subject = "\(type.code)\(scopePart)\(breakingPart): \(normalizedSummary)"
        var sections: [String] = [subject]
        let normalizedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedBody.isEmpty { sections.append(normalizedBody) }
        let breaking = breakingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBreakingChange && !breaking.isEmpty { sections.append("BREAKING CHANGE: \(breaking)") }
        let issue = issueReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if !issue.isEmpty { sections.append("Refs: \(issue)") }
        let author = coAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty { sections.append("Co-authored-by: \(author)") }
        return sections.joined(separator: "\n\n")
    }

    private var canCommit: Bool {
        (stagedCount > 0 || amend)
            && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isPerformingGitAction
    }

    private var conventionHint: String? {
        let value = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.count > 72 { return AppLanguage.text("建议将摘要控制在 72 个字符以内", "Keep the summary within 72 characters") }
        if value.contains("\n") { return AppLanguage.text("摘要不应包含换行", "Summary should stay on one line") }
        return nil
    }

    var body: some View {
        ZStack {
            if stagedCount == 0 && !amend && !forceExpanded {
                collapsedComposer
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else {
                expandedComposer
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18), value: stagedCount == 0 && !amend && !forceExpanded)
    }

    private var expandedComposer: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Label("创建提交", systemImage: "checkmark.seal")
                    .orbitFont(.headline)
                Text("\(stagedCount) 个文件")
                    .orbitFont(.caption, weight: .semibold)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.16), value: stagedCount)
                    .foregroundStyle(OrbitDesign.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OrbitDesign.accent.opacity(0.11), in: Capsule())
                Spacer()
                identityView
            }

            HStack(spacing: 9) {
                Menu {
                    ForEach(CommitType.allCases) { item in
                        Button {
                            type = item
                        } label: {
                            Label("\(item.title) · \(item.code)", systemImage: item.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: type.symbol)
                        Text(type.title)
                        Text(type.code)
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(OrbitDesign.accent)
                        Image(systemName: "chevron.up.chevron.down")
                            .orbitFont(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if showsAdvanced {
                    TextField("影响范围（可选）", text: $scope)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }

                    if !scopeHistory.isEmpty {
                        Menu {
                            ForEach(scopeHistory, id: \.self) { value in
                                Button(value) { scope = value }
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .frame(width: 28, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .help("最近使用的影响范围")
                    }

                    Toggle(isOn: $isBreakingChange) {
                        Text("不兼容变更")
                            .orbitFont(.caption, weight: .semibold)
                    }
                    .toggleStyle(.checkbox)
                    .fixedSize()
                }
            }

            if showsAdvanced {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(CommitTemplate.allCases) { template in
                            Button(template.title, systemImage: template.symbol) { apply(template) }
                        }
                        if !appState.recentCommitMessages.isEmpty {
                            Divider()
                            ForEach(appState.recentCommitMessages, id: \.self) { message in
                                Button(message.components(separatedBy: "\n").first ?? message) { applyRecent(message) }
                            }
                        }
                    } label: {
                        Label("模板与最近记录", systemImage: "text.badge.star")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Toggle("Amend 最近提交", isOn: $amend)
                        .toggleStyle(.checkbox)
                    Toggle("追加 Sign-off", isOn: $signOff)
                        .toggleStyle(.checkbox)
                    Spacer()
                    if amend {
                        Label("Amend 会替换最近一次提交", systemImage: "exclamationmark.triangle")
                            .orbitFont(.caption2)
                            .foregroundStyle(OrbitDesign.amber)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .orbitFont(.caption, weight: .semibold)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            TextField("简要说明本次变更…", text: $summary)
                .textFieldStyle(.plain)
                .orbitFont(.callout, weight: .medium)
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(summary.isEmpty ? OrbitDesign.separator : OrbitDesign.accent.opacity(0.45), lineWidth: 1)
                }

            if let conventionHint {
                Label(conventionHint, systemImage: "info.circle")
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if showsBody {
                VStack(spacing: 8) {
                    TextEditor(text: $bodyText)
                        .orbitFont(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 52, maxHeight: 70)
                        .padding(7)
                        .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
                    HStack(spacing: 8) {
                        if isBreakingChange {
                            compactField("不兼容变更说明", text: $breakingDescription)
                        }
                        compactField("Issue，如 #123", text: $issueReference)
                        compactField("协作者 Name <email>", text: $coAuthor)
                        if !coauthorHistory.isEmpty {
                            Menu {
                                ForEach(coauthorHistory, id: \.self) { value in
                                    Button(value) { coAuthor = value }
                                }
                            } label: { Image(systemName: "person.2") }
                            .menuStyle(.borderlessButton)
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.16)) {
                        showsAdvanced.toggle()
                    }
                } label: {
                    Label(showsAdvanced ? "收起高级选项" : "更多选项", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(showsAdvanced ? OrbitDesign.accent : OrbitDesign.secondaryText)

                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.86)) {
                        showsBody.toggle()
                    }
                } label: {
                    Label(showsBody ? "收起正文" : "添加正文", systemImage: showsBody ? "chevron.up" : "text.alignleft")
                }
                .buttonStyle(.plain)
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)

                if !summary.isEmpty {
                    Text(finalMessage.components(separatedBy: "\n").first ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .lineLimit(1)
                        .transition(.opacity)
                }

                Spacer()
                Text("⌘↩")
                    .font(.caption2.monospaced())
                    .foregroundStyle(OrbitDesign.secondaryText)

                Button {
                    submit()
                } label: {
                    Label(
                        appState.isPerformingGitAction ? "正在创建…" : (amend ? "更新最近提交" : "提交 \(stagedCount) 个文件"),
                        systemImage: amend ? "arrow.triangle.2.circlepath" : "checkmark"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(OrbitDesign.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(OrbitDesign.separator).frame(height: 1) }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18), value: summary.isEmpty)
    }

    private var collapsedComposer: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .foregroundStyle(OrbitDesign.secondaryText)
                .frame(width: 30, height: 30)
                .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("暂存文件后即可创建提交")
                    .orbitFont(.caption, weight: .semibold)
                Text("提交编排器会在需要时展开，不占用文件审阅空间。")
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer(minLength: 12)
            Button("Amend 最近提交…") {
                amend = true
                forceExpanded = true
                showsAdvanced = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("展开编排器") {
                forceExpanded = true
            }
            .buttonStyle(.plain)
            .orbitFont(.caption, weight: .semibold)
            .foregroundStyle(OrbitDesign.accent)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .background(OrbitDesign.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(OrbitDesign.separator).frame(height: 1) }
    }

    private var identityView: some View {
        HStack(spacing: 7) {
            CurrentUserAvatarView(size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.gitIdentity.displayName)
                    .orbitFont(.caption, weight: .semibold)
                Text(appState.gitIdentity.detail)
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .lineLimit(1)
            }
        }
        .help("本次提交使用的本机 Git 身份")
    }

    private func submit() {
        let message = finalMessage
        Task {
            await appState.commit(message: message, amend: amend, signOff: signOff)
            guard appState.errorMessage == nil else { return }
            rememberMetadata()
            summary = ""
            bodyText = ""
            scope = ""
            isBreakingChange = false
            amend = false
            signOff = false
            breakingDescription = ""
            issueReference = ""
            coAuthor = ""
        }
    }

    private var scopeHistory: [String] {
        scopeHistoryData.split(separator: "\u{1f}").map(String.init)
    }

    private var coauthorHistory: [String] {
        coauthorHistoryData.split(separator: "\u{1f}").map(String.init)
    }

    private func compactField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .orbitFont(.caption)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func rememberMetadata() {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedScope.isEmpty {
            var values = scopeHistory.filter { $0 != normalizedScope }
            values.insert(normalizedScope, at: 0)
            scopeHistoryData = values.prefix(10).joined(separator: "\u{1f}")
        }
        let normalizedAuthor = coAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedAuthor.isEmpty {
            var values = coauthorHistory.filter { $0 != normalizedAuthor }
            values.insert(normalizedAuthor, at: 0)
            coauthorHistoryData = values.prefix(8).joined(separator: "\u{1f}")
        }
    }

    private func apply(_ template: CommitTemplate) {
        type = template.type
        scope = template.scope
        summary = template.summary
        bodyText = template.body
        showsBody = !template.body.isEmpty
    }

    private func applyRecent(_ message: String) {
        let components = message.components(separatedBy: "\n\n")
        let subject = components.first ?? message
        bodyText = components.dropFirst().joined(separator: "\n\n")
        showsBody = !bodyText.isEmpty
        guard let separator = subject.range(of: ": ") else {
            summary = subject
            return
        }
        let prefix = String(subject[..<separator.lowerBound])
        summary = String(subject[separator.upperBound...])
        isBreakingChange = prefix.hasSuffix("!")
        let cleanPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "!"))
        if let open = cleanPrefix.firstIndex(of: "("), let close = cleanPrefix.lastIndex(of: ")"), open < close {
            scope = String(cleanPrefix[cleanPrefix.index(after: open)..<close])
            type = CommitType.allCases.first { $0.code == String(cleanPrefix[..<open]) } ?? type
        } else {
            scope = ""
            type = CommitType.allCases.first { $0.code == cleanPrefix } ?? type
        }
    }
}

private enum CommitTemplate: String, CaseIterable, Identifiable {
    case feature
    case bugFix
    case performance
    case refactor
    case documentation

    var id: Self { self }
    var title: String {
        switch self {
        case .feature: "新功能模板"
        case .bugFix: "缺陷修复模板"
        case .performance: "性能优化模板"
        case .refactor: "重构模板"
        case .documentation: "文档模板"
        }
    }
    var type: CommitType {
        switch self {
        case .feature: .feature
        case .bugFix: .fix
        case .performance: .performance
        case .refactor: .refactor
        case .documentation: .documentation
        }
    }
    var scope: String { "" }
    var summary: String { "" }
    var body: String {
        switch self {
        case .bugFix: "问题原因：\n\n处理方式："
        case .performance: "性能瓶颈：\n\n优化结果："
        case .refactor: "调整范围：\n\n行为保持："
        case .feature: "功能说明：\n\n验证方式："
        case .documentation: "更新内容："
        }
    }
    var symbol: String { type.symbol }
}

private enum CommitType: String, CaseIterable, Identifiable {
    case feature
    case fix
    case refactor
    case performance
    case documentation
    case test
    case build
    case integration
    case maintenance
    case revert
    case workInProgress

    var id: Self { self }

    var code: String {
        switch self {
        case .feature: "feat"
        case .fix: "fix"
        case .refactor: "refactor"
        case .performance: "perf"
        case .documentation: "docs"
        case .test: "test"
        case .build: "build"
        case .integration: "ci"
        case .maintenance: "chore"
        case .revert: "revert"
        case .workInProgress: "wip"
        }
    }

    var title: String {
        switch self {
        case .feature: "功能"
        case .fix: "修复"
        case .refactor: "重构"
        case .performance: "性能"
        case .documentation: "文档"
        case .test: "测试"
        case .build: "构建"
        case .integration: "持续集成"
        case .maintenance: "维护"
        case .revert: "回滚"
        case .workInProgress: "进行中"
        }
    }

    var symbol: String {
        switch self {
        case .feature: "sparkles"
        case .fix: "wrench.and.screwdriver"
        case .refactor: "arrow.triangle.2.circlepath"
        case .performance: "gauge.with.dots.needle.67percent"
        case .documentation: "doc.text"
        case .test: "checkmark.circle"
        case .build: "shippingbox"
        case .integration: "gearshape.2"
        case .maintenance: "hammer"
        case .revert: "arrow.uturn.backward"
        case .workInProgress: "clock"
        }
    }
}
