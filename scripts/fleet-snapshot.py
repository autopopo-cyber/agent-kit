#!/usr/bin/env python3
"""采集舰队数据，注入 cron prompt 作为上下文"""
import subprocess, json, os, time

API_KEY = "mc_08c9022bb3c89453004c2cce9b05a7881492c96c9add6c29"
MC = "http://127.0.0.1:3000"
now = int(time.time())

print(f"## 舰队数据快照 — {time.strftime('%H:%M:%S')}")
print(f"时间戳: {now}")
print()

# 1. 心跳
try:
    r = subprocess.run(["curl", "-sf", "-m", "5", f"{MC}/api/agents",
                       "-H", f"x-api-key: {API_KEY}"], capture_output=True, text=True, timeout=6)
    agents = json.loads(r.stdout).get("agents", [])
    fleet = [a for a in agents if a.get("global_id")]
    stale = 0
    print("### 1. 全舰队心跳")
    for a in sorted(fleet, key=lambda x: str(x.get("global_id", "0"))):
        ls = a.get("last_seen", 0)
        ago_m = int((now - ls) / 60) if ls else 999
        flag = "🟢" if ago_m < 15 else "🟡" if ago_m < 30 else "🔴"
        if ago_m >= 15:
            stale += 1
        print(f"  {flag} #{a['global_id']} {a.get('name','?'):8s} status={a.get('status','?')} last_seen={ago_m}m前")
    print(f"  总结: {len(fleet)-stale}/{len(fleet)} 正常, {stale} 过期")
except Exception as e:
    print(f"  ❌ 心跳查询失败: {e}")

# 2. 萱萱的任务
print()
print("### 2. 萱萱(105) 的任务")
try:
    r = subprocess.run(["curl", "-sf", "-m", "5", f"{MC}/api/tasks?assigned_to=105",
                       "-H", f"x-api-key: {API_KEY}"], capture_output=True, text=True, timeout=6)
    tasks = json.loads(r.stdout)
    tasks = tasks if isinstance(tasks, list) else tasks.get("tasks", [])
    by_status = {}
    for t in tasks:
        s = t.get("status", "?")
        by_status[s] = by_status.get(s, 0) + 1
    print(f"  任务分布: {by_status if by_status else '无任务'}")
    actionable = [t for t in tasks if t.get("status") in ("inbox", "assigned")]
    for t in actionable[:5]:
        print(f"  #{t['id']} [{t.get('status','?')}] {t.get('title','')[:80]}")
except Exception as e:
    print(f"  ❌ 任务查询失败: {e}")

# 3. 锁
print()
print("### 3. 萱萱(105) 锁")
lock = os.path.expanduser("~/.xianqin/mc-poll-105.lock")
if os.path.exists(lock):
    age = int((now - os.path.getmtime(lock)) / 60)
    content = open(lock).read().strip()
    print(f"  锁存在: age={age}m, content={content}")
else:
    print("  无锁")

# 4. MC 健康（用 API key 验证 — 避免 307 重定向）
print()
print("### 4. MC 健康")
try:
    r = subprocess.run(["curl", "-sf", "-m", "5",
                       f"{MC}/api/agents",
                       "-H", f"x-api-key: {API_KEY}"], capture_output=True, text=True, timeout=6)
    if r.returncode == 0:
        print(f"  MC API → HTTP 200 OK")
    else:
        print(f"  MC API → 异常 (exit={r.returncode})")
except Exception as e:
    print(f"  ❌ MC 不通: {e}")

# 5. 全舰队任务概览
print()
print("### 5. 全舰队任务概览")
try:
    r = subprocess.run(["curl", "-sf", "-m", "5", f"{MC}/api/tasks?status=in_progress&limit=20",
                       "-H", f"x-api-key: {API_KEY}"], capture_output=True, text=True, timeout=6)
    tasks = json.loads(r.stdout)
    tasks = tasks if isinstance(tasks, list) else tasks.get("tasks", [])
    if tasks:
        for t in tasks[:10]:
            print(f"  #{t['id']} → {t.get('assigned_to','?')} [{t.get('status','?')}] {t.get('title','')[:60]}")
    else:
        print("  无进行中任务")
except:
    pass

print()
print("---")
print("以上数据由 bash/python 采集。请根据实际数据写巡报，不要编造。")
