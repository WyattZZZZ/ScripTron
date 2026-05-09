#!/usr/bin/env python3
"""
Dailight — GitHub README 交互式日记解析引擎
用法: python dailight/generate.py
将 dailight/entries/*.md 解析后生成 dailight/README.md
"""

import os
import re
import sys
from datetime import datetime, date
from pathlib import Path
from collections import Counter

# ── 路径配置 ──────────────────────────────────────────────────────
SCRIPT_DIR   = Path(__file__).parent          # dailight/
ENTRIES_DIR  = SCRIPT_DIR / "entries"
README_PATH  = SCRIPT_DIR / "README.md"


# ── Frontmatter 解析器（无需第三方依赖）──────────────────────────
def parse_frontmatter(text: str) -> tuple[dict, str]:
    """
    解析 YAML frontmatter。
    返回 (meta_dict, body_str)。
    若无 frontmatter，返回 ({}, 原文)。
    """
    meta = {}
    body = text

    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            fm_block = text[3:end].strip()
            body = text[end + 4:].lstrip("\n")
            for line in fm_block.splitlines():
                if ":" in line:
                    key, _, val = line.partition(":")
                    key = key.strip()
                    val = val.strip()
                    # 解析列表：[a, b, c]
                    if val.startswith("[") and val.endswith("]"):
                        items = [v.strip().strip("'\"") for v in val[1:-1].split(",")]
                        meta[key] = [i for i in items if i]
                    else:
                        meta[key] = val.strip("'\"")

    return meta, body


# ── 从正文提取标题（第一行 # 标题）─────────────────────────────
def extract_title_from_body(body: str) -> str | None:
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("# "):
            return line[2:].strip()
    return None


# ── 计算连续写作天数 ──────────────────────────────────────────
def calc_streak(dates: list[date]) -> int:
    if not dates:
        return 0
    sorted_dates = sorted(set(dates), reverse=True)
    today = date.today()
    streak = 0
    current = today
    for d in sorted_dates:
        diff = (current - d).days
        if diff <= 1:
            streak += 1
            current = d
        else:
            break
    return streak


# ── 加载所有日记条目 ──────────────────────────────────────────
def load_entries() -> list[dict]:
    entries = []
    if not ENTRIES_DIR.exists():
        return entries

    for md_file in sorted(ENTRIES_DIR.glob("*.md"), reverse=True):
        name = md_file.stem  # YYYY-MM-DD

        # 验证文件名格式
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", name):
            continue

        text = md_file.read_text(encoding="utf-8")
        meta, body = parse_frontmatter(text)

        # 日期：frontmatter > 文件名
        raw_date = meta.get("date", name)
        try:
            entry_date = datetime.strptime(str(raw_date).strip(), "%Y-%m-%d").date()
        except ValueError:
            entry_date = datetime.strptime(name, "%Y-%m-%d").date()

        # 标题：frontmatter > 正文首行 # > 日期
        title = (
            meta.get("title")
            or extract_title_from_body(body)
            or str(entry_date)
        )

        tags = meta.get("tags", [])
        if isinstance(tags, str):
            tags = [t.strip() for t in tags.split(",") if t.strip()]

        entries.append({
            "date":  entry_date,
            "title": title,
            "mood":  meta.get("mood", ""),
            "tags":  tags,
            "body":  body.strip(),
            "file":  md_file.name,
        })

    # 按日期降序
    entries.sort(key=lambda e: e["date"], reverse=True)
    return entries


# ── 生成单条 <details> 块 ────────────────────────────────────
def render_entry(entry: dict) -> str:
    """生成单条可折叠日记块"""
    date_str = entry["date"].strftime("%Y-%m-%d")
    weekday  = entry["date"].strftime("%a")
    title    = entry["title"]
    mood     = f" · {entry['mood']}" if entry["mood"] else ""

    # 标签行（在正文内部，展开后可见）
    tag_str  = "  ".join(f"`{t}`" for t in entry["tags"]) if entry["tags"] else ""
    tag_line = f"\n🏷 {tag_str}\n" if tag_str else ""

    summary  = f"📅 **{date_str}** &nbsp;·&nbsp; *{weekday}* &nbsp;·&nbsp; {title}{mood}"
    body     = entry["body"]

    lines = [
        "<details>",
        f"<summary>{summary}</summary>",
        "",        # ← 空行使 GitHub 将后续内容当 Markdown 渲染
        tag_line,
        body,
        "",
        "</details>",
        "",
    ]
    return "\n".join(lines)


# ── 生成统计数据行 ────────────────────────────────────────────
def render_stats(entries: list[dict]) -> str:
    if not entries:
        return "> 还没有日记，写第一篇吧！\n"

    total      = len(entries)
    latest     = entries[0]["date"].strftime("%Y-%m-%d")
    earliest   = entries[-1]["date"].strftime("%Y-%m-%d")
    all_dates  = [e["date"] for e in entries]
    span_days  = (entries[0]["date"] - entries[-1]["date"]).days + 1
    streak     = calc_streak(all_dates)

    # 标签云
    all_tags = [t for e in entries for t in e["tags"]]
    tag_count = Counter(all_tags)
    if tag_count:
        top_tags = "  ".join(f"`{t}`×{c}" for t, c in tag_count.most_common(10))
        tag_cloud = f"\n**标签：** {top_tags}\n"
    else:
        tag_cloud = ""

    stats = (
        f"> 📖 共 **{total}** 篇 &nbsp;·&nbsp; "
        f"🗓 {earliest} → {latest} &nbsp;·&nbsp; "
        f"📆 跨度 {span_days} 天 &nbsp;·&nbsp; "
        f"🔥 连续 {streak} 天\n"
    )
    return stats + tag_cloud


# ── 生成完整 README ───────────────────────────────────────────
def generate_readme(entries: list[dict]) -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    header = (
        "# 📔 Dailight\n\n"
        "> 我的 Markdown 日记 · 点击条目展开阅读\n\n"
    )

    stats   = render_stats(entries)
    divider = "\n---\n\n"

    if not entries:
        body = "> 还没有任何日记条目。在 `entries/` 目录下新建 `YYYY-MM-DD.md` 即可。\n"
    else:
        body = "\n".join(render_entry(e) for e in entries)

    footer = (
        "\n---\n\n"
        "<sub>📌 本文件由 "
        "[`generate.py`](generate.py) 自动生成 · "
        f"最后更新：{now} · "
        "新增日记请在 [`entries/`](entries/) 目录下创建 `YYYY-MM-DD.md`</sub>\n"
    )

    return header + stats + divider + body + footer


# ── 入口 ──────────────────────────────────────────────────────
def main():
    print(f"🔍 扫描 {ENTRIES_DIR} …")
    entries = load_entries()
    print(f"📝 找到 {len(entries)} 篇日记")

    readme = generate_readme(entries)
    README_PATH.write_text(readme, encoding="utf-8")

    print(f"✅ 已生成 {README_PATH}")
    if entries:
        print(f"   最新：{entries[0]['date']} — {entries[0]['title']}")


if __name__ == "__main__":
    main()
