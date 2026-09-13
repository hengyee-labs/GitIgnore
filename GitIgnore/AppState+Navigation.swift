import AppKit
import Foundation

extension AppState {
    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "选择 Git 仓库"
        panel.prompt = "打开仓库"
        panel.message = "请选择包含 Git 仓库的文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveRepositoryBookmark(for: url)
        beginOpeningRepository(url)
    }

    func openRecentRepository(_ recent: RecentRepository) {
        beginOpeningRepository(URL(fileURLWithPath: recent.path, isDirectory: true))
    }

    func removeRecentRepository(_ recent: RecentRepository) {
        recentRepositories.removeAll { $0.path == recent.path }
        persistRecentRepositories()
    }

    func clearRecentRepositories() {
        recentRepositories.removeAll()
        persistRecentRepositories()
    }

    func openTerminal() {
        guard let repository else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", repository.path]
        try? process.run()
    }

    func openRemote(path: String) {
        guard let base = remoteInfo?.webURL else {
            presentMessage("当前仓库没有可识别的远程地址。", title: "无法打开远程页面")
            return
        }
        NSWorkspace.shared.open(base.appendingPathComponent(path))
    }

    func selectSection(_ section: SidebarSection) {
        selectedSection = section
        isCommandPalettePresented = false
    }

    func beginOpeningRepository(_ url: URL) {
        repositoryOpenTask?.cancel()
        repositoryOpenTask = Task { [weak self] in
            await self?.openRepository(url, selectOverview: true)
        }
    }
}
