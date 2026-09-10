import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class GitIgnoreAppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        AppIconController.restorePersistedChoice()
        Task.detached(priority: .utility) {
            GitTemporaryFileCleanup.removeStaleDiffDirectories()
        }
        retainMainWindowAfterLaunch()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppIconController.restorePersistedChoice()
        retainMainWindowAfterLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        guard let window = mainWindow(in: sender) else { return true }
        configureMainWindow(window)
        window.makeKeyAndOrderFront(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func retainMainWindowAfterLaunch() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.mainWindow(in: NSApp) else { return }
            self.configureMainWindow(window)
        }
    }

    private func mainWindow(in application: NSApplication) -> NSWindow? {
        application.windows.first {
            $0.identifier?.rawValue == "GitIgnore.main-window"
                || ($0.title == "GitIgnore" && !($0 is NSPanel))
        }
    }

    private func configureMainWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("GitIgnore.main-window")
        window.isReleasedWhenClosed = false
    }
}

@main
@MainActor
struct GitIgnoreApp: App {
    @NSApplicationDelegateAdaptor(GitIgnoreAppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var interfaceLocale: Locale {
        (AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese).locale
    }

    var body: some Scene {
        let appState = appDelegate.appState
        let mainWindowContent = RootView()
            .environment(appState)
            .environment(\.locale, interfaceLocale)
        let settingsContent = SettingsView()
            .environment(appState)
            .environment(\.locale, interfaceLocale)

        Window("GitIgnore", id: "main") {
            mainWindowContent
        }
        .defaultSize(width: 1_280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开仓库…") {
                    appState.chooseRepository()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("导航") {
                Button("命令面板…") { appState.isCommandPalettePresented = true }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("仓库概览") { appState.selectSection(.overview) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("工作区变更") { appState.selectSection(.changes) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("提交历史") { appState.selectSection(.history) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("分支与标签") { appState.selectSection(.branches) }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("刷新仓库") { Task { await appState.refreshRepository() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Fetch 远程更新") { Task { await appState.fetch() } }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Pull 远程提交") { Task { await appState.pull() } }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Push 本地提交") { Task { await appState.push() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("在终端中打开") { appState.openTerminal() }
                    .keyboardShortcut("t", modifiers: .option)
            }
        }

        Settings {
            settingsContent
        }
    }
}
