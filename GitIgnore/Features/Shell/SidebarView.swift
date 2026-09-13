import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: SidebarSection
    @State private var hoveredSection: SidebarSection?
    @State private var repositoryHeaderHovered = false
    @State private var recentSearch = ""
    @AppStorage("orbit.sidebarFooter.enabled") private var footerEnabled = true
    @AppStorage("orbit.sidebarFooter.message") private var footerMessage = "保持专注，\n让每次提交都有意义。"
    @AppStorage("orbit.sidebarFooter.wraps") private var footerWraps = true
    @AppStorage("orbit.sidebarFooter.maxLines") private var footerMaxLines = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    repositoryHeader
                    navigationContent
                }
                .padding(.horizontal, 12)
                .padding(.top, 44)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background { OrbitChromeBackground(region: .sidebar) }
    }

    private var repositoryHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                repoMark
                VStack(alignment: .leading, spacing: 5) {
                    Text(appState.repository?.name ?? "选择仓库")
                        .orbitFont(.subheadline, weight: .semibold)
                        .foregroundStyle(OrbitDesign.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(appState.repository?.name ?? "选择仓库")

                    if let repository = appState.repository {
                        HStack(spacing: 7) {
                            Label(repository.branch, systemImage: "arrow.triangle.branch")
                                .foregroundStyle(OrbitDesign.violet)
                                .lineLimit(1)
                            if repository.behindCount > 0 {
                                Label("\(repository.behindCount)", systemImage: "arrow.down.circle.fill")
                                    .foregroundStyle(OrbitDesign.amber)
                                    .contentTransition(.numericText())
                            }
                        }
                        .orbitFont(.caption2, weight: .semibold)
                    } else {
                        Text("打开本地 Git 仓库")
                            .orbitFont(.caption2)
                            .foregroundStyle(OrbitDesign.secondaryText)
                    }
                }
                Spacer(minLength: 4)
                repositoryMenu
            }

            if let repository = appState.repository {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .padding(.top, 2)
                    Text(repository.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OrbitDesign.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(OrbitDesign.panelBorder.opacity(0.34), lineWidth: 0.5)
                }
                .help(repository.path)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(repositoryHeaderHovered ? OrbitDesign.hoverFill.opacity(0.7) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onHover { repositoryHeaderHovered = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.12), value: repositoryHeaderHovered)
    }

    private var repositoryMenu: some View {
        Menu {
            Button("选择其他仓库…", systemImage: "folder.badge.plus") {
                appState.chooseRepository()
            }
            if !appState.recentRepositories.isEmpty {
                Divider()
                Text("最近打开的项目")
                if appState.recentRepositories.count > 5 {
                    TextField("搜索项目…", text: $recentSearch)
                }
                ForEach(filteredRecentRepositories) { recent in
                    Button {
                        appState.openRecentRepository(recent)
                    } label: {
                        Label {
                            Text(recent.name)
                        } icon: {
                            Image(systemName: appState.repository?.path == recent.path ? "checkmark.circle.fill" : "folder")
                        }
                    }
                }
                Divider()
                Menu("管理最近项目") {
                    ForEach(appState.recentRepositories) { recent in
                        Button {
                            togglePinned(recent)
                        } label: {
                            Label(
                                isPinned(recent) ? "取消固定 \(recent.name)" : "固定 \(recent.name)",
                                systemImage: isPinned(recent) ? "pin.slash" : "pin"
                            )
                        }
                        Button("移除 \(recent.name)", systemImage: "xmark") {
                            appState.removeRecentRepository(recent)
                        }
                    }
                    Divider()
                    Button("清空最近项目", systemImage: "trash", role: .destructive) {
                        appState.clearRecentRepositories()
                    }
                }
            }
            if let repository = appState.repository {
                Divider()
                Button(AppLanguage.text("授权项目父目录…", "Authorize Projects Folder…"), systemImage: "folder.badge.person.crop") {
                    appState.authorizeRepositoryParent()
                }
                .disabled(appState.isPerformingGitAction || appState.isLoadingRepository)
                Button("在 Finder 中显示", systemImage: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repository.path)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OrbitDesign.secondaryText)
                .frame(width: 28, height: 28)
                .background(OrbitDesign.primaryText.opacity(0.045), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .help("切换或管理仓库")
    }

    private var filteredRecentRepositories: [RecentRepository] {
        let query = recentSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? appState.recentRepositories
            : appState.recentRepositories.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
            }
        return filtered.sorted { lhs, rhs in
            if isPinned(lhs) != isPinned(rhs) { return isPinned(lhs) }
            return lhs.lastOpened > rhs.lastOpened
        }
    }

    private func isPinned(_ recent: RecentRepository) -> Bool {
        let paths = UserDefaults.standard.stringArray(forKey: "orbit.pinnedRepositories") ?? []
        return paths.contains(recent.path)
    }

    private func togglePinned(_ recent: RecentRepository) {
        var paths = UserDefaults.standard.stringArray(forKey: "orbit.pinnedRepositories") ?? []
        if let index = paths.firstIndex(of: recent.path) { paths.remove(at: index) }
        else { paths.insert(recent.path, at: 0) }
        UserDefaults.standard.set(paths, forKey: "orbit.pinnedRepositories")
    }

    private var repoMark: some View {
        RepositoryIdentityMark(identity: appState.repository?.path ?? "GitIgnore")
    }

    private var navigationContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            navigationSection(title: AppLanguage.text("工作区", "Workspace"), sections: SidebarSection.workspace)
            navigationSection(title: AppLanguage.text("协作", "Collaboration"), sections: SidebarSection.collaboration)
            navigationSection(title: AppLanguage.text("分支资源", "Branch Resources"), sections: SidebarSection.resources)
        }
    }

    @ViewBuilder
    private func navigationSection(title: String, sections: [SidebarSection]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .orbitFont(.caption2, weight: .bold)
                .tracking(0.8)
                .foregroundStyle(OrbitDesign.tertiaryText)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)

            ForEach(sections) { section in
                navigationRow(section)
            }
        }
    }

    private func navigationRow(_ section: SidebarSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .orbitFont(.caption, weight: isSelected ? .semibold : .regular)
                    .frame(width: 18)
                Text(section.title)
                    .orbitFont(.subheadline, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if section == .changes, let repository = appState.repository, repository.changedFileCount > 0 {
                    Text("\(repository.changedFileCount)")
                        .orbitFont(.caption2, weight: .bold)
                        .contentTransition(.numericText())
                        .foregroundStyle(isSelected ? OrbitDesign.accent : OrbitDesign.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(OrbitDesign.accent.opacity(0.12), in: Capsule())
                        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.22), value: repository.changedFileCount)
                }
            }
            .foregroundStyle(isSelected ? OrbitDesign.primaryText : OrbitDesign.secondaryText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? OrbitDesign.selectionFill :
                            (isHovered ? OrbitDesign.hoverFill : .clear))
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(OrbitDesign.accent)
                        .frame(width: 3, height: 17)
                        .offset(x: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hoveredSection = $0 ? section : nil }
        .help(section.title)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.12), value: isSelected)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 9) {
            if footerEnabled {
                SidebarFooterIcon(size: 26)
                Text(footerDisplayMessage)
                    .orbitFont(.caption, weight: .medium)
                    .foregroundStyle(OrbitDesign.primaryText)
                    .lineSpacing(2)
                    .lineLimit(footerWraps ? max(1, min(footerMaxLines, 4)) : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 3)

            CurrentUserAvatarView(size: 30)
                .accessibilityLabel("当前用户头像")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(OrbitDesign.surface.opacity(0.14))
        .overlay(alignment: .top) {
            Rectangle().fill(OrbitDesign.separator).frame(height: 1)
        }
    }

    private var footerDisplayMessage: String {
        let value = footerMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "保持专注，让每次提交都有意义。" : value
    }
}

struct ProfileAvatarView: View {
    let name: String
    let data: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = ProfileImageCache.image(for: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(OrbitTypography.ui(size: size * 0.32, latin: "", cjk: "", weight: .bold))
                    .foregroundStyle(OrbitDesign.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OrbitDesign.accent.opacity(0.22))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private var initials: String {
        let words = name.split(whereSeparator: \ .isWhitespace)
        if words.count > 1 { return String(words.prefix(2).compactMap(\.first)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}

@MainActor
private enum ProfileImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for encodedData: String) -> NSImage? {
        guard !encodedData.isEmpty else { return nil }
        let key = NSString(string: String(encodedData.hashValue))
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: encodedData), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct CurrentUserAvatarView: View {
    @AppStorage("orbit.profile.displayName") private var displayName = "Heng Yee"
    @AppStorage("orbit.profile.avatarData") private var avatarData = ""
    let size: CGFloat

    var body: some View {
        ProfileAvatarView(name: displayName, data: avatarData, size: size)
    }
}

struct CommitAuthorAvatarView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("orbit.profile.displayName") private var displayName = "Heng Yee"
    @AppStorage("orbit.profile.avatarData") private var avatarData = ""
    let author: String
    let size: CGFloat

    var body: some View {
        ProfileAvatarView(name: author, data: usesCurrentUserAvatar ? avatarData : "", size: size)
    }

    private var usesCurrentUserAvatar: Bool {
        let normalizedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [displayName, appState.gitIdentity.name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.contains { $0.localizedCaseInsensitiveCompare(normalizedAuthor) == .orderedSame }
    }
}

struct AvatarPickerButton: View {
    @Binding var avatarData: String
    @State private var importError: String?

    var body: some View {
        Button(avatarData.isEmpty ? "选择图片…" : "更换图片…", systemImage: "photo") {
            let panel = NSOpenPanel()
            panel.title = "选择头像"
            panel.prompt = "使用图片"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image]
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                avatarData = try normalizedAvatarData(from: url).base64EncodedString()
                UserDefaults.standard.synchronize()
            } catch {
                importError = error.localizedDescription
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .alert("无法使用这张图片", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "请选择其他图片后重试。")
        }
    }

    private func normalizedAvatarData(from url: URL) throws -> Data {
        guard let sourceImage = NSImage(contentsOf: url),
              sourceImage.isValid,
              sourceImage.size.width > 0,
              sourceImage.size.height > 0 else {
            throw AvatarImportError.unsupportedImage
        }

        let side: CGFloat = 512
        let sourceSize = sourceImage.size
        let cropLength = min(sourceSize.width, sourceSize.height)
        let cropRect = NSRect(
            x: (sourceSize.width - cropLength) / 2,
            y: (sourceSize.height - cropLength) / 2,
            width: cropLength,
            height: cropLength
        )
        let normalizedImage = NSImage(size: NSSize(width: side, height: side))
        normalizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: cropRect,
            operation: .copy,
            fraction: 1
        )
        normalizedImage.unlockFocus()

        guard let tiffData = normalizedImage.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData),
              let pngData = representation.representation(using: .png, properties: [:]),
              pngData.count <= 4_000_000 else {
            throw AvatarImportError.cannotEncode
        }
        return pngData
    }
}

private enum AvatarImportError: LocalizedError {
    case unsupportedImage
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "图片无法读取，请尝试 PNG、JPG、HEIC 或 WebP 格式。"
        case .cannotEncode:
            "图片处理失败或文件过大，请选择另一张图片。"
        }
    }
}
