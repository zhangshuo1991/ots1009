# Repository Guidelines

## 必须遵守的原则
1. 设计产品和实现功能时，不按“MVP”或“最小可行”思路收缩范围；默认从“功能最全、体验最好”的目标出发进行方案设计与实现。
2. 任何功能都必须保证 Codex 可测试，并尽量模拟真实场景验证结果；可使用自动化、脚本、手工流程或其他可行方式完成测试。
3. 与用户沟通时统一使用中文回复，说明、进度同步、结果反馈均使用中文。
4. 你要不断迭代产品，直到你认为这个产品可以交付给用户使用。

## 反思问题（强制检查）
每次开始实现前，必须先回答以下问题；任一项答案不清晰，禁止进入编码阶段。
1. 这次 UI 是否先定义了主流程（用户第一步、第二步、第三步）？是否避免“工程面板堆叠”导致认知负担？
2. 用户明确点名的 skill（如 `ui-ux-pro-max`、`swiftui-expert-skill`）是否已按流程执行，而不是只做功能实现？
3. 关键系统能力是否覆盖真实运行环境差异（例如 `.app` 启动 PATH 与终端 PATH 不一致）？
4. “未安装/不可用”类结论是否做了多路径与回退检测，避免误报？
5. 是否在提交前完成可用性验证（按钮可见、核心路径可达、首次使用有引导）而不仅是测试通过？

### 交付门禁（必须全部满足）
- UI 改动必须附带“主流程说明 + 可用性自测结果”。
- 涉及外部 CLI/环境检测，必须在“终端启动”和“`.app` 启动”两种场景各验证一次。
- 若用户反馈“看不懂/不好用”，优先重构信息架构，不得仅做样式微调。
- 未执行用户指定 skill 时，必须在回复中明确原因并征得同意。
- 每次任务完成前，必须执行计划实施强制校验：`bash scripts/verify-plan-implementation.sh --plan <计划文档> --report <完成报告文档>`；校验不通过禁止交付结果。
- 完成报告必须落盘到 `docs/operations/task-reports/`，并逐项勾选计划中的检查项（`P1/P2/...`）。

## Project Structure & Module Organization
- `AgentOS/` 是当前主产品（Swift Package + SwiftUI）。
- `AgentOS/Sources/AgentOS/Models|Services|ViewModels|Views/` 分别放领域模型、服务层、状态编排与界面。
- `AgentOS/Tests/AgentOSTests/` 放单元与流程回归测试。
- `docs/brainstorms/`, `docs/plans/`, `docs/operations/`, `docs/solutions/` 保存需求、计划、运维与经验沉淀。
- `vibe-kanba/` 为历史/参考目录，非当前交付主线。

## Build, Test, and Development Commands
在仓库根目录执行：
- `cd AgentOS && swift build`：编译产品，检查语法与依赖。
- `cd AgentOS && swift test`：运行全部自动化测试（提测前必跑）。
- `cd AgentOS && swift run`：本地启动应用进行冒烟验证。
- `git status --short`：提交前核对变更范围，避免误提无关文件。

## Coding Style & Naming Conventions
- 使用 Swift 5 风格与 4 空格缩进。
- 类型用 `UpperCamelCase`，属性/方法用 `lowerCamelCase`。
- `View` 仅负责渲染与交互，业务规则放 `Services`/`ViewModels`。
- 保持函数短小、命名可读，优先显式逻辑而非技巧性抽象。

## Testing Guidelines
- 测试框架：Swift Testing/XCTest（位于 `AgentOS/Tests/AgentOSTests/`）。
- 命名建议：`testScenarioProviderInjectsTimeoutFailure()` 这类“行为+预期”格式。
- 每个新功能至少补 1 条主路径测试 + 1 条异常/边界测试。
- 修复缺陷时必须添加回归测试，防止问题复发。

## Commit & Pull Request Guidelines
- Commit 建议使用 Conventional Commits：`feat:`, `fix:`, `refactor:`。
- 单次提交聚焦一个逻辑单元，避免混入无关文件。
- PR 描述需包含：变更摘要、动机、测试证据（命令与结果）、UI 变更截图（如有）。
- 涉及流程/策略变更时，同步更新 `docs/operations/` 或 `docs/solutions/`。
