# 上传 GitHub 与发布程序

## 日常更新流程（0.3.2 起）

1. 修复和测试后提交全部公开源码及文档，推送到 `origin/main`。
2. 在 Windows PowerShell 5.1 执行 `scripts/publish-github.ps1`。Git 需已登录且有仓库发布权限。
3. 脚本检查干净工作区与远程提交一致，拒绝覆盖已有版本；自动重新构建并验证源码、包内代码、默认入口和真实启动，再导出源码包。
4. 脚本创建新版本草稿，上传 EXE、对应 SHA-256、源码 ZIP，下载三个附件核对哈希，通过后才公开并标记为最新版。失败时保留草稿供检查，不宣称发布成功。
5. 从 Releases 最新版下载并确认窗口版本号。已打开的旧进程需要关闭后重新运行。

`scripts/publish-release.ps1` **仅同步本地 dist 默认入口**，不访问 GitHub。推送源码、移动标签或本地构建都不会自动替换 Release 的 EXE 附件。不要覆盖旧附件或只改文件名；修复发布使用新版本号。当前版本为 **0.3.2**，详见 [发布说明](RELEASE_NOTES_v0.3.2.md)。

以下首次发布记录保留作历史参考。

> 状态更正（2026-09-24）：v0.2.0 已发布。本文“当前仓库已有的历史”描述的是整理前旧仓库，其 .git 现保存在本地历史 ZIP 中；当前源码仓库的根提交为 eddee00。现状与证据见 [开发日志](DEVELOPMENT_LOG.md)。下文保留首次上传时的操作说明。

## 适合提交的内容

提交根目录的 README、`LICENSE`、`.gitignore`、`.gitattributes`、`.editorconfig`，以及 `src/`、`scripts/`、`tests/`、`docs/`。这些文件足以阅读、运行、测试和构建项目。

`dist/`、`artifacts/`、`.local/` 已被忽略。EXE 和源码 ZIP 使用 GitHub Releases 附件分发；本机 `.pow` 备份、原始测试日志、迁移清单及个人绝对路径记录保留在本地。

## 当前仓库已有的历史

工程整理前的首次提交已经包含 EXE、重复解包文件、原始日志及本机路径。`.gitignore` 只能影响之后的文件选择，不能清除既有提交历史。本次整理保留了原 `.git`，没有改写或删除历史。

如果首次上传希望只包含整理后的工程，使用 `scripts/export-source.ps1` 生成的 `dist/PowerPlanManager-GitHub-source.zip`：

1. 解压到一个新目录，不复制原工程的 `.git`、`.local`、`dist` 或 `artifacts`。
2. 在新目录用 GitHub Desktop 创建本地仓库，检查待提交文件，再提交并发布到你的 GitHub 仓库。
3. 源码包内的 `SOURCE_MANIFEST.sha256` 用于核对导出文件，可随首次提交保留。

也可在新目录使用 Git：

```powershell
git init -b main
git add .
git status --short
git commit -m "Prepare Power Plan Manager source project"
```

仓库地址、公开/私有设置由发布时决定。若继续使用原仓库，先提交这次目录整理；正常推送仍会包含原始历史。不要以为新增忽略规则已经让历史文件消失。

## 发布 EXE

在 Windows PowerShell 5.1 下运行 `scripts/build.ps1`，完成验证后，为相应版本创建 GitHub Release。附件选择 `dist/` 中带版本的 EXE、对应 SHA-256，以及需要时重新生成的源码 ZIP。不要上传本地归档或测试备份。

更新版本时同步程序标题、启动器、构建和校验脚本中的版本，以及使用说明和报告。0.3.1 的历史范围及验证边界见 [进度汇总](PROGRESS_0.3.1.md) 和 [发布说明](RELEASE_NOTES_v0.3.1.md)；实际发布状态以 GitHub Releases 为准。不能直接改文件名冒充新版本。

## 许可证

2026-09-28 确定采用 [自定义许可](../LICENSE)：允许所有人免费使用（包括公司内部使用），禁止收费销售本软件、源码或修改版；对外分发修改版时须同时公开完整的对应源码。仅自用或组织内部使用的修改无需公开，不额外要求署名或向原项目提交修改。

项目使用“源码公开”的描述，不宣称采用 MIT、GPL 或标准开源许可证。`scripts/export-source.ps1` 会把 `LICENSE` 纳入源码 ZIP 和校验清单。

该授权也覆盖著作权人有权授权的此前发布版本。历史标签及旧附件可能没有内置许可证；发布页应链接当前 `LICENSE` 并附上许可说明。公开前核对所有远程分支、标签及发布附件，不能只检查工作区或 `.gitignore`。

旧版 Release 可追加以下说明（无需改动原 EXE 或其校验值）：

> 许可说明（2026-09-28）：本版本适用仓库中的 [使用与分发许可](https://github.com/Myan0316/PowerPlanManager-GitHub-source/blob/main/LICENSE)。个人及公司均可免费使用；禁止收费销售本软件、源码或修改版；对外分发修改版须同时公开完整的对应源码。仅自用或组织内部使用的修改无需公开。
