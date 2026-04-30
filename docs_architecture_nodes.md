# Unified Node + Blackboard 架构（无 RAG 版本）

## 核心原则
- `tool node = skill + exec`：节点安装后生成 skill，执行时调用 CLI。
- `memory node = upload_to_model_api`：文档不入库、不切分、不向量检索。
- Agent Loop 采用 blackboard：一个文档一个 blackboard，cell 输出发布到 blackboard 供后续 cell 消费。

## 多层记忆（无 RAG）

### Layer A：全局主记忆（跨项目）
- 用途：统一用户偏好与 Agent 人格风格。
- 示例：
  - 用户称呼偏好
  - 输出语言/语气偏好
  - 全局执行偏好（是否默认 dry-run）

### Layer B：项目记忆（项目级）
- 用途：约束当前项目内的格式、规范、术语与目标。
- 示例：
  - 文件命名规范
  - 代码格式要求
  - 文档模板要求

### Layer C：文档 blackboard（文件级）
- 用途：记录当前 `.tron` 文件运行历史、产物和中间决策。
- 特性：随 `.tron` 持久化，打开时加载到内存，保存/关闭时落盘。

## Node 抽象
```json
{
  "id": "feishu.cli",
  "kind": "tool|memory",
  "name": "Feishu CLI",
  "version": "x.y.z",
  "source": {
    "type": "official",
    "url": "https://...",
    "signature": "..."
  },
  "runtime": {
    "engine": "cli|model_upload",
    "command": "feishu",
    "skill_path": "skills/feishu.md"
  }
}
```

## Blackboard 结构
```json
{
  "board_id": "doc:xxx.tron",
  "cells": [
    {
      "cell_id": "run-1",
      "input": "...",
      "output": "...",
      "status": "ok|error",
      "published_at": "..."
    }
  ],
  "artifacts": [
    {"type": "file", "path": "..."},
    {"type": "tool_result", "node": "feishu.cli", "payload": "..."}
  ]
}
```

## 执行流程
1. Agent 读取当前文档，创建 blackboard。
2. 加载全局记忆 + 项目记忆到当前上下文。
3. 逐个执行可运行 cell。
4. 每个 cell 的输出写入 blackboard（success/error 都要记录）。
5. 下一个 cell 优先读取 blackboard 上下文（而不是重新推断历史）。
6. 任务结束后 blackboard 可用于 UI 回放与审计。

## 主 Agent（Project Orchestrator）
- 职责：在一个项目内编排所有节点与文件操作。
- 能力：
  - 创建/编辑普通文件
  - 创建 `.tron` 文件
  - 调用官方 CLI tool node
  - 维护项目记忆与 blackboard

## 软件内建 CLI（给 Agent 调用）
- `scriptron project create <name>`：在 `~/Documents` 创建项目目录。
- `scriptron file create <path>`：创建普通文件。
- `scriptron tron create <path>`：创建带默认 blackboard 的 `.tron` 文件。
- `scriptron project open <path>`：打开/切换项目。

## CLI 市场
- 只展示官方源。
- 下载与安装走官方仓库。
- 安装完成后自动生成 skill（由 CLI `--help` 推导参数模板与示例）。

## Memory Node（@文档）
- 用户通过 `@path/to/file.pdf` 显式引用。
- 运行时由 memory node 调模型 API 文件上传工具。
- 上传返回 file id，后续 cell 可直接引用该 file id。
