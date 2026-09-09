# Releasing GitIgnore

GitIgnore currently publishes an ad-hoc signed, non-notarized Universal macOS application.

## Prepare a release

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Update `CHANGELOG.md` with the release date, user-visible changes and known limitations.
3. Run a local Release build and the performance regression script.
4. Confirm that no access token, private repository path, certificate or local build artifact is staged.

## Publish

Create an annotated tag that matches the version:

```bash
git tag -a v0.1.0-alpha -m "GitIgnore v0.1.0-alpha"
git push origin v0.1.0-alpha
```

The release workflow builds a Universal app, applies an ad-hoc signature, creates a ZIP and SHA-256 file, and publishes a prerelease on GitHub.

## Gatekeeper limitation

The release is not signed with Apple Developer ID and is not notarized. Users may need to right-click the app and choose Open on first launch. Never describe this package as notarized or as bypassing macOS security controls.
