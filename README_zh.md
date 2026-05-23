<div align="center">

# ScripTron

**本地优先的 macOS 自动化工作室 —— 用 LLM Agent 跑 `.tron` 文档。**

简体中文 · [English](./README.md)

</div>

---

ScripTron 是一个 macOS 原生 app，让你像写 Markdown 笔记一样编排和运行
Agent 自动化任务。每个 `.tron` 文件是一份"运行单元"（agent 指令）和
"文档单元"（静态上下文）混合的笔记本，背后是本地的工作区、Rust 网关层、
Hermes Agent，以及一个用于发布 CLI / 技能的插件市场（TronHub）。

![Workspace](docs/screenshots/workspace.png)

## 特性

- **原生 SwiftUI** 前端 + **Rust** 内核。不是 Electron，不是浏览器标签页。
- **`.tron` 笔记编辑器**：运行单元、文档单元、隐藏黑板、内联表格、
  Gen 单元（自然语言 → Markdown）。
- **Hermes Agent 运行时**：模型登录、供应方选择、工具和 skill 统一交给
  Hermes 管理，不再由 ScripTron 自己保存 API key。
- **工具调用循环**：Hermes Agent 可以调用工作区 registry 里所有已安装的 CLI，
  支持结构化参数和可审计的运行日志。
- **TronHub 插件系统**：从
  [`WyattZZZZ/ScripTron_Extension`](https://github.com/WyattZZZZ/ScripTron_Extension)
  一键安装 CLI、技能。插件需要时可自带 `install.sh`。
- **记忆系统**：全局 + 项目级记忆持久化在 `.troner.json`
  （偏好、格式规则、术语表、长上下文笔记）。
- **`@` 提及选择器**：把已装技能、项目文件、`.tron` 模块导出直接拽到
  agent prompt 里。
- **本地优先**：一切都在 `~/ScripTron/` 下，无云同步、无需注册账号。

## 截图

| 项目工作台 | 模型管理 |
| --- | --- |
| ![Project Studio](docs/screenshots/project-studio.png) | ![Model Management](docs/screenshots/model-management.png) |

| 插件市场 | 运行单元 & `@` 引用 |
| --- | --- |
| ![Marketplace](docs/screenshots/marketplace.png) | ![Run cell with @ mention picker](docs/screenshots/run-cell.png) |

## 安装

### 直接下载（推荐）

到 [Releases](https://github.com/WyattZZZZ/ScripTron/releases) 下载最新的
`ScripTron.app`，拖到 `/Applications`。第一次打开时右键 → 打开
（应用是 ad-hoc 签名）。

### 从源码构建

依赖：macOS 13+、Xcode 15+、Rust（rustup）、Swift 6.0、Node 18+
（仅当插件用到 `npm install`）。

```bash
git clone https://github.com/WyattZZZZ/ScripTron.git
cd ScripTron/macos/ScripTronNative
bash make-app.sh
open dist/ScripTron.app
```

`make-app.sh` 会跑 `cargo build -p scriptron-ffi`、`swift build`，
然后把 dylib 一起打包到 `dist/ScripTron.app`。

## 快速开始

1. **检查 Hermes。** 打开 *模型管理*，通过 Hermes 检查本地安装、登录、
   选择模型并查看网关状态。
2. **创建项目。** 点 *+ 新建项目* 起个名字，会自动生成一个起始 `.tron` 文件。
3. **写单元。** 混合 `markdown` 单元（上下文）和 `run` 单元（指令）。
   `Cmd+Enter` 运行当前 run 单元。Agent 可以访问已装 CLI 和 Hermes Agent skill。
4. **迭代。** 编辑、重跑、看运行日志。Agent 可以读写项目文件、通过 Hermes 调用 CLI，
   并把结果写回隐藏黑板供下一轮运行使用。

## `.tron` 文件格式

```
---blackboard---
{ "topic": "本周回顾" }
---

---run: false---
[[scriptron:run-name]] context

用户希望我们整理过去一周的事故快照。
---

---run: true---
[[scriptron:run-name]] generate

用 5 条 bullet 点总结事故，并把结果挂到黑板的 `digest` 字段。
---
```

- **运行单元**（`---run: true---`）按依赖顺序作为 agent prompt 执行。
  单元之间通过 `[[scriptron:run-name]] <name>` 互相引用。
- **文档单元**（`---run: false---` 或无标记）是静态上下文，每次运行都会
  共享。
- **黑板**（`---blackboard---` 块）是跨单元、跨运行共享的隐藏 JSON。
- **Gen 单元**（`[[scriptron:gen-markdown]]` 前缀）把自然语言用当前模型展开
  成 Markdown。

## 架构

```
macos/ScripTronNative              SwiftUI 应用（前端）
├── RustBridge.swift               C FFI 客户端（scriptron_call/scriptron_free_string）
├── AppModel.swift                 @MainActor ObservableObject，所有 UI 状态
└── Views: Workspace, ProjectStudio, ModelManagement, …

crates/
├── scriptron-ffi                  C-ABI 动态库（libscriptron_ffi.dylib）
│                                  C 字符串上的 JSON-RPC 派发
├── scriptron-core                 Host 逻辑（工作区、项目、.tron 文件、
│                                  blackboard、Hermes 迁移占位）
├── tron-parser                    .tron 文件解析
├── cli-registry                   .register/<name>/manifest.json 注册表
├── process-runner                 带超时的异步子进程
└── scriptron-cli                  CLI 二进制（`scriptron project create` 等）
```

Swift 端**只**通过 `RustBridge.swift` 调用 `scriptron_call(json_string)` 和 Rust
通信，再解析 JSON 响应。Agent runtime、模型、OAuth、工具、skills、审批、
clarify 与多 Agent 能力将迁移到官方 Hermes Agent TUI Gateway。

### 磁盘上的工作区结构

```
~/ScripTron/
├── <项目名>/                       一个项目一个目录，存 *.tron 文件
├── .register/<name>/              已安装的 CLI / 模型插件（带 manifest.json）
├── .skills/<name>/                已安装的技能（带 skill.json）
├── .tronhub/ScripTron_Extension/  TronHub 插件仓库的本地缓存
└── .troner.json                   全局 + 项目记忆，审计日志
```

## TronHub 插件

插件通过
[`WyattZZZZ/ScripTron_Extension`](https://github.com/WyattZZZZ/ScripTron_Extension)
分发。每个插件是一个目录，包含：

- `manifest.json`（或 `model.json` / `cli.json`）— 元数据
- `install.sh` — 安装底层工具（比如 `npm install -g @openai/codex`）
- `run.sh` — 入口脚本，按 `./run.sh --action {login,chat,run} [...]` 调用

ScripTron 点*安装*会把插件文件复制到 `.register/`，自动跑 `install.sh`
拉底层 CLI，然后给出*登录*按钮，点击后跑 `./run.sh --action login`。

## 路线图

完整的分阶段计划见 [docs/UI_REFACTOR_PLAN.md](docs/UI_REFACTOR_PLAN.md)。
Phase 0–10（Workspace UI、Project Studio、Node Library、编辑器、运行日志、
记忆、Agent、Hermes Agent skills、`@` 提及选择器）已全部完成。

## 贡献

- Bug 反馈和功能请求：欢迎开 issue。
- PR 欢迎 —— 提交前请确保 `cargo build` 和 `swift build` 都通过。
- Swift ↔ Rust FFI 边界是有意为之：业务逻辑全部留在 Rust crate，
  Swift 端只负责渲染状态和转发事件。

## 协议

待定。
