import Foundation

extension AppState {
    func startWatchingRepository(at root: URL) {
        repositoryWatcher.start(path: root.path) { [weak self] changedPaths in
            Task { @MainActor [weak self] in
                self?.scheduleLiveRefresh(for: changedPaths)
            }
        }
    }

    func scheduleLiveRefresh(for changedPaths: [String]) {
        if pendingLiveRefreshPaths.count < 128 {
            pendingLiveRefreshPaths.formUnion(changedPaths.prefix(128))
        } else {
            pendingLiveRefreshPaths = ["__bulk_workspace_change__"]
        }
        liveRefreshTask?.cancel()
        let refreshGeneration = liveRefreshGeneration
        liveRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard refreshGeneration == self.liveRefreshGeneration else { return }
            let paths = Array(self.pendingLiveRefreshPaths)
            self.pendingLiveRefreshPaths.removeAll(keepingCapacity: true)
            await self.refreshFromFileChanges(paths)
        }
    }

    func cancelPendingLiveRefresh() {
        liveRefreshGeneration &+= 1
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        pendingLiveRefreshPaths.removeAll(keepingCapacity: true)
    }

    func refreshFromFileChanges(_ changedPaths: [String]) async {
        guard let repository else { return }
        if isLoadingRepository || isPerformingGitAction || isCheckingRemoteUpdates {
            mergeDeferredLiveRefreshPaths(changedPaths)
            return
        }
        let metadataPaths = changedPaths.filter { $0.contains("/.git/") || $0.hasSuffix("/.git") }
        if metadataPaths.contains(where: {
            $0.contains("/.git/refs/") || $0.contains("/.git/logs/")
                || $0.hasSuffix("/.git/HEAD") || $0.hasSuffix("/.git/FETCH_HEAD")
        }) {
            await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
            return
        }
        if !metadataPaths.isEmpty {
            await refresh(scope: .workingCopy)
            return
        }

        let repositoryPath = URL(fileURLWithPath: repository.path, isDirectory: true)
            .standardizedFileURL.path
        let selectedAbsolutePath = selectedFile.map {
            URL(fileURLWithPath: repositoryPath, isDirectory: true)
                .appendingPathComponent($0.path)
                .standardizedFileURL.path
        }
        let shouldRefreshSelectedDiff = changedPaths.contains { changedPath in
            if changedPath == "__bulk_workspace_change__" { return true }
            guard let selectedAbsolutePath else { return false }
            let normalizedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path
            return normalizedPath == repositoryPath
                || normalizedPath == selectedAbsolutePath
                || selectedAbsolutePath.hasPrefix(normalizedPath + "/")
        }
        await refresh(scope: .workingCopy, refreshSelectedDiff: shouldRefreshSelectedDiff)
    }

    func scheduleDeferredLiveRefreshIfNeeded() {
        guard !deferredLiveRefreshPaths.isEmpty else { return }
        let paths = Array(deferredLiveRefreshPaths)
        deferredLiveRefreshPaths.removeAll(keepingCapacity: true)
        scheduleLiveRefresh(for: paths)
    }

    private func mergeDeferredLiveRefreshPaths(_ paths: [String]) {
        if deferredLiveRefreshPaths.count + paths.count > 128 {
            deferredLiveRefreshPaths = ["__bulk_workspace_change__"]
        } else {
            deferredLiveRefreshPaths.formUnion(paths.prefix(128))
        }
    }
}
