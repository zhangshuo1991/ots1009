# AgentOS Delivery Runbook (2026-02-15)

## 目标
在本地可重复验证 AgentOS 的“创建 -> 执行 -> 决策 -> 恢复 -> 验收 -> 报告导出”闭环，作为可交付证据。

## 前置条件
- macOS 15+
- Swift 6.2
- 仓库路径：`/Users/zhangshuo/Desktop/code_2/NexusProtocolTest/AgentOS`

## 启动流程
1. `cd AgentOS`
2. `swift build`
3. `swift run`

## 快速验证路径
1. 新建任务（`⌘N`）
2. 选择策略与执行模式（本地执行 / 场景模拟）
3. 启动任务（`⌘R`）
4. 在决策中心处理审批：
- 选择审批角色（Owner/Approver/Observer）
- 验证 quorum 未满足时任务不恢复
- 验证审批超时后 fallback 动作（自动放行/自动阻塞）
5. 在恢复中心确认失败分类与建议动作，执行重试或恢复点回滚
6. 推进阶段（`⇧⌘P`），直到验收完成
7. 在复盘总结面板执行：
- 生成总结
- 导出报告（Markdown + JSON）

## 测试命令
- `swift test`
- `swift build`
- `swift run`（启动冒烟）

## 验收标准
- 所有测试通过
- 决策中心显示审批 quorum、剩余时间、fallback
- 恢复中心显示失败分类与推荐动作
- Summary 面板显示恢复均时、预算偏差、阶段门通过率
- 报告导出成功并落盘于 Application Support

## 回归关注点
- executionMode 切换后是否仍能一致触发事件
- 超时 fallback 是否会误改非审批会话
- 导出报告在 summary 为空时是否自动补摘要
