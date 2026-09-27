# 安全与健壮性测试执行台账

日期：2026-09-27　对应 [测试方案 1.0](SECURITY_TEST_PLAN.md)。

本文件为执行前初始化台账。已完成源码/已有测试审查和测试设计；未执行下面的动态用例，未确认漏洞，未修改真实电源状态。初始统计：100 项 NOT_RUN；PASS/FAIL/BLOCKED/N/A 均为 0。历史测试结果不计入本轮。

## 执行记录规则

每次运行补充运行 ID、日期、执行人、源码/产物哈希、环境、权限、方法、夹具/种子、前后状态、证据路径与哈希、恢复清理结果。一个 ID 的多个输入/入口/环境拆为子编号；任一子场景失败则父项 FAIL，有必要子场景未执行则父项不能 PASS。

下表为父项索引；实际执行时链接到每次运行的子场景记录和缺陷。不得仅改为 PASS 而不填证据。

| ID | 状态 | 运行/环境/证据 | 缺陷或阻塞说明 |
| --- | --- | --- | --- |
| LA-01 | NOT_RUN | — | — |
| LA-02 | NOT_RUN | — | — |
| LA-03 | NOT_RUN | — | — |
| LA-04 | NOT_RUN | — | — |
| LA-05 | NOT_RUN | — | — |
| LA-06 | NOT_RUN | — | — |
| LA-07 | NOT_RUN | — | — |
| LA-08 | NOT_RUN | — | — |
| LA-09 | NOT_RUN | — | — |
| LA-10 | NOT_RUN | — | — |
| IN-01 | NOT_RUN | — | — |
| IN-02 | NOT_RUN | — | — |
| IN-03 | NOT_RUN | — | — |
| IN-04 | NOT_RUN | — | — |
| IN-05 | NOT_RUN | — | — |
| IN-06 | NOT_RUN | — | — |
| IN-07 | NOT_RUN | — | — |
| IN-08 | NOT_RUN | — | — |
| IN-09 | NOT_RUN | — | — |
| IN-10 | NOT_RUN | — | — |
| FS-01 | NOT_RUN | — | — |
| FS-02 | NOT_RUN | — | — |
| FS-03 | NOT_RUN | — | — |
| FS-04 | NOT_RUN | — | — |
| FS-05 | NOT_RUN | — | — |
| FS-06 | NOT_RUN | — | — |
| FS-07 | NOT_RUN | — | — |
| FS-08 | NOT_RUN | — | — |
| FS-09 | NOT_RUN | — | — |
| FS-10 | NOT_RUN | — | — |
| PD-01 | NOT_RUN | — | — |
| PD-02 | NOT_RUN | — | — |
| PD-03 | NOT_RUN | — | — |
| PD-04 | NOT_RUN | — | — |
| PD-05 | NOT_RUN | — | — |
| PD-06 | NOT_RUN | — | — |
| PD-07 | NOT_RUN | — | — |
| PD-08 | NOT_RUN | — | — |
| PD-09 | NOT_RUN | — | — |
| PD-10 | NOT_RUN | — | — |
| TX-01 | NOT_RUN | — | — |
| TX-02 | NOT_RUN | — | — |
| TX-03 | NOT_RUN | — | — |
| TX-04 | NOT_RUN | — | — |
| TX-05 | NOT_RUN | — | — |
| TX-06 | NOT_RUN | — | — |
| TX-07 | NOT_RUN | — | — |
| TX-08 | NOT_RUN | — | — |
| TX-09 | NOT_RUN | — | — |
| TX-10 | NOT_RUN | — | — |
| VS-01 | NOT_RUN | — | — |
| VS-02 | NOT_RUN | — | — |
| VS-03 | NOT_RUN | — | — |
| VS-04 | NOT_RUN | — | — |
| VS-05 | NOT_RUN | — | — |
| VS-06 | NOT_RUN | — | — |
| VS-07 | NOT_RUN | — | — |
| VS-08 | NOT_RUN | — | — |
| VS-09 | NOT_RUN | — | — |
| VS-10 | NOT_RUN | — | — |
| UI-01 | NOT_RUN | — | — |
| UI-02 | NOT_RUN | — | — |
| UI-03 | NOT_RUN | — | — |
| UI-04 | NOT_RUN | — | — |
| UI-05 | NOT_RUN | — | — |
| UI-06 | NOT_RUN | — | — |
| UI-07 | NOT_RUN | — | — |
| UI-08 | NOT_RUN | — | — |
| UI-09 | NOT_RUN | — | — |
| UI-10 | NOT_RUN | — | — |
| RS-01 | NOT_RUN | — | — |
| RS-02 | NOT_RUN | — | — |
| RS-03 | NOT_RUN | — | — |
| RS-04 | NOT_RUN | — | — |
| RS-05 | NOT_RUN | — | — |
| RS-06 | NOT_RUN | — | — |
| RS-07 | NOT_RUN | — | — |
| RS-08 | NOT_RUN | — | — |
| RS-09 | NOT_RUN | — | — |
| RS-10 | NOT_RUN | — | — |
| PK-01 | NOT_RUN | — | — |
| PK-02 | NOT_RUN | — | — |
| PK-03 | NOT_RUN | — | — |
| PK-04 | NOT_RUN | — | — |
| PK-05 | NOT_RUN | — | — |
| PK-06 | NOT_RUN | — | — |
| PK-07 | NOT_RUN | — | — |
| PK-08 | NOT_RUN | — | — |
| PK-09 | NOT_RUN | — | — |
| PK-10 | NOT_RUN | — | — |
| QA-01 | NOT_RUN | — | — |
| QA-02 | NOT_RUN | — | — |
| QA-03 | NOT_RUN | — | — |
| QA-04 | NOT_RUN | — | — |
| QA-05 | NOT_RUN | — | — |
| QA-06 | NOT_RUN | — | — |
| QA-07 | NOT_RUN | — | — |
| QA-08 | NOT_RUN | — | — |
| QA-09 | NOT_RUN | — | — |
| QA-10 | NOT_RUN | — | — |

## 优先验证队列

| 静态线索 | 关联用例 | 当前状态 |
| --- | --- | --- |
| H-01：恢复确认与文件节点绑定 | VS-05 | HYPOTHESIS，未复现 |
| H-02：文件系统对象越过路径边界 | FS-03、VS-06、PK-06 | HYPOTHESIS，未复现 |
| H-03：低权限可写代码的高权限加载 | LA-01、LA-02、LA-04 | HYPOTHESIS，未验证权限链 |
| H-04：部分写入与恢复竞争 | TX-05、TX-06、TX-10 | HYPOTHESIS，未复现 |
| H-05：属性日志记账失败与重放 | VS-07、VS-08、VS-09 | HYPOTHESIS，未复现 |
| H-06：启动测试报告覆盖 | LA-08 | HYPOTHESIS，未复现 |
| H-07：输出/管道/记录资源耗尽 | RS-02、RS-04、VS-10 | HYPOTHESIS，未复现 |
| H-08：多文件发布失败不一致 | PK-05 | HYPOTHESIS，未复现 |

## 单次执行记录模板

```text
Run ID / 日期 / 执行人：
用例 ID / 子编号 / 方法：
源码提交及哈希 / EXE 哈希：
系统 / 宿主 / 语言 / 文件系统 / 权限 / 桌面会话：
前提与隔离快照 / 本轮所有权清单：
夹具路径与哈希 / 随机种子 / 故障同步点：
执行命令及步骤：
预期结果：
实际结果 / 原始退出码 / 实际调用与对象：
独立前后状态核对：
证据路径及哈希：
状态 / 缺陷编号 / 未验证范围：
恢复清理结果 / 残留及处置：
复测版本及结果：
```
