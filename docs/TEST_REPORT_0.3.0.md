# 0.3.0 界面与配色更新报告

日期：2026-09-25。基线：`53ce94d`。平台：本机 Windows 11、Windows PowerShell 5.1。

## 用户可见变化

- 首页：计划选择、当前使用状态、屏幕/睡眠常用卡片、计划管理。GUID 和原始输出转入技术详情。
- 高级设置：分类与参数双栏，参数说明、插电/电池值、枚举名称、草稿保留及保存前差异确认。一次保存一项，不伪装成批量事务。
- 常用时间：按分钟和“从不”选择，保存仍使用秒；非标准秒数保留，原始数值输入可用。
- 外观：系统/浅色/深色模式；系统强调色及海洋蓝、森林绿、鸢尾紫、暖琥珀、玫瑰红、石墨灰。自动保存，可随系统颜色变化更新。

## 自动验证

| 项目 | 结果 |
| --- | --- |
| 核心回归 | 57/57；核心代码未修改 |
| GUI 回归 | 972 条断言；174 次设置选择（120 次枚举或时间预设，54 次原始数值） |
| 新 UI 专项 | 48 项；颜色对比度、偏好持久化/回退/写入失败、模拟系统颜色变化、时间转换、分类草稿、取消不写入、主题切换保留输入 |
| 进程通信 | 9 类参数、双流、非零退出、超时通过 |
| 布局 | 主窗口 1120×760、940×640、1400×900，三页横向不溢出；高级设置最小尺寸下保存/关闭可达 |
| 打包内容 | GUI、Core、UI、启动器共 4 个运行文件哈希一致；解包后 GUI、UI、核心回归通过 |
| 实际 EXE 启动 | 窗口可见，3 个计划、1 个选中项、详情已加载，ConsoleAttached=false；启动测试自动退出 |
| 默认入口 | 默认 EXE 与 0.3.0 版本 EXE 内容相同，默认 EXE 独立启动验证通过 |

命令：`scripts/test.ps1`、`scripts/build.ps1`，均由 Windows PowerShell 5.1 / STA 执行。证据位于 `artifacts/ui-0.3.0/`。UI 测试偏好保存在 `artifacts/tests/ui-*`；电源写入使用测试替身。

## 未覆盖与边界

- 本轮没有执行真实电源写入，没有改变 Windows 明暗模式或系统强调色。0.2.0 的实机写入结果仍为历史结果。
- 尚未完成跨设备、Windows 10、不同真实 DPI、高对比度系统切换的人工矩阵。高对比度代码路径已实现，不把普通主题测试等同于高对比度验收。
- WinForms 的系统消息框、文件选择器、滚动条等部分原生控件由 Windows 绘制，可能不完全匹配手动配色。
- 多步系统操作仍同步执行。完整隐藏设置管理、自动按操作提权、批量保存仍未实现。
- 首页只展示能够按已知 GUID 识别的常用项，缺失时显示说明；无电池设备仍可查看计划中存储的电池配置。

主题依据：[Microsoft UISettings / Win32 主题](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-windows-themes)。时间语义依据：[显示超时](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/display-settings-display-idle-timeout)、[睡眠超时](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/sleep-settings-sleep-idle-timeout)。这些已知项目之外的参数不做语义猜测。

## 交付状态

本地 `dist/电源计划管理器.exe` 与 `dist/电源计划管理器_0.3.0.exe` 已更新，并附配套 SHA-256 文件。GitHub Release 未更新。完整构建日志记录本轮生成文件的 SHA-256，重新构建可能改变包哈希。
