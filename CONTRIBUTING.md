# Contributing to GitIgnore

感谢你对 GitIgnore 的兴趣。

## Before opening an issue

- Confirm the issue can be reproduced with the latest `main` build.
- Remove repository paths, tokens, passwords and private code from screenshots and logs.
- For performance reports, include repository size, changed-file count, commit count and the affected interaction.

## Pull requests

1. Keep each PR focused on one behavior or visual change.
2. Do not change Git history, POM-like project metadata, signing credentials or user data as part of an unrelated PR.
3. Preserve the local-first behavior and the existing Chinese/English localization model.
4. Git write operations must remain serialized per repository; long reads must be cancellable and bounded.
5. Add or update tests when changing parsers, Git commands, state transitions or localization.

## Local checks

```bash
xcodebuild \
  -project GitIgnore.xcodeproj \
  -scheme GitIgnore \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

zsh Tools/performance-regression.sh --scenario all --report /tmp/gitignore-performance.json
```

In the PR description, include the changed areas, manual verification steps, and any known limitations.
