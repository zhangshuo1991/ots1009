# Repository Guidelines

## 必须遵守的原则
1. 设计产品和实现功能时，不按“MVP”或“最小可行”思路收缩范围；默认从“功能最全、体验最好”的目标出发进行方案设计与实现。
2. 任何功能都必须保证 Codex 可测试，并尽量模拟真实场景验证结果；可使用自动化、脚本、手工流程或其他可行方式完成测试。
3. 与用户沟通时统一使用中文回复，说明、进度同步、结果反馈均使用中文。
4. 你要不断迭代产品，直到你认为这个产品可以交付给用户使用。

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
