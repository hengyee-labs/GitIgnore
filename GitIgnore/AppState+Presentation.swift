import Foundation

extension AppState {
    func clearActionMessage() {
        actionMessage = nil
    }

    func clearFeedback() {
        feedback = nil
        errorMessage = nil
    }

    func clearHistoryUpdate() {
        historyUpdateMessage = nil
        recentlyAddedCommitIDs.removeAll()
    }

    func clearSelectedCommitFilePreview() {
        commitFileLoadGeneration &+= 1
        commitFileLoadTask?.cancel()
        selectedCommitFilePath = nil
        selectedCommitFileDiff = nil
        isLoadingCommitFileDiff = false
        isDiffFocusPresented = false
    }

    func dismissDiffFocus() {
        isDiffFocusPresented = false
    }

    func presentDiffFocus() {
        guard selectedFileDiff != nil || selectedCommitFileDiff != nil else { return }
        isDiffFocusPresented = true
    }

    func dismissInspector() {
        switch selectedSection {
        case .changes:
            diffLoadGeneration &+= 1
            diffLoadTask?.cancel()
            selectedFile = nil
            selectedFileDiff = nil
            selectedFileDiffError = nil
            isLoadingDiff = false
            isDiffFocusPresented = false
        case .history:
            commitDetailLoadGeneration &+= 1
            commitFileLoadGeneration &+= 1
            commitDetailLoadTask?.cancel()
            commitFileLoadTask?.cancel()
            selectedCommit = nil
            selectedCommitDetail = nil
            selectedCommitFilePath = nil
            selectedCommitFileDiff = nil
            isLoadingCommitDetail = false
            isLoadingCommitFileDiff = false
            isDiffFocusPresented = false
        default:
            break
        }
    }

    func synchronizeInspectorSelection() {
        isDiffFocusPresented = false
        switch selectedSection {
        case .changes:
            commitDetailLoadTask?.cancel()
            commitFileLoadTask?.cancel()
            selectedCommit = nil
            selectedCommitDetail = nil
            selectedCommitFilePath = nil
            selectedCommitFileDiff = nil
        case .history:
            diffLoadTask?.cancel()
            selectedFile = nil
            selectedFileDiff = nil
            selectedFileDiffError = nil
        default:
            diffLoadTask?.cancel()
            commitDetailLoadTask?.cancel()
            commitFileLoadTask?.cancel()
            selectedCommit = nil
            selectedCommitDetail = nil
            selectedCommitFilePath = nil
            selectedCommitFileDiff = nil
            selectedFile = nil
            selectedFileDiff = nil
            selectedFileDiffError = nil
        }
    }

    func presentMessage(_ message: String, title: String) {
        errorMessage = message
        feedback = AppFeedback(kind: .failure, title: title, message: message)
    }

    func present(error: Error, title: String) {
        if !workflows.isPerformingSafeBranchSwitch,
           let request = branchSwitchRecoveryRequest(for: error) {
            errorMessage = nil
            feedback = nil
            workflows.safeBranchSwitchRequest = request
            return
        }
        let message = error.localizedDescription
        let details = (error as? GitRunnerError)?.technicalDetails
        errorMessage = message
        feedback = AppFeedback(kind: .failure, title: title, message: message, technicalDetails: details)
    }
}
