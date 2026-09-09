# GitIgnore

GitIgnore 是一个原生 macOS Git 客户端，目标是让仓库状态、提交历史、分支和 Diff 更容易理解，同时保持界面安静、响应稳定。

> 当前状态：`v0.1.0-alpha`。这是一个早期 Alpha 项目，适合尝试、反馈和贡献，不建议作为唯一的生产恢复工具。

## Features

- 原生 SwiftUI + AppKit 三栏界面
- macOS 14+，支持 Apple Silicon 和 Intel
- 浅色、深色和跟随系统外观
- 中英文界面与独立的中英文字体设置
- 工作区状态、暂存、取消暂存、批量 Stage 和提交
- 工作区 Diff、暂存区 Diff 和提交详情
- 本地分支、远程分支、标签、Stash 和 Worktree
- Fetch、Pull、Push，以及无 upstream 分支的首次发布
- Merge、Rebase、Cherry-pick、Revert 和 Reset 工作流
- 冲突文件识别和三方冲突编辑器
- 远程提交可 Pull、本地提交待 Push 的状态提示
- Git 操作超时、取消、`index.lock` 预检和错误反馈
- 代码评审与问题追踪入口（GitHub、GitLab、Gitee）
- 性能诊断和大 Diff 的分块读取保护

## Requirements

- macOS 14.0 或更高版本
- Xcode 16 或更高版本
- 系统已安装 Git（通常位于 `/usr/bin/git`）

## Build from source

```bash
git clone https://github.com/hengyee-labs/GitIgnore.git
cd GitIgnore
xcodebuild \
  -project GitIgnore.xcodeproj \
  -scheme GitIgnore \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/GitIgnoreDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

构建产物位于：

```text
/tmp/GitIgnoreDerivedData/Build/Products/Debug/GitIgnore.app
```

也可以直接使用 Xcode 打开 `GitIgnore.xcodeproj`，选择 `GitIgnore` Scheme 后运行。

当前工程关闭了 App Sandbox，方便个人版访问任意本地仓库并调用系统 Git。正式分发前需要重新评估 Sandbox、安全书签、Hardened Runtime、Developer ID 和 Notarization。

## Privacy

- Git 操作由本机 Git CLI 执行，GitIgnore 不会上传仓库文件内容。
- 远程更新检测只读取远程分支状态。
- 代码评审和问题追踪请求只在用户打开对应页面时发起。
- GitHub、GitLab、Gitee Token 保存在当前 Mac 的系统钥匙串，不写入仓库文件或普通偏好设置。
- GitIgnore 不包含遥测服务，不收集仓库路径、提交内容或使用行为。

## Security notes

请不要在 Issue、Discussion、日志或诊断信息中提交 Token、密码、私钥、内部仓库地址或完整的认证 URL。发现安全问题请按照 [SECURITY.md](SECURITY.md) 联系维护者，不要公开发布可利用的细节。

## Performance regression

性能夹具覆盖 10 / 100 / 1,000 个工作区变更、10,000 条提交历史，以及 1 / 10 / 100 MB Diff：

```bash
zsh Tools/performance-fixtures.sh all
zsh Tools/performance-regression.sh --scenario all --report /tmp/gitignore-performance.json
```

应用内部“设置 → Git → 性能诊断”会记录 Git 进程、输出解析、状态应用、Diff 解析、刷新和仓库切换阶段。命令行报告用于比较关键路径，空闲 CPU、内存和界面滚动应结合应用内诊断或 Instruments 评估。

## Roadmap

- 更完整的行内和并排 Diff 引擎
- 大型提交历史的虚拟化和筛选
- 更完整的三方冲突编辑器
- Sparkle 或 GitHub Releases 更新中心
- Developer ID 签名与 Notarization 发布流程

## Releases

推送形如 `v0.1.0-alpha` 的 Git tag 后，GitHub Actions 会构建 arm64 + x86_64 Universal 应用，执行 ad-hoc 签名，生成 ZIP 和 SHA-256，并创建 GitHub Release。由于当前没有 Apple Developer ID 和 Notarization，下载版本可能触发 Gatekeeper 提示；用户应核对校验值，并通过右键“打开”确认首次启动。

## Contributing

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。提交 PR 前至少执行一次 Release 构建，并在描述中说明影响的页面、Git 操作、性能风险和手动验证步骤。

## License

GitIgnore 使用 MIT License，详见 [LICENSE](LICENSE)。
