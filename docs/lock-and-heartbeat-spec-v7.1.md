# 仙秦舰队 — 锁与心跳流程规范 v7.1

> 最后更新: 2026-04-28 17:35
> 适用范围: 全舰队 8 agent（101相邦 ~ 108红婳）

---

## 1. 核心原则

```
心跳 > 锁 > 任务
```

- **心跳是健康检查，永远最先执行，不受锁影响**
- **锁保护任务执行，心跳负责发现和清理僵尸锁**
- 确定性操作（打卡、锁）走 bash curl，非确定性（执行任务）走 hermes LLM

---

## 2. 锁文件格式

```
路径: ~/.xianqin/mc-poll-{GLOBAL_ID}.lock
格式: PID:TASK_ID
示例: 12345:117
```

| 字段 | 含义 | 用途 |
|------|------|------|
| `PID` | 执行任务的进程 ID | `kill -0 PID` 判断进程是否存活 |
| `TASK_ID` | MC 中的任务编号 | 查询任务状态，判断是否已完成 |

**TTL**: 600 秒（10 分钟）。超过 TTL 的锁进入僵尸检测流程。

---

## 3. 完整生命周期

```
┌─────────────────────────────────────────────────┐
│              mc-poll.sh v7.1 每次 cron 触发       │
├─────────────────────────────────────────────────┤
│                                                 │
│  Phase 0: 心跳                                  │
│    ├─ llm_ping() → DeepSeek API ping            │
│    ├─ 200 + content OK → heartbeat() curl MC    │
│    └─ 其他错误码 → 跳过 (不打卡)                  │
│                                                 │
│  Phase 0.5: 锁检查                              │
│    ├─ 无锁 → 继续 Phase 1                       │
│    ├─ 锁有效 (<600s) → exit 0 (有人在干活)       │
│    └─ 锁过期 (>600s) → is_zombie_lock() 四步判定 │
│        ├─ PID alive? → 不清理, exit 0            │
│        ├─ 任务已结束? → 🧹清理, 继续 Phase 1      │
│        └─ PID dead → 🧹清理, 继续 Phase 1        │
│                                                 │
│  Phase 1: 拉任务                                │
│    ├─ mc-poll.py → MC API GET inbox 任务         │
│    ├─ 无任务 → 巡逻完成, exit 0                   │
│    └─ 有任务 → 继续 Phase 2                      │
│                                                 │
│  Phase 2: 执行                                  │
│    ├─ echo "PID:TASK_ID" > LOCK  ← 🔒 获取锁     │
│    ├─ trap 'rm -f LOCK' EXIT                     │
│    ├─ PUT /api/tasks/{id} status=in_progress     │
│    ├─ hermes chat → 执行任务                      │
│    └─ hermes 失败 → exit 0 (trap 自动释放锁)      │
│                                                 │
│  Phase 3: 验证 + 交活 + 释放锁                    │
│    ├─ 产物文件不存在 → exit 0 (trap 释放锁)       │
│    ├─ llm_ping() → heartbeat() → PUT review      │
│    └─ exit 0 → trap EXIT 触发 → rm -f LOCK 🔓    │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 4. 僵尸锁四步判定

函数 `is_zombie_lock()` 在 `parse_lock()` 之后调用（已解析出 LOCK_PID, LOCK_TASK, LOCK_AGE）。

```
Step 1: LOCK_AGE <= 600s?
  → YES: 锁有效 — 不清理（return 1）
  → NO:  继续 Step 2

Step 2: kill -0 LOCK_PID 成功?
  → YES: 进程还活着（可能是慢任务）— 不清理（return 1）
  → NO:  继续 Step 3

Step 3: 查 MC API GET /api/tasks/LOCK_TASK
  → status ∈ {review, completed, failed}?
  → YES: 任务已结束 — 确认僵尸（return 0）
  → NO:  继续 Step 4

Step 4: PID 死了 + 任务状态未知
  → 判定僵尸（return 0）
```

**判定为僵尸后**: `rm -f "$LOCK"` → 脚本继续执行 Phase 1 拉新任务。

---

## 5. 各场景演练

### 5.1 正常获取任务 → 执行 → 完成

```
cron 触发
  → 心跳 OK
  → 无锁
  → 拉任务: mc-poll.py 返回 task #117
  → echo "12345:117" > LOCK      ← 获取锁
  → PUT tasks/117 in_progress
  → hermes 执行...
  → 产物验证通过
  → PUT tasks/117 review
  → exit 0 → trap EXIT → rm LOCK ← 释放锁
```

**锁存在时间**: hermes 执行时间（通常 1-5 分钟）


### 5.2 无任务时

```
cron 触发
  → 心跳 OK
  → 无锁
  → 拉任务: mc-poll.py 返回空
  → 巡逻完成, exit 0
```

**锁**: 不创建


### 5.3 任务执行中，下一次 cron 触发

```
cron 触发                   ← 第一个实例还在执行 #117
  → 心跳 OK                 ← 心跳不受锁影响
  → 锁检查: LOCK 存在, age=180s < 600s
  → "锁有效 — 跳过"
  → exit 0                  ← 不拉新任务
```

**锁保护了并发**: 不会同时执行两个任务。


### 5.4 进程被 SIGKILL → 僵尸锁

```
cron 触发 → 获取锁 → 执行任务 #117
  → SIGKILL!                ← 进程直接被杀死
  → trap EXIT 未触发          ← 锁残留！
```

下一次 cron:
```
cron 触发
  → 心跳 OK
  → 锁检查: LOCK 存在, age=720s > 600s
  → Step 2: kill -0 LOCK_PID → 失败 (进程已死)
  → Step 3: GET /api/tasks/117 → status="in_progress" (未结束)
  → Step 4: PID 死了 → 僵尸
  → 🧹 rm LOCK               ← 清理
  → 继续 Phase 1 拉新任务
```


### 5.5 慢任务（超过 10 分钟）

```
cron 触发
  → 心跳 OK
  → 锁检查: LOCK 存在, age=780s > 600s
  → Step 2: kill -0 LOCK_PID → 成功! (进程还在跑)
  → "锁过期但进程仍在跑 — 保留锁"
  → exit 0
```

**不清理**: 进程活着说明任务确实还在执行。


### 5.6 任务已 MC 完成但锁残留

```
cron 触发
  → 心跳 OK
  → 锁检查: LOCK 存在, age=900s > 600s
  → Step 2: kill -0 LOCK_PID → 失败
  → Step 3: GET /api/tasks/117 → status="review"
  → "僵尸锁: 任务已结束"
  → 🧹 rm LOCK
```

**通过 MC 任务状态确认**: 比只检查 PID 更可靠。


## 6. 心跳的生命周期

心跳在每次 cron 中有 **最多 3 次** 发送机会：

| 时机 | 位置 | 条件 |
|------|------|------|
| Phase 0 | 脚本开头 | llm_ping() 通过 |
| Phase 3 | 任务完成 | llm_ping() 通过 |
| Phase 0 | 无任务 | llm_ping() 通过 |

**llm_ping() 通过 = DeepSeek 返回 HTTP 200 + content 非空**

心跳失败（LLM 不通）不影响任务拉取——心跳和任务是解耦的。

---

## 7. 故障矩阵

| 故障 | 心跳？ | 锁清理？ | 任务？ |
|------|:---:|:---:|:---:|
| DeepSeek 500 (服务端挂) | ❌ 跳过 | ✅ 正常 | ✅ 拉取但跳过执行 |
| LLM ping 401 (key过期) | ❌ 跳过 | ✅ 正常 | ✅ 拉取但跳过执行 |
| hermes 执行失败 | ✅ | ✅ trap释放 | ❌ 不交活 |
| SIGKILL 杀进程 | ✅ 下轮发 | ✅ 下轮清理 | ❌ 孤儿任务 |
| 机器重启 | ✅ 下轮发 | ✅ 文件系统清理 | ❌ 孤儿任务 |
| 网络断 (到MC) | ❌ | ✅ 锁正常 | 拉不到任务 |

---

## 8. 8 Agent 配置参考

| GID | 名称 | 节点 | DB ID | 偏移 | MC_API_KEY |
|-----|------|------|-------|------|------------|
| 101 | 相邦 | localhost | 10 | 0s | mc_08c...6c29 |
| 102 | 白起 | 100.64.63.98 | 4 | 15s | mc_08c...6c29 |
| 103 | 王翦 | 100.67.214.106 | 5 | 30s | mc_08c...6c29 |
| 104 | 丞相 | 100.76.65.47 | 6 | 45s | mc_08c...6c29 |
| 105 | 萱萱 | localhost | 18 | 60s | mc_08c...6c29 |
| 106 | 俊秀 | 100.64.63.98 | 19 | 75s | mc_08c...6c29 |
| 107 | 雪莹 | 100.67.214.106 | 20 | 90s | mc_08c...6c29 |
| 108 | 红婳 | 100.76.65.47 | 21 | 105s | mc_08c...6c29 |

**偏移规则**: 每 15 秒错峰，避免 8 个 agent 同时打 MC。

---

## 9. 验证清单

| 检查项 | 预期 |
|--------|------|
| `ls ~/.xianqin/mc-poll-*.lock` | 无僵尸锁存在 |
| `pgrep -f "hermes.*chat"` | 无僵尸 hermes 进程 |
| MC Agent 面板 | 8 个 agent last_seen < 10 分钟 |
| `crontab -l | grep mc-poll` | 每个节点有对应 cron |
| `tail /tmp/mc-poll-*.log` | 最近一次显示 "心跳 OK" 或 "巡逻完成" |

---

## 10. 快速诊断命令

```bash
# 看全舰队锁状态
for host in qin@100.64.63.98 qin@100.67.214.106 qinj@100.76.65.47; do
  ssh "$host" 'ls -la ~/.xianqin/mc-poll-*.lock 2>/dev/null || echo "无锁"'
done

# 看全舰队心跳
sqlite3 mission-control.db \
  "SELECT name, status, datetime(last_seen,'unixepoch','localtime') as hb FROM agents WHERE id IN (4,5,6,10,18,19,20,21)"

# 手动清理所有僵尸锁
for host in ...; do
  ssh "$host" 'for f in ~/.xianqin/mc-poll-*.lock; do
    [ ! -f "$f" ] && continue
    age=$(($(date +%s) - $(stat -c %Y "$f")))
    [ "$age" -gt 600 ] && rm -v "$f"
  done'
done
```
