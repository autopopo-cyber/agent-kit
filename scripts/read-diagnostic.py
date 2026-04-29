#!/usr/bin/env python3
"""
诊断文件阅读器 — 从 task-{id}-diagnostic.json 生成人类可读报告。

用法:
  python3 read-diagnostic.py <path/to/task-NNN-diagnostic.json>
  python3 read-diagnostic.py --all ~/wiki-102/raw/   # 扫描目录下所有诊断文件
  python3 read-diagnostic.py --summary ~/wiki-102/raw/  # 仅摘要表格

输出:
  - 任务ID、Agent、时间
  - 退出原因（STUCK / TIMEOUT / HERMES_EXIT_N / NO_RESULT）
  - 产物状态（是否生成、大小、行数、最后修改时间）
  - 判定建议（是永久失败还是可重试）
"""
import json, sys, os, glob
from datetime import datetime, timezone

EXIT_REASON_LABELS = {
    "STUCK": "🔴 卡住（产物长时间无更新）",
    "TIMEOUT": "⏱️ 超时（执行超过硬超时限制）",
    "NO_RESULT": "📭 无产物（hermes 退出但未生成文件）",
    "HERMES_EXIT_1": "❌ Hermes 通用错误",
    "HERMES_EXIT_2": "❌ Hermes 误用",
    "HERMES_EXIT_124": "⏱️ timeout 命令杀死",
    "HERMES_EXIT_130": "🛑 SIGINT 中断",
    "HERMES_EXIT_137": "💀 SIGKILL 强制终止",
    "HERMES_EXIT_143": "🛑 SIGTERM 终止",
}

RETRYABLE = {"STUCK", "TIMEOUT", "HERMES_EXIT_137", "HERMES_EXIT_143"}
NON_RETRYABLE = {"NO_RESULT", "HERMES_EXIT_1", "HERMES_EXIT_2"}


def read_diagnostic(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def format_report(d: dict, path: str = "") -> str:
    lines = []
    task_id = d.get("task_id", "?")
    reason = d.get("exit_reason", "?")
    reason_label = EXIT_REASON_LABELS.get(reason, f"未知({reason})")
    retry = "🔄 可重试" if reason in RETRYABLE else "⛔ 不建议重试" if reason in NON_RETRYABLE else "❓ 未知"

    lines.append(f"{'='*60}")
    lines.append(f"📋 诊断报告: 任务 #{task_id}")
    lines.append(f"{'='*60}")
    lines.append(f"  Agent:      GID={d.get('agent_gid','?')} (DBID={d.get('agent_dbid','?')})")
    lines.append(f"  时间:       {d.get('timestamp','?')}")
    lines.append(f"  退出原因:   {reason_label}")
    lines.append(f"  详情:       {d.get('exit_detail','-')}")
    lines.append(f"  判定:       {retry}")
    lines.append(f"  {'-'*40}")

    rf = d.get("result_file", {})
    if rf.get("exists"):
        lines.append(f"  📄 产物:    ✅ 存在")
        lines.append(f"     大小:    {rf.get('size_bytes',0)} bytes")
        lines.append(f"     行数:    {rf.get('lines',0)} lines")
        lines.append(f"     修改:    {rf.get('mtime_human','?')}")
    else:
        lines.append(f"  📄 产物:    ❌ 不存在")

    lines.append(f"  ⚙️ 配置:")
    lines.append(f"     卡住阈值: {d.get('stuck_timeout','?')}s")
    lines.append(f"     硬超时:   {d.get('hermes_timeout','?')}s")
    lines.append(f"{'='*60}")
    return "\n".join(lines)


def scan_directory(dirpath: str) -> list:
    pattern = os.path.join(dirpath, "task-*-diagnostic.json")
    return sorted(glob.glob(pattern))


def summary_table(files: list) -> str:
    if not files:
        return "📋 无诊断文件"
    
    rows = []
    for f in files:
        d = read_diagnostic(f)
        task_id = d.get("task_id", "?")
        reason = d.get("exit_reason", "?")
        rf = d.get("result_file", {})
        has_result = "✅" if rf.get("exists") else "❌"
        retry = "🔄" if reason in RETRYABLE else "⛔"
        ts = d.get("timestamp", "")[:16].replace("T", " ")
        rows.append(f"| T{task_id} | {ts} | {reason:20s} | {has_result} | {retry} |")

    header = "| 任务 | 时间 | 原因 | 产物 | 重试 |\n|------|------|------|------|------|"
    return header + "\n" + "\n".join(rows)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: read-diagnostic.py <diagnostic.json>")
        print("      read-diagnostic.py --all <wiki-dir/raw/>")
        print("      read-diagnostic.py --summary <wiki-dir/raw/>")
        sys.exit(1)

    arg = sys.argv[1]
    
    if arg == "--all":
        dpath = sys.argv[2] if len(sys.argv) > 2 else "."
        for f in scan_directory(dpath):
            print(format_report(read_diagnostic(f), f))
            print()
    elif arg == "--summary":
        dpath = sys.argv[2] if len(sys.argv) > 2 else "."
        print(summary_table(scan_directory(dpath)))
    else:
        print(format_report(read_diagnostic(arg), arg))
