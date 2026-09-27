# 开发与测试

当前项目是 Windows PowerShell / WinForms 原型。历史开发计划中的 C# + WPF 路线是设计目标，不代表当前代码结构。

## 修改入口

| 文件 | 职责 |
| --- | --- |
| `src/PowerPlan.Core.ps1` | 系统命令、解析、校验、计划操作、备份和恢复 |
| `src/PowerPlanManager.ps1` | 窗体、事件、编辑草稿与状态反馈 |
| `src/PowerPlan.UI.ps1` | 首页、分类编辑器、常用设置说明、主题和外观偏好 |
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

- `dist/电源计划管理器_0.3.1.exe`：当前带版本文件；原 0.2.0 版本文件保留作历史产物。
- `dist/电源计划管理器.exe`：同一内容的默认入口。
- 两个对应的 `.sha256.txt` 校验文件。
- `dist/` 下供审阅的主脚本及核心模块副本。
- `artifacts/build/` 下启动器、IExpress 配置、暂存文件和解包检查记录。

构建会短暂启动程序自己的测试窗体并自动关闭。已有 0.2.0 测试报告是历史证据；重新整理目录后的验证记录单独见 [工程整理验证](REPOSITORY_REORGANIZATION.md)。

## 缺陷与需求

问题按 [Bug Fix Log](BUG_FIX_LOG.md) 的格式记录，包含触发步骤、根因、修复和证据。覆盖目标与验收要求见 [测试需求](TEST_REQUIREMENTS.md)。尚未实现的功能、未执行和受阻的用例不能记作通过。

0.3.0 新增 `tests/test-ui.ps1`，覆盖配色持久化/失败、跟随系统状态变化、前景对比度、时间显示与真实秒数、分类草稿和主题切换保留输入。偏好写入定向到本轮 `artifacts/tests/ui-*`，不修改用户外观偏好；电源写入继续使用替身。打包必须包含 `PowerPlan.UI.ps1`，默认脚本入口旁也必须同步此模块。

0.3.1 新增 `tests/test-visibility.ps1`：本机 `/query` 与 `/qh` 只读对照、所有隐藏参数的选择、隐藏项筛选及草稿保留、逐节点属性位修改/恢复、取消、备份失败、权限失败、读回失败、外部冲突、跨机及损坏备份。原生属性写入被替换为测试桩，不会改动系统属性。构建也会针对解包后的源码执行该测试。

显示属性读取使用注册表节点自身的原始 DWORD，设置节点和分类节点分开；无分类设置位于 PowerSettings 根下。写入调用 `PowerWriteSettingAttributes`，只将原值的 `POWER_ATTRIBUTE_HIDE` 位清除，其他位不变。原值缺失或类型异常时拒绝改写。恢复要求本机标识、GUID、属性掩码关系和当前状态全部匹配；记录保存在当前账号的 `VisibilityBackups`。本程序的互斥锁只约束本程序窗口，不能对其他软件提供原子事务保证。[属性读取的合并语义](https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-powerreadsettingattributes)、[属性写入接口](https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-powerwritesettingattributes)。

主题读取遵循 [Windows UISettings 明暗检测与 DWM 标题栏说明](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-windows-themes)。主窗口的 UI 线程计时器每 1.5 秒检测颜色变化，不订阅跨线程 PowerShell 回调；关闭时释放计时器。高对比度优先使用 SystemColors。
