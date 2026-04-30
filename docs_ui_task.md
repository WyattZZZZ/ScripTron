# ScripTron UI 长任务（Tailwind + Manrope 主题重构）

## 目标
将当前 `ui/index.html + ui/style.css` 的深色 IDE 风格界面，重构为你提供的浅色「Workspace Dashboard」视觉体系，同时尽量保留现有产品核心能力（文件树、编辑区、执行日志、Marketplace、Settings）。

---

## 总体策略

- **不一次性推倒重来**，采用「分阶段迁移」：
  1. 先引入新设计 token（颜色、字体、圆角、阴影）；
  2. 再做布局替换（Sidebar / Topbar / Canvas）；
  3. 最后把业务组件映射到新卡片化风格。
- **保留原有 DOM id 与关键数据挂载点**（例如 `#file-tree`、`#tabs`、`#editor-area`、`#exec-log`），降低 JS 逻辑改造成本。
- **建立兼容层**：先让旧 class 与新 class 并行一段时间，避免一次改动过大导致功能不可用。

---

## 里程碑拆解（Long Task）

## Phase 0：基线冻结与可视回归（0.5 天）
- [x] 保存当前 UI 截图基线（欢迎页、打开文件态、运行日志展开/折叠态）。
- [x] 标注关键交互流程：
  - 新建文件
  - 打开/切换标签
  - Run 执行
  - 查看 log
  - Marketplace 安装
  - Settings 切换 provider
- [x] 添加最小视觉回归脚本（可选 Playwright）。

**验收标准**
- 任何后续改版都可对照同场景截图。

---

## Phase 1：设计系统底座（1 天）
- [x] 迁移颜色 token 到 CSS 变量（基于你给的 Tailwind 颜色命名）：
  - `--primary`, `--surface-container-low`, `--on-surface-variant` 等。
- [x] 引入 `Manrope` 字体；补充数字与等宽字体回退策略。
- [x] 定义统一间距、圆角、阴影、边框 token。
- [x] 增加浅色为默认、深色可选（`html.light / html.dark`）双主题结构。

**验收标准**
- 全局无需改 DOM，仅替换变量即可让页面从旧暗色切到新浅色语义色。

---

## Phase 2：壳层布局重构（1~1.5 天）
- [x] Sidebar 改成新视觉：品牌区、新建按钮、导航分组、底部帮助区。
- [x] Main 区增加 Topbar（搜索、通知、设置、用户信息）。
- [x] 保持现有业务容器 id：
  - `#file-tree` 挂到 “All Projects” 容器
  - `#panel-marketplace`、`#panel-settings` 改为页面内二级分区
- [x] 适配窗口高度与滚动策略（Sidebar 独立滚动，主内容滚动）。

**验收标准**
- 新布局可正常显示且核心按钮可点击。

### Phase 0~2 完成说明（2026-04-30）

- 已完成浅色主题 token 迁移、字体切换、Tailwind 主题注入及双主题 class 基础。
- 已完成壳层重构，保留关键挂载点：`#file-tree`、`#tabs`、`#editor-area`、`#exec-log`。
- 已完成执行日志区域的交互回归修正（含 `toggle-icon`）。
- 已完成黑板（blackboard）隐式持久化接入，保证后续 Phase 3 可以直接消费运行历史。

---

## Phase 3：编辑器与执行面板样式重做（1.5~2 天）
- [x] 将 `#tab-bar` 改为轻量胶囊/卡片标签风格。
- [x] `Run` 按钮改为主题主按钮（含运行中态、禁用态）。
- [x] Cell 组件改为浅色卡片体系：
  - Header 的 run/static badge 改新语义色
  - hover/focus 阴影统一
- [x] `#exec-panel` 改为玻璃态/卡片态可折叠日志抽屉。
- [x] Log 条目按类型重着色（thinking/tool_call/success/fail/error）。

**验收标准**
- 编辑、运行、日志三条主链路体验完整，视觉统一。

---

## Phase 4：Marketplace / Settings 卡片化（1 天）
- [ ] `tool-card` 升级为 dashboard 卡片（状态、版本、操作按钮层次优化）。
- [ ] provider-card 采用新卡片视觉 + 激活态强调。
- [ ] 表单控件（select/input/textarea）统一为轻量面板风格。

**验收标准**
- Marketplace 与 Settings 视觉风格与主界面一致。

---

## Phase 5：微交互与可访问性（1 天）
- [ ] Hover/active/focus ring 统一动画时长（150~250ms）。
- [ ] 键盘可达性：Tab 顺序、Enter/Space 操作、Esc 关闭 modal。
- [ ] 对比度校正（尤其 `on-surface-variant` 文本）。
- [ ] 减少动画模式支持（prefers-reduced-motion）。

**验收标准**
- 可访问性扫描无严重错误，交互手感一致。

---

## Phase 6：收尾与发布（0.5~1 天）
- [ ] 清理兼容样式（删除旧 class 冗余）。
- [ ] 补齐 UI 文档：色板、组件说明、状态规范。
- [ ] 回归测试 + 打包验证（Tauri 多平台）。

**验收标准**
- 无功能回退；样式技术债可控。

---

## Phase 7：多层记忆机制（Claude Code 风格）+ 主 Agent（1.5~2 天）

- [ ] 新增全局主记忆（跨项目）：
  - [ ] 用户称呼偏好（例如“如何称呼用户”）
  - [ ] Agent 性格与输出风格偏好（简洁/详细、语气、语言）
  - [ ] 全局执行守则（是否默认先预览再写入、是否自动运行命令）
- [ ] 新增项目记忆（项目级）：
  - [ ] 项目内代码/文档格式要求（命名、目录结构、注释规范）
  - [ ] 项目内任务约束（禁止目录、必须测试、输出模板）
  - [ ] 项目内长期上下文（业务术语、缩写解释）
- [ ] 记忆读写策略：
  - [ ] 打开项目时：加载全局记忆 + 项目记忆到内存
  - [ ] 执行中：Agent 可追加记忆草稿（需可审计）
  - [ ] 保存/关闭时：持久化回本地存储
- [ ] UI 支持：
  - [ ] Settings 增加 “Global Memory / Project Memory” 管理入口
  - [ ] 支持查看差异与回滚历史

**验收标准**
- 全局记忆对所有项目生效；项目记忆仅在对应项目生效。
- Agent 输出风格与格式可被稳定约束，并可追溯来源。

---

## Phase 8：项目主 Agent + 本地 CLI 接口（1.5~2 天）

- [ ] 新增“主 Agent”概念（Project Orchestrator）：
  - [ ] 能创建普通文件、目录、`.tron` 文件
  - [ ] 能读取/更新项目级记忆与 blackboard
  - [ ] 能调用已安装官方 CLI 节点
- [ ] 软件自身提供本地 CLI（供 Agent 调用）：
  - [ ] `scriptron project create <name>`：在 `~/Documents` 下创建项目目录
  - [ ] `scriptron file create <path>`：创建普通文件
  - [ ] `scriptron tron create <path>`：创建 `.tron` 文件（带默认 blackboard）
  - [ ] `scriptron project open <path>`：切换/打开项目
- [ ] 安全与边界：
  - [ ] CLI 默认仅允许在 `~/Documents` 与当前项目目录内写入
  - [ ] 所有写操作进入执行日志与 blackboard 审计
  - [ ] 提供 dry-run 模式（先展示计划再执行）

**验收标准**
- 主 Agent 可独立完成“创建项目 → 生成文件 → 生成 tron 工作流 → 执行”闭环。
- 所有文件操作可在日志与 blackboard 中回放。

---

## Phase 9：Adaptive Skill 自修复机制（1~1.5 天）

- [ ] 新增 `adaptive_skill_runner`：
  - [ ] 每次调用 skill 失败后自动重试（指数退避 + 最大重试次数）。
  - [ ] 每次失败都记录失败原因（参数错误、命令不存在、权限问题、超时等）。
  - [ ] 重试前自动修改 skill 调用参数（基于错误类型修正）。
- [ ] 新增 skill 自更新流程：
  - [ ] 若连续失败达到阈值，触发“skill patch”流程，自动重写该 skill 的参数映射或命令模板。
  - [ ] Patch 后再次执行验证，直到成功或达到安全终止条件。
  - [ ] 将每次 patch 版本写入 blackboard 与 skill 版本历史（可回滚）。
- [ ] 终止与安全策略：
  - [ ] 设置最大重试轮次（防止无限循环）。
  - [ ] 对高风险操作必须先 dry-run 再正式执行。
  - [ ] patch 不可越权（禁止修改未授权路径与未授权命令）。
- [ ] 可观测性：
  - [ ] UI 增加“Skill Retry Trace”面板，展示每轮失败原因与修正动作。
  - [ ] blackboard 持久化每轮尝试输入、输出、错误、修复 diff。

**验收标准**
- skill 首次失败后，系统能够自动修复调用并重试，直到成功或达到安全阈值。
- 每次自动修复都有完整审计日志，可追踪、可回滚。

---

## 技术实现建议

1. **是否直接引入 Tailwind CDN？**
   - Tauri 本地可用，但生产更建议本地构建 Tailwind（可控、可离线、可裁剪）。
2. **推荐路径**
   - 第一步先用现有 `style.css` 实现你这套主题 token；
   - 第二步再决定是否切换 Tailwind 工程化。
3. **图标**
   - `material-symbols-outlined` 可用，但建议给关键操作保留 SVG fallback。
4. **性能**
   - 控制 blur/glass 使用范围，避免大面积 `backdrop-filter` 导致渲染压力。

---

## 风险与规避

- 风险：一次性替换 HTML 导致 `editor.js/main.js/marketplace.js` 绑定失效。
  - 规避：保留旧 id，不改事件锚点；样式优先，结构渐进。
- 风险：浅色主题在日志与代码文本可读性下降。
  - 规避：日志和编辑区使用更高对比度文本与中性底色。
- 风险：跨平台标题栏拖拽区域冲突。
  - 规避：延续 `-webkit-app-region` 规则并单独验收 macOS。

---

## 交付物清单
- [ ] 新版 `ui/style.css`（或拆分为 `theme.css + components.css`）
- [ ] 结构升级后的 `ui/index.html`
- [ ] 关键页面截图（before/after）
- [ ] UI 规范文档（token + 组件 + 状态）
- [ ] 回归测试记录

---

## 我建议的执行顺序（可直接开工）
1. 先做 **Phase 1 + Phase 2**（低风险，高可见收益）。
2. 再做 **Phase 3**（核心编辑体验）。
3. 最后做 **Phase 4~6**（打磨与发布）。
