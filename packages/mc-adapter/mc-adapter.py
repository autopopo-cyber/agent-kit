#!/usr/bin/env python3
"""
MC Adapter — agent 与 MC 之间的薄适配层。

职责：把所有 MC API 调用收敛到这里。MC 升级时只改此文件。
Agent 代码不直接调 curl，通过此适配器。

用法：
  python3 mc-adapter.py heartbeat <GID>
  python3 mc-adapter.py pull-task <GID>
  python3 mc-adapter.py claim-task <TASK_ID> <GID>
  python3 mc-adapter.py report <TASK_ID> <STATUS> [outcome]
  python3 mc-adapter.py fleet-status
  python3 mc-adapter.py my-tasks <GID>
"""

import json, os, subprocess, sys

MC_URL = os.environ.get("MC_URL", "http://localhost:3000")
MC_API_KEY = os.environ.get("MC_API_KEY", "")

# ─── GID → DBID 映射（这是我们的约定，非 MC 原生）───
GID_TO_DBID = {"101":"10","102":"4","103":"5","104":"6","105":"18","106":"19","107":"20","108":"21"}
AGENT_NAMES = {"101":"相邦","102":"白起","103":"王翦","104":"丞相","105":"萱萱","106":"俊秀","107":"雪莹","108":"红婳"}


def _call(method: str, path: str, data: dict = None) -> dict:
    """调用 MC REST API。这是唯一的 HTTP 出口。"""
    cmd = ["curl", "-sf", "-m", "5", "-X", method,
           "-H", f"x-api-key: {MC_API_KEY}",
           "-H", "Content-Type: application/json"]
    if data:
        cmd += ["-d", json.dumps(data)]
    cmd.append(f"{MC_URL}{path}")
    
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {}
    except Exception:
        return {}


# ─── Public API ───

def heartbeat(gid: str) -> bool:
    """发送心跳。返回 True/False。"""
    dbid = GID_TO_DBID.get(gid, gid)
    result = _call("POST", f"/api/agents/{dbid}/heartbeat", {})
    return bool(result)


def fleet_status() -> list:
    """获取全舰队状态。"""
    data = _call("GET", "/api/agents")
    return data.get("agents", [])


def pull_task(gid: str) -> dict:
    """拉取分配给该 agent 的下一个 inbox 任务。无任务返回 {}。"""
    dbid = GID_TO_DBID.get(gid, gid)
    # 先查已分配的
    data = _call("GET", f"/api/tasks?assigned_to={dbid}&status=inbox&limit=5")
    tasks = data.get("tasks", data) if isinstance(data, dict) else data
    inbox = [t for t in tasks if t.get("status") == "inbox"]
    if inbox:
        t = inbox[0]
        _call("PUT", f"/api/tasks/{t['id']}", {"status": "in_progress"})
        return {"id": t["id"], "title": t.get("title", "")[:120]}
    return {}


def claim_task(task_id: str, gid: str) -> dict:
    """认领并开始执行任务。"""
    dbid = GID_TO_DBID.get(gid, gid)
    _call("PUT", f"/api/tasks/{task_id}", {"status": "in_progress"})
    data = _call("GET", f"/api/tasks/{task_id}")
    t = data.get("task", data) if isinstance(data, dict) else (data[0] if isinstance(data, list) else {})
    return {"id": t.get("id"), "title": t.get("title", "")[:120]}


def report(task_id: str, status: str, outcome: str = "") -> bool:
    """上报任务状态。"""
    body = {"status": status}
    if outcome:
        body["outcome"] = outcome[:200]
    result = _call("PUT", f"/api/tasks/{task_id}", body)
    return bool(result)


def my_tasks(gid: str) -> dict:
    """获取我的所有任务。"""
    dbid = GID_TO_DBID.get(gid, gid)
    data = _call("GET", f"/api/tasks?assigned_to={dbid}&limit=8")
    tasks = data.get("tasks", data) if isinstance(data, dict) else data
    inbox = [{"id": t["id"], "title": t.get("title","")[:80]} for t in tasks if t.get("status") == "inbox"]
    active = [{"id": t["id"], "title": t.get("title","")[:80], "status": t.get("status","?")}
              for t in tasks if t.get("status") in ("in_progress", "review")]
    return {"inbox": inbox, "active": active}


# ─── CLI ───
if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    
    if cmd == "heartbeat":
        gid = sys.argv[2]
        ok = heartbeat(gid)
        print(f"heartbeat: {'OK' if ok else 'FAIL'}")
    elif cmd == "pull-task":
        gid = sys.argv[2]
        task = pull_task(gid)
        if task:
            print(json.dumps(task))
    elif cmd == "claim-task":
        tid, gid = sys.argv[2], sys.argv[3]
        task = claim_task(tid, gid)
        print(json.dumps(task))
    elif cmd == "report":
        tid, status = sys.argv[2], sys.argv[3]
        outcome = sys.argv[4] if len(sys.argv) > 4 else ""
        report(tid, status, outcome)
    elif cmd == "fleet-status":
        agents = fleet_status()
        print(json.dumps([{"name": a["name"], "status": a.get("status","?")} for a in agents[:8]]))
    elif cmd == "my-tasks":
        gid = sys.argv[2]
        tasks = my_tasks(gid)
        print(json.dumps(tasks))
    else:
        print(f"Unknown command: {cmd}")
        print("Commands: heartbeat, pull-task, claim-task, report, fleet-status, my-tasks")
