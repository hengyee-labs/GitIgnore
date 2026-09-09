# Privacy

GitIgnore is designed as a local-first macOS application.

## Data handled locally

- Repository paths, recent repositories, interface preferences and recent commit messages are stored locally using macOS preferences.
- Remote access tokens are stored in the macOS Keychain.
- Git output, repository contents and Diff data are processed on the local Mac.

## Network requests

- GitIgnore invokes the local Git executable for Fetch, Pull, Push and other Git operations.
- Remote update checks contact the configured Git remote through Git.
- Code review and issue tracking pages may call the selected GitHub, GitLab or Gitee API after the user opens those pages.

GitIgnore does not include analytics or telemetry and does not sell personal data.

## Sensitive information

Do not paste access tokens, passwords, private keys or private repository contents into public Issues or Discussions. If you believe a credential may have been exposed, revoke it immediately at the relevant Git hosting provider.
