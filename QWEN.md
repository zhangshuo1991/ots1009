# QWEN.md — AgentOS Project Context

## Project Overview

**AgentOS** 是一个基于 SwiftUI 开发的 macOS 原生应用，用于统一管理和操作各类编程工具（CLI）。应用集成了 Ghostty 终端模拟器，提供工具检测、安装、更新、配置编辑以及嵌入式终端会话管理等功能。

### 核心技术栈
- **语言**: Swift 6.2+
- **平台**: macOS 15.0+
- **UI 框架**: SwiftUI (采用 light theme 设计)
- **架构模式**: MVVM (Model-View-ViewModel) + Observable
- **终端引擎**: Ghostty (通过 GhosttyKit.xcframework 集成)
- **构建工具**: Swift Package Manager

### 项目结构

```
AgentOS/
├── Package.swift                    # Swift Package 配置
├── Sources/AgentOS/
│   ├── AgentOSApp.swift             # 应用入口
│   ├── MainView.swift               # 主界面布局
│   ├── AppState.swift               # 全局状态管理
│   ├── DesignTokens.swift           # 设计系统/颜色令牌
│   ├── AgentTypes.swift             # 核心类型定义
│   ├── Views/                       # UI 组件
│   │   ├── ToolSidebarRowView.swift
│   │   ├── ToolDetailPanelView.swift
│   │   ├── CLITerminalSessionView.swift
│   │   └── ...
│   ├── Services/                    # 业务服务层
│   │   ├── CLIDetectionService.swift
│   │   ├── ToolInstallationService.swift
│   │   └── ConfigEditorService.swift
│   └── Resources/                   # 资源文件
├── Tests/AgentOSTests/              # 单元测试
└── Frameworks/
    └── GhosttyKit.xcframework       # Ghostty 终端框架
```

## 构建与运行

### 前置要求
- macOS 15.0 或更高版本
- Xcode 16.0+ (含 Swift 6.2 工具链)
- Zig 0.14+ (用于构建 GhosttyKit，可选)

### 常用命令

```bash
# 进入项目目录
cd AgentOS

# 构建项目
swift build

# 运行测试
swift test

# 本地运行应用
swift run

# 生成 macOS .app 包
# (使用 scripts/package-agentos-macos.sh)
```

### GhosttyKit 构建

如需从源码构建 Ghostty 终端框架：

```bash
# 构建 GhosttyKit.xcframework
bash scripts/build-ghosttykit.sh

# 脚本会自动处理：
# 1. 检查 Zig 版本
# 2. 克隆/更新 Ghostty 源码
# 3. 构建 xcframework
# 4. 复制到 AgentOS/Frameworks/
```

## 开发规范

### 代码风格
- **缩进**: 4 个空格
- **命名**: 类型使用 `UpperCamelCase`，属性/方法使用 `lowerCamelCase`
- **导入顺序**: Foundation → AppKit/SwiftUI → 内部模块
- **访问控制**: 默认 `internal`，需要时显式标记 `public`/`private`

### 架构原则
1. **单一职责**: View 仅负责渲染和交互，业务逻辑放在 Services/ViewModels
2. **状态管理**: 使用 `@Observable` 和 `@Bindable` 进行状态绑定
3. **依赖注入**: 通过构造函数注入服务，便于测试替换
4. **错误处理**: 使用 `Result` 类型或 `throws`，避免裸异常

### 测试规范
- **框架**: Swift Testing / XCTest
- **命名**: `testScenarioProviderInjectsTimeoutFailure()` (行为+预期格式)
- **覆盖要求**: 每个新功能至少 1 条主路径测试 + 1 条异常/边界测试
- **回归测试**: 修复缺陷时必须添加对应回归测试

### 文档规范
- 计划文档存放于 `docs/plans/`
- 运维手册存放于 `docs/operations/`
- 经验沉淀存放于 `docs/solutions/`
- 头脑风暴存放于 `docs/brainstorms/`
- 任务报告存放于 `docs/operations/task-reports/`

## 核心功能模块

### 1. 工具管理 (Tool Management)
- 自动检测已安装的 CLI 工具
- 支持安装、更新、卸载操作
- 批量操作支持（多选批量检查更新/更新/卸载）
- 工具配置编辑（支持直接编辑配置文件的工具）

### 2. 终端工作台 (Terminal Workspace)
- 集成 Ghostty 高性能终端
- 多会话管理（创建、切换、关闭、恢复）
- 工作目录管理（最近使用、收藏夹）
- 终端状态持久化（会话恢复）

### 3. 配置服务 (Config Services)
- `CLIDetectionService`: 检测工具安装状态
- `ToolInstallationService`: 处理安装/更新/卸载
- `ConfigEditorService`: 管理配置文件编辑

### 4. 设计系统 (Design System)
- 基于 DesignTokens 的颜色系统
- Light theme 为主，支持无障碍减少动画
- 品牌色: `#007BFF` (蓝色系)

## 交付门禁 (来自 AGENTS.md)

实施任务前必须回答：
1. UI 是否定义了主流程（用户第一步、第二步、第三步）？
2. 关键系统能力是否覆盖真实运行环境差异（.app 启动 PATH vs 终端 PATH）？
3. "未安装/不可用"类结论是否做了多路径与回退检测？
4. 是否完成可用性验证（按钮可见、核心路径可达、首次使用有引导）？

### 提交前必须执行
```bash
bash scripts/verify-plan-implementation.sh \
  --plan <计划文档> \
  --report <完成报告文档>
```

## 关键文件索引

| 文件路径 | 说明 |
|---------|------|
| `AgentOS/Package.swift` | Swift Package 配置，定义依赖和构建目标 |
| `AgentOS/Sources/AgentOS/AgentOSApp.swift` | 应用入口，窗口配置 |
| `AgentOS/Sources/AgentOS/MainView.swift` | 主界面，侧边栏+详情面板布局 |
| `AgentOS/Sources/AgentOS/AppState.swift` | 全局状态管理，业务逻辑编排 |
| `AgentOS/Sources/AgentOS/DesignTokens.swift` | 设计令牌，颜色定义 |
| `scripts/build-ghosttykit.sh` | GhosttyKit 构建脚本 |
| `scripts/verify-plan-implementation.sh` | 计划实施校验脚本 |
| `AGENTS.md` | 项目级代理行为规范 |

## 外部依赖

- **Ghostty**: 终端模拟器核心 (Zig 编写，通过 xcframework 集成)
- **SwiftUI**: Apple 原生 UI 框架
- **AppKit**: macOS 原生应用支持

## 注意事项

1. **PATH 环境**: .app 启动时的 PATH 可能与终端不同，需做回退检测
2. **Ghostty 版本**: 与 Ghostty 源码版本需保持兼容
3. **权限**: 部分 CLI 操作可能需要用户授权
4. **持久化**: 终端会话状态存储于 UserDefaults， schema version 管理
