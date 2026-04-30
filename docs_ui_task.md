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
- [ ] 保存当前 UI 截图基线（欢迎页、打开文件态、运行日志展开/折叠态）。
- [ ] 标注关键交互流程：
  - 新建文件
  - 打开/切换标签
  - Run 执行
  - 查看 log
  - Marketplace 安装
  - Settings 切换 provider
- [ ] 添加最小视觉回归脚本（可选 Playwright）。

**验收标准**
- 任何后续改版都可对照同场景截图。

---

## Phase 1：设计系统底座（1 天）
- [ ] 迁移颜色 token 到 CSS 变量（基于你给的 Tailwind 颜色命名）：
  - `--primary`, `--surface-container-low`, `--on-surface-variant` 等。
- [ ] 引入 `Manrope` 字体；补充数字与等宽字体回退策略。
- [ ] 定义统一间距、圆角、阴影、边框 token。
- [ ] 增加浅色为默认、深色可选（`html.light / html.dark`）双主题结构。

**验收标准**
- 全局无需改 DOM，仅替换变量即可让页面从旧暗色切到新浅色语义色。

---

## Phase 2：壳层布局重构（1~1.5 天）
- [ ] Sidebar 改成新视觉：品牌区、新建按钮、导航分组、底部帮助区。
- [ ] Main 区增加 Topbar（搜索、通知、设置、用户信息）。
- [ ] 保持现有业务容器 id：
  - `#file-tree` 挂到 “All Projects” 容器
  - `#panel-marketplace`、`#panel-settings` 改为页面内二级分区
- [ ] 适配窗口高度与滚动策略（Sidebar 独立滚动，主内容滚动）。

**验收标准**
- 新布局可正常显示且核心按钮可点击。

---

## Phase 3：编辑器与执行面板样式重做（1.5~2 天）
- [ ] 将 `#tab-bar` 改为轻量胶囊/卡片标签风格。
- [ ] `Run` 按钮改为主题主按钮（含运行中态、禁用态）。
- [ ] Cell 组件改为浅色卡片体系：
  - Header 的 run/static badge 改新语义色
  - hover/focus 阴影统一
- [ ] `#exec-panel` 改为玻璃态/卡片态可折叠日志抽屉。
- [ ] Log 条目按类型重着色（thinking/tool_call/success/fail/error）。

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

