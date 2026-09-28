# 电源计划管理器

一个 Windows 中文桌面工具：自动发现本机电源计划，切换计划，创建副本、重命名、删除，以及备份和编辑 AC/DC 设置。换电脑后重新读取本机计划，无需修改 GUID。

当前版本：**0.3.2**。恢复切换计划时的防闪烁修复，保留不适用输入选项的隐藏修复，并统一源码与下载包的发布验证。采用简洁首页、分类高级设置和可保存的外观配色，支持隐藏参数浏览、编辑和 Windows 显示属性管理。实现采用 Windows PowerShell 5.1、WinForms 和系统电源接口；C# 启动器负责让便携 EXE 启动时不附带控制台窗口。本版更新和验证见 [0.3.2 发布说明](docs/RELEASE_NOTES_v0.3.2.md)，此前功能范围见 [进度汇总](docs/PROGRESS_0.3.1.md)。下载以 [GitHub 最新版](https://github.com/Myan0316/PowerPlanManager-GitHub-source/releases/latest) 为准。

版本、进度与历史核对见 [开发日志](docs/DEVELOPMENT_LOG.md)（2026-09-27 更新，含已发布状态、历史索引和本次回归结果）。根目录 `SOURCE_MANIFEST.sha256` 保留为原发布源码基线，不随开发中的文档修改更新。

0.3.1 的改动、验证和限制见 [界面及隐藏项更新报告](docs/TEST_REPORT_0.3.1.md)。

安全检查见 [安全与健壮性测试方案](docs/SECURITY_TEST_PLAN.md) 和 [执行台账](docs/SECURITY_TEST_EXECUTION.md)：包含 100 项测试设计及优先复现线索，当前为文档准备阶段，不代表安全测试已通过。

## 使用

从项目发布的 GitHub Release 下载 EXE 与对应 SHA-256 文件，或按下文自行构建。仓库只保存源码、测试和文档；EXE 发布在 Releases 中。

双击 `电源计划管理器.exe`。支持：

- 查看与切换已有计划，写入后重新读取核对。
- 复制创建、重命名与删除，保护当前活动计划和最后一个计划。
- 导入、导出 `.pow` 文件；恢复备份时创建新计划，不自动启用。
- 编辑具有可靠范围或枚举定义的接通电源 / 使用电池设置。
- 修改、改名和删除前备份；部分失败时尝试恢复并报告实际结果。
- 首页按列展示屏幕和睡眠时间，选择“调整”进入单项编辑；计划管理默认收起。高级设置支持类别、搜索及“包含系统隐藏项”。
- “管理 Windows 隐藏项”可对选定设置或分类解除隐藏，先备份原显示属性，保留其他属性位，并支持冲突检查后的恢复。显示属性对本机所有计划共用。
- 外观支持跟随系统、浅色、深色；支持系统强调色和蓝、绿、紫、琥珀、玫瑰、石墨六组配色，自动记住选择。

本机验证环境为 Windows 11 x64、Windows PowerShell 5.1；支持中文和英文设置输出。其他硬件、系统版本和 DPI 的兼容性仍需验证。权限不足时按错误提示以管理员身份重新运行；当前版本没有自动按操作提权。

计划备份位于当前运行账号的 `%LOCALAPPDATA%\PowerPlanManager\Backups`；显示属性备份位于同级 `VisibilityBackups`，与 `.pow` 计划备份分开。外观偏好为 `appearance.json`。未知设置保持只读；批量保存和按需自动提权尚未实施。解除隐藏标记不保证硬件或系统策略允许显示及使用该功能。

更多说明见 [使用指南](docs/USER_GUIDE.md)、[Bug Fix Log](docs/BUG_FIX_LOG.md) 和 [0.2.0 历史测试报告](docs/TEST_REPORT_0.2.0.md)。

## 从源码运行

在 Windows 下克隆或解压完整项目，在项目根目录执行：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\src\PowerPlanManager.ps1
```

无需安装 Python、第三方 PowerShell 模块或 .NET SDK。使用 Windows PowerShell 5.1 执行构建；脚本的执行策略参数只用于当前进程。

## 测试与构建

```powershell
# 模拟写入、进程通信、布局和 GUI 回归；不请求真实电源写入
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\test.ps1

# 执行回归、编译启动器、打包并核验最终 EXE
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\build.ps1

# 生成可上传 GitHub 的干净源码 ZIP，不含本地 Git 历史
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-source.ps1
```

构建使用 Windows 的 IExpress，需要可交互的 Windows 桌面会话完成窗口启动验证；不适合直接在 Linux 或没有桌面的任务中执行整套构建。产物写入 `dist/`，中间文件和测试记录写入 `artifacts/`。

真实写入测试另行显式执行，步骤见 [开发与测试说明](docs/DEVELOPMENT.md)。

## 工程结构

```text
src/          GUI、核心逻辑、C# 启动器与脚本启动入口
scripts/      构建、本地发布、统一测试及源码打包脚本
tests/        核心、GUI、进程通信、实机和发布验证
docs/         使用、开发计划、测试需求、历史报告与 Bug Fix Log
dist/         本地发布产物（Git 忽略）
artifacts/    构建和测试中间文件（Git 忽略）
.local/       历史文件、迁移记录和原始证据（Git 忽略）
```

源码的唯一维护入口是 `src/`。`dist/` 中的脚本副本由构建生成，不直接修改。Windows PowerShell 5.1 的 `.ps1` 文件保存为 UTF-8 BOM，避免中文被错误解码。

## 上传 GitHub

首次发布的文件选择、旧 Git 历史处理和 Releases 附件清单见 [上传与发布说明](docs/GITHUB_PUBLISHING.md)。

提交并推送到 `origin/main` 后，运行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\publish-github.ps1`：从当前提交重新构建、导出源码，上传草稿并下载核对全部附件，再发布为最新版。需要 Git 已登录且具有该仓库的发布权限。`publish-release.ps1` 仅更新本地默认入口；单独推送源码不会更新 GitHub Release 附件。

## 许可

个人、公司和其他组织均可免费使用、学习、修改和免费分享，包括公司内部使用。仅有两项条件：

1. **禁止收费销售**本软件、源码或修改版，包括付费下载、付费解锁及实质上对本软件收费的捆绑销售。
2. **对外发布或分发修改版时，须同时公开完整的对应源码**，让接收者可以免费获取、检查和修改。仅自用或组织内部使用的修改，无需向公众公开。

完整条款见 [LICENSE](LICENSE)，也适用于本项目此前已发布且由著作权人有权授权的版本。不额外要求署名或向原项目提交修改。项目采用自定义的源码公开许可，含收费销售限制，不宣称采用 MIT、GPL 或标准开源许可证。
