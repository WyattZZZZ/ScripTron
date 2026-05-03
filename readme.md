# ScripTron UI 长任务（Workspace + Project Studio 重构）

## 目标
当前主 UI 存在信息层级、导航归属、视觉一致性与工作流表达问题。重新以两张参考图为准，重构为浅色「Workspace Dashboard + Project Studio」双层产品结构，同时保留现有核心能力（项目、文件树、编辑区、运行、日志、Marketplace/Node Library、Settings）。

> 当前优先级调整：先把软件核心体验做扎实（编辑、运行、blackboard、项目流转），CLI 生态扩展后置。

---

## 总体策略

- **双层信息架构**：
  1. Workspace 层：项目总览、搜索、协作入口、最近活动、创建自动化。
  2. Project Studio 层：当前项目、脚本标签、Explorer/Search/Tool Nodes/RAG Nodes/History、Run/Debug、底部状态栏。
- **视觉基准以参考图为准**：
  - 浅灰应用背景，白色/浅灰内容卡片，深青绿色作为主操作色，紫色作为知识/RAG 辅助色。
  - 大面积留白、宽 Sidebar、强标题层级、圆角卡片、轻阴影、细分割线。
  - 图标优先，文本只用于必要导航与业务内容。
- **代码迁移策略**：
  - 保留关键 DOM id 与数据挂载点（例如 `#file-tree`、`#tabs`、`#editor-area`、`#exec-log`），但允许外层布局重写。
  - 先做静态壳层与路由状态，再接回现有 JS 事件。
  - Workspace 与 Project Studio 共用 token、按钮、卡片、状态徽标、顶部栏与 Sidebar 组件。

---

## 里程碑拆解（Long Task）

## Phase 0：问题复盘与参考图拆解（0.5 天）
- [x] 保存当前主 UI 截图，记录现有问题：
  - [x] Workspace/Project/Editor/Marketplace 边界不清。
  - [x] 主导航与当前任务状态不够明显。
  - [x] 卡片密度、按钮层级、日志区域和编辑区域视觉不统一。
  - [x] 运行态、空状态、错误态、加载态缺少同一套语言。
- [x] 拆解参考图 1：Workspace Dashboard。
  - [x] 左侧品牌区：logo、Scriptron、Automation Studio。
  - [x] 顶部搜索：Search automations。
  - [x] 右侧工具区：通知、设置、用户信息。
  - [x] 主内容：Workspace 标题、协作头像、项目卡片、Start Automating CTA、底部 Command Center。
- [x] 拆解参考图 2：Project Studio / Node Library。
  - [x] 左侧项目 Sidebar：Project Alpha、New Script、Explorer/Search/Tool Nodes/RAG Nodes/History、Extensions/Settings。
  - [x] 顶部栏：Scriptron、文件标签、Share/Settings、Debug、Run、头像。
  - [x] 主内容：Node Library、Tool Nodes、RAG Nodes、状态栏。
- [x] 列出必须保留的产品能力与 DOM 锚点。

**验收标准**
- 输出一份可对照的 UI 问题清单与参考图组件清单。
- 明确 Workspace 层与 Project Studio 层的切换关系。

---

## Phase 1：视觉系统重建（1 天）
- [x] 重新定义浅色设计 token：
  - [x] Background：应用背景使用冷浅灰，不使用纯白铺满。
  - [x] Surface：白色主卡片、浅灰二级卡片、淡青激活态、淡紫 RAG 态。
  - [x] Primary：深青绿色，用于 New Project/New Script/Run/CTA。
  - [x] Accent：紫色，用于 RAG、可靠性、知识库进度。
  - [x] Text：标题近黑，正文冷灰，辅助信息大写小字母间距。
- [x] 字体系统统一为 Manrope 优先，代码/日志使用等宽回退。
- [x] 组件 token：
  - [x] 卡片圆角 20-24px，内部控件圆角 10-14px。
  - [x] Sidebar 宽度约 320px，主内容最大宽度按视口伸展。
  - [x] 阴影只用于浮层、主卡片与 Command Center。
  - [x] 分割线使用低对比边框，不使用重边框。
- [x] 图标策略：
  - [x] 使用现有图标库或 Material Symbols，按钮内优先图标。
  - [x] 关键图标需要统一线宽、尺寸与颜色。

**验收标准**
- 仅看空壳页面时，视觉应接近两张参考图：浅色、通透、克制、深青主色明确。
- token 能支撑 Workspace 卡片、Project Sidebar、Node Library、Editor、日志面板共用。

---

## Phase 2：Workspace Dashboard 重做（1~1.5 天）
- [x] 实现 Workspace 顶层布局。
  - [x] 左侧固定 Sidebar：品牌、New Project、All Projects/Shared/Recent/Archived、Help Center/Log Out。
  - [x] 顶部栏：搜索框、通知、设置、用户资料。
  - [x] 主区域：Workspace 标题、说明文案、协作头像、Share Workspace。
- [x] 项目卡片体系。
  - [x] 普通项目卡：图标、状态徽标、标题、描述、Health Metric、进度条、更新时间。
  - [x] Draft/Idle/Active 状态分别使用低饱和徽标。
  - [x] 大横向项目卡：关键指标、插图区、同步/运行摘要。
  - [x] Start Automating CTA：深青背景、居中加号、短文案。
- [x] 底部 Command Center。
  - [x] 居中浮动胶囊，包含快捷键、Quick Action、View History。
  - [x] 保持不遮挡主要内容，窄屏时收缩。
- [x] 交互映射。
  - [x] New Project 进入项目创建流程。
  - [x] 点击项目卡进入 Project Studio。
  - [x] All Projects/Recent/Archived 过滤项目列表。

**验收标准**
- 打开应用默认进入 Workspace。
- 第一屏能明确表达“自动化项目管理工作台”，不再像编辑器或设置页。
- 项目卡、CTA、Command Center 在桌面宽度下与参考图 1 构图一致。

---

## Phase 3：Project Studio 壳层重做（1~1.5 天）
- [x] 实现项目工作台布局。
  - [x] 左侧 Project Sidebar：项目图标、项目名、路径、New Script。
  - [x] 导航项：Explorer、Search、Tool Nodes、RAG Nodes、History。
  - [x] 底部项：Extensions、Settings。
  - [x] 当前导航使用深青文字、图标和右侧竖线指示。
- [x] 顶部文件栏。
  - [x] 左侧显示 Scriptron 与打开文件标签：Main.script、Utils.py、Data.json 等。
  - [x] 右侧显示 Share、Settings、Debug、Run、用户头像。
  - [x] Run 按钮为深青主按钮，Debug 为低调文本按钮。
- [x] 底部状态栏。
  - [x] 显示运行环境、编码、光标位置、连接状态。
  - [x] 状态栏固定底部，不挤压主内容。
- [x] 保留现有编辑器挂载点。
  - [x] `#file-tree` 放入 Explorer 面板。
  - [x] `#tabs` 映射到顶部文件标签。
  - [x] `#editor-area` 保留在编辑视图中。
  - [x] `#exec-log` 映射到 History/运行抽屉。

**验收标准**
- 点击 Workspace 项目卡后进入 Project Studio。
- 项目侧栏、顶部文件栏、底部状态栏与参考图 2 构图一致。
- Run、Debug、文件切换、Explorer 不破坏现有功能。

---

## Phase 4：Node Library / Marketplace 重做（1~1.5 天）
- [x] 将 Marketplace 重命名或映射为 Node Library 视图。
- [x] Tool Nodes 区。
  - [x] 标题行：Tool Nodes、细分割线、右侧 active units。
  - [x] 三列工具卡：Web Search、REST API、Notification。
  - [x] 每张卡包含图标、标题、描述、能力标签。
  - [x] 工具卡使用浅灰卡片，不使用强边框。
- [x] RAG Nodes 区。
  - [x] 大型 Enterprise Knowledge Base 卡：紫色渐变、图标、标题、描述。
  - [x] 右侧知识库小卡：Doc Search、状态徽标、进度条。
  - [x] 保留离线/同步/错误状态样式。
- [x] 安装与配置流程。
  - [x] 未安装节点显示 Install/Configure。
  - [x] 已安装节点显示 Synced/Active/Offline。
  - [x] 安装日志进入运行记录与 blackboard。

**验收标准**
- Node Library 页面视觉接近参考图 2。
- Tool Nodes 与 RAG Nodes 区分清楚，不再混成普通设置页。
- 现有 registry/安装流程可从新卡片入口触发。

---

## Phase 5：编辑器、运行日志与状态体验统一（1~1.5 天）
- [x] 编辑器视图按 Project Studio 风格重排。
  - [x] Explorer 与文件标签保持参考图 2 的导航语言。
  - [x] Cell/Script 编辑区使用浅色代码面板，不做厚重 IDE 暗色。
  - [x] 空状态引导创建 New Script。
- [x] 运行体验。
  - [x] Run 按钮支持 ready/running/success/error/disabled 状态。
  - [x] Debug 与 Run 行为区分清楚。
  - [x] 执行日志可从 History 导航或抽屉打开。
  - [x] success/error 顶层运行态需要进一步同步到顶部栏。
- [x] 日志样式。
  - [x] thinking/tool_call/success/fail/error 使用统一状态色。
  - [x] blackboard 产物以可折叠条目展示。
  - [x] 错误态提供重试与查看详情入口。
- [x] Settings/Extensions。
  - [x] 与 Project Sidebar 底部入口一致。
  - [x] 表单、provider-card、API key 输入框全部套用新 token。
  - [x] Extensions 需要接入真实扩展列表。

**验收标准**
- 编辑、运行、日志三条主链路能在新 Project Studio 中完整闭环。
- 错误、空、加载、运行中状态都有一致视觉，不再临时拼接。

---

## Phase 6：响应式、可访问性与回归发布（0.5~1 天）
- [x] 响应式适配。
  - [x] 桌面宽屏按参考图构图完整展示。
  - [x] 中等宽度下卡片从三列降为两列，Sidebar 可收起为图标栏。
  - [x] 小宽度下 Workspace 和 Project Studio 仍可完成核心操作。
- [x] 可访问性与微交互。
  - [x] Tab 顺序覆盖 Sidebar、Topbar、卡片、编辑器、日志。
  - [x] Enter/Space 激活主要按钮，Esc 返回 Workspace/关闭当前项目上下文。
  - [x] hover/active/focus/running 动画统一 150-250ms。
  - [x] 支持 prefers-reduced-motion。
- [x] 视觉回归。
  - [x] 截图场景：Workspace、Project Studio Explorer、Node Library、Editor、Run Log、Settings。
  - [x] 检查文本不溢出、不重叠，卡片高度稳定。
  - [x] Tauri build 验证。
- [x] 清理旧 UI。
  - [x] 删除不再使用的深色 IDE 兼容样式。
  - [x] 补齐 UI 规范文档：token、组件、状态、页面结构。

**验证记录**
- `node --check ui/main.js`
- `node --check ui/marketplace.js`
- `node --check ui/editor.js`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" npm run build`
- 视觉截图：Workspace、Project Studio Explorer、Node Library、History、Settings、Extensions、Blackboard、760px Project Studio。

**验收标准**
- Phase 0-6 重新验收后，主 UI 不再沿用有问题的旧结构。
- 两张参考图对应的 Workspace 与 Project Studio 都有可运行实现。
- 进入 Phase 7 之前，基础产品壳层稳定。

---

## Phase 7：多层记忆机制（Claude Code 风格）+ 主 Agent（1.5~2 天）

- [x] 新增全局主记忆（跨项目）：
  - [x] 用户称呼偏好（例如“如何称呼用户”）
  - [x] Agent 性格与输出风格偏好（简洁/详细、语气、语言）
  - [x] 全局执行守则（是否默认先预览再写入、是否自动运行命令）
- [x] 新增项目记忆（项目级）：
  - [x] 项目内代码/文档格式要求（命名、目录结构、注释规范）
  - [x] 项目内任务约束（禁止目录、必须测试、输出模板）
  - [x] 项目内长期上下文（业务术语、缩写解释）
  - [x] 项目配置文件，是否achieve，项目基本信息
- [x] 记忆读写策略：
  - [x] 打开项目时：加载全局记忆 + 项目记忆到内存
  - [x] 执行中：Agent 可追加记忆草稿（需可审计）
  - [x] 保存/关闭时：持久化回本地存储
- [x] UI 支持：
  - [x] Settings 增加 “Global Memory / Project Memory” 管理入口
  - [x] 支持查看差异与回滚历史

**验收标准**
- 全局记忆对所有项目生效；项目记忆仅在对应项目生效。
- Agent 输出风格与格式可被稳定约束，并可追溯来源。

---

## Phase 8：项目主 Agent + 本地 CLI 接口（1.5~2 天）

- [x] 新增“主 Agent”概念（Project Orchestrator）：
  - [x] 能创建普通文件、目录、`.tron` 文件
  - [x] 能读取/更新项目级记忆与 blackboard
  - [x] 能调用已安装官方 CLI 节点
- [x] 软件自身提供本地 CLI（供 Agent 调用）：
  - [x] `scriptron project create <name>`：在 `~/Documents` 下创建项目目录
  - [x] `scriptron file create <path>`：创建普通文件
  - [x] `scriptron tron create <path>`：创建 `.tron` 文件（带默认 blackboard）
  - [x] `scriptron project open <path>`：切换/打开项目
- [x] 安全与边界：
  - [x] CLI 默认仅允许在 `~/Documents` 与当前项目目录内写入
  - [x] 所有写操作进入执行日志与 blackboard 审计
  - [x] 提供 dry-run 模式（先展示计划再执行）

**验收标准**
- 主 Agent 可独立完成“创建项目 → 生成文件 → 生成 tron 工作流 → 执行”闭环。
- 所有文件操作可在日志与 blackboard 中回放。

---

## Phase 9：Adaptive Skill 自修复机制（1~1.5 天）

- [x] 新增 `adaptive_skill_runner`：
  - [x] 每次调用 skill 失败后自动重试（指数退避 + 最大重试次数）。
  - [x] 每次失败都记录失败原因（参数错误、命令不存在、权限问题、超时等）。
  - [x] 重试前自动修改 skill 调用参数（基于错误类型修正）。
- [x] 新增 skill 自更新流程：
  - [x] 若连续失败达到阈值，触发“skill patch”流程，自动重写该 skill 的参数映射或命令模板。
  - [x] Patch 后再次执行验证，直到成功或达到安全终止条件。
  - [x] 将每次 patch 版本写入 blackboard 与 skill 版本历史（可回滚）。
- [x] 终止与安全策略：
  - [x] 设置最大重试轮次（防止无限循环）。
  - [x] 对高风险操作必须先 dry-run 再正式执行。
  - [x] patch 不可越权（禁止修改未授权路径与未授权命令）。
- [x] 可观测性：
  - [x] UI 增加“Skill Retry Trace”面板，展示每轮失败原因与修正动作。
  - [x] blackboard 持久化每轮尝试输入、输出、错误、修复 diff。

**验收标准**
- skill 首次失败后，系统能够自动修复调用并重试，直到成功或达到安全阈值。
- 每次自动修复都有完整审计日志，可追踪、可回滚。

---

## Phase 10：`@` 引用选择器 + `.tron` 模块化（无记忆节点）（2~3 天）

- [x] 输入框 `@` 触发下拉选择器（mention picker）。
- [x] 下拉选择器包含双 Tab：
  - [x] CLI 工具 Tab
  - [x] 文件 Tab
- [x] 搜索行为：
  - [x] 用户输入后本地实时搜索（项目内文件 + 已安装工具）。
  - [x] 输入停顿后触发云端插件库搜索（当前为 marketplace suggestion 占位实现）。
  - [x] 以空格作为搜索结束边界，后续字符进入普通输入。
- [x] 文件处理策略：
  - [x] 非 `.tron` 文件：直接作为输入附件上传给模型。
  - [x] `.tron` 文件：展示二级选择栏（位于原下拉栏左侧）：
    - [x] 可执行模块（作为函数调用）
    - [x] 文本模块（作为提示词注入）
- [x] `.tron` 模块化规范：
  - [x] 文件包含目录索引区（模块元信息）+ 内容区。
  - [x] 可执行模块必须显式命名。
  - [x] 文本模块以标题作为模块名。
- [x] blackboard 记录：
  - [x] 每次 `@` 选择写入 blackboard（引用类型、目标、模块名、注入方式）。

**验收标准**
- 用户通过 `@` 能在一次交互中完成“搜索→选择→注入”。
- `.tron` 文件可按模块精确引用，且执行/提示词路径清晰可追溯。

---

## 技术实现建议

1. **页面状态先行**
   - 先在前端建立 `workspace | project` 两个顶层 view state，再逐步接回真实数据。
   - Workspace 负责项目列表与创建入口；Project Studio 负责脚本、节点、运行与设置。
2. **样式拆分**
   - 建议从单个 `ui/style.css` 拆成 `theme.css + layout.css + components.css`，再按需要迁移。
   - 若暂时不拆文件，也必须按 token/layout/component/view 顺序组织 CSS。
3. **组件优先级**
   - 先做 Shell：Sidebar、Topbar、Statusbar、Command Center。
   - 再做 Card：project-card、node-card、rag-card、metric-card、log-item。
   - 最后做业务视图：Workspace、Node Library、Editor、Settings。
4. **图标与插图**
   - 导航和按钮优先使用图标库图标，保持统一线宽。
   - Workspace 项目卡里的插图只做低对比装饰，不抢内容层级。
5. **性能**
   - 少用大面积 `backdrop-filter`；参考图里的通透感主要依赖浅色层级、阴影和留白。
   - 卡片 hover 只改变阴影、边框或轻微位移，避免布局跳动。

---

## 风险与规避

- 风险：Workspace 与 Project Studio 混在一个页面里，导致导航语义继续混乱。
  - 规避：顶层 view state 明确区分，项目卡点击才进入项目工作台。
- 风险：重写外层结构导致 `editor.js/main.js/marketplace.js` 绑定失效。
  - 规避：保留关键 id，迁移前列出事件锚点，迁移后逐项验收。
- 风险：参考图中的 RAG 表述与当前“无 RAG 版本”架构冲突。
  - 规避：UI 可保留 RAG Nodes 视觉分区，但实现层先映射为知识/文档节点或禁用态，后续再调整术语。
- 风险：浅色编辑器与日志可读性不足。
  - 规避：代码/日志区域使用更高对比文本，状态色只做辅助，不承担主要可读信息。
- 风险：Tauri 标题栏、拖拽区、窗口高度与自定义 Topbar 冲突。
  - 规避：单独验收 macOS 窗口拖拽、按钮点击、全屏与最小宽度。

---

## 交付物清单
- [x] 新版 UI token 与组件样式（`ui/style.css` 或拆分后的 CSS 文件）
- [x] 重写后的 `ui/index.html` 顶层结构：Workspace view + Project Studio view
- [x] Workspace Dashboard 页面实现
- [x] Project Studio Shell 页面实现
- [x] Node Library / Marketplace 页面实现
- [x] Editor + Run Log + Settings 视图回归
- [x] 关键页面截图：Workspace、Node Library、Editor、Run Log、Settings
- [x] UI 规范文档：token、组件、状态、响应式、交互规则
- [x] 回归测试记录：点击链路、键盘链路、Tauri dev/build
