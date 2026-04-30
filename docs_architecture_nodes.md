# Unified Node + Blackboard 架构（无 RAG 版本）

## 核心原则
- `tool node = skill + exec`：节点安装后生成 skill，执行时调用 CLI。
- `memory node = upload_to_model_api`：文档不入库、不切分、不向量检索。
- Agent Loop 采用 blackboard：一个文档一个 blackboard，cell 输出发布到 blackboard 供后续 cell 消费。

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
2. 逐个执行可运行 cell。
3. 每个 cell 的输出写入 blackboard（success/error 都要记录）。
4. 下一个 cell 优先读取 blackboard 上下文（而不是重新推断历史）。
5. 任务结束后 blackboard 可用于 UI 回放与审计。

## CLI 市场
- 只展示官方源。
- 下载与安装走官方仓库。
- 安装完成后自动生成 skill（由 CLI `--help` 推导参数模板与示例）。

## Memory Node（@文档）
- 用户通过 `@path/to/file.pdf` 显式引用。
- 运行时由 memory node 调模型 API 文件上传工具。
- 上传返回 file id，后续 cell 可直接引用该 file id。

