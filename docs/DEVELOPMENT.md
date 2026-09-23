# 开发与测试

当前项目是 Windows PowerShell / WinForms 原型。历史开发计划中的 C# + WPF 路线是设计目标，不代表当前代码结构。

## 修改入口

| 文件 | 职责 |
| --- | --- |
| `src/PowerPlan.Core.ps1` | 系统命令、解析、校验、计划操作、备份和恢复 |
| `src/PowerPlanManager.ps1` | 窗体、事件、编辑草稿与状态反馈 |
| `src/PowerPlanLauncher.cs` | 无控制台启动 PowerShell，传递参数及处理启动失败 |
| `scripts/build.ps1` | 回归、编译启动器、IExpress 打包、解包与启动核验 |
| `scripts/publish-release.ps1` | 更新本地 dist 默认入口和脚本副本；不会上传 GitHub |

所有路径从脚本所在目录推导，不依赖当前终端目录或作者电脑的盘符。每次改动至少运行 `scripts/test.ps1`；涉及启动、依赖或打包时运行 `scripts/build.ps1`。

## 测试层次

默认测试包含核心模拟、真实子进程参数通信、实际窗体构建及 GUI 事件回归。GUI 测试使用真实控件，但替换写入服务。它们不能替代人工交互和跨设备测试。

只读系统检查：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\test-live.ps1
```

真实写入测试应在有备份或快照的测试环境中，用管理员 Windows PowerShell 5.1 执行：

```powershell
# 创建、修改和删除本轮临时计划，并比较原有状态
.\tests\test-live.ps1 -ExecuteWrites

# 另外包含切换到等价副本并恢复活动计划
.\tests\test-live.ps1 -ExecuteWrites -IncludeActivation
```

`tests/run-live-admin.ps1` 是已提升权限会话中的完整实机测试入口，会启用写入和活动计划切换；它不会自动请求提权。默认测试与构建不调用该入口。

报告和临时 `.pow` 文件写入 `artifacts/tests/`，应保留失败证据，但不提交到公开仓库。执行前后核对计划状态；清理仅针对本轮创建且符合清理条件的 GUID。

## 构建输出

- `dist/电源计划管理器_0.2.0.exe`：带版本文件。
- `dist/电源计划管理器.exe`：同一内容的默认入口。
- 两个对应的 `.sha256.txt` 校验文件。
- `dist/` 下供审阅的主脚本及核心模块副本。
- `artifacts/build/` 下启动器、IExpress 配置、暂存文件和解包检查记录。

构建会短暂启动程序自己的测试窗体并自动关闭。已有 0.2.0 测试报告是历史证据；重新整理目录后的验证记录单独见 [工程整理验证](REPOSITORY_REORGANIZATION.md)。

## 缺陷与需求

问题按 [Bug Fix Log](BUG_FIX_LOG.md) 的格式记录，包含触发步骤、根因、修复和证据。覆盖目标与验收要求见 [测试需求](TEST_REQUIREMENTS.md)。尚未实现的功能、未执行和受阻的用例不能记作通过。
