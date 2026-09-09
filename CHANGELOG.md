# Changelog

## [Unreleased]

## [0.1.3-alpha] - 2026-09-09

### Fixed

- Correct the Universal binary verification command so packaging can complete.
- Add a manual release workflow for existing tags.

## [0.1.2-alpha] - 2026-09-09

### Fixed

- Fix Swift 6 compilation on Xcode 16.2 when collecting process memory diagnostics.
- Package the complete app bundle and an Applications shortcut at the DMG root.
- Verify Universal architectures and the DMG before publishing; retain packages as workflow artifacts.
- Match the packaged app version to the release tag.
- Compilation succeeded, but packaging failed; use 0.1.3-alpha or newer for downloads.

## [0.1.1-alpha] - 2026-09-09

### Added

- Bilingual README with screenshots and a DMG release workflow.
- This tag did not produce release binaries because the CI build failed; use 0.1.3-alpha or newer.

## [0.1.0-alpha] - 2026-09-09

### Added

- Native macOS Git client shell with overview, changes, history, branches, Stash and Worktree sections.
- Stage, Unstage, Commit, Fetch, Pull, Push and first-time local branch publishing.
- Branch and commit actions, conflict status and merge editor entry points.
- Chinese and English interface support with separate Latin and CJK font settings.
- Remote update notifications and bounded Git operation diagnostics.

### Known limitations

- The application is not notarized and is distributed for development and testing.
- Remote collaboration APIs and GitHub/GitLab/Gitee authentication continue to evolve.
- Sparkle automatic updates are not included in this release.
